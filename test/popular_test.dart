import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/tmdb_provider.dart';
import 'package:next_episode/data/catalog/tvmaze_provider.dart';

import 'api_test.dart' show StubAdapter, response;

void main() {
  test('TMDB popular combines shows and movies with distinct identities', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = StubAdapter((request) async {
      expect(request.queryParameters['language'], 'en-US');
      final tv = request.path == '/tv/popular';
      expect(request.path, isIn(['/tv/popular', '/movie/popular']));
      return response({'total_pages': 4, 'results': [
        {'id': 1, if (tv) 'name': 'Popular show' else 'title': 'Popular movie', 'popularity': tv ? 20 : 30},
      ]});
    });
    final result = await TmdbProvider(token: 'test', client: dio).popular(1);
    expect(result.results.map((e) => e.key), ['movie:1', 'tv:1']);
    expect(result.totalPages, 4);
  });
  test('TVmaze reads ordered popular links and resolves unique API shows', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.tvmaze.com'));
    dio.httpClientAdapter = StubAdapter((request) async {
      if (request.uri.host == 'www.tvmaze.com') {
        return ResponseBody.fromString('<h2><a href="/shows/42/reacher">Reacher</a></h2><h2><a href="/shows/42/reacher">duplicate</a></h2><h2><a href="/shows/99/silo">Silo</a></h2>', 200,
          headers: {Headers.contentTypeHeader: ['text/html']});
      }
      final id = int.parse(request.uri.path.split('/').last);
      return response({'id': id, 'name': id == 42 ? 'Reacher' : 'Silo'});
    });
    final result = await TvmazeProvider(client: dio, wait: (_) async {}).popular(1);
    expect(result.results.map((e) => e.sourceId), [42, 99]);
    expect(result.results.every((e) => e.isTv), isTrue);
  });
}
