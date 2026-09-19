import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/data/alerts.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/ui/alert_time_picker.dart';
import 'package:next_episode/ui/settings.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibrarySnapshot> build() async => LibrarySnapshot([], {}, {});
}

class SavingAlerts extends EpisodeAlerts {
  int saves = 0;
  @override
  Future<void> refresh(
    AppDatabase db,
    Iterable<SeriesBundle> series,
    Map<String, DateTime> watched,
  ) async {
    saves++;
    // Keep the loading indicator on screen across frames, as on a real device.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'alert wheel stays expanded through repeated saves and keeps selection',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.memory();
      final alerts = SavingAlerts();
      await const AlertSettings(minutes: 1).save(db);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            episodeAlertsProvider.overrideWithValue(alerts),
            libraryProvider.overrideWith(EmptyLibrary.new),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alert Time'));
      await tester.pumpAndSettle();
      final originalState = tester.state(find.byType(AlertTimePicker));
      for (final target in [15, 30, 45]) {
        final wheel = tester.widget<CupertinoPicker>(
          find.byType(CupertinoPicker).at(1),
        );
        final scrolling = wheel.scrollController!.animateToItem(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.linear,
        );
        await tester.pumpAndSettle();
        await scrolling;
        final tile = tester.widget<ExpansionTile>(
          find.descendant(
            of: find.byType(AlertTimePicker),
            matching: find.byType(ExpansionTile),
          ),
        );
        expect(tester.state(find.byType(AlertTimePicker)), same(originalState));
        expect((tile.subtitle as Text).data, '$target m before');
        expect(find.byType(CupertinoPicker).hitTestable(), findsNWidgets(3));
        expect((await AlertSettings.load(db)).minutes, target);
      }
      expect(alerts.saves, 3);
      await tester.tap(find.text('Alert Time'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker).hitTestable(), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await db.close();
    },
  );
}
