import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/alerts.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/domain/models.dart';
import 'package:drift/native.dart';

import 'startup_performance_test.dart' show LibraryApi, seed, show;

class CountingDatabase extends AppDatabase {
  CountingDatabase() : super(NativeDatabase.memory());
  int catalogReads = 0;
  int libraryReads = 0;
  Completer<void>? decodeStarted;
  Completer<void>? releaseDecode;
  @override
  Future<Map<int, SeriesBundle>> cachedLibrarySeries({Set<int>? ids}) async {
    catalogReads++;
    final result = await super.cachedLibrarySeries(ids: ids);
    decodeStarted?.complete();
    await releaseDecode?.future;
    return result;
  }

  @override
  Future<List<LibraryEntry>> library() {
    libraryReads++;
    return super.library();
  }
}

class SlowAlerts extends EpisodeAlerts {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> refresh(
    AppDatabase db,
    Iterable<SeriesBundle> series,
    Map<String, DateTime> watched,
  ) async {
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

class SlowSyncApi extends LibraryApi {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<SeriesBundle> series(int id) async {
    started.complete();
    await release.future;
    return super.series(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('marking 80 episodes in a 210-show library reuses catalog and original timestamps', () async {
    final db = CountingDatabase();
    final api = LibraryApi();
    final now = DateTime.now();
    await db.transaction(() async {
      for (var id = 1; id <= 210; id++) {
        await seed(db, show(id), now);
      }
    });
    final originalTime = now.subtract(const Duration(days: 1));
    await db.mark('episode:1:101', true, originalTime);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiProvider.overrideWithValue(api),
      ],
    );
    final before = await container.read(libraryProvider.future);
    final unchangedProgress = before.progress(2);
    final reads = (db.catalogReads, db.libraryReads);
    final timer = Stopwatch()..start();
    await container
        .read(libraryProvider.notifier)
        .markEpisodesSeen(before.series[1]!.episodes);
    timer.stop();
    // Benchmark output is intentional; correctness assertions avoid timing limits.
    // ignore: avoid_print
    print(
      'Mark 80 / 210 shows: ${timer.elapsedMilliseconds}ms; catalog reads: ${db.catalogReads - reads.$1}; library reads: ${db.libraryReads - reads.$2}',
    );
    final after = container.read(libraryProvider).requireValue;
    expect(after.watched.length, 80);
    expect(after.watched['episode:1:101'], originalTime);
    expect(api.fetched, isEmpty);
    expect(identical(after.progress(2), unchangedProgress), true);
    container.dispose();
    await db.close();
    expect(db.catalogReads, reads.$1);
    expect(db.libraryReads, reads.$2);
    expect(identical(before.series, after.series), true);
  });

  test(
    'batch history is idempotent, atomic and preserves existing marked dates',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 1));
      await db.mark('episode:1:101', true, old);
      await db.markMany(
        ['episode:1:101', 'episode:1:102', 'episode:1:102'],
        true,
        now,
      );
      expect((await db.watched())['episode:1:101'], old);
      expect(
        (await db.customSelect('SELECT * FROM user_history').get()).length,
        2,
      );
      await db.markMany(
        ['episode:1:101', 'episode:1:101', 'episode:1:999'],
        false,
        now,
      );
      expect((await db.watched()).keys, ['episode:1:102']);
      expect(
        (await db.customSelect('SELECT * FROM user_history').get()).length,
        3,
      );
      await expectLater(
        db.transaction(() async {
          await db.markMany(['episode:1:102', 'episode:1:103'], false, now);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect((await db.watched()).keys, ['episode:1:102']);
      expect(
        (await db.customSelect('SELECT * FROM user_history').get()).length,
        3,
      );
      final items = show(1).episodes;
      final future = EpisodeData(1, 100, {
        ...items.last.raw,
        'air_date': now.add(const Duration(days: 5)).toIso8601String(),
      });
      await expectLater(
        ProgressRepository(db).episodes([items.first, future], true),
        throwsA(isA<ApiFailure>()),
      );
      expect((await db.watched()).keys, ['episode:1:102']);
    },
  );

  test('progress is visible before alerts finish and survives an older metadata reload', () async {
    final db = CountingDatabase();
    final alerts = SlowAlerts();
    await seed(db, show(1), DateTime.now());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiProvider.overrideWithValue(LibraryApi()),
        episodeAlertsProvider.overrideWithValue(alerts),
      ],
    );
    final before = await container.read(libraryProvider.future);
    final controller = container.read(libraryProvider.notifier);
    db.decodeStarted = Completer<void>();
    db.releaseDecode = Completer<void>();
    final loading = controller.reload();
    await db.decodeStarted!.future;
    final marking = controller.markEpisodesSeen(before.series[1]!.episodes);
    await alerts.started.future;
    expect(container.read(libraryProvider).requireValue.watched.length, 80);
    db.releaseDecode!.complete();
    alerts.release.complete();
    await Future.wait([loading, marking]);
    expect(container.read(libraryProvider).requireValue.watched.length, 80);
    await controller.markSeason(before.series[1]!.seasons.first, false);
    expect(container.read(libraryProvider).requireValue.watched, isEmpty);
    await controller.markMovie(10, true);
    expect(
      container
          .read(libraryProvider)
          .requireValue
          .watched
          .containsKey('movie:10'),
      true,
    );
    container.dispose();
    await db.close();
  });

  test(
    'marking remains available during a pending startup network refresh',
    () async {
      final db = AppDatabase.memory();
      final api = SlowSyncApi();
      api.shows[1] = show(1);
      await seed(
        db,
        show(1),
        DateTime.now().subtract(const Duration(hours: 8)),
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          apiProvider.overrideWithValue(api),
        ],
      );
      final before = await container.read(libraryProvider.future);
      final controller = container.read(libraryProvider.notifier);
      final syncing = controller.sync(onlyStale: true);
      await api.started.future;
      await controller.markEpisodesSeen(before.series[1]!.episodes);
      expect(container.read(libraryProvider).requireValue.watched.length, 80);
      api.release.complete();
      await syncing;
      expect(container.read(libraryProvider).requireValue.watched.length, 80);
      container.dispose();
      await db.close();
    },
  );
}
