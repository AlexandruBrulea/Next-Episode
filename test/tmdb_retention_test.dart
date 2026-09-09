import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/tmdb_retention.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';
import 'package:next_episode/data/catalog/content_configuration.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/domain/models.dart';

import 'catalog_router_test.dart' show CatalogFixture;

class DelayedTmdb extends CatalogFixture {
  DelayedTmdb() : super('tmdb', 99, 9001);
  bool delay = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<SeriesBundle> series(int id) async {
    final result = await super.series(id);
    if (delay) {
      started.complete();
      await release.future;
    }
    return result;
  }
}

void main() {
  test('a late response after disable cannot restore or return the old offline cache', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final provider = DelayedTmdb();
    final router = CatalogRouter(db: db, modules: {'tmdb': provider}, active: 'tmdb');
    final title = (await router.search('show', null, 1)).results.single;
    await router.series(title.id);
    provider.delay = true;
    final result = SeriesRepository(router, db).load(title.id, refresh: true);
    await provider.started.future;
    await db.setTmdbContentEnabled(false, 1);
    final rejected = expectLater(result, throwsStateError);
    provider.release.complete();
    await rejected;
    expect(await db.cached('series:${title.id}'), isNull);
  });

  test('reading and copying metadata does not extend the original expiration', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final obtained = DateTime.utc(2026, 1, 31);
    var clock = obtained;
    db.retentionClock = () => clock;
    await db.cache('movie:1', {'id': 1, 'provider': 'tmdb', 'title': 'Old'}, obtained);
    clock = DateTime.utc(2026, 7, 30);
    final original = (await db.cached('movie:1'))!.data;
    await db.cache('movie:2', {...original, 'id': 2}, clock);
    clock = DateTime.utc(2026, 7, 31);
    expect(await db.cached('movie:1'), isNull);
    expect(await db.cached('movie:2'), isNull);
  });

  test('prepared shutdown is ignored and normal offline errors preserve fresh cache', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final provider = CatalogFixture('tmdb', 99, 9001);
    final router = CatalogRouter(db: db, modules: {'tmdb': provider}, active: 'tmdb');
    final title = (await router.search('show', null, 1)).results.single;
    await router.series(title.id);
    provider.fail = true;
    await ContentCoordinator(router, FixedContentConfiguration(const ContentRelease(
      'tmdb', 'prepare-disable', 2, phase: 'prepared', tmdbContentEnabled: false))).refresh();
    expect(await db.tmdbContentAllowed(), true);
    final result = await SeriesRepository(router, db).load(title.id, refresh: true);
    expect(result.offline, true);
    expect(result.value.title.title, 'Same show');
  });
  test('six calendar months clamp correctly including leap years', () {
    expect(tmdbExpiry(DateTime.utc(2023, 8, 31)), DateTime.utc(2024, 2, 29));
    expect(tmdbExpiry(DateTime.utc(2024, 8, 31)), DateTime.utc(2025, 2, 28));
  });

  test('expiry purges descriptive copies, preserves selections and watched slots, refetch restores progress', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var clock = DateTime.now().toUtc();
    db.retentionClock = () => clock;
    final tmdb = CatalogFixture('tmdb', 99, 9001);
    final maze = CatalogFixture('tvmaze', 42, 101);
    final router = CatalogRouter(
      db: db,
      modules: {'tmdb': tmdb, 'tvmaze': maze},
      active: 'tmdb',
    );
    final selected = (await router.search('show', null, 1)).results.single;
    final loaded = await router.series(selected.id);
    await db.add(loaded.title, clock);
    final episodeKey = loaded.episodes.single.key;
    await db.mark(episodeKey, true, clock);
    await db.setPreference('alerts', 'unchanged');
    final mazeTitle = TitleData(MediaType.tv, {...maze.show.raw, 'id': 50});
    await db.add(mazeTitle, clock);
    final beforeMaze = (await db.library())
        .firstWhere((e) => e.title.id == 50)
        .title
        .raw;
    clock = tmdbExpiry(clock).add(const Duration(days: 1));
    final library = await db.library();
    expect(library.length, 2);
    expect(
      library
          .firstWhere((e) => e.title.id == selected.id)
          .title
          .raw['content_unavailable'],
      true,
    );
    expect(library.firstWhere((e) => e.title.id == 50).title.raw, beforeMaze);
    expect(await db.cached('series:${selected.id}'), isNull);
    expect((await db.watched()).containsKey(episodeKey), true);
    expect(await db.preference('alerts'), 'unchanged');
    // A new fetch at the advanced clock restores the same logical episode.
    final fresh = await router.series(selected.id);
    expect(fresh.episodes.single.key, episodeKey);
    expect(
      (await db.library())
          .firstWhere((e) => e.title.id == selected.id)
          .title
          .title,
      'Same show',
    );
    expect((await db.watched()).containsKey(episodeKey), true);
  });

  test('cache of removed title expires; an offline load cannot return expired details', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var clock = DateTime.now().toUtc();
    db.retentionClock = () => clock;
    final provider = CatalogFixture('tmdb', 99, 9001);
    final router = CatalogRouter(
      db: db,
      modules: {'tmdb': provider},
      active: 'tmdb',
    );
    final title = (await router.search('show', null, 1)).results.single;
    final bundle = await router.series(title.id);
    await db.add(bundle.title, clock);
    await db.remove(title.key);
    clock = tmdbExpiry(clock).add(const Duration(days: 1));
    provider.fail = true;
    await expectLater(
      SeriesRepository(router, db).load(title.id),
      throwsA(anything),
    );
    expect(await db.cached('series:${title.id}'), isNull);
    expect(await db.library(), isEmpty);
  });

  test(
    'explicit committed disable is sticky and prevents reads and late writes',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final provider = CatalogFixture('tmdb', 99, 9001);
      final router = CatalogRouter(
        db: db,
        modules: {'tmdb': provider},
        active: 'tmdb',
      );
      final title = (await router.search('show', null, 1)).results.single;
      final bundle = await router.series(title.id);
      await db.add(bundle.title, DateTime.now());
      await db.mark(bundle.episodes.single.key, true, DateTime.now());
      await ContentCoordinator(
        router,
        FixedContentConfiguration(
          const ContentRelease('tmdb', 'disable', 5, tmdbContentEnabled: false),
        ),
      ).refresh();
      expect(await db.tmdbContentAllowed(), false);
      expect(await db.cached('series:${title.id}'), isNull);
      await expectLater(router.search('show', null, 1), throwsStateError);
      await expectLater(
        db.cache('series:${title.id}', bundle.toJson(), DateTime.now()),
        throwsStateError,
      );
      expect(await db.setTmdbContentEnabled(true, 4), false);
      expect((await db.watched()).length, 1);
      expect((await db.library()).length, 1);
      expect(await db.setTmdbContentEnabled(true, 6), true);
      expect(await db.tmdbContentAllowed(), true);
    },
  );

  test('migration backups cannot resurrect expired embedded JSON', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final old = DateTime.utc(2020);
    final raw = {
      'id': 5,
      'provider': 'tmdb',
      'name': 'Secret metadata',
      tmdbObtainedKey: old.toIso8601String(),
    };
    await db.customStatement(
      'INSERT INTO admin_migrations VALUES (?,?,?,?,?,?,?,?)',
      [
        'old',
        'tvmaze',
        1,
        'committed',
        '{}',
        jsonEncode({
          'catalog_titles': [
            {'type': 'tv', 'local_id': 5, 'data': jsonEncode(raw)},
          ],
        }),
        '[]',
        DateTime.now().toIso8601String(),
      ],
    );
    await db.enforceTmdbRetention();
    final row = await db
        .customSelect("SELECT * FROM admin_migrations WHERE id='old'")
        .getSingle();
    expect(row.read<String>('backup'), '{}');
    expect(row.read<String>('status'), 'retention_expired');
  });
}
