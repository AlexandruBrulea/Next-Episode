import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/alerts.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/domain/models.dart';
import 'fixtures.dart';

void main() {
  test('before and after use exact airtime across midnight', () {
    final episode = EpisodeData(10, 100, {...episodeJson(1, 1), 'air_stamp': '2026-09-10T00:10:00Z'});
    expect(episodeAlertTime(episode, const AlertSettings(minutes: 30)), DateTime.utc(2026, 9, 9, 23, 40));
    expect(episodeAlertTime(episode, const AlertSettings(minutes: 65, after: true)), DateTime.utc(2026, 9, 10, 1, 15));
  });
  test('date-only uses configured fallback; unknown release is skipped', () {
    final settings = AlertSettings(minutes: 15, fallbackHour: 18, fallbackMinute: 30);
    expect(episodeAlertTime(EpisodeData(10, 100, episodeJson(1, 1, air: '2026-09-10')), settings), DateTime(2026, 9, 10, 18, 15));
    expect(episodeAlertTime(EpisodeData(10, 100, episodeJson(1, 1, air: null)), settings), isNull);
  });
  test('alert preferences persist and disabling keeps selected offset', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    expect((await AlertSettings.load(db)).enabled, isFalse);
    await const AlertSettings(enabled: true, after: true, minutes: 125, fallbackHour: 9).save(db);
    final enabled = await AlertSettings.load(db);
    expect(enabled.enabled, isTrue);
    expect(enabled.after, isTrue);
    expect(enabled.minutes, 125);
    await AlertSettings(enabled: false, after: enabled.after, minutes: enabled.minutes, fallbackHour: enabled.fallbackHour).save(db);
    final disabled = await AlertSettings.load(db);
    expect(disabled.enabled, isFalse);
    expect(disabled.minutes, 125);
  });
}
