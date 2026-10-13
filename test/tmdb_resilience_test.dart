import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/tmdb_provider.dart';
import 'package:next_episode/data/catalog/tmdb_transport.dart';
import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/domain/request_diagnostic.dart';

import 'api_test.dart' show StubAdapter, response;

Future<void> until(bool Function() ready) async {
  await (() async {
    while (!ready()) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  })().timeout(const Duration(seconds: 5));
}

void main() {
  test(
    'authentication failure pauses other resources without additional HTTP',
    () async {
      var calls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async {
        calls++;
        return response({}, 401);
      });
      final api = TmdbProvider(token: 'secret', client: dio);
      await expectLater(
        api.title(MediaType.movie, 1),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        api.title(MediaType.movie, 2),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.diagnostic?.exceptionType,
            'pause',
            'authenticationCooldown',
          ),
        ),
      );
      expect(calls, 1);
      api.close();
    },
  );

  test(
    'permission revoked during retry prevents another HTTP request',
    () async {
      var allowed = true;
      var calls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async {
        calls++;
        return response({}, 503);
      });
      final api = TmdbProvider(
        token: 'secret',
        client: dio,
        checkContentAccess: () async {
          if (!allowed) throw StateError('disabled');
        },
        sleep: (_) async {
          allowed = false;
        },
      );
      await expectLater(api.title(MediaType.movie, 1), throwsStateError);
      expect(calls, 1);
      api.close();
    },
  );

  for (final type in [
    DioExceptionType.badCertificate,
    DioExceptionType.cancel,
    DioExceptionType.unknown,
  ]) {
    test('$type is not retried and failed single-flight is released', () async {
      var calls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async {
        calls++;
        if (calls == 1) throw DioException(requestOptions: o, type: type);
        return response({'id': 1, 'title': 'Recovered'});
      });
      final api = TmdbProvider(
        token: 'secret',
        client: dio,
        sleep: (_) async {
          fail('Must not retry');
        },
      );
      await expectLater(
        api.title(MediaType.movie, 1),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 1);
      expect((await api.title(MediaType.movie, 1)).title, 'Recovered');
      expect(calls, 2);
      api.close();
    });
  }

  test(
    'temporary GET failure retries only the failed season with bounded jitter',
    () async {
      final calls = <String>[];
      final waits = <Duration>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async {
        calls.add(o.path);
        if (o.path == '/tv/7') {
          return response({
            'id': 7,
            'name': 'Show',
            'seasons': [
              {'season_number': 1},
            ],
          });
        }
        if (calls.length == 2) return response({}, 503);
        return response({'id': 70, 'season_number': 1, 'episodes': []});
      });
      final api = TmdbProvider(
        token: 'secret',
        client: dio,
        sleep: (d) async {
          waits.add(d);
        },
        random: () => 0.5,
      );
      await api.series(7);
      expect(calls, ['/tv/7', '/tv/7/season/1', '/tv/7/season/1']);
      expect(waits, [const Duration(milliseconds: 500)]);
      api.close();
    },
  );

  test(
    'timeouts stop at three attempts and preserve safe request diagnostics',
    () async {
      var calls = 0;
      final waits = <Duration>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async {
        calls++;
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.receiveTimeout,
          message: 'secret-body',
        );
      });
      final api = TmdbProvider(
        token: 'secret-token',
        client: dio,
        sleep: (d) async {
          waits.add(d);
        },
        random: () => 0.5,
      );
      try {
        await api.season(7, 3);
        fail('Expected timeout');
      } on ApiFailure catch (e) {
        expect(e.diagnostic!.endpoint, '/tv/7/season/3');
        expect(e.diagnostic!.exceptionType, 'receiveTimeout');
        expect(e.diagnostic!.attempts, 3);
        expect(jsonEncode(e.diagnostic!.toJson()), isNot(contains('secret')));
      }
      expect(calls, 3);
      expect(waits, [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
      ]);
      api.close();
    },
  );

  for (final status in [400, 401, 403, 404, 422, 501]) {
    test('HTTP $status is not retried', () async {
      var calls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = StubAdapter((o) async {
        calls++;
        return response({}, status);
      });
      final api = TmdbProvider(
        token: 'secret',
        client: dio,
        sleep: (_) async {
          fail('Must not retry');
        },
      );
      await expectLater(
        api.title(MediaType.movie, 7),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.diagnostic?.statusCode,
            'status',
            status,
          ),
        ),
      );
      expect(calls, 1);
      api.close();
    });
  }

  for (final asDate in [false, true]) {
    test(
      '429 respects Retry-After ${asDate ? 'HTTP date' : 'seconds'}',
      () async {
        var clock = DateTime.utc(2026, 10, 13);
        final start = clock;
        var calls = 0;
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
        dio.httpClientAdapter = StubAdapter((o) async {
          calls++;
          if (calls == 1) {
            return ResponseBody.fromString(
              '{}',
              429,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
                'retry-after': [
                  asDate
                      ? HttpDate.format(start.add(const Duration(seconds: 4)))
                      : '4',
                ],
              },
            );
          }
          expect(
            clock.difference(start),
            greaterThanOrEqualTo(const Duration(seconds: 4)),
          );
          return response({'id': 7, 'title': 'Film'});
        });
        final api = TmdbProvider(
          token: 'secret',
          client: dio,
          now: () => clock,
          sleep: (d) async {
            clock = clock.add(d);
          },
        );
        await api.title(MediaType.movie, 7);
        expect(calls, 2);
        api.close();
      },
    );
  }

  test('long Retry-After defers other titles without sleeping or sending more HTTP', () async {
    var clock = DateTime.utc(2026, 10, 13);
    var calls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = StubAdapter((o) async {
      calls++;
      return ResponseBody.fromString(
        '{}',
        429,
        headers: {
          'retry-after': ['120'],
        },
      );
    });
    final api = TmdbProvider(
      token: 'secret',
      client: dio,
      concurrency: 1,
      now: () => clock,
      sleep: (_) async {
        fail('Must defer');
      },
    );
    await expectLater(
      api.title(MediaType.movie, 1),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.diagnostic?.retryAfterSeconds,
          'retry',
          120,
        ),
      ),
    );
    await expectLater(
      api.title(MediaType.movie, 2),
      throwsA(
        isA<ApiFailure>().having((e) => e.diagnostic?.attempts, 'no HTTP', 0),
      ),
    );
    expect(calls, 1);
    clock = clock.add(const Duration(seconds: 121));
    await expectLater(
      api.title(MediaType.movie, 2),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 2);
    api.close();
  });

  test('identical requests share work and all endpoints share a four-request ceiling', () async {
    var calls = 0, active = 0, peak = 0;
    final release = Completer<void>();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = StubAdapter((o) async {
      calls++;
      active++;
      if (active > peak) peak = active;
      await release.future;
      active--;
      return response({
        'id': int.parse(o.path.split('/').last),
        'title': 'Film',
      });
    });
    final api = TmdbProvider(token: 'secret', client: dio, concurrency: 100);
    final same = List.generate(10, (_) => api.title(MediaType.movie, 1));
    final others = List.generate(8, (i) => api.title(MediaType.movie, i + 2));
    await until(() => calls == 4);
    release.complete();
    await Future.wait([...same, ...others]);
    expect(calls, 9);
    expect(peak, 4);
    await api.title(MediaType.movie, 1);
    expect(
      calls,
      10,
      reason: 'Completed responses are not cached by single-flight',
    );
    api.close();
  });

  test('request budget cancels a stalled GET', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = StubAdapter(
      (o) => Completer<ResponseBody>().future,
    );
    final api = TmdbProvider(
      token: 'secret',
      client: dio,
      requestBudget: const Duration(milliseconds: 20),
    );
    await expectLater(
      api.title(MediaType.movie, 1),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.diagnostic?.exceptionType,
          'timeout',
          'receiveTimeout',
        ),
      ),
    );
    api.close();
  });

  test(
    'diagnostic parsing never imports arbitrary URL, headers, type or body',
    () {
      final diagnostic = RequestDiagnostic.fromJson({
        'endpoint': 'https://example.test?token=secret',
        'exceptionType': 'secret',
        'durationMs': 100,
        'attempts': 2,
        'occurredAt': '2026-10-13T00:00:00Z',
        'headers': {'Authorization': 'secret'},
        'body': 'secret',
      })!;
      expect(jsonEncode(diagnostic.toJson()), isNot(contains('secret')));
      expect(TmdbTransport.retryAfter('invalid', DateTime.now()), isNull);
      expect(TmdbTransport.retryAfter('-1', DateTime.now()), Duration.zero);
    },
  );
}
