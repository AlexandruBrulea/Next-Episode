import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/catalog_provider.dart';
import '../../domain/models.dart';
import '../database.dart';
import '../tmdb_retention.dart';
import 'internal_catalog.dart';

/// Public reads use the committed catalog. Only the administrative migration
/// service may change that commitment; constructor configuration is a bootstrap.
class CatalogRouter extends CatalogProvider {
  final AppDatabase db;
  final Map<String, CatalogProvider> modules;
  final String requested;
  String _active;
  bool _initialized = false;
  Future<void> Function()? refreshConfiguration;
  CatalogRouter({
    required this.db,
    required this.modules,
    required String active,
  }) : requested = active,
       _active = active {
    if (!modules.containsKey(active)) {
      throw ArgumentError('Unknown catalog configuration');
    }
  }
  String get active => _active;
  @override
  String get id => _active;
  CatalogProvider get selected => modules[_active]!;
  @override
  String get label => selected.label;
  @override
  CatalogCapabilities get capabilities => selected.capabilities;
  Future<void> initialize() async {
    if (_initialized) return;
    await db.transaction(() async {
      var row = await db
          .customSelect('SELECT * FROM content_state WHERE singleton=1')
          .getSingleOrNull();
      if (row == null) {
        final library = await db.library();
        final initial = library.isEmpty
            ? requested
            : library.first.title.provider;
        final safe = modules.containsKey(initial) ? initial : requested;
        await db.customStatement('INSERT INTO content_state VALUES (1,?,0,?)', [
          safe,
          'bootstrap',
        ]);
        row = await db
            .customSelect('SELECT * FROM content_state WHERE singleton=1')
            .getSingle();
      }
      _active = row.read<String>('provider');
      if (!modules.containsKey(_active)) {
        throw const ApiFailure('The saved catalog is temporarily unavailable.');
      }
    });
    _initialized = true;
  }

  Future<void> reloadCommitted() async {
    final row = await db
        .customSelect('SELECT provider FROM content_state WHERE singleton=1')
        .getSingle();
    _active = row.read<String>('provider');
  }

  static bool sameExternal(Map<String, String> a, Map<String, String> b) {
    final common = a.keys.toSet().intersection(b.keys.toSet());
    return common.isNotEmpty && common.every((key) => a[key] == b[key]);
  }

  Future<TitleData> identity(MediaType type, int localId) async {
    final row = await db
        .customSelect(
          'SELECT data FROM catalog_titles WHERE type=? AND local_id=?',
          variables: [Variable(type.name), Variable(localId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const ApiFailure('This title cannot be loaded right now.');
    }
    final data = Json.from(jsonDecode(row.read<String>('data')));
    final scrubber = TmdbScrubber(
      db.retentionClock(),
      enabled: await db.tmdbContentAllowed(),
    );
    final cleaned = Json.from(scrubber.scrub(data, legacyTitle: true) as Map);
    if (scrubber.changed) {
      await db.customStatement(
        'UPDATE catalog_titles SET data=? WHERE type=? AND local_id=?',
        [jsonEncode(cleaned), type.name, localId],
      );
    }
    return TitleData(type, cleaned);
  }

  Future<TitleData> _register(TitleData remote) => db.transaction(() async {
    if (remote.provider == 'tmdb') await db.requireTmdbContent();
    final alias = await db
        .customSelect(
          'SELECT local_id FROM catalog_refs WHERE provider=? AND type=? AND remote_id=?',
          variables: [
            Variable(remote.provider),
            Variable(remote.type.name),
            Variable(remote.sourceId),
          ],
        )
        .getSingleOrNull();
    var localId = alias?.read<int>('local_id');
    if (localId == null && remote.externalIds.isNotEmpty) {
      final candidates =
          (await db
                  .customSelect(
                    'SELECT data FROM catalog_titles WHERE type=?',
                    variables: [Variable(remote.type.name)],
                  )
                  .get())
              .map(
                (r) => TitleData(
                  remote.type,
                  Json.from(jsonDecode(r.read<String>('data'))),
                ),
              )
              .where((t) => sameExternal(t.externalIds, remote.externalIds))
              .toList();
      if (candidates.length == 1) localId = candidates.single.id;
    }
    localId ??=
        (await db
                .customSelect(
                  'SELECT COALESCE(MAX(local_id),0)+1 AS next FROM catalog_titles WHERE type=?',
                  variables: [Variable(remote.type.name)],
                )
                .getSingle())
            .read<int>('next');
    final local = TitleData(remote.type, {
      ...remote.raw,
      'id': localId,
      'source_id': remote.sourceId,
    });
    await db.importIdentity(local);
    await db.recordLink(
      local.key,
      local.type.name,
      remote.provider,
      remote.sourceId,
      externalIds: remote.externalIds,
    );
    return local;
  });
  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async {
    await initialize();
    final provider = _active;
    if (provider == 'tmdb') await db.requireTmdbContent();
    final result = await selected.search(query, type, page);
    if (provider != _active) return search(query, type, page);
    final titles = <TitleData>[];
    for (final t in result.results) {
      titles.add(await _register(t));
    }
    return SearchPage(titles, result.page, result.totalPages);
  }

  @override
  Future<SearchPage> popular(int page) async {
    await initialize();
    final provider = _active;
    if (provider == 'tmdb') await db.requireTmdbContent();
    final key = 'popular:$provider:$page';
    final cache = await db.cached(key);
    SearchPage? saved() => cache == null
        ? null
        : SearchPage(
            objects(cache.data['results'])
                .map(
                  (item) => TitleData(
                    MediaType.values.byName(item['type']),
                    Json.from(item['data']),
                  ),
                )
                .toList(),
            page,
            integer(cache.data['total_pages'], 1),
          );
    if (cache != null &&
        DateTime.now().difference(cache.fetchedAt) < const Duration(hours: 12)) {
      return saved()!;
    }
    try {
      final remote = await selected.popular(page);
      if (provider != _active) return await popular(page);
      final titles = <TitleData>[];
      for (final title in remote.results) {
        titles.add(await _register(title));
      }
      await db.cache(key, {
        'results': [
          for (final title in titles)
            {'type': title.type.name, 'data': title.raw},
        ],
        'total_pages': remote.totalPages,
      }, DateTime.now());
      return SearchPage(titles, remote.page, remote.totalPages);
    } catch (_) {
      if (provider != _active) return popular(page);
      if (provider == 'tmdb') await db.requireTmdbContent();
      if (await db.cached(key) != null && cache != null) return saved()!;
      rethrow;
    }
  }

  @override
  Future<TitleData> title(MediaType type, int id) async {
    await initialize();
    final old = await identity(type, id);
    if (old.provider == 'tmdb') await db.requireTmdbContent();
    final module = modules[old.provider];
    if (module == null) {
      throw const ApiFailure('Information cannot be updated right now.');
    }
    final remote = await module.title(type, old.sourceId);
    final local = TitleData(type, {
      ...remote.raw,
      'id': id,
      'source_id': remote.sourceId,
    });
    if (type == MediaType.movie) {
      await db.transaction(() async {
        if ((await identity(type, id)).provider != old.provider) {
          throw const CatalogConflict(
            'stale_request',
            'Catalog changed during request',
          );
        }
        await InternalCatalog(db).saveTitle(local);
        await db.cache('movie:$id', local.raw, DateTime.now());
        await db.updateTitle(local, DateTime.now());
      });
    }
    return local;
  }

  @override
  Future<SeriesBundle> series(int id) async {
    await initialize();
    final old = await identity(MediaType.tv, id);
    if (old.provider == 'tmdb') await db.requireTmdbContent();
    final module = modules[old.provider];
    if (module == null) {
      throw const ApiFailure('Information cannot be updated right now.');
    }
    final remote = await module.series(old.sourceId);
    try {
      return await db.transaction(() async {
        if ((await identity(MediaType.tv, id)).provider != old.provider) {
          throw const CatalogConflict(
            'stale_request',
            'Catalog changed during request',
          );
        }
        final store = InternalCatalog(db);
        final result = await store.bind(id, remote);
        await store.persist(result);
        return result;
      });
    } on CatalogConflict catch (e) {
      await db.administrativeConflict(old.key, e.toString());
      throw const ApiFailure(
        'Your saved data is safe. Some information could not be updated.',
      );
    }
  }

  @override
  Future<SeasonData> season(int seriesId, int number) async =>
      (await series(seriesId)).seasons.firstWhere((s) => s.number == number);
  @override
  void close() {
    for (final module in modules.values) {
      module.close();
    }
  }
}
