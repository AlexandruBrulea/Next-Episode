import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/main.dart';
import 'package:next_episode/ui/details.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'startup and resume refresh even recently cached series automatically',
    (tester) async {
      final db = AppDatabase.memory();
      final api = FakeApi();
      final old = bundle(episodes: [episodeJson(1, 1)]);
      await db.add(old.title, DateTime.now());
      await db.cache('series:10', old.toJson(), DateTime.now());
      await db.updateTitle(old.title, DateTime.now());
      await db.mark('episode:10:1', true, now);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            apiProvider.overrideWithValue(api),
          ],
          child: const NextEpisodeApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls, greaterThan(0));
      expect((await db.cached('series:10'))!.data['seasons'][0]['episodes'], hasLength(4));
      expect((await db.watched())['episode:10:1'], now);
      expect(find.byTooltip('Refresh library'), findsNothing);
      final calls = api.calls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.calls, greaterThan(calls));
      await tester.tap(find.text('Serial test'));
      await tester.pumpAndSettle();
      expect(find.text('Refresh'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
    },
  );
  testWidgets('search add detail mark remove/readd flow', (tester) async {
    final db = AppDatabase.memory();
    final api = FakeApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          apiProvider.overrideWithValue(api),
        ],
        child: const NextEpisodeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Your library is empty. Add a title from Search.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search shows and movies · TMDB'), findsOneWidget);
    expect(find.textContaining('TVmaze'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'Test');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Serial test'), findsOneWidget);
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serial test'));
    await tester.pumpAndSettle();
    expect(find.byType(SeriesScreen), findsOneWidget);
    expect(find.textContaining('TMDB'), findsNothing);
    expect(find.textContaining('TVmaze'), findsNothing);
    final seriesScroll = find.descendant(of: find.byType(SeriesScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byTooltip('Mark as watched').first, 350, scrollable: seriesScroll);
    await tester.tap(find.byTooltip('Mark as watched').first);
    await tester.pumpAndSettle();
    expect((await db.watched()).containsKey('episode:10:1'), isTrue);
    await tester.tap(find.descendant(of: find.byType(SeriesScreen), matching: find.byType(ListTile)).first);
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeScreen), findsNothing);
    expect(find.byType(SeriesScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Remove from library'),
      -500,
      scrollable: seriesScroll,
    );
    await tester.tap(find.text('Remove from library'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Your watch history and dates'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(await db.library(), isEmpty);
    expect((await db.watched()).containsKey('episode:10:1'), isTrue);
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    expect(await db.library(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });
}
