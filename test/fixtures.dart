import 'package:next_episode/domain/models.dart';
import 'package:next_episode/domain/catalog_provider.dart';

final now = DateTime(2026, 9, 8, 14);
Json episodeJson(
  int id,
  int number, {
  int season = 1,
  String? air = '2026-09-01',
  String name = '',
}) => {
  'id': id,
  'season_number': season,
  'episode_number': number,
  'name': name,
  'air_date': air,
  'runtime': 42,
  'vote_average': 8.1,
  'vote_count': 20,
  'crew': [
    {'name': 'Director', 'job': 'Director'},
  ],
  'guest_stars': [
    {'name': 'Actor', 'character': 'Guest'},
  ],
};
TitleData tv({String status = 'Returning Series'}) => TitleData(MediaType.tv, {
  'id': 10,
  'name': 'Serial test',
  'original_name': 'Test Show',
  'overview': 'Descriere',
  'status': status,
  'first_air_date': '2020-01-02',
  'number_of_seasons': 1,
  'number_of_episodes': 5,
  'networks': [
    {'name': 'Network'},
  ],
  'genres': [
    {'name': 'Drama'},
  ],
  'origin_country': ['US'],
  'episode_run_time': [42],
  'seasons': [
    {'id': 100, 'season_number': 1, 'name': 'Season 1'},
  ],
});
TitleData movie() => TitleData(MediaType.movie, {
  'id': 10,
  'title': 'Film test',
  'original_title': 'Test Movie',
  'overview': 'Descriere film',
  'release_date': '2025-02-03',
  'runtime': 110,
  'status': 'Released',
  'credits': {
    'cast': [
      {'name': 'Actor'},
    ],
    'crew': [
      {'name': 'Director', 'job': 'Director'},
    ],
  },
});
SeriesBundle bundle({
  String status = 'Returning Series',
  List<Json>? episodes,
}) => SeriesBundle(tv(status: status), [
  SeasonData(10, {
    'id': 100,
    'season_number': 1,
    'episodes':
        episodes ??
        [
          episodeJson(1, 1),
          episodeJson(2, 2, air: '2026-09-08'),
          episodeJson(3, 3, air: '2026-09-09'),
          episodeJson(4, 4, air: null),
        ],
  }),
  SeasonData(10, {
    'id': 99,
    'season_number': 0,
    'episodes': [episodeJson(5, 1, season: 0)],
  }),
]);

class FakeApi extends CatalogProvider {
  @override
  String get id => 'tmdb';
  @override
  String get label => 'Test';
  @override
  CatalogCapabilities get capabilities => const CatalogCapabilities(
    movies: true,
    localizedText: true,
    paginatedSearch: true,
  );
  SeriesBundle value = bundle();
  bool fail = false;
  int calls = 0;
  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async {
    calls++;
    if (fail) throw const ApiFailure('Offline');
    return SearchPage(
      [
        if (type != MediaType.movie) value.title,
        if (type != MediaType.tv) movie(),
      ],
      page,
      1,
    );
  }

  @override
  Future<TitleData> title(MediaType type, int id) async {
    calls++;
    if (fail) throw const ApiFailure('Offline');
    return type == MediaType.tv ? value.title : movie();
  }

  @override
  Future<SeasonData> season(int seriesId, int number) async {
    if (fail) throw const ApiFailure('Offline');
    return value.seasons.firstWhere((s) => s.number == number);
  }
}
