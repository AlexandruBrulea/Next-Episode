import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/domain/schedule.dart';
import 'package:next_episode/domain/watch_time.dart';
import 'package:next_episode/ui/app_theme.dart';
import 'package:next_episode/ui/calendar.dart';
import 'package:next_episode/ui/details.dart';
import 'package:next_episode/ui/home.dart';
import 'package:next_episode/ui/library_grid.dart';

import 'fixtures.dart';

class FixedLibrary extends LibraryController {
  final LibrarySnapshot snapshot;
  FixedLibrary(this.snapshot);
  @override
  Future<LibrarySnapshot> build() async => snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('CAPTURE_UI')) {
    setUpAll(() async {
      for (final font in [
        ('Roboto', 'roboto-regular.ttf'),
        ('MaterialIcons', 'materialicons-regular.otf'),
      ]) {
        final loader = FontLoader(font.$1);
        loader.addFont(
          File('.tools/flutter/bin/cache/artifacts/material_fonts/${font.$2}')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      }
    });
  }
  test(
    'same-day releases group by show and season without invented ranges',
    () {
      final data = bundle(
        episodes: [
          for (var n = 1; n <= 9; n++) episodeJson(n, n, air: '2026-09-19'),
        ],
      );
      final one = groupReleasesByDay([
        ScheduleEntry(data.title, 1, data.seasons.first.episodes),
      ]);
      expect(one, hasLength(1));
      expect(one.single.episodeRange, 'S01 E01–E09');
      final split = bundle(
        episodes: [
          for (var n = 1; n <= 6; n++)
            episodeJson(n, n, air: n <= 3 ? '2026-09-19' : '2026-09-21'),
          episodeJson(8, 8, air: '2026-09-21'),
        ],
      );
      final groups = groupReleasesByDay([
        ScheduleEntry(split.title, 1, split.seasons.first.episodes),
      ]);
      expect(groups.map((e) => e.episodeRange), [
        'S01 E01–E03',
        'S01 E04–E06, E08',
      ]);
      expect(groups.map((e) => e.dateRange), ['Sep 19', 'Sep 21']);
      final anotherSeason = EpisodeData(
        10,
        200,
        episodeJson(99, 1, season: 2, air: '2026-09-19'),
      );
      expect(
        groupReleasesByDay([
          ...one,
          ScheduleEntry(data.title, 2, [anotherSeason]),
        ]),
        hasLength(2),
      );
    },
  );

  test(
    'watch time counts library once, marks, known and estimated durations',
    () {
      final title = tv(); // 42-minute fallback.
      final data = SeriesBundle(title, [
        SeasonData(10, {
          'id': 100,
          'episodes': [
            {...episodeJson(1, 1), 'runtime': 60},
            {...episodeJson(2, 2), 'runtime': 0},
          ],
        }),
      ]);
      final film = movie(); // 110 minutes.
      final unknown = TitleData(MediaType.movie, {
        'id': 20,
        'title': 'Unknown',
      });
      final entries = [
        for (final t in [title, film, unknown]) LibraryEntry(t, now, now),
      ];
      final summary = WatchTimeSummary.calculate(
        entries,
        {10: data},
        {'episode:10:1': now, film.key: now, 'movie:999': now},
      );
      expect(summary.totalMinutes, 212);
      expect(summary.watchedMinutes, 170);
      expect(summary.estimatedItems, 1);
      expect(summary.unknownItems, 1);
      final empty = WatchTimeSummary.calculate([], {}, {});
      expect(empty.fraction, 0);
    },
  );

  for (final config in [(320.0, 1.0), (390.0, 1.0), (430.0, 2.0)]) {
    testWidgets(
      'three-column library at ${config.$1}, text scale ${config.$2}',
      (tester) async {
        tester.view.physicalSize = Size(config.$1, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.memory();
        final titles = [
          TitleData(MediaType.tv, {
            ...tv(status: 'Ended').raw,
            'name': 'The Long Journey Home',
          }),
          movie(),
          TitleData(MediaType.tv, {
            ...tv(status: 'Canceled').raw,
            'id': 12,
            'name': 'Nightfall',
          }),
        ];
        final snapshot = LibrarySnapshot(
          [for (final t in titles) LibraryEntry(t, now, now)],
          {'movie:10': now},
          {10: bundle()},
        );
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            apiProvider.overrideWithValue(FakeApi()),
            libraryProvider.overrideWith(() => FixedLibrary(snapshot)),
          ],
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: nextEpisodeTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$2)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: const Scaffold(
                  backgroundColor: Color(0xFF080E1B),
                  appBar: null,
                  body: SafeArea(child: LibraryScreen()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cards = find.byType(LibraryPosterCard);
        expect(cards, findsNWidgets(3));
        expect(
          tester.getTopLeft(cards.at(0)).dy,
          tester.getTopLeft(cards.at(2)).dy,
        );
        expect(
          tester.getTopLeft(cards.at(0)).dx,
          lessThan(tester.getTopLeft(cards.at(1)).dx),
        );
        expect(find.text('YOUR WATCH TIME'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (config == (390.0, 1.0) &&
            const bool.fromEnvironment('CAPTURE_UI')) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('build/library-preview.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      },
    );
  }

  testWidgets('calendar batch opens episode chooser then individual details', (
    tester,
  ) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final data = bundle(
      episodes: [for (var n = 1; n <= 9; n++) episodeJson(n, n, air: today)],
    );
    final snapshot = LibrarySnapshot(
      [LibraryEntry(data.title, now, now)],
      {},
      {10: data},
    );
    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith(() => FixedLibrary(snapshot)),
        tmdbAllowedProvider.overrideWith((ref) async => true),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: nextEpisodeTheme(),
          home: const Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('S01 E01–E09'), findsOneWidget);
    await tester.tap(find.text('S01 E01–E09'));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseEpisodesScreen), findsOneWidget);
    await tester.tap(find.text('S01E01 · Episode 1'));
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
