import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';
import 'database.dart';
import 'tmdb_retention.dart';

class AlertSettings {
  final bool enabled, after, badgeEnabled;
  final int minutes, fallbackHour, fallbackMinute;
  const AlertSettings({
    this.enabled = false,
    this.badgeEnabled = false,
    this.after = false,
    this.minutes = 15,
    this.fallbackHour = 20,
    this.fallbackMinute = 0,
  });
  static Future<AlertSettings> load(AppDatabase db) async {
    final value = await db.preference('alerts');
    if (value == null) return const AlertSettings();
    final data = jsonDecode(value) as Map;
    return AlertSettings(
      enabled: data['enabled'] == true,
      badgeEnabled: (data['badgeEnabled'] ?? data['enabled']) == true,
      after: data['after'] == true,
      minutes: integer(data['minutes'], 15).clamp(0, 1439).toInt(),
      fallbackHour: integer(data['hour'], 20).clamp(0, 23).toInt(),
      fallbackMinute: integer(data['minute']).clamp(0, 59).toInt(),
    );
  }

  Future<void> save(AppDatabase db) => db.setPreference(
    'alerts',
    jsonEncode({
      'enabled': enabled,
      'badgeEnabled': badgeEnabled,
      'after': after,
      'minutes': minutes,
      'hour': fallbackHour,
      'minute': fallbackMinute,
    }),
  );
}

DateTime? episodeAlertTime(EpisodeData episode, AlertSettings settings) {
  final stamp = date(episode.raw['air_stamp']);
  final air = episode.airDate;
  if (stamp == null && air == null) return null;
  final reference =
      stamp ??
      DateTime(
        air!.year,
        air.month,
        air.day,
        settings.fallbackHour,
        settings.fallbackMinute,
      );
  final offset = Duration(minutes: settings.minutes);
  return settings.after ? reference.add(offset) : reference.subtract(offset);
}

class EpisodeAlerts {
  static const settingsChannel = MethodChannel(
    'next_episode/notification_settings',
  );
  bool get supportsSystemSettings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  Future<void> openSystemSettings() async {
    if (!supportsSystemSettings) return;
    if (await settingsChannel.invokeMethod<bool>('open') != true) {
      throw StateError('Notification settings could not be opened');
    }
  }

  final plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  Future<void> _queue = Future.value();
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (!supported) return;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  Future<bool> requestPermission({bool badgeOnly = false}) async {
    if (!supported) return false;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(
              alert: !badgeOnly,
              sound: !badgeOnly,
              badge: true,
            ) ??
        false;
  }

  Future<void> refresh(
    AppDatabase db,
    Iterable<SeriesBundle> series,
    Map<String, DateTime> watched,
  ) {
    final bundles = series.toList();
    final next = _queue
        .catchError((Object _) {})
        .then((_) => _refresh(db, bundles, watched));
    _queue = next;
    return next;
  }

  Future<void> _refresh(
    AppDatabase db,
    List<SeriesBundle> series,
    Map<String, DateTime> watched,
  ) async {
    if (!supported) return;
    await initialize();
    final settings = await AlertSettings.load(db);
    await plugin.cancelAll();
    final now = DateTime.now();
    final allowed = <SeriesBundle>[];
    final expiries = <String, DateTime>{};
    final tmdbAllowed = await db.tmdbContentAllowed();
    for (final bundle in series) {
      if (bundle.title.raw['content_unavailable'] == true) continue;
      if (bundle.title.provider == 'tmdb') {
        if (!tmdbAllowed) continue;
        final obtained = DateTime.tryParse(
          string(bundle.title.raw[tmdbObtainedKey]),
        );
        if (obtained == null) continue;
        final expiry = tmdbExpiry(obtained);
        if (!expiry.isAfter(now.toUtc())) continue;
        expiries[bundle.title.key] = expiry;
      }
      allowed.add(bundle);
    }
    // Count each episode once; scheduling up to 60 notifications must not scan
    // the entire library 60 times on the UI isolate.
    final badgeTimeline = EpisodeBadgeTimeline(
      allowed,
      watched,
      expiries: expiries,
    );
    int countAt(DateTime time) => badgeTimeline.countAt(time);
    var badgeSchedules = 0;
    if (supportsSystemSettings) {
      await settingsChannel.invokeMethod<bool>(
        'setBadge',
        settings.badgeEnabled ? countAt(now) : 0,
      );
      if (settings.badgeEnabled) {
        // Badge-only notifications also work without audible episode reminders.
        final changes = badgeTimeline.times.where(
          (time) => time.isAfter(now.toUtc()),
        );
        for (final time in changes.take(30)) {
          await plugin.zonedSchedule(
            id: 1000 + badgeSchedules++,
            scheduledDate: tz.TZDateTime.from(time, tz.UTC),
            notificationDetails: NotificationDetails(
              iOS: DarwinNotificationDetails(
                presentAlert: false,
                presentSound: false,
                presentBanner: false,
                presentList: false,
                presentBadge: true,
                badgeNumber: countAt(time.toLocal()),
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    }
    if (!settings.enabled) return;
    final pending = <({TitleData title, EpisodeData episode, DateTime time})>[];
    for (final bundle in allowed) {
      final expiry = expiries[bundle.title.key];
      for (final episode in bundle.episodes) {
        if (episode.isSpecial || watched.containsKey(episode.key)) continue;
        final time = episodeAlertTime(episode, settings);
        if (time != null &&
            time.isAfter(now) &&
            (expiry == null || time.toUtc().isBefore(expiry))) {
          pending.add((title: bundle.title, episode: episode, time: time));
        }
      }
    }
    pending.sort((a, b) => a.time.compareTo(b.time));
    // Keep below iOS's 64 pending notification limit. Refill on each library sync.
    for (var i = 0; i < pending.length && i < 60 - badgeSchedules; i++) {
      final item = pending[i];
      await plugin.zonedSchedule(
        id: i + 1,
        title: item.title.title,
        body: '${item.episode.code} · ${item.episode.title}',
        scheduledDate: tz.TZDateTime.from(item.time, tz.UTC),
        notificationDetails: NotificationDetails(
          android: const AndroidNotificationDetails(
            'episode_alerts',
            'Episode alerts',
            channelDescription: 'Reminders for episodes in your library',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: settings.badgeEnabled,
            badgeNumber: settings.badgeEnabled
                ? countAt(item.time.toLocal())
                : null,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

/// Prefix counts at release days and metadata expirations. Dates match To watch.
class EpisodeBadgeTimeline {
  final List<DateTime> times;
  final List<int> counts;
  EpisodeBadgeTimeline._(this.times, this.counts);

  factory EpisodeBadgeTimeline(
    Iterable<SeriesBundle> series,
    Map<String, DateTime> watched, {
    Map<String, DateTime> expiries = const {},
  }) {
    final deltas = <DateTime, int>{};
    final keys = <String>{};
    for (final bundle in series) {
      if (!bundle.title.isTv || bundle.title.raw['content_unavailable'] == true) {
        continue;
      }
      final expiry = expiries[bundle.title.key]?.toUtc();
      for (final episode in bundle.episodes) {
        final air = episode.airDate;
        if (episode.isSpecial ||
            air == null ||
            watched.containsKey(episode.key) ||
            !keys.add(episode.key)) {
          continue;
        }
        final start = day(air).toUtc();
        if (expiry != null && !start.isBefore(expiry)) continue;
        deltas.update(start, (n) => n + 1, ifAbsent: () => 1);
        if (expiry != null) {
          deltas.update(expiry, (n) => n - 1, ifAbsent: () => -1);
        }
      }
    }
    final times = deltas.keys.where((time) => deltas[time] != 0).toList()
      ..sort();
    var total = 0;
    return EpisodeBadgeTimeline._(times, [
      for (final time in times) total += deltas[time]!,
    ]);
  }

  int countAt(DateTime time) {
    var low = 0, high = times.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (times[middle].isAfter(time)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low == 0 ? 0 : counts[low - 1];
  }
}

/// Mirrors To watch: released regular episodes from the saved library only.
int unwatchedEpisodeCount(
  Iterable<SeriesBundle> series,
  Map<String, DateTime> watched,
  DateTime now,
) {
  final keys = <String>{};
  for (final bundle in series) {
    if (!bundle.title.isTv || bundle.title.raw['content_unavailable'] == true) {
      continue;
    }
    for (final episode in bundle.episodes) {
      if (!episode.isSpecial &&
          episode.released(now) &&
          !watched.containsKey(episode.key)) {
        keys.add(episode.key);
      }
    }
  }
  return keys.length;
}
