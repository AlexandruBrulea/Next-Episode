import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/demo_source.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/ui/feeds.dart';
import 'package:next_episode/ui/details.dart';

void main() {
  testWidgets(
    'mobile feeds separate aired, future, unknown, specials and movies',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.memory();
      final api = DemoSource();
      await SeriesRepository(api, db).load(api.demoSeries.id);
      await db.add(api.demoSeries, DateTime.now());
      await db.add(api.film, DateTime.now());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          apiProvider.overrideWithValue(api),
        ],
      );
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
      expect(find.textContaining('S01E01'), findsOneWidget);
      expect(find.textContaining('S01E03'), findsNothing);
      expect(find.textContaining('S00'), findsNothing);
      expect(find.text('Demo movie'), findsNothing);
      await tester.tap(find.byTooltip('Mark as watched').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('S01E01'), findsNothing);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: EpisodeFeed(calendar: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Past & upcoming'), findsOneWidget);
      expect(find.text('Date TBA'), findsWidgets);
      expect(find.textContaining('S01E01'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      container.dispose();
      await db.close();
    },
  );
  testWidgets('movie details persist watched state and support undo', (
    tester,
  ) async {
    final db = AppDatabase.memory();
    final api = DemoSource();
    await db.add(api.film, DateTime.now());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiProvider.overrideWithValue(api),
      ],
    );
    await container.read(libraryProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: MovieScreen(id: api.film.id)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Mark as watched'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as watched'));
    await tester.pumpAndSettle();
    expect((await db.watched()).containsKey(api.film.key), isTrue);
    await tester.tap(find.text('Mark as unwatched'));
    await tester.pumpAndSettle();
    expect(await db.watched(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    container.dispose();
    await db.close();
  });
}
