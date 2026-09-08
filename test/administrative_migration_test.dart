import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/admin_migration.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';
import 'package:next_episode/data/catalog/content_configuration.dart';
import 'package:next_episode/data/catalog/internal_catalog.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/domain/models.dart';

class ReacherProvider extends CatalogProvider {
  @override
  final String id;
  final int offset;
  bool found = true, ambiguous = false, fail = false, external = true;
  bool missing = false, renumber = false, extra = false, conflict = false;
  int fetches = 0;
  ReacherProvider(this.id, this.offset);
  @override
  String get label => id;
  @override
  CatalogCapabilities get capabilities => const CatalogCapabilities(
    movies: true,
    localizedText: true,
    paginatedSearch: false,
  );
  TitleData show([int? remote]) => TitleData(MediaType.tv, {
    'id': remote ?? offset,
    'source_id': remote ?? offset,
    'provider': id,
    'name': 'Reacher',
    'original_name': 'Reacher',
    'first_air_date': '2022-02-04',
    'origin_country': ['US'],
    'networks': [
      {'name': 'Prime Video'},
    ],
    'overview': 'Description from $id',
    'external_ids': external
        ? {'imdb_id': 'tt9288030', 'tvdb_id': conflict ? 'wrong' : '366924'}
        : {},
    'seasons': [
      for (var s = 1; s <= 4; s++)
        {'id': offset + s, 'season_number': renumber && s == 4 ? 5 : s},
    ],
  });
  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async =>
      SearchPage([if (found) show(), if (ambiguous) show(offset + 1)], 1, 1);
  @override
  Future<TitleData> title(MediaType type, int id) async => show(id);
  @override
  Future<TitleData?> lookup(
    MediaType type,
    Map<String, String> externalIds,
  ) async => found ? show() : null;
  @override
  Future<SeasonData> season(int id, int number) async {
    fetches++;
    if (fail) throw const ApiFailure('Offline');
    return SeasonData(offset, {
      'id': offset + number,
      'season_number': number,
      'episodes': [
        for (var e = 1; e <= (extra && number == 4 ? 9 : 8); e++)
          if (!(missing && number == 2 && e == 3))
            {
              'id': offset * 100 + number * 10 + e,
              'season_number': number,
              'episode_number': e,
              'name': '$id translated episode $e',
              'air_date': e == 9
                  ? '2099-01-01'
                  : (this.id == 'tmdb' ? '2024-02-02' : '2024-01-01'),
            },
      ],
    });
  }
}

class Manifest extends ContentConfigurationSource {
  ContentRelease? release;
  bool fail = false;
  int readyCount = 0;
  @override
  Future<ContentRelease?> fetch() async {
    if (fail) throw StateError('offline');
    return release;
  }

  @override
  Future<void> ready(AdministrativeReport report) async {
    readyCount++;
  }
}

void main() {
  late AppDatabase db;
  late ReacherProvider tvmaze, tmdb;
  late CatalogRouter router;
  late AdminMigration admin;
  final date = DateTime(2026, 9, 8);
  Future<SeriesBundle> seed() async {
    final title = (await router.search('Reacher', null, 1)).results.single;
    final bundle = await router.series(title.id);
    await db.add(bundle.title, date);
    for (final e in bundle.episodes.take(5)) {
      await db.mark(e.key, true, date);
    }
    await db.setPreference('library.sort', 'Title');
    return bundle;
  }

  Future<String> userState() async => jsonEncode({
    'library': (await db.library())
        .map((e) => [e.title.key, e.addedAt.toIso8601String()])
        .toList(),
    'watched': (await db.watched()).map(
      (k, v) => MapEntry(k, v.toIso8601String()),
    ),
    'preferences': (await db.customSelect('SELECT * FROM preferences').get())
        .map((e) => e.data)
        .toList(),
    'history': (await db.customSelect('SELECT * FROM user_history').get())
        .map((e) => e.data)
        .toList(),
  });
  Future<AdministrativeReport> prepare() =>
      admin.prepare(deploymentId: 'switch', target: 'tmdb', generation: 1);
  setUp(() {
    db = AppDatabase.memory();
    tvmaze = ReacherProvider('tvmaze', 42);
    tmdb = ReacherProvider('tmdb', 108978);
    router = CatalogRouter(
      db: db,
      modules: {'tvmaze': tvmaze, 'tmdb': tmdb},
      active: 'tvmaze',
    );
    admin = AdminMigration(router);
  });
  tearDown(() => db.close());

  test('Reacher: 4 seasons, 5 watched, all internal IDs, progress, history and preferences survive TVmaze to TMDB', () async {
    final old = await seed();
    final before = await userState();
    final progress = WatchProgress.calculate(old, await db.watched(), date);
    expect((await prepare()).status, 'prepared');
    expect(router.active, 'tvmaze');
    expect(
      (await InternalCatalog(db).cached(old.title.id))!.title.provider,
      'tvmaze',
    );
    expect((await admin.activate('switch')).status, 'committed');
    final fresh = (await InternalCatalog(db).cached(old.title.id))!;
    expect(await userState(), before);
    expect((await db.library()).single.title.title, 'Reacher');
    expect(fresh.seasons, hasLength(4));
    expect(fresh.title.id, old.title.id);
    expect(fresh.seasons.map((s) => s.id), old.seasons.map((s) => s.id));
    expect(fresh.episodes.map((e) => e.key), old.episodes.map((e) => e.key));
    expect(
      fresh.episodes.map((e) => e.logicalKey),
      old.episodes.map((e) => e.logicalKey),
    );
    expect(
      WatchProgress.calculate(fresh, await db.watched(), date).fraction,
      progress.fraction,
    );
    expect(await db.watched(), hasLength(5));
    expect(fresh.title.raw['overview'], 'Description from tmdb');
    expect(fresh.title.sourceId, 108978);
    final links = await db.customSelect('SELECT * FROM entity_links').get();
    expect(links, hasLength((1 + 4 + 32) * 2));
    expect(
      links.every(
        (r) =>
            r.read<double>('match_confidence') == 1 &&
            r.read<String>('last_verified_at').isNotEmpty,
      ),
      isTrue,
    );
    expect(
      (await db.customSelect('SELECT * FROM catalog_refs').get())
          .map((r) => r.read<int>('remote_id'))
          .toSet(),
      {42, 108978},
    );
    expect(
      (await router.search('Reacher', null, 1)).results.single.id,
      old.title.id,
    );
    await admin.activate('switch');
    expect(await userState(), before);
  });

  for (final scenario in [
    'not_found',
    'ambiguous_title',
    'missing_episode',
    'renumbered_season',
    'external_conflict',
  ]) {
    test(
      '$scenario preserves cache and user data and records administrative review',
      () async {
        if (scenario == 'ambiguous_title') {
          tvmaze.external = false;
          tmdb.external = false;
          tmdb.ambiguous = true;
        }
        final old = await seed();
        final before = await userState();
        if (scenario == 'not_found') tmdb.found = false;
        if (scenario == 'missing_episode') tmdb.missing = true;
        if (scenario == 'renumbered_season') tmdb.renumber = true;
        if (scenario == 'external_conflict') tmdb.conflict = true;
        final report = await prepare();
        expect(report.items.single['status'], 'review');
        expect(
          (await admin.activate('switch')).status,
          'committed_with_review',
        );
        expect(
          (await InternalCatalog(db).cached(old.title.id))!.toJson(),
          old.toJson(),
        );
        expect(await userState(), before);
        expect(
          await db
              .customSelect("SELECT * FROM episode_refs WHERE provider='tmdb'")
              .get(),
          isEmpty,
        );
      },
    );
  }

  test('unique original title/year/country/network fallback has explicit confidence', () async {
    tvmaze.external = false;
    tmdb.external = false;
    await seed();
    expect((await prepare()).items.single['confidence'], 0.9);
    await admin.activate('switch');
    expect(router.active, 'tmdb');
  });
  test(
    'new future episode is added without changing existing progress',
    () async {
      final old = await seed();
      final before = await userState();
      tmdb.extra = true;
      await prepare();
      await admin.activate('switch');
      final fresh = (await InternalCatalog(db).cached(old.title.id))!;
      expect(fresh.episodes, hasLength(33));
      expect(await userState(), before);
      expect(
        WatchProgress.calculate(fresh, await db.watched(), date).fraction,
        5 / 32,
      );
    },
  );
  test('interrupted preparation resumes and reuses completed items', () async {
    await seed();
    final before = await userState();
    await expectLater(
      admin.prepare(
        deploymentId: 'switch',
        target: 'tmdb',
        generation: 1,
        afterItem: (_) async => throw StateError('interrupted'),
      ),
      throwsStateError,
    );
    expect(router.active, 'tvmaze');
    expect(await userState(), before);
    final calls = tmdb.fetches;
    await prepare();
    expect(tmdb.fetches, calls);
    await admin.activate('switch');
    expect(await userState(), before);
  });
  test('interrupted activation rolls back metadata, mappings and pointer; retry is atomic', () async {
    final old = await seed();
    final before = await userState();
    await prepare();
    await expectLater(
      admin.activate(
        'switch',
        afterWrite: (_) async => throw StateError('crash'),
      ),
      throwsStateError,
    );
    expect(router.active, 'tvmaze');
    expect(
      (await InternalCatalog(db).cached(old.title.id))!.toJson(),
      old.toJson(),
    );
    expect(
      await db
          .customSelect("SELECT * FROM entity_links WHERE provider='tmdb'")
          .get(),
      isEmpty,
    );
    await admin.activate('switch');
    expect(await userState(), before);
  });
  test(
    'offline destination blocks activation and resumes after recovery',
    () async {
      await seed();
      tmdb.fail = true;
      expect((await prepare()).status, 'pending');
      await expectLater(admin.activate('switch'), throwsStateError);
      expect(router.active, 'tvmaze');
      tmdb.fail = false;
      await prepare();
      await admin.activate('switch');
      expect(router.active, 'tmdb');
    },
  );
  test('rollback retains subsequent watched/unwatched history and both provider mappings', () async {
    final old = await seed();
    tmdb.extra = true;
    await prepare();
    await admin.activate('switch');
    final fresh = (await InternalCatalog(db).cached(old.title.id))!;
    await db.mark(old.episodes.first.key, false, date);
    await db.mark(fresh.episodes.last.key, true, date);
    await db.setPreference('library.sort', 'Progress');
    final before = await userState();
    await admin.rollback('switch', generation: 2);
    expect(router.active, 'tvmaze');
    expect(await userState(), before);
    expect(
      (await InternalCatalog(db).cached(old.title.id))!.episodes
          .map((e) => e.key),
      contains(fresh.episodes.last.key),
    );
    expect(
      await db.customSelect('SELECT * FROM catalog_refs').get(),
      hasLength(2),
    );
  });
  test('prepared global configuration waits for commit; offline and stale manifests retain active revision', () async {
    await seed();
    final source = Manifest()
      ..release = const ContentRelease('tmdb', 'switch', 1, phase: 'prepared');
    final coordinator = ContentCoordinator(router, source);
    await coordinator.refresh();
    expect(router.active, 'tvmaze');
    expect(source.readyCount, 1);
    source.release = const ContentRelease('tmdb', 'switch', 1);
    await coordinator.refresh();
    expect(router.active, 'tmdb');
    source.release = const ContentRelease('tvmaze', 'stale', 1);
    await coordinator.refresh();
    expect(router.active, 'tmdb');
    source.fail = true;
    await coordinator.refresh();
    expect(router.active, 'tmdb');
  });
  test(
    'one unresolved title does not prevent the other title from migrating',
    () async {
      final old = await seed();
      await db.add(
        TitleData(MediaType.tv, {
          'id': 200,
          'provider': 'tvmaze',
          'source_id': 200,
          'name': 'Unknown',
          'external_ids': {'imdb_id': 'ttUnknown'},
        }),
        date,
      );
      final before = await userState();
      final report = await prepare();
      expect(report.items.map((e) => e['status']).toSet(), {'ready', 'review'});
      expect((await admin.activate('switch')).status, 'committed_with_review');
      expect(
        (await InternalCatalog(db).cached(old.title.id))!.title.provider,
        'tmdb',
      );
      expect(await userState(), before);
    },
  );
  test(
    'staged migration survives database close and resumes with a new router',
    () async {
      await db.close();
      final dir = await Directory.systemTemp.createTemp('next_episode_admin_');
      final file = File('${dir.path}/test.sqlite');
      db = AppDatabase.file(file);
      router = CatalogRouter(
        db: db,
        modules: {'tvmaze': tvmaze, 'tmdb': tmdb},
        active: 'tvmaze',
      );
      admin = AdminMigration(router);
      await seed();
      final before = await userState();
      await expectLater(
        admin.prepare(
          deploymentId: 'switch',
          target: 'tmdb',
          generation: 1,
          afterItem: (_) async => throw StateError('interrupted'),
        ),
        throwsStateError,
      );
      await db.close();
      db = AppDatabase.file(file);
      router = CatalogRouter(
        db: db,
        modules: {'tvmaze': tvmaze, 'tmdb': tmdb},
        active: 'tmdb',
      );
      admin = AdminMigration(router);
      await router.initialize();
      expect(router.active, 'tvmaze');
      await prepare();
      await admin.activate('switch');
      expect(await userState(), before);
      await db.close();
      db = AppDatabase.memory();
      await dir.delete(recursive: true);
    },
  );
  test(
    'configuration rejects per-user rollout fields and malformed revisions',
    () {
      expect(
        () => ContentRelease.fromJson({
          'provider': 'tmdb',
          'deploymentId': 'one',
          'generation': 2,
          'phase': 'committed',
          'percentage': 10,
        }),
        throwsFormatException,
      );
      expect(
        () => ContentRelease.fromJson({
          'provider': 'tmdb',
          'deploymentId': 'one',
          'generation': 0,
          'phase': 'committed',
        }),
        throwsFormatException,
      );
      expect(
        () => RemoteContentConfiguration('http://example.test/release'),
        throwsArgumentError,
      );
    },
  );
  test(
    'an orphaned watched identity is retained for administrative review',
    () async {
      final old = await seed();
      await db.mark('episode:${old.title.id}:9999', true, date);
      final before = await userState();
      expect(
        (await prepare()).items.single['code'],
        'missing_internal_episode',
      );
      await admin.activate('switch');
      expect(await userState(), before);
      expect(
        (await InternalCatalog(db).cached(old.title.id))!.toJson(),
        old.toJson(),
      );
    },
  );
}
