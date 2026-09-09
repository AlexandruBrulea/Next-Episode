import 'dart:convert';

import '../domain/models.dart';

/// Six calendar months, clamped at the last day of the destination month.
DateTime tmdbExpiry(DateTime obtained) {
  final utc = obtained.toUtc();
  final first = DateTime.utc(utc.year, utc.month + 6);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(
    first.year,
    first.month,
    utc.day > last ? last : utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  );
}

const tmdbObtainedKey = '_tmdb_obtained_at';

Json stampTmdb(Json data, DateTime obtained) {
  final result = Json.from(data);
  if (result['title'] is Map) {
    result['title'] = stampTmdb(Json.from(result['title']), obtained);
  } else if (result['provider'] == 'tmdb' ||
      (result['provider'] == null && result['id'] is num)) {
    result.putIfAbsent(
      tmdbObtainedKey,
      () => obtained.toUtc().toIso8601String(),
    );
  }
  return result;
}

/// Retain only the user's stable selection pointer, never descriptive content.
Json unavailableTmdb(Json data) => {
  'id': data['id'],
  'provider': 'tmdb',
  'source_id': data['source_id'] ?? data['id'],
  'content_unavailable': true,
  'name': 'Details temporarily unavailable',
  'title': 'Details temporarily unavailable',
};

/// Handles embedded JSON in migration snapshots as well as normal metadata.
class TmdbScrubber {
  final DateTime now;
  final bool enabled;
  bool changed = false;
  DateTime? nextExpiry;
  TmdbScrubber(this.now, {required this.enabled});

  dynamic scrub(dynamic value, {DateTime? obtained, bool legacyTitle = false}) {
    if (value is String && (value.startsWith('{') || value.startsWith('['))) {
      try {
        final parsed = jsonDecode(value);
        final cleaned = scrub(
          parsed,
          obtained: obtained,
          legacyTitle: legacyTitle,
        );
        return jsonEncode(cleaned);
      } on FormatException {
        return value;
      }
    }
    if (value is List) {
      return [for (final item in value) scrub(item, obtained: obtained)];
    }
    if (value is! Map) return value;
    final data = Json.from(value);
    final timestamp =
        DateTime.tryParse(string(data[tmdbObtainedKey])) ?? obtained;
    final isTmdb =
        data['provider'] == 'tmdb' ||
        (legacyTitle && data['provider'] == null && data['id'] is num);
    if (isTmdb && data['content_unavailable'] != true && timestamp != null) {
      final expiry = tmdbExpiry(timestamp);
      if (expiry.isAfter(now.toUtc()) &&
          (nextExpiry == null || expiry.isBefore(nextExpiry!))) {
        nextExpiry = expiry;
      }
    }
    if (isTmdb &&
        data['content_unavailable'] != true &&
        (!enabled ||
            timestamp == null ||
            !now.toUtc().isBefore(tmdbExpiry(timestamp)))) {
      changed = true;
      return unavailableTmdb(data);
    }
    // A series envelope must lose its seasons along with its title.
    if (data['title'] is Map && data['seasons'] is List) {
      final title = scrub(
        data['title'],
        obtained: timestamp,
        legacyTitle: true,
      );
      if (title is Map && title['content_unavailable'] == true) {
        if ((data['seasons'] as List).isNotEmpty) changed = true;
        return {'title': title, 'seasons': <dynamic>[]};
      }
    }
    final rowTime =
        DateTime.tryParse(string(data['fetched_at'])) ??
        DateTime.tryParse(string(data['updated_at'])) ??
        timestamp;
    return {
      for (final entry in data.entries)
        entry.key: scrub(
          entry.value,
          obtained: rowTime,
          legacyTitle:
              (entry.key == 'title' && entry.value is Map) ||
              (entry.key == 'data' &&
                  (data.containsKey('local_id') || data.containsKey('type'))),
        ),
    };
  }
}
