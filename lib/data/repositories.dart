import 'dart:convert';

import '../domain/models.dart';
import 'database.dart';
import 'feedback.dart';
import 'catalog/catalog_router.dart';
import '../domain/catalog_provider.dart';
import '../domain/request_diagnostic.dart';
import 'request_control.dart';

class Loaded<T> {
  final T value;
  final bool offline;
  final String? warning;
  final ApiFailure? failure;
  const Loaded(this.value, {this.offline = false, this.warning, this.failure});
}

class SeriesRepository {
  final CatalogProvider api;
  final AppDatabase db;
  SeriesRepository(this.api, this.db);
  Future<SeriesBundle?> cached(int id) async {
    final result = await db.cached('series:$id');
    return result == null ? null : SeriesBundle.fromJson(result.data);
  }

  Future<SeriesBundle> fetch(int id) async {
    return api.series(id);
  }

  Future<void> save(SeriesBundle bundle, DateTime now) async {
    // The router commits identities and cache together. A delayed repository
    // continuation must never overwrite a newer administrative deployment.
    if (api is CatalogRouter) return;
    await db.cache('series:${bundle.title.id}', bundle.toJson(), now);
    await db.updateTitle(bundle.title, now);
  }

  Future<Loaded<SeriesBundle>> load(int id, {bool refresh = false}) async {
    final previous = await cached(id);
    if (previous != null && !refresh) return Loaded(previous);
    try {
      final value = await fetch(id);
      await db.transaction(() async {
        await save(value, DateTime.now());
        if (previous != null) {
          await db.saveChanges(
            SyncRepository.compare(previous, value),
            DateTime.now(),
          );
        }
      });
      return Loaded(value);
    } catch (error) {
      final permitted = await cached(id);
      if (permitted != null) {
        return Loaded(permitted, offline: true, warning: '$error');
      }
      rethrow;
    }
  }
}

class MoviesRepository {
  final CatalogProvider api;
  final AppDatabase db;
  MoviesRepository(this.api, this.db);
  Future<Loaded<TitleData>> load(int id, {bool refresh = false}) async {
    final old = await db.cached('movie:$id');
    if (old != null && !refresh) {
      return Loaded(TitleData(MediaType.movie, old.data));
    }
    try {
      final value = await api.title(MediaType.movie, id);
      await db.transaction(() async {
        if (api is CatalogRouter) return;
        await db.cache('movie:$id', value.raw, DateTime.now());
        await db.updateTitle(value, DateTime.now());
      });
      return Loaded(value);
    } catch (error) {
      final permitted = await db.cached('movie:$id');
      if (permitted != null) {
        return Loaded(
          TitleData(MediaType.movie, permitted.data),
          offline: true,
          warning: error is ApiFailure
              ? error.message
              : 'Movie information could not be updated.',
          failure: error is ApiFailure ? error : null,
        );
      }
      rethrow;
    }
  }
}

class LibraryRepository {
  final AppDatabase db;
  LibraryRepository(this.db);
  Future<List<LibraryEntry>> all() => db.library();
  Future<void> add(TitleData title) => db.add(title, DateTime.now());
  // Deliberately retain watched and cached rows for re-adding and offline use.
  Future<void> remove(String key) => db.remove(key);
}

class ProgressRepository {
  final AppDatabase db;
  ProgressRepository(this.db);
  Future<Map<String, DateTime>> all() => db.watched();
  Future<void> episode(EpisodeData episode, bool seen, {DateTime? now}) async {
    await episodes([episode], seen, now: now);
  }

  Future<void> episodes(
    Iterable<EpisodeData> episodes,
    bool seen, {
    DateTime? now,
  }) async {
    final instant = now ?? DateTime.now();
    final items = episodes.toList();
    if (seen && items.any((episode) => !episode.released(instant))) {
      throw const ApiFailure(
        'This episode has not been released yet or has no announced air date.',
      );
    }
    await db.markMany(items.map((e) => e.key), seen, instant);
  }

  Future<void> movie(int id, bool seen) =>
      db.mark('movie:$id', seen, DateTime.now());
  Future<void> season(SeasonData season, bool seen, {DateTime? now}) async {
    final instant = now ?? DateTime.now();
    await episodes(
      season.episodes.where((e) => !seen || e.released(instant)),
      seen,
      now: instant,
    );
  }
}

class SyncReport {
  final Set<String> refreshedKeys;
  final List<SyncChanges> changes;
  final List<String> errors;
  final List<SyncIssue> issues;
  const SyncReport(
    this.changes,
    this.errors, {
    this.refreshedKeys = const {},
    this.issues = const [],
  });
  String get message => errors.isEmpty
      ? 'Your library is up to date.'
      : 'Your data is safe. Some information could not be updated right now.';
}

class SyncIssue {
  final String title, message;
  final String? entityKey;
  final DateTime? occurredAt;
  final RequestDiagnostic? diagnostic;
  const SyncIssue(
    this.title,
    this.message, {
    this.entityKey,
    this.occurredAt,
    this.diagnostic,
  });
  FeedbackIssue toFeedback() => FeedbackIssue(
    title,
    message,
    occurredAt ?? DateTime.now(),
    entityKey: entityKey,
    diagnostic: diagnostic,
  );
}

class SyncRepository {
  final AppDatabase db;
  final SeriesRepository series;
  final MoviesRepository movies;
  final int concurrency;
  final DateTime Function() now;
  final _refreshes = SingleFlight<SyncReport>();
  final _failures =
      <String, ({DateTime retryAt, SyncIssue issue, String identity})>{};
  SyncRepository(
    this.db,
    this.series,
    this.movies, {
    int concurrency = const int.fromEnvironment(
      'SYNC_CONCURRENCY',
      defaultValue: 3,
    ),
    DateTime Function()? now,
  }) : concurrency = concurrency.clamp(1, 4),
       now = now ?? DateTime.now;
  static SyncChanges compare(SeriesBundle? before, SeriesBundle after) {
    String metadata(TitleData title) => jsonEncode({
      for (final entry in title.raw.entries)
        if (entry.key != '_tmdb_obtained_at') entry.key: entry.value,
    });
    final old = {for (final e in before?.episodes ?? <EpisodeData>[]) e.id: e};
    final current = {for (final e in after.episodes) e.id: e};
    final oldSeasons = before?.seasons.map((s) => s.number).toSet() ?? <int>{};
    return SyncChanges(
      after.title.key,
      current.keys.where((id) => !old.containsKey(id)).toList(),
      current.keys
          .where(
            (id) =>
                old.containsKey(id) &&
                jsonEncode(old[id]!.raw) != jsonEncode(current[id]!.raw),
          )
          .toList(),
      old.keys.where((id) => !current.containsKey(id)).toList(),
      after.seasons
          .map((s) => s.number)
          .where((n) => !oldSeasons.contains(n))
          .toList(),
      before != null && before.title.status != after.title.status,
      before != null && metadata(before.title) != metadata(after.title),
    );
  }

  Future<SyncReport> refresh({bool onlyStale = false}) =>
      _refreshes.run('library', () => _refresh(onlyStale: onlyStale));

  Future<SyncReport> _refresh({required bool onlyStale}) async {
    final changes = <SyncChanges>[];
    final errors = <String>[];
    final issues = <SyncIssue>[];
    final refreshedKeys = <String>{};
    final entries = await db.library(); // Also removes expired cache rows.
    final keys = entries.map((e) => e.title.key).toSet();
    _failures.removeWhere((key, _) => !keys.contains(key));
    final cachedKeys = {
      for (final row in await db.customSelect('SELECT key FROM cache').get())
        row.read<String>('key'),
    };
    final pending = <LibraryEntry>[];
    for (final entry in entries) {
      final deferred = _failures[entry.title.key];
      final failedIdentity =
          deferred != null &&
          deferred.identity ==
              '${entry.title.provider}:${entry.title.sourceId}';
      if (onlyStale &&
          deferred != null &&
          now().isBefore(deferred.retryAt) &&
          failedIdentity) {
        issues.add(deferred.issue);
        errors.add('${deferred.issue.title}: ${deferred.issue.message}');
        continue;
      }
      if (onlyStale &&
          !failedIdentity &&
          entry.title.provider == series.api.id &&
          entry.updatedAt != null &&
          now().difference(entry.updatedAt!) <
              (['Ended', 'Canceled'].contains(entry.title.status)
                  ? const Duration(days: 7)
                  : const Duration(hours: 6)) &&
          cachedKeys.contains(
            entry.title.isTv
                ? 'series:${entry.title.id}'
                : 'movie:${entry.title.id}',
          )) {
        continue;
      }
      pending.add(entry);
    }
    // Active shows first; retain the existing ordering within each group.
    final ordered = [
      ...pending.where(
        (e) => e.title.isTv && !['Ended', 'Canceled'].contains(e.title.status),
      ),
      ...pending.where(
        (e) => !e.title.isTv || ['Ended', 'Canceled'].contains(e.title.status),
      ),
    ];
    var next = 0;
    Future<void> worker() async {
      while (next < ordered.length) {
        final entry = ordered[next++];
        try {
          if (entry.title.isTv) {
            final old = await series.cached(entry.title.id);
            final fresh = await series.fetch(entry.title.id);
            final diff = compare(old, fresh);
            await db.transaction(() async {
              await series.save(fresh, DateTime.now());
              await db.saveChanges(diff, DateTime.now());
            });
            changes.add(diff);
          } else {
            final result = await movies.load(entry.title.id, refresh: true);
            if (result.offline) {
              throw result.failure ??
                  ApiFailure(
                    result.warning ?? 'Movie information could not be updated.',
                  );
            }
          }
          refreshedKeys.add(entry.title.key);
          _failures.remove(entry.title.key);
        } catch (e) {
          final message = e is ApiFailure
              ? e.message
              : 'An unexpected update error occurred. Please try again later.';
          final diagnostic = e is ApiFailure ? e.diagnostic : null;
          final issue = SyncIssue(
            entry.title.title,
            message,
            entityKey: entry.title.key,
            occurredAt: diagnostic?.occurredAt ?? now(),
            diagnostic: diagnostic,
          );
          errors.add('${entry.title.title}: $message');
          issues.add(issue);
          _failures[entry.title.key] = (
            retryAt: now().add(
              diagnostic?.statusCode == 404
                  ? const Duration(days: 1)
                  : const Duration(minutes: 5),
            ),
            issue: issue,
            identity: '${entry.title.provider}:${entry.title.sourceId}',
          );
          try {
            await db.administrativeConflict(
              entry.title.key,
              jsonEncode({
                'message': message,
                if (diagnostic != null) 'request': diagnostic.toJson(),
              }),
            );
          } catch (_) {
            // Diagnostic storage must never prevent other titles from syncing.
          }
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    if (issues.isNotEmpty || refreshedKeys.isNotEmpty) {
      try {
        await FeedbackIssueStore(db).record(
          [for (final issue in issues) issue.toFeedback()],
          resolvedKeys: refreshedKeys,
          resolvedAt: now(),
        );
      } catch (_) {
        // Reporting must never turn a recoverable catalog failure into a
        // failure of the library sync itself.
      }
    }
    return SyncReport(
      changes,
      errors,
      refreshedKeys: refreshedKeys,
      issues: issues,
    );
  }
}
