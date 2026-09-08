import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/data/catalog/tmdb_provider.dart';
import 'package:next_episode/domain/models.dart';

class StubAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  StubAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody response(dynamic json, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
void main() {
  test(
    'multi excludes people; English fallback uses ID and request auth/config',
    () async {
      final calls = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((options) async {
        calls.add(options);
        if (options.path == '/search/multi') {
          return response({
            'page': 2,
            'total_pages': 3,
            'results': [
              {'media_type': 'person', 'id': 99, 'name': 'Person'},
              {'media_type': 'tv', 'id': 1, 'name': '', 'overview': ''},
              {
                'media_type': 'movie',
                'id': 1,
                'title': 'Film',
                'overview': 'Rezumat',
              },
            ],
          });
        }
        return response({
          'id': 1,
          'name': 'English show',
          'overview': 'English description',
        });
      });
      final client = TmdbProvider(token: 'test-only-token', client: dio);
      final page = await client.search('Titlu tradus', null, 2);
      expect(page.results.map((e) => e.key), ['tv:1', 'movie:1']);
      expect(page.results.first.title, 'English show');
      expect(page.totalPages, 3);
      expect(calls.first.queryParameters['language'], 'en-US');
      expect(calls.first.queryParameters['page'], 2);
      expect(calls.first.queryParameters['include_adult'], false);
      expect(calls.first.headers['Authorization'], 'Bearer test-only-token');
      expect(calls.last.path, '/tv/1');
      expect(calls.last.queryParameters['language'], 'en-US');
    },
  );
  test(
    'filtered search routes to movie and tv and ignores empty search',
    () async {
      final calls = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async {
        calls.add(o.path);
        return response({'results': [], 'page': 1, 'total_pages': 0});
      });
      final client = TmdbProvider(token: 'test', client: dio);
      await client.search('Film', MediaType.movie, 1);
      await client.search('Serial', MediaType.tv, 1);
      await client.search(' ', null, 1);
      expect(calls, ['/search/movie', '/search/tv']);
    },
  );
  test(
    'season fallback translates episode text but never invents air date',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter(
        (o) async => response({
          'id': 10,
          'season_number': 1,
          'episodes': [
            {
              'id': 1,
              'name': o.queryParameters['language'] == 'ro-RO'
                  ? ''
                  : 'English episode',
              'season_number': 1,
              'episode_number': 1,
              'air_date': null,
            },
          ],
        }),
      );
      final season = await TmdbProvider(
        token: 'test',
        client: dio,
      ).season(2, 1);
      expect(season.episodes.single.title, 'English episode');
      expect(season.episodes.single.airDate, isNull);
    },
  );
  test(
    'missing token, invalid response and timeout are actionable failures',
    () async {
      await expectLater(
        TmdbProvider(token: '').title(MediaType.tv, 1),
        throwsA(isA<ApiFailure>()),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter(
        (o) async => response('not an object'),
      );
      await expectLater(
        TmdbProvider(token: 'test', client: dio).title(MediaType.tv, 1),
        throwsA(isA<ApiFailure>()),
      );
      dio.httpClientAdapter = StubAdapter(
        (o) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionTimeout,
        ),
      );
      await expectLater(
        TmdbProvider(token: 'test', client: dio).title(MediaType.tv, 1),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('timp'),
          ),
        ),
      );
    },
  );
  test('401 and rate limiting do not expose token in error', () async {
    for (final status in [401, 429]) {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async => response({}, status));
      await expectLater(
        TmdbProvider(
          token: 'secret-placeholder',
          client: dio,
        ).title(MediaType.movie, 1),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret-placeholder')),
          ),
        ),
      );
    }
  });
}
