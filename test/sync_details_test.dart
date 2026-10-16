import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/feedback.dart';
import 'package:next_episode/data/repositories.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/ui/home.dart';
import 'package:next_episode/ui/feedback.dart';
import 'package:next_episode/ui/settings.dart';

import 'fixtures.dart';

class UnexpectedFailureApi extends FakeApi {
  @override
  Future<SeriesBundle> series(int id) async =>
      throw StateError('private diagnostic');
}

class FailingSyncController extends LibraryController {
  int attempts = 0;
  @override
  Future<SyncReport> sync({bool onlyStale = false}) async {
    attempts++;
    throw StateError('private background diagnostic');
  }
}

void main() {
  testWidgets(
    'background orchestration failures are recorded silently and retry on resume',
    (tester) async {
      final db = AppDatabase.memory();
      final controller = FailingSyncController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            apiProvider.overrideWithValue(FakeApi()),
            libraryProvider.overrideWith(() => controller),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.attempts, 1);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      final issues = await FeedbackIssueStore(db).load();
      expect(issues.single.title, 'Library sync');
      expect(issues.single.reason, isNot(contains('private')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.attempts, 2);
      expect((await FeedbackIssueStore(db).load()), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
    },
  );

  testWidgets(
    'startup failures stay silent but remain available in Settings for email',
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
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Your data is safe. Some information could not be updated right now.',
        ),
        findsNothing,
      );
      expect(find.byType(MaterialBanner), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Offline'), findsNothing);
      expect((await FeedbackIssueStore(db).load()).single.title, 'Serial test');
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Update issues'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Update issues'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(FeedbackScreen),
          matching: find.text('Update issues'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FeedbackScreen),
          matching: find.text('Serial test'),
        ),
        findsOneWidget,
      );
      expect(find.text('Email report'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FeedbackScreen),
          matching: find.byType(TextField),
        ),
        findsNothing,
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
    expect(report.errors.single, isNot(contains('private diagnostic')));
  });
}
