import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/painting.dart';

import '../data/database.dart';
import '../data/alerts.dart';
import '../data/repositories.dart';
import '../data/tmdb_retention.dart';
import '../domain/catalog_provider.dart';

import '../data/catalog/catalog_router.dart';
import '../domain/models.dart';
import '../domain/watch_time.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Override at startup'),
);
final apiProvider = Provider<CatalogProvider>(
  (ref) => throw UnimplementedError('Override at startup'),
);
final tmdbAllowedProvider = FutureProvider<bool>(
  (ref) => ref.watch(databaseProvider).tmdbContentAllowed(),
);
final episodeAlertsProvider = Provider((ref) => EpisodeAlerts());
final alertErrorProvider = NotifierProvider<AlertError, String?>(
  AlertError.new,
);

class AlertError extends Notifier<String?> {
  @override
  String? build() => null;
  void update(String? value) => state = value;
}

final seriesRepositoryProvider = Provider(
  (ref) =>
      SeriesRepository(ref.watch(apiProvider), ref.watch(databaseProvider)),
);
final moviesRepositoryProvider = Provider(
  (ref) =>
      MoviesRepository(ref.watch(apiProvider), ref.watch(databaseProvider)),
);
final libraryRepositoryProvider = Provider(
  (ref) => LibraryRepository(ref.watch(databaseProvider)),
);
final progressRepositoryProvider = Provider(
  (ref) => ProgressRepository(ref.watch(databaseProvider)),
);
final syncRepositoryProvider = Provider(
  (ref) => SyncRepository(
    ref.watch(databaseProvider),
    ref.watch(seriesRepositoryProvider),
    ref.watch(moviesRepositoryProvider),
  ),
);

class LibrarySnapshot {
  final List<LibraryEntry> entries;
  final Map<String, DateTime> watched;
  final Map<int, SeriesBundle> series;
  LibrarySnapshot(this.entries, this.watched, this.series);
  LibrarySnapshot withWatched(Map<String, DateTime> value) {
    final result = LibrarySnapshot(entries, value, series);
    final changedShows = <int>{};
    for (final key in {...watched.keys, ...value.keys}) {
      if (watched[key] == value[key] || !key.startsWith('episode:')) continue;
      final id = int.tryParse(key.split(':')[1]);
      if (id != null) changedShows.add(id);
    }
    result._progressDay = _progressDay;
    result._progress.addEntries(
      _progress.entries.where((e) => !changedShows.contains(e.key)),
    );
    return result;
  }

  late final watchTime = WatchTimeSummary.calculate(entries, series, watched);
  final Map<int, WatchProgress> _progress = {};
  DateTime? _progressDay;
  bool contains(String key) => entries.any((e) => e.title.key == key);
  WatchProgress progress(int id) {
    final now = DateTime.now();
    if (_progressDay != day(now)) {
      _progress.clear();
      _progressDay = day(now);
    }
    return _progress.putIfAbsent(
      id,
      () => WatchProgress.calculate(series[id]!, watched, now),
    );
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryController, LibrarySnapshot>(
      LibraryController.new,
    );

class LibraryController extends AsyncNotifier<LibrarySnapshot> {
  Future<void> maintainRetention() async {
    final changed = await ref.read(databaseProvider).enforceTmdbRetention();
    if (!changed) return;
    await reload();
    ref.invalidate(seriesDetailsProvider);
    ref.invalidate(movieDetailsProvider);
    ref.invalidate(searchProvider);
    ref.invalidate(tmdbAllowedProvider);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  Future<LibrarySnapshot> build() => _read();
  Future<LibrarySnapshot> _read({Set<String>? changedKeys}) async {
    final entries = await ref.read(libraryRepositoryProvider).all();
    final watched = await ref.read(progressRepositoryProvider).all();
    final previous = state.asData?.value;
    final cachedKeys = changedKeys == null
        ? null
        : {
            for (final row
                in await ref
                    .read(databaseProvider)
                    .customSelect('SELECT key FROM cache')
                    .get())
              row.read<String>('key'),
          };
    final ids = changedKeys == null || previous == null
        ? null
        : {
            for (final entry in entries)
              if (entry.title.isTv &&
                  (changedKeys.contains(entry.title.key) ||
                      !previous.series.containsKey(entry.title.id)))
                entry.title.id,
          };
    final series = <int, SeriesBundle>{
      if (ids != null)
        for (final entry in entries)
          if (entry.title.isTv &&
              !ids.contains(entry.title.id) &&
              cachedKeys!.contains('series:${entry.title.id}') &&
              entry.title.raw['content_unavailable'] != true &&
              previous!.series.containsKey(entry.title.id))
            entry.title.id: previous.series[entry.title.id]!,
      ...await ref.read(databaseProvider).cachedLibrarySeries(ids: ids),
    };
    return LibrarySnapshot(entries, watched, series);
  }

  Future<void> reload({Set<String>? changedKeys}) async {
    final revision = _progressRevision;
    var snapshot = await _read(changedKeys: changedKeys);
    // A metadata read can finish after the user has saved newer watch marks.
    if (revision != _progressRevision && state.asData != null) {
      snapshot = snapshot.withWatched(state.asData!.value.watched);
    }
    state = AsyncData(snapshot);
    await _refreshAlerts(snapshot);
  }

  int _progressRevision = 0;
  Future<void> _refreshProgress() async {
    final revision = ++_progressRevision;
    final watched = await ref.read(progressRepositoryProvider).all();
    if (revision != _progressRevision) return;
    final previous = state.asData?.value;
    if (previous == null) {
      await reload();
      return;
    }
    final snapshot = previous.withWatched(watched);
    state = AsyncData(snapshot);
    await _refreshAlerts(snapshot);
  }

  DateTime? _alertsDay;
  Future<void> _refreshAlerts(LibrarySnapshot snapshot) async {
    try {
      await ref
          .read(episodeAlertsProvider)
          .refresh(
            ref.read(databaseProvider),
            snapshot.series.values,
            snapshot.watched,
          );
      ref.read(alertErrorProvider.notifier).update(null);
      _alertsDay = day(DateTime.now());
    } catch (_) {
      ref
          .read(alertErrorProvider.notifier)
          .update(
            'Alerts could not be updated. Check notification permissions in your device settings.',
          );
    }
  }

  Future<void> add(TitleData title) async {
    // Resolve the complete catalog first so todo/progress are never partial.
    if (title.isTv) {
      title = (await ref.read(seriesRepositoryProvider).load(title.id))
          .value
          .title;
    } else {
      title = (await ref.read(moviesRepositoryProvider).load(title.id)).value;
    }
    await ref.read(libraryRepositoryProvider).add(title);
    final cache = await ref
        .read(databaseProvider)
        .cached(title.isTv ? 'series:${title.id}' : 'movie:${title.id}');
    if (cache != null) {
      await ref.read(databaseProvider).updateTitle(title, cache.fetchedAt);
    }
    await reload();
  }

  Future<void> remove(String key) async {
    await ref.read(libraryRepositoryProvider).remove(key);
    await reload();
  }

  Future<void> markEpisode(EpisodeData e, bool seen) async {
    await ref.read(progressRepositoryProvider).episode(e, seen);
    await _refreshProgress();
  }

  Future<void> markEpisodesSeen(List<EpisodeData> episodes) async {
    await ref.read(progressRepositoryProvider).episodes(episodes, true);
    await _refreshProgress();
  }

  Future<void> markSeason(SeasonData s, bool seen) async {
    await ref.read(progressRepositoryProvider).season(s, seen);
    await _refreshProgress();
  }

  Future<void> markMovie(int id, bool seen) async {
    await ref.read(progressRepositoryProvider).movie(id, seen);
    await _refreshProgress();
  }

  Future<SyncReport> sync({bool onlyStale = false}) async {
    final db = ref.read(databaseProvider);
    final removed = await db.enforceTmdbRetention();
    final before =
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n');
    final catalog = ref.read(apiProvider);
    if (catalog is CatalogRouter) {
      await catalog.refreshConfiguration?.call();
    }
    final after =
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n');
    final disabled = !await db.tmdbContentAllowed();
    final staleDisabled =
        disabled &&
        (state.asData?.value.entries.any(
              (e) =>
                  e.title.provider == 'tmdb' &&
                  e.title.raw['content_unavailable'] != true,
            ) ??
            false);
    // Configuration changes and purges must be visible before network refresh.
    if (removed || before != after || staleDisabled) {
      await reload();
      ref.invalidate(tmdbAllowedProvider);
      ref.invalidate(seriesDetailsProvider);
      ref.invalidate(movieDetailsProvider);
    }
    if (_alertsDay != day(DateTime.now()) && state.asData != null) {
      await _refreshAlerts(state.asData!.value);
    }
    if (removed || disabled) {
      ref.invalidate(searchProvider);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    final result = await ref
        .read(syncRepositoryProvider)
        .refresh(onlyStale: onlyStale);
    if (result.refreshedKeys.isNotEmpty) {
      await reload(changedKeys: result.refreshedKeys);
      for (final key in result.refreshedKeys) {
        final id = int.parse(key.split(':').last);
        if (key.startsWith('tv:')) {
          ref.invalidate(seriesDetailsProvider(id));
        } else {
          ref.invalidate(movieDetailsProvider(id));
        }
      }
    }
    return result;
  }
}

final seriesDetailsProvider = FutureProvider.autoDispose
    .family<Loaded<SeriesBundle>, int>(
      (ref, id) => ref.watch(seriesRepositoryProvider).load(id),
    );
// Saved shows already have complete, retention-checked bundles in the library.
// Only unsaved, missing or expired content needs the asynchronous loader.
final seriesContentProvider = Provider.autoDispose
    .family<AsyncValue<Loaded<SeriesBundle>>, int>((ref, id) {
      final bundle = ref.watch(
        libraryProvider.select((value) => value.asData?.value.series[id]),
      );
      if (bundle != null && bundle.title.raw['content_unavailable'] != true) {
        final obtained = DateTime.tryParse(
          string(bundle.title.raw[tmdbObtainedKey]),
        );
        final expired =
            bundle.title.provider == 'tmdb' &&
            obtained != null &&
            !DateTime.now().toUtc().isBefore(tmdbExpiry(obtained));
        if (!expired) return AsyncData(Loaded(bundle));
      }
      return ref.watch(seriesDetailsProvider(id));
    });
final movieDetailsProvider = FutureProvider.autoDispose
    .family<Loaded<TitleData>, int>(
      (ref, id) => ref.watch(moviesRepositoryProvider).load(id),
    );

class SearchState {
  final String query;
  final MediaType? type;
  final List<TitleData> results;
  final int page, totalPages;
  final bool loading;
  final String? error;
  const SearchState({
    this.query = '',
    this.type,
    this.results = const [],
    this.page = 0,
    this.totalPages = 0,
    this.loading = false,
    this.error,
  });
}

final searchProvider = NotifierProvider<SearchController, SearchState>(
  SearchController.new,
);

class SearchController extends Notifier<SearchState> {
  int _generation = 0;
  Timer? _debounce;
  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _generation++;
    });
    return const SearchState();
  }

  void queryChanged(String input) {
    _debounce?.cancel();
    _generation++;
    final query = input.trim();
    if (query.isEmpty) {
      search('', null);
      return;
    }
    // Invalidate old results immediately, before the debounce expires.
    state = SearchState(query: query, loading: true);
    _debounce = Timer(const Duration(seconds: 3), () => search(query, null));
  }

  Future<void> search(
    String query,
    MediaType? type, {
    bool more = false,
  }) async {
    _debounce?.cancel();
    query = query.trim();
    if (type == MediaType.movie && !ref.read(apiProvider).capabilities.movies) {
      type = null;
      more = false;
    }
    if (more && (state.loading || state.page >= state.totalPages)) return;
    final generation = ++_generation;
    final previous = more ? state.results : <TitleData>[];
    final page = more ? state.page + 1 : 1;
    state = SearchState(
      query: query,
      type: type,
      results: previous,
      page: more ? state.page : 0,
      totalPages: more ? state.totalPages : 0,
      loading: true,
    );
    try {
      final api = ref.read(apiProvider);
      final result = query.isEmpty
          ? await api.popular(page)
          : await api.search(query, type, page);
      if (generation != _generation) return;
      final merged = {
        for (final title in [...previous, ...result.results]) title.key: title,
      };
      state = SearchState(
        query: query,
        type: type,
        results: merged.values.toList(),
        page: result.page,
        totalPages: result.totalPages,
      );
    } catch (e) {
      if (generation != _generation) return;
      state = SearchState(
        query: query,
        type: type,
        results: previous,
        page: page - 1,
        totalPages: more ? state.totalPages : 0,
        error: '$e',
      );
    }
  }
}
