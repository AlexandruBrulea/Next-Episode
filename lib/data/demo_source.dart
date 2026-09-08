import '../domain/models.dart';
import '../domain/catalog_provider.dart';

/// Explicit fictional fixtures, available only with --dart-define=DEMO=true.
/// Demo uses an in-memory database and never impersonates live TMDB responses.
class DemoSource extends CatalogProvider {
  @override
  String get id => 'demo';
  @override
  String get label => 'Demo';
  @override
  CatalogCapabilities get capabilities => const CatalogCapabilities(
    movies: true,
    localizedText: true,
    paginatedSearch: false,
  );
  String _date(int offset) =>
      day(DateTime.now())
          .add(Duration(days: offset))
          .toIso8601String()
          .split('T')
          .first;
  TitleData get demoSeries => TitleData(MediaType.tv, {
    'id': 900001,
    'name': 'Demo show',
    'original_name': 'Demo show',
    'overview': 'Sample data for testing. Mark the first episode, check your progress and open Calendar.',
    'status': 'Returning Series',
    'first_air_date': _date(-14),
    'number_of_seasons': 1,
    'number_of_episodes': 4,
    'networks': [
      {'name': 'Demo network'},
    ],
    'seasons': [
      {'id': 900010, 'season_number': 1, 'name': 'Season 1'},
      {'id': 900009, 'season_number': 0, 'name': 'Specials'},
    ],
  });
  TitleData get film => TitleData(MediaType.movie, {
    'id': 900002,
    'title': 'Demo movie',
    'overview': 'Sample movie for testing watched and unwatched states.',
    'release_date': _date(-30),
    'runtime': 95,
    'status': 'Released',
  });
  @override
  Future<SearchPage> popular(int page) async => SearchPage([demoSeries, film], 1, 1);

  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async =>
      SearchPage(
        [demoSeries, film]
            .where(
              (title) =>
                  (type == null || title.type == type) &&
                  '${title.title} ${title.originalTitle}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList(),
        1,
        1,
      );
  @override
  Future<TitleData> title(MediaType type, int id) async =>
      type == MediaType.tv ? demoSeries : film;
  @override
  Future<SeasonData> season(int seriesId, int number) async =>
      SeasonData(seriesId, {
        'id': number == 0 ? 900009 : 900010,
        'season_number': number,
        'name': number == 0 ? 'Specials' : 'Season 1',
        'episodes': [
          for (var i = 1; i <= (number == 0 ? 1 : 4); i++)
            {
              'id': 900100 + number * 10 + i,
              'season_number': number,
              'episode_number': i,
              'name': i == 4 ? '' : 'Demo episode $i',
              'overview': 'Sample description.',
              'air_date': i == 4
                  ? null
                  : _date(
                      i == 1
                          ? -7
                          : i == 2
                          ? 0
                          : 1,
                    ),
              'runtime': 42,
            },
        ],
      });
}
