import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

import '../../domain/catalog_provider.dart';
import '../../domain/models.dart';

class TvmazeProvider extends CatalogProvider {
  Future<SearchPage>? _popularLoading;
  final Dio dio;
  final Future<void> Function(Duration) delay;
  TvmazeProvider({
    Dio? client,
    String baseUrl = 'https://api.tvmaze.com',
    Future<void> Function(Duration)? wait,
  }) : dio =
           client ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               headers: {'User-Agent': 'NextEpisode/0.1 (Flutter)'},
             ),
           ),
       delay = wait ?? Future<void>.delayed;
  @override
  String get id => 'tvmaze';
  @override
  String get label => 'TVmaze';
  @override
  CatalogCapabilities get capabilities => const CatalogCapabilities(
    movies: false,
    localizedText: false,
    paginatedSearch: false,
  );

  Future<dynamic> _get(
    String path, [
    Json parameters = const {},
    bool allowMissing = false,
  ]) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return (await dio.get<dynamic>(path, queryParameters: parameters)).data;
      } on DioException catch (e) {
        if (allowMissing && e.response?.statusCode == 404) return null;
        if (e.response?.statusCode == 429 && attempt < 2) {
          await delay(Duration(seconds: 2 << attempt));
          continue;
        }
        throw ApiFailure(switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout =>
            'TVmaze timed out. Please try again.',
          DioExceptionType.connectionError =>
            'No connection. Your saved library is still available.',
          _ =>
            e.response?.statusCode == 429
                ? 'TVmaze is rate limiting requests. Please try again later.'
                : 'Unable to load TVmaze data. Please try again.',
        });
      }
    }
  }

  Json _object(dynamic data) {
    if (data is! Map || integer(data['id']) <= 0) {
      throw const ApiFailure('Invalid TVmaze response.');
    }
    return Json.from(data);
  }

  List<Json> _list(dynamic data) {
    if (data is! List || data.any((e) => e is! Map)) {
      throw const ApiFailure('Invalid TVmaze response.');
    }
    return objects(data);
  }

  String _plain(dynamic value) =>
      html
          .parseFragment(
            string(value)
                .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
                .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
          )
          .text
          ?.trim() ??
      '';
  String _image(dynamic value) =>
      value is Map ? textOr(value['medium'], string(value['original'])) : '';
  Json _embedded(Json data) =>
      data['_embedded'] is Map ? Json.from(data['_embedded']) : {};

  TitleData _show(
    Json show, {
    List<Json> seasons = const [],
    List<Json> episodes = const [],
  }) {
    final network = show['network'] ?? show['webChannel'];
    final country = network is Map ? network['country'] : null;
    final externals = show['externals'] is Map
        ? Json.from(show['externals'])
        : <String, dynamic>{};
    final embedded = _embedded(show);
    return TitleData(MediaType.tv, {
      'id': show['id'],
      'source_id': show['id'],
      'provider': id,
      'source_url': show['url'],
      'name': show['name'],
      'original_name': show['name'],
      'overview': _plain(show['summary']),
      'poster_path': _image(show['image']),
      'backdrop_path': '',
      'first_air_date': show['premiered'],
      'last_air_date': embedded['previousepisode'] is Map
          ? embedded['previousepisode']['airdate']
          : show['ended'],
      'status': switch (show['status']) {
        'Running' => 'Returning Series',
        'Ended' => 'Ended',
        'In Development' => 'In Production',
        _ => '',
      },
      'source_status': show['status'],
      'created_by': objects(show['crew']).where((e) => e['type'] == 'Creator')
          .map((e) => {'name': e['person']?['name']}).toList(),
      'original_language': show['language'],
      'vote_average': show['rating'] is Map ? show['rating']['average'] : null,
      'vote_count': null,
      'genres': (show['genres'] as List? ?? [])
          .map((g) => {'name': string(g)})
          .toList(),
      'networks': [
        if (network is Map) {'name': network['name']},
      ],
      'origin_country': [if (country is Map) country['code']],
      'episode_run_time': [
        if ((show['averageRuntime'] ?? show['runtime']) is num)
          show['averageRuntime'] ?? show['runtime'],
      ],
      'number_of_seasons': seasons
          .where((s) => integer(s['season_number']) > 0)
          .length,
      'number_of_episodes': episodes
          .where((e) => e['is_special'] != true)
          .length,
      'seasons': seasons,
      'last_episode_to_air': embedded['previousepisode'] is Map
          ? _episode(Json.from(embedded['previousepisode']))
          : null,
      'next_episode_to_air': embedded['nextepisode'] is Map
          ? _episode(Json.from(embedded['nextepisode']))
          : null,
      'credits': {
        'cast': objects(embedded['cast'])
            .map(
              (e) => {
                'name': e['person']?['name'],
                'profile_path': _image(e['person']?['image']),
                'character': e['character']?['name'],
              },
            )
            .toList(),
      },
      'external_ids': {
        'imdb_id': externals['imdb'],
        'tvdb_id': externals['thetvdb'],
      },
    });
  }

  Json _episode(Json episode) {
    _object(episode);
    final special =
        string(episode['type']).contains('special') ||
        episode['number'] == null;
    return {
      'id': episode['id'],
      'source_id': episode['id'],
      'provider': id,
      'source_url': episode['url'],
      'name': episode['name'],
      'overview': _plain(episode['summary']),
      'season_number': special ? 0 : episode['season'],
      'original_season': episode['season'],
      'episode_number': episode['number'] ?? 0,
      'is_special': special,
      'air_date': episode['airdate'],
      'air_stamp': episode['airstamp'],
      'runtime': episode['runtime'],
      'still_path': _image(episode['image']),
      'vote_average': episode['rating'] is Map
          ? episode['rating']['average']
          : null,
      'vote_count': null,
    };
  }

  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async {
    if (type == MediaType.movie) {
      throw const ApiFailure(
        'TVmaze provides shows, not movies. Saved movies remain in your library.',
      );
    }
    if (query.trim().isEmpty || page > 1) return SearchPage([], page, 1);
    final results = _list(await _get('/search/shows', {'q': query.trim()}));
    return SearchPage(
      results.map((r) => _show(_object(r['show']))).toList(),
      1,
      1,
    );
  }

  @override
  Future<SearchPage> popular(int page) {
    if (page > 1) return Future.value(SearchPage([], page, 1));
    return _popularLoading ??= _loadPopular().whenComplete(() {
      _popularLoading = null;
    });
  }

  Future<SearchPage> _loadPopular() async {
    // The public API has no popularity endpoint. Read the ordered show links
    // from TVmaze's public popular listing, then normalize via the public API.
    final response = await dio.get<String>('https://www.tvmaze.com/shows',
      options: Options(responseType: ResponseType.plain));
    final document = html.parse(response.data ?? '');
    final ids = <int>{};
    for (final anchor in document.querySelectorAll('h2 a[href]')) {
      final uri = Uri.tryParse(anchor.attributes['href'] ?? '');
      if (uri == null || (uri.hasAuthority && uri.host != 'www.tvmaze.com' && uri.host != 'tvmaze.com')) continue;
      final match = RegExp(r'^/shows/(\d+)(?:/|$)').firstMatch(uri.path);
      if (match != null) ids.add(int.parse(match.group(1)!));
      if (ids.length == 20) break;
    }
    if (ids.isEmpty) throw const ApiFailure('Popular shows are temporarily unavailable.');
    final ordered = ids.toList();
    final shows = <TitleData>[];
    for (var i = 0; i < ordered.length; i += 2) {
      if (i > 0) await delay(const Duration(seconds: 1));
      shows.addAll(await Future.wait(ordered.skip(i).take(2).map((id) async => _show(_object(await _get('/shows/$id'))))));
    }
    return SearchPage(shows, 1, 1);
  }

  @override
  Future<TitleData> title(MediaType type, int id) async {
    if (type != MediaType.tv) throw const ApiFailure('TVmaze does not provide movies.');
    final show = _object(
      await _get('/shows/$id', {
        'embed[]': ['cast', 'previousepisode', 'nextepisode'],
      }),
    );
    if (integer(show['id']) != id) {
      throw const ApiFailure('Invalid TVmaze identity.');
    }
    await _loadCrew(show, id);
    return _show(show);
  }

  Future<void> _loadCrew(Json show, int id) async {
    try {
      show['crew'] = _list(await _get('/shows/$id/crew'));
    } catch (_) {
      // Optional credits must not prevent access to the show or watch history.
    }
  }

  @override
  Future<SeriesBundle> series(int id) async {
    final show = _object(
      await _get('/shows/$id', {
        'embed[]': ['cast', 'previousepisode', 'nextepisode'],
      }),
    );
    if (integer(show['id']) != id) {
      throw const ApiFailure('Invalid TVmaze identity.');
    }
    await _loadCrew(show, id);
    final seasonRows = _list(await _get('/shows/$id/seasons'));
    final episodes = _list(await _get('/shows/$id/episodes', {'specials': 1}))
        .map(_episode)
        .toList();
    final seasons = <Json>[
      for (final season in seasonRows)
        {
          'id': _object(season)['id'],
          'season_number': season['number'],
          'name': season['name'],
          'overview': _plain(season['summary']),
          'poster_path': _image(season['image']),
          'air_date': season['premiereDate'],
          'episodes': episodes
              .where(
                (e) =>
                    e['season_number'] == season['number'] &&
                    e['is_special'] != true,
              )
              .toList(),
        },
      if (episodes.any((e) => e['is_special'] == true))
        {
          'id': 0,
          'season_number': 0,
          'name': 'Specials',
          'episodes': episodes.where((e) => e['is_special'] == true).toList(),
        },
    ];
    // Do not silently lose episodes if provider metadata lacks their season.
    for (final n
        in episodes
            .where((e) => e['is_special'] != true)
            .map((e) => integer(e['season_number']))
            .toSet()) {
      if (!seasons.any((s) => s['season_number'] == n)) {
        throw const ApiFailure(
          'TVmaze returned episodes without a matching season. Please try again later.',
        );
      }
    }
    return SeriesBundle(
      _show(show, seasons: seasons, episodes: episodes),
      seasons.map((s) => SeasonData(id, s)).toList(),
    );
  }

  @override
  Future<SeasonData> season(int seriesId, int number) async =>
      (await series(seriesId)).seasons.firstWhere(
        (s) => s.number == number,
        orElse: () => throw const ApiFailure('Season unavailable.'),
      );
  @override
  Future<TitleData?> lookup(
    MediaType type,
    Map<String, String> externalIds,
  ) async {
    if (type != MediaType.tv) return null;
    for (final key in ['imdb_id', 'tvdb_id']) {
      final value = externalIds[key];
      if (value == null || value.isEmpty) continue;
      final response = await _get('/lookup/shows', {
        key == 'imdb_id' ? 'imdb' : 'thetvdb': value,
      }, true);
      if (response != null) return _show(_object(response));
    }
    return null;
  }

  @override
  void close() => dio.close();
}
