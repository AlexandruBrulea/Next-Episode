import 'dart:convert';

import '../domain/models.dart';
import 'database.dart';
import 'catalog/catalog_router.dart';
import '../domain/catalog_provider.dart';

class Loaded<T> {
  final T value;
  final bool offline;
  final String? warning;
  const Loaded(this.value, {this.offline = false, this.warning});
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
          warning: '$error',
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
    final instant = now ?? DateTime.now();
    if (seen && !episode.released(instant)) {
      throw const ApiFailure(
        'This episode has not been released yet or has no announced air date.',
      );
    }
    await db.mark(episode.key, seen, instant);
  }

  Future<void> movie(int id, bool seen) =>
      db.mark('movie:$id', seen, DateTime.now());
  Future<void> season(SeasonData season, bool seen, {DateTime? now}) async {
    final instant = now ?? DateTime.now();
    await db.transaction(() async {
      for (final episode in season.episodes) {
        if (!seen || episode.released(instant)) {
          await db.mark(episode.key, seen, instant);
        }
      }
    });
  }
}

class SyncReport {
  final List<SyncChanges> changes;
  final List<String> errors;
  const SyncReport(this.changes, this.errors);
  String get message => errors.isEmpty
      ? 'Your library is up to date.'
      : 'Your data is safe. Some information could not be updated right now.';
}

class SyncRepository {
  final AppDatabase db;
  final SeriesRepository series;
  final MoviesRepository movies;
  bool _running = false;
  SyncRepository(this.db, this.series, this.movies);
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

  Future<SyncReport> refresh({bool onlyStale = false}) async {
    if (_running) return const SyncReport([], []);
    _running = true;
    final changes = <SyncChanges>[];
    final errors = <String>[];
    try {
      for (final entry in await db.library()) {
        if (onlyStale &&
            entry.title.provider == series.api.id &&
            entry.updatedAt != null &&
            DateTime.now().difference(entry.updatedAt!) <
                const Duration(hours: 6)) {
          continue;
        }
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
              throw const ApiFailure('Movie information could not be updated.');
            }
          }
        } catch (e) {
          await db.administrativeConflict(entry.title.key, '$e');
          errors.add('${entry.title.title}: $e');
        }
      }
      return SyncReport(changes, errors);
    } finally {
      _running = false;
    }
  }
}
