import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/data/tmdb_retention.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/ui/common.dart';
import 'package:next_episode/ui/details.dart';
import 'package:next_episode/ui/feeds.dart';

import 'startup_performance_test.dart' show show;

class MemoryLibrary extends LibraryController {
  LibrarySnapshot snapshot;
  MemoryLibrary(this.snapshot);
  @override
  Future<LibrarySnapshot> build() async => snapshot;
  void publish(LibrarySnapshot value) => state = AsyncData(snapshot = value);
}

LibrarySnapshot library(Iterable<SeriesBundle> shows) => LibrarySnapshot(
  [
    for (final show in shows)
      LibraryEntry(show.title, DateTime.now(), DateTime.now()),
  ],
  {},
  {for (final show in shows) show.title.id: show},
);

void main() {
  testWidgets('210 shows build To Watch rows on demand with an ahead buffer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MemoryLibrary(
      library([for (var id = 1; id <= 210; id++) show(id)]),
    );
    final container = ProviderContainer(
      overrides: [libraryProvider.overrideWith(() => controller)],
    );
    addTearDown(container.dispose);
    await container.read(libraryProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: EpisodeFeed(calendar: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(list.childrenDelegate.estimatedChildCount, 210 * 7);
    expect(list.scrollCacheExtent?.value, 1);
    expect(find.byType(Card).evaluate().length, lessThan(30));
    await tester.ensureVisible(find.text('Show more').first);
    await tester.tap(find.text('Show more').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListView>(find.byType(ListView))
          .childrenDelegate
          .estimatedChildCount,
      210 * 7 + 3,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.byType(Card).evaluate().length, lessThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved show and season open from memory and follow watched updates',
    (tester) async {
      final bundle = show(1);
      final controller = MemoryLibrary(library([bundle]));
      var loads = 0;
      final container = ProviderContainer(
        overrides: [
          libraryProvider.overrideWith(() => controller),
          seriesDetailsProvider(1).overrideWith((ref) async {
            loads++;
            throw StateError('Saved show should not reload');
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(libraryProvider.future);
      Widget page(Widget screen) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      );
      await tester.pumpWidget(page(const SeriesScreen(id: 1)));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(bundle.title.title), findsWidgets);
      container.invalidate(seriesDetailsProvider(1));
      await tester.pump();
      expect(loads, 0);
      await tester.pumpWidget(
        page(const SeasonScreen(seriesId: 1, seasonNumber: 1)),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('0/80 released watched'), findsOneWidget);
      controller.publish(
        controller.snapshot.withWatched({
          bundle.episodes.first.key: DateTime.now(),
        }),
      );
      await tester.pump();
      expect(find.textContaining('1/80 released watched'), findsOneWidget);
      controller.publish(controller.snapshot.withWatched({}));
      await tester.pump();
      expect(find.textContaining('0/80 released watched'), findsOneWidget);
      expect(loads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'missing and expired bundles fall back to the existing loader',
    () async {
      final controller = MemoryLibrary(library([]));
      final fresh = show(1);
      var loads = 0;
      final container = ProviderContainer(
        overrides: [
          libraryProvider.overrideWith(() => controller),
          seriesDetailsProvider(1).overrideWith((ref) async {
            loads++;
            return Loaded(fresh);
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(libraryProvider.future);
      final subscription = container.listen(
        seriesContentProvider(1),
        (_, next) {},
      );
      addTearDown(subscription.close);
      await container.read(seriesDetailsProvider(1).future);
      expect(
        container.read(seriesContentProvider(1)).requireValue.value,
        same(fresh),
      );
      expect(loads, 1);
      final expired = SeriesBundle(
        TitleData(MediaType.tv, {
          ...fresh.title.raw,
          tmdbObtainedKey: '2020-01-01T00:00:00Z',
        }),
        fresh.seasons,
      );
      controller.publish(library([expired]));
      expect(
        container.read(seriesContentProvider(1)).requireValue.value,
        same(fresh),
      );
    },
  );

  test(
    'poster variants respect display density, cover crop and image host',
    () {
      const url = 'https://image.tmdb.org/t/p/w500/poster.jpg';
      expect(sizedPosterUrl(url, const Size(48, 72), 3), contains('/w185/'));
      expect(sizedPosterUrl(url, const Size(110, 165), 3), contains('/w342/'));
      expect(sizedPosterUrl(url, const Size(140, 210), 3), url);
      expect(sizedPosterUrl(url, const Size(48, 300), 2), url);
      expect(sizedPosterUrl(url, const Size(390, 320), 3), url);
      expect(sizedPosterUrl(url, const Size(double.infinity, 72), 3), url);
      const external = 'https://example.org/t/p/w500/poster.jpg';
      expect(sizedPosterUrl(external, const Size(48, 72), 1), external);
    },
  );
}
