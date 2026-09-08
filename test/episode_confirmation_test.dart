import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/ui/common.dart';

import 'fixtures.dart';

void main() {
  for (final choice in ['yes', 'no', 'dismiss']) {
    testWidgets('episode 5 confirmation: $choice', (tester) async {
      final db = AppDatabase.memory();
      final series = bundle(
        episodes: [
          for (var i = 1; i <= 10; i++) episodeJson(i, i, air: '2020-01-01'),
        ],
      );
      await db.cache('series:10', series.toJson(), now);
      await db.add(series.title, now);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          apiProvider.overrideWithValue(FakeApi()),
        ],
      );
      await container.read(libraryProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => markEpisodeWithConfirmation(
                    context,
                    ref,
                    series.seasons.first.episodes[4],
                    true,
                  ),
                  child: const Text('Episode 5'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Episode 5'));
      await tester.pumpAndSettle();
      expect(find.textContaining('You have 4 earlier unwatched episodes'), findsOneWidget);
      expect(await db.watched(), isEmpty);
      if (choice == 'dismiss') {
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      } else {
        await tester.tap(
          find.text(
            choice == 'yes'
                ? 'Yes, include earlier episodes'
                : 'No, only this episode',
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(
        (await db.watched()).keys.toSet(),
        choice == 'yes'
            ? {for (var i = 1; i <= 5; i++) 'episode:10:$i'}
            : choice == 'no'
            ? {'episode:10:5'}
            : <String>{},
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await db.close();
    });
  }
}
