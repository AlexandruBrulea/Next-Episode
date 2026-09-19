import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/alerts.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/domain/models.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'count matches released unwatched regular episodes, without duplicates',
    () {
      final data = bundle();
      expect(unwatchedEpisodeCount([data, data], {}, now), 2);
      final watched = {data.seasons.first.episodes.first.key: now};
      expect(unwatchedEpisodeCount([data], watched, now), 1);
      expect(
        unwatchedEpisodeCount(
          [data],
          watched,
          now.add(const Duration(days: 1)),
        ),
        2,
      );
      expect(unwatchedEpisodeCount([], watched, now), 0);
      expect(
        unwatchedEpisodeCount(
          [
            SeriesBundle(
              TitleData(MediaType.tv, {
                ...data.title.raw,
                'content_unavailable': true,
              }),
              data.seasons,
            ),
          ],
          {},
          now,
        ),
        0,
      );
    },
  );

  test('iOS badge works without reminders, updates after watching and clears when disabled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final notifications = <MethodCall>[];
    final badges = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      notifications.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(EpisodeAlerts.settingsChannel, (
      call,
    ) async {
      if (call.method == 'setBadge') badges.add(call.arguments as int);
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(EpisodeAlerts.settingsChannel, null);
    });
    final today = day(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final original = bundle(
      episodes: [
        episodeJson(
          1,
          1,
          air: today.subtract(const Duration(days: 1)).toIso8601String(),
        ),
        episodeJson(2, 2, air: tomorrow.toIso8601String()),
        episodeJson(3, 3, air: tomorrow.toIso8601String()),
        episodeJson(4, 4, air: null),
      ],
    );
    final data = SeriesBundle(
      TitleData(MediaType.tv, {...original.title.raw, 'provider': 'tvmaze'}),
      original.seasons,
    );
    final alerts = EpisodeAlerts();
    await const AlertSettings(badgeEnabled: true).save(db);
    await alerts.refresh(db, [data], {});
    expect(badges.last, 1);
    final scheduled = notifications
        .where((c) => c.method == 'zonedSchedule')
        .toList();
    expect(scheduled, hasLength(1));
    final args = scheduled.single.arguments as Map;
    final details = args['platformSpecifics'] as Map;
    expect(details['badgeNumber'], 3);
    expect(details['presentSound'], false);
    expect(details['presentAlert'], false);
    expect(args['title'], null);

    notifications.clear();
    final watched = {data.seasons.first.episodes.first.key: today};
    await alerts.refresh(db, [data], watched);
    expect(badges.last, 0);
    final updated =
        notifications.firstWhere((c) => c.method == 'zonedSchedule').arguments
            as Map;
    expect((updated['platformSpecifics'] as Map)['badgeNumber'], 2);

    notifications.clear();
    await const AlertSettings(enabled: true, badgeEnabled: true).save(db);
    await alerts.refresh(db, [data], {});
    final reminders = notifications.where(
      (c) =>
          c.method == 'zonedSchedule' && (c.arguments as Map)['title'] != null,
    );
    expect(reminders, hasLength(2));
    for (final reminder in reminders) {
      expect(
        ((reminder.arguments as Map)['platformSpecifics']
            as Map)['badgeNumber'],
        3,
      );
    }

    notifications.clear();
    await const AlertSettings().save(db);
    await alerts.refresh(db, [data], {});
    expect(badges.last, 0);
    expect(notifications.any((c) => c.method == 'cancelAll'), true);
    expect(notifications.any((c) => c.method == 'zonedSchedule'), false);

    await alerts.requestPermission(badgeOnly: true);
    final permission =
        notifications
                .lastWhere((c) => c.method == 'requestPermissions')
                .arguments
            as Map;
    expect(permission['badge'], true);
    expect(permission['sound'], false);
    expect(permission['alert'], false);
  });

  test(
    'existing alert users inherit badges and explicit opt-out persists',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.setPreference('alerts', '{"enabled":true}');
      expect((await AlertSettings.load(db)).badgeEnabled, true);
      await const AlertSettings(enabled: true, badgeEnabled: false).save(db);
      expect((await AlertSettings.load(db)).badgeEnabled, false);
    },
  );
}
