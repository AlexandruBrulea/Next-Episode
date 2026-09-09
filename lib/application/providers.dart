import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/painting.dart';

import '../data/database.dart';
import '../data/alerts.dart';
import '../data/repositories.dart';
import '../domain/catalog_provider.dart';

import '../data/catalog/catalog_router.dart';
import '../domain/models.dart';

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
  const LibrarySnapshot(this.entries, this.watched, this.series);
  bool contains(String key) => entries.any((e) => e.title.key == key);
  WatchProgress progress(int id) =>
      WatchProgress.calculate(series[id]!, watched, DateTime.now());
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
  Future<LibrarySnapshot> _read() async {
    final entries = await ref.read(libraryRepositoryProvider).all();
    final watched = await ref.read(progressRepositoryProvider).all();
    final series = <int, SeriesBundle>{};
    for (final entry in entries.where((e) => e.title.isTv)) {
      final bundle = await ref
          .read(seriesRepositoryProvider)
          .cached(entry.title.id);
      if (bundle != null) series[entry.title.id] = bundle;
    }
    return LibrarySnapshot(entries, watched, series);
  }

  Future<void> reload() async {
    final snapshot = await _read();
    state = AsyncData(snapshot);
    try {
      await ref
          .read(episodeAlertsProvider)
          .refresh(
            ref.read(databaseProvider),
            snapshot.series.values,
            snapshot.watched,
          );
      ref.read(alertErrorProvider.notifier).update(null);
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
    await reload();
  }

  Future<void> markEpisodesSeen(List<EpisodeData> episodes) async {
    final now = DateTime.now();
    await ref.read(databaseProvider).transaction(() async {
      for (final episode in episodes) {
        await ref
            .read(progressRepositoryProvider)
            .episode(episode, true, now: now);
      }
    });
    await reload();
  }

  Future<void> markSeason(SeasonData s, bool seen) async {
    await ref.read(progressRepositoryProvider).season(s, seen);
    await reload();
  }

  Future<void> markMovie(int id, bool seen) async {
    await ref.read(progressRepositoryProvider).movie(id, seen);
    await reload();
  }

  Future<SyncReport> sync({bool onlyStale = false}) async {
    final removed = await ref.read(databaseProvider).enforceTmdbRetention();
    final catalog = ref.read(apiProvider);
    if (catalog is CatalogRouter) {
      await catalog.refreshConfiguration?.call();
    }
    // Publish purged data before waiting for any network refresh.
    await reload();
    ref.invalidate(tmdbAllowedProvider);
    ref.invalidate(seriesDetailsProvider);
    ref.invalidate(movieDetailsProvider);
    if (removed || !await ref.read(databaseProvider).tmdbContentAllowed()) {
      ref.invalidate(searchProvider);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    final result = await ref
        .read(syncRepositoryProvider)
        .refresh(onlyStale: onlyStale);
    await reload();
    ref.invalidate(seriesDetailsProvider);
    ref.invalidate(movieDetailsProvider);
    return result;
  }
}

final seriesDetailsProvider = FutureProvider.autoDispose
    .family<Loaded<SeriesBundle>, int>(
      (ref, id) => ref.watch(seriesRepositoryProvider).load(id),
    );
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
    if (query.runes.length < 3) {
      search('', null);
      return;
    }
    // Invalidate old results immediately, before the debounce expires.
    state = SearchState(query: query, loading: true);
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => search(query, null),
    );
  }

  Future<void> search(
    String query,
    MediaType? type, {
    bool more = false,
  }) async {
    _debounce?.cancel();
    query = query.trim();
    if (query.runes.length < 3) query = '';
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
