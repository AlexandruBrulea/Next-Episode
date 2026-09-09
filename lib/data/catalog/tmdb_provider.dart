import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../../domain/catalog_provider.dart';
import '../tmdb_retention.dart';

class TmdbProvider extends CatalogProvider {
  @override
  String get id => 'tmdb';
  @override
  String get label => 'TMDB';
  @override
  CatalogCapabilities get capabilities => const CatalogCapabilities(
    movies: true,
    localizedText: true,
    paginatedSearch: true,
  );
  final Dio dio;
  final String token;
  final Future<void> Function()? checkContentAccess;
  TmdbProvider({
    required this.token,
    this.checkContentAccess,
    Dio? client,
    String baseUrl = 'https://api.themoviedb.org/3',
  }) : dio =
           client ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
             ),
           );
  Future<Json> _get(
    String path,
    String language, [
    Json parameters = const {},
  ]) async {
    await checkContentAccess?.call();
    if (token.trim().isEmpty) {
      throw const ApiFailure(
        'Missing TMDB token. Configure TMDB_TOKEN as described in the README. Your local library is still available.',
      );
    }
    try {
      final response = await dio.get<dynamic>(
        path,
        queryParameters: {...parameters, 'language': language},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'accept': 'application/json',
          },
        ),
      );
      await checkContentAccess?.call();
      if (response.data is! Map) throw const FormatException();
      return Json.from(response.data);
    } on DioException catch (e) {
      throw ApiFailure(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'TMDB timed out. Please try again.',
        DioExceptionType.connectionError =>
          'No connection. Check your internet connection.',
        _ => switch (e.response?.statusCode) {
          401 || 403 => 'Invalid or unauthorized TMDB token.',
          429 => 'Too many TMDB requests. Please try again later.',
          _ => 'Unable to load TMDB data. Please try again.',
        },
      });
    } on FormatException {
      throw const ApiFailure('Invalid TMDB response.');
    }
  }

  Future<Json> _localized(String path, [Json parameters = const {}]) async {
    return _get(path, 'en-US', parameters);
  }

  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async {
    if (query.trim().isEmpty) return const SearchPage([], 1, 0);
    final data = await _get('/search/${type?.name ?? 'multi'}', 'en-US', {
      'query': query.trim(),
      'page': page,
      'include_adult': false,
    });
    if (data['results'] is! List || data['total_pages'] is! num) {
      throw const ApiFailure('Invalid search response.');
    }
    final results = <TitleData>[];
    for (final item in objects(data['results'])) {
      final media = type?.name ?? string(item['media_type']);
      if (media != 'tv' && media != 'movie') continue;
      final kind = MediaType.values.byName(media);
      var merged = item;
      if (string(item[media == 'tv' ? 'name' : 'title']).trim().isEmpty ||
          string(item['overview']).trim().isEmpty) {
        // Match by identity, never by translated title or page position.
        merged = localized(
          item,
          await _get('/$media/${integer(item['id'])}', 'en-US'),
        );
      }
      results.add(_normalize(kind, merged));
    }
    return SearchPage(
      results,
      integer(data['page'], page),
      integer(data['total_pages']),
    );
  }

  @override
  Future<SearchPage> popular(int page) async {
    final responses = await Future.wait([
      _get('/tv/popular', 'en-US', {'page': page}),
      _get('/movie/popular', 'en-US', {'page': page}),
    ]);
    final titles = <TitleData>[];
    var totalPages = 1;
    for (var i = 0; i < responses.length; i++) {
      final data = responses[i];
      if (data['results'] is! List) {
        throw const ApiFailure('Invalid popular titles response.');
      }
      final pages = integer(data['total_pages'], 1);
      if (i == 0 || pages < totalPages) totalPages = pages;
      for (final item in objects(data['results'])) {
        if (item['adult'] == true) continue;
        titles.add(_normalize(i == 0 ? MediaType.tv : MediaType.movie, item));
      }
    }
    titles.sort(
      (a, b) =>
          decimal(b.raw['popularity']).compareTo(decimal(a.raw['popularity'])),
    );
    return SearchPage(titles, page, totalPages.clamp(1, 500).toInt());
  }

  @override
  Future<TitleData> title(MediaType type, int id) async {
    final data = await _localized('/${type.name}/$id', {
      'append_to_response': 'credits,external_ids,videos,watch/providers',
    });
    if (integer(data['id']) != id ||
        (type == MediaType.tv && data['seasons'] is! List)) {
      throw const ApiFailure('Invalid details response.');
    }
    return _normalize(type, data);
  }

  @override
  Future<SeasonData> season(int seriesId, int number) async {
    final data = await _localized('/tv/$seriesId/season/$number');
    if (data['episodes'] is! List ||
        integer(data['id']) <= 0 ||
        integer(data['season_number'], -1) != number) {
      throw const ApiFailure('Invalid season response.');
    }
    final result = SeasonData(seriesId, {
      ...data,
      'poster_path': _image(data['poster_path']),
      'episodes': objects(data['episodes'])
          .map((e) => {...e, 'still_path': _image(e['still_path'])})
          .toList(),
    });
    result.episodes; // Validate before any snapshot can be persisted.
    return result;
  }

  String _image(dynamic path) =>
      string(path).isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$path';
  TitleData _normalize(MediaType type, Json data) => TitleData(type, {
    ...data,
    'provider': id,
    tmdbObtainedKey: DateTime.now().toUtc().toIso8601String(),
    'source_id': data['id'],
    'source_url': 'https://www.themoviedb.org/${type.name}/${data['id']}',
    'poster_path': _image(data['poster_path']),
    'backdrop_path': _image(data['backdrop_path']),
    'seasons': objects(data['seasons'])
        .map((s) => {...s, 'poster_path': _image(s['poster_path'])})
        .toList(),
    'external_ids': {
      if (data['external_ids'] is Map) ...Json.from(data['external_ids']),
      if (data['imdb_id'] != null) 'imdb_id': data['imdb_id'],
    },
  });
  @override
  Future<TitleData?> lookup(
    MediaType type,
    Map<String, String> externalIds,
  ) async {
    for (final key in ['imdb_id', if (type == MediaType.tv) 'tvdb_id']) {
      final value = externalIds[key];
      if (value == null || value.isEmpty) continue;
      final response = await _get(
        '/find/${Uri.encodeComponent(value)}',
        'en-US',
        {'external_source': key},
      );
      final candidates = objects(
        response[type == MediaType.tv ? 'tv_results' : 'movie_results'],
      );
      if (candidates.length == 1) {
        return title(type, integer(candidates.single['id']));
      }
      if (candidates.length > 1) return null;
    }
    return null;
  }

  @override
  void close() => dio.close();
}
