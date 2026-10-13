import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../domain/catalog_provider.dart';
import '../../domain/models.dart';
import '../../domain/request_diagnostic.dart';
import '../request_control.dart';

/// Bounded GET retries and a shared cooldown; never logs a Dio request/response.
class TmdbTransport {
  final Dio dio;
  final String token;
  final Future<void> Function()? checkContentAccess;
  final int maxAttempts;
  final Duration requestBudget;
  final DateTime Function() now;
  final Future<void> Function(Duration) sleep;
  final double Function() random;
  final RequestGate _gate;
  final _requests = SingleFlight<Json>();
  DateTime? _cooldownUntil;
  int _cooldownStatus = 429;
  bool _closed = false;

  TmdbTransport({
    required this.dio,
    required this.token,
    this.checkContentAccess,
    int concurrency = 4,
    int maxAttempts = 3,
    this.requestBudget = const Duration(seconds: 60),
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    double Function()? random,
  }) : maxAttempts = maxAttempts.clamp(1, 3),
       _gate = RequestGate(concurrency),
       now = now ?? DateTime.now,
       sleep = sleep ?? Future<void>.delayed,
       random = random ?? Random().nextDouble;

  Future<Json> get(String path, String language, Json parameters) {
    final key = jsonEncode([path, language, parameters]);
    return _requests.run(
      key,
      () => _gate.run(() => _get(path, language, parameters)),
    );
  }

  static Duration? retryAfter(String? value, DateTime now) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 2147483647));
    try {
      final delay = HttpDate.parse(value).difference(now.toUtc());
      return delay.isNegative ? Duration.zero : delay;
    } catch (_) {
      return null;
    }
  }

  void _cooldown(Duration delay, int status) {
    final until = now().add(delay);
    if (_cooldownUntil == null || until.isAfter(_cooldownUntil!)) {
      _cooldownUntil = until;
      _cooldownStatus = status;
    }
  }

  bool _temporary(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.badResponse => const {
      408,
      429,
      500,
      502,
      503,
      504,
    }.contains(error.response?.statusCode),
    _ => false,
  };

  String _message(String type, int? status) {
    if (status == 404) {
      return 'TMDB could not find this resource. Your saved data has been kept.';
    }
    if (status == 401 || status == 403) {
      return 'Invalid or unauthorized TMDB token.';
    }
    if (status == 429) return 'Too many TMDB requests. Please try again later.';
    if (type == 'invalidResponse') return 'Invalid TMDB response.';
    if (type.endsWith('Timeout')) return 'TMDB timed out. Please try again.';
    if (type == 'connectionError') {
      return 'No connection. Check your internet connection.';
    }
    return 'Unable to load TMDB data. Please try again.';
  }

  Future<Json> _get(String path, String language, Json parameters) async {
    await checkContentAccess?.call();
    if (token.trim().isEmpty) {
      throw const ApiFailure(
        'Missing TMDB token. Configure TMDB_TOKEN as described in the README. Your local library is still available.',
      );
    }
    final watch = Stopwatch()..start();
    var attempts = 0;
    ApiFailure failure(String type, int? status, {Duration? retry}) =>
        ApiFailure(
          _message(type, status),
          diagnostic: RequestDiagnostic(
            endpoint: path,
            exceptionType: type,
            statusCode: status,
            durationMs: watch.elapsedMilliseconds,
            attempts: attempts,
            occurredAt: now(),
            retryAfterSeconds: retry == null
                ? null
                : (retry.inMilliseconds / 1000).ceil(),
          ),
        );
    while (true) {
      if (_closed) throw failure('cancel', null);
      final cooldown = _cooldownUntil?.difference(now()) ?? Duration.zero;
      if (cooldown > Duration.zero) {
        // Long server pauses are deferred, not truncated or slept through while
        // holding up every title in a large library.
        if (cooldown > const Duration(seconds: 8) ||
            watch.elapsed + cooldown >= requestBudget) {
          throw failure(
            _cooldownStatus == 429
                ? 'rateLimitCooldown'
                : 'authenticationCooldown',
            _cooldownStatus,
            retry: cooldown,
          );
        }
        await sleep(cooldown);
        continue; // A concurrent response may have extended the global pause.
      }
      await checkContentAccess?.call();
      if (_closed) throw failure('cancel', null);
      final remaining = requestBudget - watch.elapsed;
      if (remaining <= Duration.zero) throw failure('receiveTimeout', null);
      attempts++;
      final cancel = CancelToken();
      try {
        final response = await dio
            .get<dynamic>(
              path,
              queryParameters: {...parameters, 'language': language},
              cancelToken: cancel,
              options: Options(
                headers: {
                  'Authorization': 'Bearer $token',
                  'accept': 'application/json',
                },
              ),
            )
            .timeout(
              remaining,
              onTimeout: () {
                cancel.cancel('Request budget exceeded');
                throw DioException(
                  requestOptions: RequestOptions(path: path),
                  type: DioExceptionType.receiveTimeout,
                );
              },
            );
        await checkContentAccess?.call();
        if (response.data is! Map) {
          throw failure('invalidResponse', response.statusCode);
        }
        return Json.from(response.data);
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        final backoff = Duration(
          milliseconds:
              (500 * pow(2, attempts - 1) * (0.5 + random().clamp(0, 1)))
                  .round(),
        );
        final serverDelay = retryAfter(
          error.response?.headers.value('retry-after'),
          now(),
        );
        if (status == 401 || status == 403) {
          _cooldown(const Duration(minutes: 5), status!);
        } else if (status == 429) {
          _cooldown(serverDelay ?? backoff, 429);
        }
        final delay = serverDelay != null && serverDelay > backoff
            ? serverDelay
            : backoff;
        if (!_temporary(error) ||
            attempts >= maxAttempts ||
            delay > const Duration(seconds: 8) ||
            watch.elapsed + delay >= requestBudget) {
          throw failure(error.type.name, status, retry: serverDelay);
        }
        await sleep(delay);
      } on FormatException {
        throw failure('invalidResponse', null);
      }
    }
  }

  void close() {
    _closed = true;
    dio.close(force: true);
  }
}
