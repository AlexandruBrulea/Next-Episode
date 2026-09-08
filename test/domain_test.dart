import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/data/repositories.dart';

import 'fixtures.dart';

void main() {
  test('parses TV, movie and credits with distinct identity', () {
    expect(tv().key, 'tv:10');
    expect(movie().key, 'movie:10');
    expect(tv().title, 'Serial test');
    expect(tv().releaseDate, DateTime(2020, 1, 2));
    expect(tv().networks, ['Network']);
    expect(tv().runtimes, [42]);
    expect(movie().runtimes, [110]);
    expect(movie().directors, ['Director']);
    expect(movie().cast.single['name'], 'Actor');
  });
  test('parses seasons episodes and missing metadata', () {
    final s = bundle().seasons.first;
    final e = s.episodes.first;
    expect(s.id, 100);
    expect(e.seriesId, 10);
    expect(e.seasonId, 100);
    expect(e.title, 'Episodul 1');
    expect(e.code, 'S01E01');
    expect(e.runtime, 42);
    expect(e.rating, 8.1);
    expect(e.crew.single['name'], 'Director');
    expect(s.episodes.last.airDate, isNull);
    expect(dateLabel(null), 'Air date TBA');
    expect(TitleData(MediaType.movie, {'id': 2}).poster, '');
    expect(() => TitleData(MediaType.tv, {}), throwsFormatException);
  });
  test(
    'Romanian-English fallback preserves IDs and dates and matches nested IDs',
    () {
      final ro = {
        'id': 1,
        'name': '',
        'overview': 'Descriere română',
        'air_date': null,
        'episodes': [
          {'id': 1, 'name': ''},
          {'id': 2, 'name': 'Doi'},
        ],
      };
      final en = {
        'id': 9,
        'name': 'English',
        'overview': 'English overview',
        'air_date': '2026-01-01',
        'episodes': [
          {'id': 2, 'name': 'Two'},
          {'id': 1, 'name': 'One'},
        ],
      };
      final merged = localized(ro, en);
      expect(merged['name'], 'English');
      expect(merged['id'], 1);
      expect(merged['overview'], 'Descriere română');
      expect(merged['air_date'], null);
      expect(objects(merged['episodes']).map((e) => e['name']), ['One', 'Doi']);
    },
  );
  test('future, unknown and season zero excluded; today is available', () {
    final progress = WatchProgress.calculate(bundle(), {
      'episode:10:3': now,
      'episode:10:5': now,
    }, now);
    expect(progress.aired.map((e) => e.id), [1, 2]);
    expect(progress.seen, isEmpty);
    expect(progress.firstUnseen!.id, 1);
    expect(progress.fraction, 0);
  });
  test('all four local states and latest mark date', () {
    WatchProgress p(
      Map<String, DateTime> marks, {
      String status = 'Returning Series',
    }) => WatchProgress.calculate(bundle(status: status), marks, now);
    expect(p({}).state, 'Not started');
    expect(p({'episode:10:1': now}).state, 'Watching');
    final marks = {
      'episode:10:1': now,
      'episode:10:2': now.subtract(const Duration(hours: 1)),
    };
    expect(p(marks).state, 'Up to date');
    expect(p(marks).lastWatched!.id, 1);
    expect(p(marks, status: 'Ended').state, 'Up to date');
    expect(
      WatchProgress.calculate(
        bundle(
          status: 'Ended',
          episodes: [episodeJson(1, 1), episodeJson(2, 2)],
        ),
        marks,
        now,
      ).state,
      'Completed',
    );
    expect(p(marks, status: 'Canceled').state, 'Up to date');
    expect(p(marks).fraction, 1);
    expect(p(marks).firstUnseen, isNull);
  });
  test('empty and unknown-date series are not falsely completed', () {
    final p = WatchProgress.calculate(
      bundle(status: 'Ended', episodes: []),
      {},
      now,
    );
    expect(p.state, 'Not started');
    expect(p.fraction, 0);
  });
  test('first unseen uses season/episode order even if input is reversed', () {
    final p = WatchProgress.calculate(
      bundle(episodes: [episodeJson(2, 2), episodeJson(1, 1)]),
      {},
      now,
    );
    expect(p.firstUnseen!.id, 1);
  });
  test('status translations and no invented renewal confirmation', () {
    for (final entry in {
      'Returning Series': 'Ongoing',
      'Ended': 'Ended',
      'Canceled': 'Canceled',
      'In Production': 'In production',
      'Planned': 'Planned',
      'unknown': 'Unknown status',
    }.entries) {
      expect(tv(status: entry.key).statusLabel, entry.value);
    }
    expect(
      SeriesBundle(tv(), []).outlook,
      contains('No new season is confirmed'),
    );
    expect(bundle(episodes: []).outlook, contains('no episodes'));
    expect(bundle().outlook, contains('without an air date'));
  });
  test('sync detects new, removed, changed episodes, season and status', () {
    final before = bundle(episodes: [episodeJson(1, 1), episodeJson(2, 2)]);
    final after = bundle(
      status: 'Ended',
      episodes: [
        episodeJson(1, 1, name: 'Titlu nou'),
        episodeJson(3, 3),
      ],
    );
    final result = SyncRepository.compare(before, after);
    expect(result.newEpisodes, [3]);
    expect(result.changedEpisodes, [1]);
    expect(result.removedEpisodes, [2]);
    expect(result.statusChanged, isTrue);
    expect(result.hasChanges, isTrue);
    expect(SyncRepository.compare(after, after).hasChanges, isFalse);
    final newSeason = SeriesBundle(after.title, [
      ...after.seasons,
      SeasonData(10, {'id': 200, 'season_number': 2, 'episodes': []}),
    ]);
    expect(SyncRepository.compare(after, newSeason).newSeasons, [2]);
  });
}
