import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/domain/schedule.dart';

import 'fixtures.dart';

void main() {
  test('continuous timeline anchors the full current week and keeps history above it', () {
    final timeline = buildScheduleTimeline([bundle(episodes: [
      episodeJson(1, 1, air: '2022-01-02'),
      episodeJson(2, 2, air: '2022-02-02'),
      episodeJson(3, 3, air: '2026-09-07'),
      episodeJson(4, 4, air: '2026-09-14'),
    ])], DateTime(2026, 9, 8));
    expect(timeline.past.map((s) => s.label), ['January 2022', 'February 2022']);
    expect(timeline.upcoming.first.label, 'Sep 7 – Sep 13 · 2026');
    expect(timeline.upcoming.first.entries.single.episodes.single.id, 3);
    expect(timeline.upcoming[1].entries.single.episodes.single.id, 4);
  });
  test('current week stays available even with no scheduled episodes', () {
    final timeline = buildScheduleTimeline([], DateTime(2026, 9, 8));
    expect(timeline.upcoming.single.label, 'Sep 7 – Sep 13 · 2026');
    expect(timeline.upcoming.single.entries, isEmpty);
  });
  test('historical shows are grouped separately by month and season', () {
    final first = bundle(episodes: [
      episodeJson(1, 1, air: '2022-01-02'),
      episodeJson(2, 2, air: '2022-01-09'),
      episodeJson(3, 3, air: '2022-02-03'),
    ]);
    final second = SeriesBundle(TitleData(MediaType.tv, {'id': 20, 'name': 'Second show'}), [
      SeasonData(20, {'id': 2, 'season_number': 2, 'episodes': [
        episodeJson(11, 1, season: 2, air: '2022-01-05'),
        episodeJson(12, 2, season: 2, air: '2022-02-05'),
      ]}),
    ]);
    final sections = buildSchedule([first, second], DateTime(2026, 9, 8), year: 2022);
    expect(sections.map((s) => s.label), ['January 2022', 'February 2022']);
    expect(sections.map((s) => s.entries.length), [2, 2]);
    final january = sections.first.entries.first;
    expect(january.dateRange, 'Jan 2 – Jan 9');
    expect(january.episodeRange, 'S01 E01–E02');
    expect(january.allWatched({'episode:10:1': now}), isFalse);
    expect(january.allWatched({'episode:10:1': now, 'episode:10:2': now}), isTrue);
  });
  test('upcoming uses weeks, keeps today and unknown dates, excludes past and specials', () {
    final series = bundle(episodes: [
      episodeJson(1, 1, air: '2026-09-07'),
      episodeJson(2, 2, air: '2026-09-08'),
      episodeJson(3, 3, air: '2026-09-13'),
      episodeJson(4, 4, air: '2026-09-14'),
      episodeJson(6, 6, air: null),
    ]);
    final sections = buildSchedule([series], DateTime(2026, 9, 8));
    expect(sections.map((s) => s.label), ['Sep 7 – Sep 13 · 2026', 'Sep 14 – Sep 20 · 2026', 'Date TBA']);
    expect(sections.first.entries.single.episodeRange, 'S01 E02–E03');
    expect(sections.expand((s) => s.entries).expand((e) => e.episodes).map((e) => e.id), [2, 3, 4, 6]);
  });
  test('gaps are not represented as consecutive episodes', () {
    final series = bundle(episodes: [episodeJson(1, 1), episodeJson(3, 3)]);
    final entry = ScheduleEntry(series.title, 1, series.seasons.first.episodes);
    expect(entry.episodeRange, 'S01 E01, E03');
  });
}
