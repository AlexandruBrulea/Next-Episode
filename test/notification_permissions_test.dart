import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:next_episode/data/alerts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('iOS requests alerts, sound and badge only on opt-in and opens native settings', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final alerts = EpisodeAlerts();
    await alerts.initialize();
    expect(calls.any((c) => c.method == 'requestPermissions'), false);
    final options =
        calls.firstWhere((c) => c.method == 'initialize').arguments as Map;
    expect(options['requestAlertPermission'], false);
    expect(options['requestBadgePermission'], false);
    expect(await alerts.requestPermission(), true);
    final permissions =
        calls.firstWhere((c) => c.method == 'requestPermissions').arguments
            as Map;
    expect(permissions['alert'], true);
    expect(permissions['sound'], true);
    expect(permissions['badge'], true);
    String? method;
    messenger.setMockMethodCallHandler(EpisodeAlerts.settingsChannel, (
      call,
    ) async {
      method = call.method;
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        EpisodeAlerts.settingsChannel,
        null,
      ),
    );
    await alerts.openSystemSettings();
    expect(method, 'open');
  });
}
