import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/ui/home.dart';

import 'fixtures.dart';

class UnexpectedFailureApi extends FakeApi {
  @override
  Future<SeriesBundle> series(int id) async =>
      throw StateError('private diagnostic');
}

void main() {
  testWidgets(
    'startup failure details name the title and keep cached progress',
    (tester) async {
      final db = AppDatabase.memory();
      final api = FakeApi()..fail = true;
      final saved = bundle(episodes: [episodeJson(1, 1)]);
      final stale = DateTime.now().subtract(const Duration(hours: 8));
      await db.add(saved.title, stale);
      await db.cache('series:10', saved.toJson(), stale);
      await db.updateTitle(saved.title, stale);
      await db.mark('episode:10:1', true, now);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            apiProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: HomeScreen(showSyncDiagnostics: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Your data is safe. Some information could not be updated right now.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Library update details'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Serial test'),
        ),
        findsOneWidget,
      );
      expect((await db.watched())['episode:10:1'], now);
      expect(await db.cached('series:10'), isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
    },
  );

  test('unexpected exception details stay out of user-facing issues', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final api = UnexpectedFailureApi();
    await db.add(tv(), DateTime.now());
    final report = await SyncRepository(
      db,
      SeriesRepository(api, db),
      MoviesRepository(api, db),
    ).refresh();
    expect(report.issues.single.title, 'Serial test');
    expect(report.issues.single.message, isNot(contains('private diagnostic')));
    expect(report.errors.single, contains('private diagnostic'));
  });
}
