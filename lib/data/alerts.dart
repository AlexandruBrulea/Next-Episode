import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';
import 'database.dart';

class AlertSettings {
  final bool enabled, after;
  final int minutes, fallbackHour, fallbackMinute;
  const AlertSettings({this.enabled = false, this.after = false,
    this.minutes = 15, this.fallbackHour = 20, this.fallbackMinute = 0});
  static Future<AlertSettings> load(AppDatabase db) async {
    final value = await db.preference('alerts');
    if (value == null) return const AlertSettings();
    final data = jsonDecode(value) as Map;
    return AlertSettings(enabled: data['enabled'] == true, after: data['after'] == true,
      minutes: integer(data['minutes'], 15).clamp(0, 1439).toInt(),
      fallbackHour: integer(data['hour'], 20).clamp(0, 23).toInt(),
      fallbackMinute: integer(data['minute']).clamp(0, 59).toInt());
  }
  Future<void> save(AppDatabase db) => db.setPreference('alerts', jsonEncode({
    'enabled': enabled, 'after': after, 'minutes': minutes,
    'hour': fallbackHour, 'minute': fallbackMinute,
  }));
}

DateTime? episodeAlertTime(EpisodeData episode, AlertSettings settings) {
  final stamp = date(episode.raw['air_stamp']);
  final air = episode.airDate;
  if (stamp == null && air == null) return null;
  final reference = stamp ?? DateTime(air!.year, air.month, air.day,
      settings.fallbackHour, settings.fallbackMinute);
  final offset = Duration(minutes: settings.minutes);
  return settings.after ? reference.add(offset) : reference.subtract(offset);
}

class EpisodeAlerts {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  Future<void> _queue = Future.value();
  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (!supported) return;
    await plugin.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false,
        requestBadgePermission: false, requestSoundPermission: false),
    ));
  }
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission() ?? false;
    }
    return await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
  }
  Future<void> refresh(AppDatabase db, Iterable<SeriesBundle> series, Map<String, DateTime> watched) {
    final bundles = series.toList();
    final next = _queue.catchError((Object _) {}).then((_) => _refresh(db, bundles, watched));
    _queue = next;
    return next;
  }
  Future<void> _refresh(AppDatabase db, List<SeriesBundle> series, Map<String, DateTime> watched) async {
    if (!supported) return;
    await initialize();
    final settings = await AlertSettings.load(db);
    await plugin.cancelAll();
    if (!settings.enabled) return;
    final now = DateTime.now();
    final pending = <({TitleData title, EpisodeData episode, DateTime time})>[];
    for (final bundle in series) {
      for (final episode in bundle.episodes) {
        if (episode.isSpecial || watched.containsKey(episode.key)) continue;
        final time = episodeAlertTime(episode, settings);
        if (time != null && time.isAfter(now)) pending.add((title: bundle.title, episode: episode, time: time));
      }
    }
    pending.sort((a,b) => a.time.compareTo(b.time));
    // Keep below iOS's 64 pending notification limit. Refill on each library sync.
    for (var i = 0; i < pending.length && i < 60; i++) {
      final item = pending[i];
      await plugin.zonedSchedule(id: i + 1, title: item.title.title,
        body: '${item.episode.code} · ${item.episode.title}',
        scheduledDate: tz.TZDateTime.from(item.time, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('episode_alerts', 'Episode alerts',
            channelDescription: 'Reminders for episodes in your library', importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ), androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }
}
