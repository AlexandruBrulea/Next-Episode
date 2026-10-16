import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/feedback.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/domain/request_diagnostic.dart';

import 'fixtures.dart';
import 'catalog_router_test.dart' show CatalogFixture;
import 'startup_performance_test.dart' show show, seed;
import 'tmdb_resilience_test.dart' show until;

class LogFailureDatabase extends AppDatabase {
  LogFailureDatabase() : super(NativeDatabase.memory());
  @override
  Future<void> administrativeConflict(String key, String detail) async {
    throw StateError('disk diagnostic failed');
  }
}

class ControlledApi extends FakeApi {
  final release = Completer<void>();
  final fetched = <int>[];
  final failures = <int>{};
  int active = 0, peak = 0;
  int status = 503;
  @override
  Future<SeriesBundle> series(int id) async {
    fetched.add(id);
    active++;
    if (active > peak) peak = active;
    try {
      await release.future;
      if (failures.contains(id)) {
        throw ApiFailure(
          'Safe failure',
          diagnostic: RequestDiagnostic(
            endpoint: '/tv/$id/season/1',
            exceptionType: 'badResponse',
            statusCode: status,
            attempts: 1,
            durationMs: 12,
            occurredAt: DateTime.utc(2026, 10, 13),
          ),
        );
      }
      return show(id);
    } finally {
      active--;
    }
  }
}

class DelayedCatalog extends CatalogFixture {
  final release = Completer<void>();
  int fetches = 0;
  DelayedCatalog() : super('tmdb', 42, 100);
  @override
  Future<SeriesBundle> series(int id) async {
    fetches++;
    await release.future;
    return super.series(id);
  }
}

class PartialSeasonCatalog extends CatalogFixture {
  bool failSecond = false;
  PartialSeasonCatalog() : super('tmdb', 42, 100);
  @override
  TitleData get show => TitleData(MediaType.tv, {
    ...super.show.raw,
    'seasons': [
      {'id': 1, 'season_number': 1},
      {'id': 2, 'season_number': 2},
    ],
  });
  @override
  Future<SeasonData> season(int id, int number) async {
    if (failSecond && number == 2) throw const ApiFailure('Season timed out');
    return SeasonData(id, {
      'id': number,
      'season_number': number,
      'episodes': [
        episodeJson(
          100 + number,
          1,
          season: number,
          name: failSecond ? 'New metadata' : 'Original',
        ),
      ],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed second season never commits the first season or alters watched dates', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final api = PartialSeasonCatalog();
    final router = CatalogRouter(
      db: db,
      modules: {'tmdb': api},
      active: 'tmdb',
    );
    final title = (await router.search('show', null, 1)).results.single;
    final saved = await router.series(title.id);
    final oldCache = jsonEncode((await db.cached('series:${title.id}'))!.data);
    final markedAt = DateTime.utc(2026, 10, 1);
    await db.mark(saved.episodes.first.key, true, markedAt);
    api.failSecond = true;
    await expectLater(router.series(title.id), throwsA(isA<ApiFailure>()));
    expect(jsonEncode((await db.cached('series:${title.id}'))!.data), oldCache);
    expect((await db.watched())[saved.episodes.first.key], markedAt);
  });

  test('bounded workers share overlapping refresh and preserve concurrently marked progress', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final api = ControlledApi();
    final date = DateTime.now().subtract(const Duration(hours: 8));
    await db.transaction(() async {
      for (var id = 1; id <= 210; id++) {
        await seed(db, show(id), date);
      }
    });
    final sync = SyncRepository(
      db,
      SeriesRepository(api, db),
      MoviesRepository(api, db),
    );
    final first = sync.refresh(onlyStale: true);
    final second = sync.refresh(onlyStale: true);
    expect(identical(first, second), isTrue);
    await until(() => api.fetched.length == 3);
    await db.mark('episode:1:101', true, date);
    api.release.complete();
    final report = await first;
    expect(report.errors, isEmpty);
    expect(report.refreshedKeys, hasLength(210));
    expect(api.fetched.toSet(), hasLength(210));
    expect(api.peak, 3);
    expect((await db.watched())['episode:1:101'], date);
  });

  test(
    'one failed title and a failed diagnostic write do not stop other titles',
    () async {
      final db = LogFailureDatabase();
      addTearDown(db.close);
      final api = ControlledApi()..failures.add(2);
      api.release.complete();
      final date = DateTime.now().subtract(const Duration(hours: 8));
      for (var id = 1; id <= 4; id++) {
        await seed(db, show(id), date);
      }
      final old = jsonEncode((await db.cached('series:2'))!.data);
      await db.mark('episode:2:201', true, date);
      final sync = SyncRepository(
        db,
        SeriesRepository(api, db),
        MoviesRepository(api, db),
      );
      final report = await sync.refresh();
      expect(report.refreshedKeys, {'tv:1', 'tv:3', 'tv:4'});
      expect(report.issues.single.diagnostic?.statusCode, 503);
      expect(report.issues.single.occurredAt, DateTime.utc(2026, 10, 13));
      expect(jsonEncode((await db.cached('series:2'))!.data), old);
      expect((await db.watched())['episode:2:201'], date);
      final issues = await FeedbackIssueStore(db).load();
      expect(issues.single.diagnostic?.endpoint, '/tv/2/season/1');
    },
  );

  test('failure cooldown skips HTTP, keeps diagnostics and marks later recovery resolved', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final api = ControlledApi()
      ..failures.add(1)
      ..status = 404;
    api.release.complete();
    var clock = DateTime.now();
    await seed(db, show(1), clock.subtract(const Duration(days: 1)));
    final sync = SyncRepository(
      db,
      SeriesRepository(api, db),
      MoviesRepository(api, db),
      now: () => clock,
    );
    await sync.refresh(onlyStale: true);
    final again = await sync.refresh(onlyStale: true);
    expect(api.fetched, [1]);
    expect(again.issues, hasLength(1));
    api.failures.clear();
    clock = clock.add(const Duration(days: 1, seconds: 1));
    expect((await sync.refresh(onlyStale: true)).errors, isEmpty);
    expect(api.fetched, [1, 1]);
    expect(
      (await FeedbackIssueStore(db).load()).single.resolvedAt,
      clock.toUtc(),
    );
  });

  for (final status in [503, 404]) {
    test(
      'failed fresh title retries after $status cooldown without refetching healthy titles',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final api = ControlledApi()
          ..failures.add(1)
          ..status = status;
        api.release.complete();
        var clock = DateTime.now();
        final originalDate = clock;
        // Ended shows have a seven-day TTL, longer than either failure cooldown.
        await seed(db, show(1, status: 'Ended'), clock);
        await seed(db, show(2, status: 'Ended'), clock);
        await db.mark('episode:1:101', true, clock);
        final sync = SyncRepository(
          db,
          SeriesRepository(api, db),
          MoviesRepository(api, db),
          now: () => clock,
        );
        await sync.refresh();
        expect(api.fetched, containsAll([1, 2]));
        expect(
          (await db.library()).firstWhere((e) => e.title.id == 1).updatedAt,
          originalDate,
        );
        api.fetched.clear();
        // Retain a fresh healthy ended show throughout the simulated interval.
        await seed(db, show(2, status: 'Ended'), clock);
        clock = clock.add(
          status == 404
              ? const Duration(hours: 23)
              : const Duration(minutes: 4),
        );
        expect((await sync.refresh(onlyStale: true)).issues, hasLength(1));
        expect(api.fetched, isEmpty);
        api.failures.clear();
        clock = clock.add(
          status == 404
              ? const Duration(hours: 1, seconds: 1)
              : const Duration(minutes: 1, seconds: 1),
        );
        final recovered = await sync.refresh(onlyStale: true);
        expect(api.fetched, [1]);
        expect(recovered.refreshedKeys, {'tv:1'});
        expect(recovered.issues, isEmpty);
        expect(
          (await FeedbackIssueStore(db).load()).single.resolvedAt,
          clock.toUtc(),
        );
        expect((await db.watched())['episode:1:101'], originalDate);
      },
    );
  }

  test(
    'active titles have priority over ended titles even when added earlier',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final api = ControlledApi();
      api.release.complete();
      final date = DateTime.now();
      await seed(db, show(1), date.subtract(const Duration(days: 1)));
      await seed(db, show(2, status: 'Ended'), date);
      final sync = SyncRepository(
        db,
        SeriesRepository(api, db),
        MoviesRepository(api, db),
        concurrency: 1,
      );
      await sync.refresh();
      expect(api.fetched, [1, 2]);
    },
  );

  test(
    'router shares whole-series download and commit across concurrent callers',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final api = DelayedCatalog();
      final router = CatalogRouter(
        db: db,
        modules: {'tmdb': api},
        active: 'tmdb',
      );
      final title = (await router.search('show', null, 1)).results.single;
      final a = router.series(title.id);
      final b = router.series(title.id);
      await until(() => api.fetches == 1);
      api.release.complete();
      final results = await Future.wait([a, b]);
      expect(api.fetches, 1);
      expect(identical(results[0], results[1]), isTrue);
      expect(await db.cached('series:${title.id}'), isNotNull);
    },
  );

  test(
    'same-provider generation change rejects an old in-flight response',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final api = DelayedCatalog();
      final router = CatalogRouter(
        db: db,
        modules: {'tmdb': api},
        active: 'tmdb',
      );
      final title = (await router.search('show', null, 1)).results.single;
      final checked = expectLater(
        router.series(title.id),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'safe conflict',
            contains('stale_request'),
          ),
        ),
      );
      await until(() => api.fetches == 1);
      await db.customStatement(
        'UPDATE content_state SET generation=generation+1',
      );
      api.release.complete();
      await checked;
      expect(await db.cached('series:${title.id}'), isNull);
    },
  );

  test(
    'movie offline fallback retains HTTP diagnostics for sync report',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final date = DateTime.now();
      final title = movie();
      await db.add(title, date);
      await db.cache('movie:10', title.raw, date);
      final api = FailingMovieApi();
      final report = await SyncRepository(
        db,
        SeriesRepository(api, db),
        MoviesRepository(api, db),
      ).refresh();
      expect(report.issues.single.diagnostic?.statusCode, 404);
      expect(await db.cached('movie:10'), isNotNull);
    },
  );
}

class FailingMovieApi extends FakeApi {
  @override
  Future<TitleData> title(MediaType type, int id) async => throw ApiFailure(
    'Unavailable',
    diagnostic: RequestDiagnostic(
      endpoint: '/movie/$id',
      exceptionType: 'badResponse',
      statusCode: 404,
      durationMs: 15,
      attempts: 1,
      occurredAt: DateTime.now(),
    ),
  );
}
