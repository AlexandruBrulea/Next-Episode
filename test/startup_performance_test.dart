import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/domain/models.dart';

import 'fixtures.dart';

class LibraryApi extends FakeApi {
  final fetched = <int>[];
  final shows = <int, SeriesBundle>{};
  @override
  Future<SeriesBundle> series(int id) async {
    fetched.add(id);
    return shows[id]!;
  }
}

SeriesBundle show(int id, {String status = 'Returning Series'}) {
  return SeriesBundle(
    TitleData(MediaType.tv, {
      ...tv(status: status).raw,
      'id': id,
      'provider': 'tmdb',
    }),
    [
      SeasonData(id, {
        'id': id * 100,
        'season_number': 1,
        'episodes': [
          for (var n = 1; n <= 80; n++) episodeJson(id * 100 + n, n),
        ],
      }),
    ],
  );
}

Future<void> seed(AppDatabase db, SeriesBundle bundle, DateTime updated) async {
  await db.add(bundle.title, updated);
  await db.cache('series:${bundle.title.id}', bundle.toJson(), updated);
  await db.updateTitle(bundle.title, updated);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('partial refresh reuses unchanged bundles; external disable clears visible content', () async {
    final db = AppDatabase.memory();
    final api = LibraryApi();
    final instant = DateTime.now();
    for (var id = 1; id <= 2; id++) {
      api.shows[id] = show(id);
      await seed(
        db,
        api.shows[id]!,
        instant.subtract(Duration(hours: id == 1 ? 7 : 1)),
      );
    }
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiProvider.overrideWithValue(api),
      ],
    );
    final first = await container.read(libraryProvider.future);
    final controller = container.read(libraryProvider.notifier);
    await controller.sync(onlyStale: true);
    final refreshed = container.read(libraryProvider).requireValue;
    expect(api.fetched, [1]);
    expect(identical(first.series[2], refreshed.series[2]), true);
    expect(identical(first.series[1], refreshed.series[1]), false);
    await db.setTmdbContentEnabled(false, 1);
    await controller.sync(onlyStale: true);
    final disabled = container.read(libraryProvider).requireValue;
    expect(disabled.series, isEmpty);
    expect(
      disabled.entries.every((e) => e.title.raw['content_unavailable'] == true),
      true,
    );
    container.dispose();
    await db.close();
  });
  test('210 fresh shows: startup sync makes no network calls or snapshot replacement', () async {
    final db = AppDatabase.memory();
    final api = LibraryApi();
    final instant = DateTime.now();
    await db.transaction(() async {
      for (var id = 1; id <= 210; id++) {
        final bundle = show(id);
        api.shows[id] = bundle;
        await seed(db, bundle, instant);
      }
    });
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiProvider.overrideWithValue(api),
      ],
    );
    final first = await container.read(libraryProvider.future);
    expect(first.series.length, 210);
    expect(
      first.series.values.fold<int>(0, (n, b) => n + b.episodes.length),
      16800,
    );
    final report = await container
        .read(libraryProvider.notifier)
        .sync(onlyStale: true);
    expect(report.refreshedKeys, isEmpty);
    expect(api.fetched, isEmpty);
    expect(
      identical(container.read(libraryProvider).requireValue, first),
      isTrue,
    );
    container.dispose();
    await db.close();
  });

  test('active 6h, ended 7d, missing cache and forced refresh preserve watched dates', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final api = LibraryApi();
    final instant = DateTime.now();
    for (var id = 1; id <= 5; id++) {
      final bundle = show(
        id,
        status: id == 3 || id == 4 ? 'Ended' : 'Returning Series',
      );
      api.shows[id] = bundle;
      await seed(
        db,
        bundle,
        instant.subtract(switch (id) {
          1 => const Duration(hours: 1),
          2 => const Duration(hours: 7),
          3 => const Duration(days: 1),
          4 => const Duration(days: 8),
          _ => Duration.zero,
        }),
      );
    }
    await db.customStatement("DELETE FROM cache WHERE key='series:5'");
    await db.mark('episode:2:201', true, instant);
    final sync = SyncRepository(
      db,
      SeriesRepository(api, db),
      MoviesRepository(api, db),
    );
    await sync.refresh(onlyStale: true);
    expect(api.fetched.toSet(), {2, 4, 5});
    expect((await db.watched())['episode:2:201'], instant);
    api.fetched.clear();
    await sync.refresh(onlyStale: true);
    expect(api.fetched, isEmpty);
    await sync.refresh();
    expect(api.fetched.toSet(), {1, 2, 3, 4, 5});
  });

  test('file database decodes bundles on worker and respects expiry', () async {
    final dir = await Directory.systemTemp.createTemp('next-episode-perf-');
    final db = AppDatabase.file(File('${dir.path}/library.sqlite'));
    try {
      final instant = DateTime.utc(2026, 1, 1);
      db.retentionClock = () => instant;
      await seed(db, show(1), instant);
      expect((await db.cachedLibrarySeries()).keys, [1]);
      db.retentionClock = () => DateTime.utc(2026, 7, 1);
      expect(await db.cachedLibrarySeries(), isEmpty);
      await db.enforceTmdbRetention();
      expect(
        (await db.library()).single.title.raw['content_unavailable'],
        true,
      );
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test(
    'retention memo handles writes, clock advance and rolled-back purge',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      var clock = DateTime.utc(2026, 1, 1);
      db.retentionClock = () => clock;
      await seed(db, show(1), clock);
      await db.enforceTmdbRetention();
      expect(await db.enforceTmdbRetention(), false);
      clock = DateTime.utc(2026, 7, 1);
      await expectLater(
        db.transaction(() async {
          expect(await db.enforceTmdbRetention(), true);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await db.enforceTmdbRetention(), true);
      expect(await db.cached('series:1'), isNull);
      await seed(db, show(2), clock);
      await db.setTmdbContentEnabled(false, 10);
      expect(await db.cached('series:2'), isNull);
    },
  );
}
