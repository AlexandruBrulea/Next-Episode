import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/catalog_provider.dart';
import '../../domain/models.dart';
import '../database.dart';
import '../tmdb_retention.dart';
import 'catalog_router.dart';
import 'internal_catalog.dart';

class AdministrativeReport {
  final String id, target, status;
  final List<Json> items;
  const AdministrativeReport(this.id, this.target, this.status, this.items);
  Json toJson() => {
    'deploymentId': id,
    'target': target,
    'status': status,
    'items': items,
  };
}

class _Validated implements Exception {}

/// Administrative control plane. Network reads are staged without changing live
/// data. Activation, every ready title and the rollback snapshot commit together.
class AdminMigration {
  final CatalogRouter router;
  AppDatabase get db => router.db;
  AdminMigration(this.router);
  Future<String> _scope() async => jsonEncode(
    (await db.library())
        .map(
          (e) => {'key': e.title.key, 'addedAt': e.addedAt.toIso8601String()},
        )
        .toList()
      ..sort((a, b) => a['key']!.compareTo(b['key']!)),
  );
  Future<String> _fingerprint(LibraryEntry entry) async {
    final cache = await db.cached(
      entry.title.isTv ? 'series:${entry.title.id}' : 'movie:${entry.title.id}',
    );
    return jsonEncode({'title': entry.title.raw, 'cache': cache?.data});
  }

  String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );
  bool _fallbackMatches(TitleData old, TitleData candidate) {
    if (old.originalTitle.isEmpty ||
        candidate.originalTitle.isEmpty ||
        old.releaseDate == null ||
        candidate.releaseDate == null ||
        old.countries.isEmpty ||
        candidate.countries.isEmpty ||
        old.networks.isEmpty ||
        candidate.networks.isEmpty) {
      return false;
    }
    return _normalize(old.originalTitle) ==
            _normalize(candidate.originalTitle) &&
        old.releaseDate!.year == candidate.releaseDate!.year &&
        old.countries
            .toSet()
            .intersection(candidate.countries.toSet())
            .isNotEmpty &&
        old.networks
            .map(_normalize)
            .toSet()
            .intersection(candidate.networks.map(_normalize).toSet())
            .isNotEmpty;
  }

  bool _externalConflict(TitleData a, TitleData b) => a.externalIds.keys
      .toSet()
      .intersection(b.externalIds.keys.toSet())
      .any((k) => a.externalIds[k] != b.externalIds[k]);
  Future<({TitleData title, double confidence})> _match(
    TitleData old,
    CatalogProvider target,
    int? approved,
  ) async {
    if (approved != null) {
      return (title: await target.title(old.type, approved), confidence: 1.0);
    }
    final link = await db
        .customSelect(
          'SELECT remote_id FROM catalog_refs WHERE provider=? AND type=? AND local_id=?',
          variables: [
            Variable(target.id),
            Variable(old.type.name),
            Variable(old.id),
          ],
        )
        .getSingleOrNull();
    if (link != null) {
      final found = await target.title(old.type, link.read<int>('remote_id'));
      if (_externalConflict(old, found)) {
        throw const CatalogConflict(
          'external_conflict',
          'Previously mapped external IDs now disagree',
        );
      }
      return (title: found, confidence: 1.0);
    }
    if (old.externalIds.isNotEmpty) {
      final exact = await target.lookup(old.type, old.externalIds);
      if (exact == null) {
        throw const CatalogConflict(
          'not_found',
          'No match for known IMDb/TVDB IDs',
        );
      }
      if (!CatalogRouter.sameExternal(old.externalIds, exact.externalIds)) {
        throw const CatalogConflict(
          'external_conflict',
          'External IDs disagree',
        );
      }
      return (title: exact, confidence: 1.0);
    }
    final search = await target.search(
      old.originalTitle.isEmpty ? old.title : old.originalTitle,
      old.type,
      1,
    );
    final results = <TitleData>[];
    for (final candidate in search.results) {
      final details = await target.title(old.type, candidate.sourceId);
      if (_fallbackMatches(old, details) && !_externalConflict(old, details)) {
        results.add(details);
      }
    }
    // More pages could contain another match: never guess from an incomplete set.
    if (search.totalPages > 1 || results.length > 1) {
      throw const CatalogConflict(
        'ambiguous_title',
        'Title/year/country/network are not unique',
      );
    }
    if (results.isEmpty) {
      throw const CatalogConflict(
        'not_found',
        'Insufficient title/year/country/network evidence',
      );
    }
    return (title: results.single, confidence: 0.9);
  }

  Future<AdministrativeReport> prepare({
    required String deploymentId,
    required String target,
    required int generation,
    Map<String, int> approvedTitles = const {},
    Future<void> Function(int)? afterItem,
  }) async {
    await router.initialize();
    await db.enforceTmdbRetention();
    if (target == 'tmdb') await db.requireTmdbContent();
    final provider = router.modules[target];
    if (provider == null) {
      throw ArgumentError('Unknown administrative provider');
    }
    final existing = await db
        .customSelect(
          'SELECT * FROM admin_migrations WHERE id=?',
          variables: [Variable(deploymentId)],
        )
        .getSingleOrNull();
    if (existing != null &&
        (existing.read<String>('target') != target ||
            existing.read<int>('generation') != generation)) {
      throw StateError(
        'Deployment ID cannot be reused for a different target/generation',
      );
    }
    if (existing != null &&
        existing.read<String>('status').startsWith('committed')) {
      return report(deploymentId);
    }
    final scope = await _scope();
    await db.customStatement(
      'INSERT INTO admin_migrations VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,scope=excluded.scope',
      [
        deploymentId,
        target,
        generation,
        'preparing',
        '{}',
        '{}',
        scope,
        DateTime.now().toIso8601String(),
      ],
    );
    var index = 0;
    await db.customStatement(
      'DELETE FROM admin_migration_items WHERE migration_id=? AND entity_key NOT IN (SELECT key FROM library)',
      [deploymentId],
    );
    for (final entry in await db.library()) {
      final fingerprint = await _fingerprint(entry);
      final previous = await db
          .customSelect(
            'SELECT * FROM admin_migration_items WHERE migration_id=? AND entity_key=?',
            variables: [Variable(deploymentId), Variable(entry.title.key)],
          )
          .getSingleOrNull();
      if (previous?.read<String>('status') == 'ready' &&
          previous?.read<String>('fingerprint') == fingerprint &&
          !approvedTitles.containsKey(entry.title.key)) {
        index++;
        continue;
      }
      var status = 'ready';
      String? staged;
      Json detail = {};
      try {
        if (!entry.title.isTv && !provider.capabilities.movies) {
          throw const CatalogConflict(
            'unsupported_type',
            'Cached film preserved; destination has no movie catalog',
          );
        }
        final match = await _match(
          entry.title,
          provider,
          approvedTitles[entry.title.key],
        );
        final collision = await db
            .customSelect(
              'SELECT local_id FROM catalog_refs WHERE provider=? AND type=? AND remote_id=?',
              variables: [
                Variable(target),
                Variable(entry.title.type.name),
                Variable(match.title.sourceId),
              ],
            )
            .getSingleOrNull();
        final stagedOwners = await db
            .customSelect(
              "SELECT entity_key,detail FROM admin_migration_items WHERE migration_id=? AND entity_key<>? AND status='ready'",
              variables: [Variable(deploymentId), Variable(entry.title.key)],
            )
            .get();
        if (stagedOwners.any(
          (r) =>
              r
                  .read<String>('entity_key')
                  .startsWith('${entry.title.type.name}:') &&
              jsonDecode(r.read<String>('detail'))['sourceId'] ==
                  match.title.sourceId,
        )) {
          throw const CatalogConflict(
            'title_collision',
            'Destination already staged for another internal title',
          );
        }
        if (collision != null &&
            collision.read<int>('local_id') != entry.title.id) {
          throw const CatalogConflict(
            'title_collision',
            'Destination belongs to another internal title',
          );
        }
        if (entry.title.isTv) {
          final incoming = await provider.series(match.title.sourceId);
          InternalCatalog(
            db,
          ).verify(await InternalCatalog(db).cached(entry.title.id), incoming);
          // Exercise alias/identity constraints inside a deliberately rolled-back
          // transaction. Conflicts become review items, never a partial switch.
          try {
            await db.transaction(() async {
              await InternalCatalog(db)
                  .bind(entry.title.id, incoming, confidence: match.confidence);
              throw _Validated();
            });
          } on _Validated {
            // No changes survive validation.
          }
          staged = jsonEncode(incoming.toJson());
        } else {
          staged = jsonEncode(match.title.raw);
        }
        detail = {
          'confidence': match.confidence,
          'sourceId': match.title.sourceId,
          'approvedByAdmin': approvedTitles.containsKey(entry.title.key),
        };
      } on CatalogConflict catch (e) {
        status = 'review';
        detail = {'code': e.code, 'message': e.detail};
      } catch (_) {
        status = 'pending';
        detail = {
          'code': 'fetch_failed',
          'message':
              'Fetch failed; retry before activation. Cached data unchanged.',
        };
      }
      final scrubber = TmdbScrubber(db.retentionClock(), enabled: await db.tmdbContentAllowed());
      scrubber.scrub(fingerprint, obtained: db.retentionClock());
      scrubber.scrub(staged, obtained: db.retentionClock(), legacyTitle: true);
      if (scrubber.changed) throw StateError('Provider content expired during preparation');
      await db.customStatement(
        'INSERT OR REPLACE INTO admin_migration_items VALUES (?,?,?,?,?,?)',
        [
          deploymentId,
          entry.title.key,
          status,
          fingerprint,
          staged,
          jsonEncode(detail),
        ],
      );
      index++;
      if (afterItem != null) await afterItem(index);
    }
    final rows = await db
        .customSelect(
          'SELECT status FROM admin_migration_items WHERE migration_id=?',
          variables: [Variable(deploymentId)],
        )
        .get();
    final state = rows.any((r) => r.read<String>('status') == 'pending')
        ? 'pending'
        : 'prepared';
    await db.customStatement(
      'UPDATE admin_migrations SET status=? WHERE id=?',
      [state, deploymentId],
    );
    return report(deploymentId);
  }

  Future<String> _userState() async => jsonEncode({
    'library': jsonDecode(await _scope()),
    for (final table in ['watched', 'preferences', 'user_history'])
      table: [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM $table ORDER BY ${table == 'user_history' ? 'id' : 'key'}',
                )
                .get())
          row.data,
      ],
  });
  Future<Json> _backup() async => {
    for (final table in ['content_state', 'cache', 'catalog_titles'])
      table: [
        for (final row in await db.customSelect('SELECT * FROM $table').get())
          row.data,
      ],
    'library': [
      for (final row
          in await db
              .customSelect('SELECT key,data,updated_at FROM library')
              .get())
        row.data,
    ],
  };

  Future<AdministrativeReport> activate(
    String deploymentId, {
    Future<void> Function(int)? afterWrite,
  }) async {
    await router.initialize();
    await db.enforceTmdbRetention();
    await db.transaction(() async {
      final migration = await db
          .customSelect(
            'SELECT * FROM admin_migrations WHERE id=?',
            variables: [Variable(deploymentId)],
          )
          .getSingle();
      if (migration.read<String>('status').startsWith('committed')) return;
      if (migration.read<String>('status') != 'prepared') {
        throw StateError(
          'Migration is not prepared; previous provider stays active',
        );
      }
      final current = await db
          .customSelect('SELECT * FROM content_state WHERE singleton=1')
          .getSingle();
      if (migration.read<int>('generation') <=
          current.read<int>('generation')) {
        throw StateError('Stale administrative deployment');
      }
      if (migration.read<String>('scope') != await _scope()) {
        throw StateError('Library changed during preparation; prepare again');
      }
      final before = await _userState();
      final backup = await _backup();
      final library = {for (final e in await db.library()) e.title.key: e};
      final rows = await db
          .customSelect(
            'SELECT * FROM admin_migration_items WHERE migration_id=? ORDER BY entity_key',
            variables: [Variable(deploymentId)],
          )
          .get();
      var written = 0;
      for (final row in rows) {
        final key = row.read<String>('entity_key');
        final entry = library[key];
        if (entry == null) continue;
        if (row.read<String>('fingerprint') != await _fingerprint(entry)) {
          throw StateError(
            'Metadata changed during preparation; prepare again',
          );
        }
        if (row.read<String>('status') == 'review') {
          await db.administrativeConflict(key, row.read<String>('detail'));
          continue;
        }
        if (row.read<String>('status') != 'ready') {
          throw StateError('Unfinished migration item');
        }
        final staged = Json.from(jsonDecode(row.read<String>('staged')));
        final confidence = decimal(
          Json.from(jsonDecode(row.read<String>('detail')))['confidence'],
        );
        final store = InternalCatalog(db);
        if (entry.title.isTv) {
          final result = await store.bind(
            entry.title.id,
            SeriesBundle.fromJson(staged),
            confidence: confidence,
          );
          await store.persist(result);
        } else {
          final title = TitleData(MediaType.movie, {
            ...staged,
            'id': entry.title.id,
            'source_id': integer(staged['source_id'], integer(staged['id'])),
          });
          await store.saveTitle(title, confidence: confidence);
          await db.cache('movie:${title.id}', title.raw, DateTime.now());
          await db.updateTitle(title, DateTime.now());
        }
        written++;
        if (afterWrite != null) await afterWrite(written);
      }
      if (before != await _userState()) {
        throw StateError('User data invariant failed; transaction rolled back');
      }
      final target = migration.read<String>('target');
      await db.customStatement(
        'UPDATE content_state SET provider=?,generation=?,deployment_id=? WHERE singleton=1',
        [target, migration.read<int>('generation'), deploymentId],
      );
      final status = rows.any((r) => r.read<String>('status') == 'review')
          ? 'committed_with_review'
          : 'committed';
      await db.customStatement(
        'UPDATE admin_migrations SET status=?,backup=? WHERE id=?',
        [status, jsonEncode(backup), deploymentId],
      );
    });
    await router.reloadCommitted();
    return report(deploymentId);
  }

  Future<AdministrativeReport> report(String id) async {
    final migration = await db
        .customSelect(
          'SELECT * FROM admin_migrations WHERE id=?',
          variables: [Variable(id)],
        )
        .getSingle();
    final rows = await db
        .customSelect(
          'SELECT entity_key,status,detail FROM admin_migration_items WHERE migration_id=? ORDER BY entity_key',
          variables: [Variable(id)],
        )
        .get();
    return AdministrativeReport(
      id,
      migration.read<String>('target'),
      migration.read<String>('status'),
      rows
          .map(
            (r) => {
              'entity': r.read<String>('entity_key'),
              'status': r.read<String>('status'),
              ...Json.from(jsonDecode(r.read<String>('detail'))),
            },
          )
          .toList(),
    );
  }

  Future<void> rollback(String deploymentId, {required int generation}) async {
    await db.enforceTmdbRetention();
    await db.transaction(() async {
      final migration = await db
          .customSelect(
            'SELECT * FROM admin_migrations WHERE id=?',
            variables: [Variable(deploymentId)],
          )
          .getSingle();
      final current = await db
          .customSelect('SELECT * FROM content_state WHERE singleton=1')
          .getSingle();
      if (current.read<String>('deployment_id') !=
              migration.read<String>('id') ||
          generation <= current.read<int>('generation')) {
        throw StateError(
          'Rollback must target the current deployment with a newer generation',
        );
      }
      final backup = Json.from(jsonDecode(migration.read<String>('backup')));
      if (backup['content_state'] == null) {
        throw StateError('No committed backup');
      }
      final before = await _userState();
      for (final row in objects(backup['cache'])) {
        final key = string(row['key']);
        var data = Json.from(jsonDecode(string(row['data'])));
        if (key.startsWith('series:')) {
          final prior = SeriesBundle.fromJson(data);
          final now = await InternalCatalog(db).cached(prior.title.id);
          if (now != null) {
            final ids = prior.episodes.map((e) => e.id).toSet();
            final seasons = [...prior.seasons];
            for (final s in now.seasons) {
              final extra = s.episodes
                  .where((e) => !ids.contains(e.id))
                  .toList();
              if (extra.isEmpty) continue;
              final index = seasons.indexWhere((p) => p.number == s.number);
              if (index < 0) {
                seasons.add(s);
              } else {
                seasons[index] = SeasonData(prior.title.id, {
                  ...seasons[index].raw,
                  'episodes': [
                    ...seasons[index].episodes.map((e) => e.raw),
                    ...extra.map((e) => e.raw),
                  ],
                });
              }
            }
            data = SeriesBundle(prior.title, seasons).toJson();
          }
        }
        await db.cache(key, data, DateTime.parse(string(row['fetched_at'])));
      }
      // Keep all identities and aliases, including newly watched episodes.
      for (final row in objects(backup['catalog_titles'])) {
        await db.customStatement(
          'UPDATE catalog_titles SET data=? WHERE type=? AND local_id=?',
          [row['data'], row['type'], row['local_id']],
        );
      }
      for (final row in objects(backup['library'])) {
        await db.customStatement(
          'UPDATE library SET data=?,updated_at=? WHERE key=?',
          [row['data'], row['updated_at'], row['key']],
        );
      }
      if (before != await _userState()) {
        throw StateError('Rollback changed user data');
      }
      final provider = objects(backup['content_state']).single['provider'];
      await db.customStatement(
        'UPDATE content_state SET provider=?,generation=?,deployment_id=? WHERE singleton=1',
        [provider, generation, 'rollback:$deploymentId'],
      );
      await db.customStatement(
        "UPDATE admin_migrations SET status='rolled_back' WHERE id=?",
        [deploymentId],
      );
    });
    await router.reloadCommitted();
  }
}
