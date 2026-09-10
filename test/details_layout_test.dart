import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/demo_source.dart';
import 'package:next_episode/ui/common.dart';
import 'package:next_episode/ui/details.dart';

void main() {
  for (final width in [390.0, 494.0, 1000.0]) {
    for (final isTv in [true, false]) {
      testWidgets('artwork fills $width modal, tv=$isTv', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.memory();
        final api = DemoSource();
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
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        openTitle(context, isTv ? api.demoSeries : api.film),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final screen = find.byType(isTv ? SeriesScreen : MovieScreen);
        final artwork = find.descendant(
          of: find.byType(TitleHeader),
          matching: find.byType(Poster),
        );
        final modalRect = tester.getRect(screen);
        final imageRect = tester.getRect(artwork);
        expect(imageRect.left, closeTo(modalRect.left, 0.01));
        expect(imageRect.right, closeTo(modalRect.right, 0.01));
        expect(imageRect.height, 320);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        container.dispose();
        await db.close();
      });
    }
  }
}
