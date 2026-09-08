import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/domain/catalog_provider.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());
  test(
    'library add/remove prevents duplicates and preserves same ID across types',
    () async {
      final library = LibraryRepository(db);
      await library.add(tv());
      await library.add(tv());
      await library.add(movie());
      expect((await library.all()).length, 2);
      await library.remove(tv().key);
      expect((await library.all()).single.title.key, 'movie:10');
    },
  );
  test('watch/unwatch timestamps and removal retain progress', () async {
    final p = ProgressRepository(db);
    final e = bundle().episodes.first;
    await db.add(tv(), now);
    await p.episode(e, true, now: now);
    await p.episode(e, true, now: now.add(const Duration(days: 1)));
    expect((await p.all())[e.key], now);
    await db.remove(tv().key);
    await db.add(tv(), now);
    expect((await p.all())[e.key], now);
    await p.episode(e, false);
    expect(await p.all(), isEmpty);
    await p.movie(10, true);
    expect((await p.all()).containsKey('movie:10'), isTrue);
    await p.movie(10, false);
    expect(await p.all(), isEmpty);
  });
  test(
    'bulk season marking excludes future/undated and is reversible',
    () async {
      final p = ProgressRepository(db);
      await p.season(bundle().seasons.first, true, now: now);
      expect((await p.all()).keys.toSet(), {'episode:10:1', 'episode:10:2'});
      await expectLater(
        p.episode(bundle().episodes[2], true, now: now),
        throwsA(isA<ApiFailure>()),
      );
      await p.season(bundle().seasons.first, false, now: now);
      expect(await p.all(), isEmpty);
    },
  );
  test('transaction rollback does not leave partial data', () async {
    await expectLater(
      db.transaction(() async {
        await db.add(tv(), now);
        throw StateError('failed');
      }),
      throwsStateError,
    );
    expect(await db.library(), isEmpty);
  });
  test('file persistence survives actual connection restart', () async {
    await db.close();
    final directory = await Directory.systemTemp.createTemp(
      'next_episode_test_',
    );
    final file = File('${directory.path}/test.sqlite');
    var persistent = AppDatabase.file(file);
    try {
      await persistent.add(tv(), now);
      await persistent.mark('episode:10:1', true, now);
      await persistent.cache('series:10', bundle().toJson(), now);
      await persistent.setPreference('library.sort', 'Title');
      await persistent.close();
      persistent = AppDatabase.file(file);
      expect((await persistent.library()).single.title.id, 10);
      expect((await persistent.watched())['episode:10:1'], now);
      expect(
        (await persistent.cached('series:10'))!.data['title']['name'],
        'Serial test',
      );
      expect(await persistent.preference('library.sort'), 'Title');
    } finally {
      await persistent.close();
      await directory.delete(recursive: true);
    }
  });
  test(
    'sync changes metadata without losing watched and logs changes',
    () async {
      final api = FakeApi();
      final series = SeriesRepository(api, db);
      await db.add(tv(), now);
      await series.save(bundle(), now);
      await db.mark('episode:10:1', true, now);
      api.value = bundle(
        episodes: [
          episodeJson(1, 1, name: 'Actualizat'),
          episodeJson(8, 2),
        ],
      );
      final sync = SyncRepository(db, series, MoviesRepository(api, db));
      final report = await sync.refresh();
      expect(report.errors, isEmpty);
      expect(report.changes.single.newEpisodes, [8]);
      expect((await db.watched())['episode:10:1'], now);
      expect((await series.cached(10))!.episodes.first.title, 'Actualizat');
      expect((await db.library()).single.updatedAt, isNotNull);
      expect(
        await db.customSelect('SELECT * FROM sync_events').get(),
        hasLength(1),
      );
    },
  );
  test(
    'failed sync retains full snapshot and cached details work offline',
    () async {
      final api = FakeApi();
      final series = SeriesRepository(api, db);
      await db.add(tv(), now);
      await series.save(bundle(), now);
      api.fail = true;
      final report = await SyncRepository(
        db,
        series,
        MoviesRepository(api, db),
      ).refresh();
      expect(report.errors, hasLength(1));
      expect((await series.cached(10))!.episodes, hasLength(5));
      expect((await series.load(10, refresh: true)).offline, isTrue);
      expect((await db.library()).single.updatedAt, now);
    },
  );
}
