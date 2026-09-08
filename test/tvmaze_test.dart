import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/tvmaze_provider.dart';
import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/domain/models.dart';

import 'api_test.dart' show StubAdapter, response;

Json showJson() => {
  'id': 42,
  'url': 'https://www.tvmaze.com/shows/42/example',
  'name': 'Example',
  'summary': '<p>One &amp; <b>two</b>.</p><p>Three.</p>',
  'status': 'Running',
  'premiered': '2020-01-01',
  'language': 'English',
  'rating': {'average': 8.5},
  'genres': ['Drama'],
  'image': {'medium': 'https://static.tvmaze.com/poster.jpg'},
  'webChannel': {'name': 'Stream', 'country': null},
  'externals': {'imdb': 'tt1234', 'thetvdb': 123},
  '_embedded': {'nextepisode': epJson(3, 3, air: '2099-01-01')},
};
Json epJson(
  int id,
  int? number, {
  String? air = '2020-01-01',
  String type = 'regular',
}) => {
  'id': id,
  'season': 1,
  'number': number,
  'name': null,
  'summary': '<p>Episode</p>',
  'type': type,
  'airdate': air,
  'runtime': 45,
  'rating': {'average': null},
  'image': null,
};

void main() {
  late Dio dio;
  late TvmazeProvider provider;
  final calls = <RequestOptions>[];
  setUp(() {
    calls.clear();
    dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    provider = TvmazeProvider(client: dio, wait: (_) async {});
    dio.httpClientAdapter = StubAdapter((o) async {
      calls.add(o);
      return response(switch (o.path) {
        '/search/shows' => [
          {'score': 1.0, 'show': showJson()},
        ],
        '/shows/42' => showJson(),
        '/shows/42/seasons' => [
          {'id': 100, 'number': 1, 'name': '', 'image': null, 'summary': null},
        ],
        '/shows/42/episodes' => [
          epJson(1, 1),
          epJson(2, null, type: 'significant_special'),
          epJson(3, 3, air: '2099-01-01'),
          epJson(4, 4, air: null),
        ],
        _ => null,
      });
    });
  });
  tearDown(() => provider.close());
  test(
    'no token, unpaginated TV search, HTML entities and full URLs',
    () async {
      final result = await provider.search('Example', null, 1);
      expect(result.totalPages, 1);
      expect(result.results.single.provider, 'tvmaze');
      expect(result.results.single.externalIds, {
        'imdb_id': 'tt1234',
        'tvdb_id': '123',
      });
      expect(result.results.single.overview, 'One & two.\nThree.');
      expect(
        result.results.single.poster,
        'https://static.tvmaze.com/poster.jpg',
      );
      expect(result.results.single.networks, ['Stream']);
      expect(calls.single.headers.containsKey('Authorization'), isFalse);
      expect(calls.single.queryParameters, {'q': 'Example'});
      expect((await provider.search('Example', null, 2)).results, isEmpty);
      expect(calls, hasLength(1));
    },
  );
  test('complete series uses three requests; specials isolated and no invented dates', () async {
    final bundle = await provider.series(42);
    expect(bundle.title.statusLabel, 'Ongoing');
    expect(bundle.title.nextEpisode!.id, 3);
    expect(bundle.seasons.map((s) => s.number), [1, 0]);
    expect(bundle.seasons.last.episodes.single.isSpecial, isTrue);
    expect(bundle.seasons.first.episodes.last.airDate, isNull);
    expect(bundle.seasons.first.episodes.first.title, 'Episodul 1');
    expect(bundle.title.raw['vote_count'], isNull);
    expect(calls, hasLength(3));
    expect(calls.last.queryParameters['specials'], 1);
    expect(
      WatchProgress.calculate(bundle, {}, DateTime(2026)).aired,
      hasLength(1),
    );
  });
  test('unsupported movies are explicit and do not make requests', () async {
    await expectLater(
      provider.search('Movie', MediaType.movie, 1),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      provider.title(MediaType.movie, 1),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, isEmpty);
  });
  test('429 retries are bounded', () async {
    var requests = 0;
    dio.httpClientAdapter = StubAdapter((o) async {
      requests++;
      return response({}, 429);
    });
    await expectLater(
      provider.search('Example', null, 1),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests, 3);
  });
  test(
    'malformed and incomplete responses cannot become empty snapshots',
    () async {
      dio.httpClientAdapter = StubAdapter(
        (o) async => response({'unexpected': true}),
      );
      await expectLater(
        provider.search('Example', null, 1),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(provider.series(42), throwsA(isA<ApiFailure>()));
    },
  );
  test(
    'external lookup handles 404 and falls back from IMDb to TVDB',
    () async {
      dio.httpClientAdapter = StubAdapter((o) async {
        calls.add(o);
        return o.queryParameters.containsKey('imdb')
            ? response({}, 404)
            : response(showJson());
      });
      final result = await provider.lookup(MediaType.tv, {
        'imdb_id': 'tt1234',
        'tvdb_id': '123',
      });
      expect(result!.id, 42);
      expect(calls, hasLength(2));
    },
  );
}
