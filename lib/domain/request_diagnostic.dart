/// Explicit allowlist: no headers, query values, bodies or exception messages.
class RequestDiagnostic {
  final String endpoint, exceptionType;
  final int? statusCode;
  final int durationMs, attempts;
  final DateTime occurredAt;
  final int? retryAfterSeconds;

  RequestDiagnostic({
    required String endpoint,
    required String exceptionType,
    this.statusCode,
    required this.durationMs,
    required this.attempts,
    required this.occurredAt,
    this.retryAfterSeconds,
  }) : endpoint = safeEndpoint(endpoint),
       exceptionType = _types.contains(exceptionType)
           ? exceptionType
           : 'unknown';

  static const _types = {
    'connectionTimeout',
    'sendTimeout',
    'receiveTimeout',
    'connectionError',
    'badResponse',
    'badCertificate',
    'cancel',
    'unknown',
    'invalidResponse',
    'rateLimitCooldown',
    'authenticationCooldown',
  };

  static String safeEndpoint(String path) {
    if (RegExp(r'^/(tv|movie)/\d+(/season/\d+)?$').hasMatch(path) ||
        RegExp(r'^/(search/(tv|movie|multi)|(tv|movie)/popular)$')
            .hasMatch(path)) {
      return path;
    }
    return path.startsWith('/find/') ? '/find/[redacted]' : '[redacted]';
  }

  Map<String, Object?> toJson() => {
    'provider': 'tmdb',
    'method': 'GET',
    'endpoint': endpoint,
    'exceptionType': exceptionType,
    'statusCode': statusCode,
    'durationMs': durationMs,
    'attempts': attempts,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (retryAfterSeconds != null) 'retryAfterSeconds': retryAfterSeconds,
  };

  static RequestDiagnostic? fromJson(Object? value) {
    if (value is! Map ||
        value['endpoint'] is! String ||
        value['exceptionType'] is! String ||
        value['durationMs'] is! int ||
        value['attempts'] is! int ||
        value['occurredAt'] is! String) {
      return null;
    }
    final date = DateTime.tryParse(value['occurredAt'] as String);
    if (date == null) return null;
    return RequestDiagnostic(
      endpoint: value['endpoint'] as String,
      exceptionType: value['exceptionType'] as String,
      statusCode: value['statusCode'] is int
          ? value['statusCode'] as int
          : null,
      durationMs: value['durationMs'] as int,
      attempts: value['attempts'] as int,
      occurredAt: date,
      retryAfterSeconds: value['retryAfterSeconds'] is int
          ? value['retryAfterSeconds'] as int
          : null,
    );
  }
}
