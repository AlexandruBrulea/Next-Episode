import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'common.dart';
import 'details.dart';
import 'feeds.dart';
import 'app_theme.dart';
import 'library_filter.dart';
import 'settings.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int tab = 0;
  Timer? timer;
  Timer? retentionTimer;
  void scheduleRetention() {
    retentionTimer?.cancel();
    if (!mounted) return;
    final expiry = ref.read(databaseProvider).nextTmdbExpiry;
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now());
    final delay = remaining.isNegative
        ? const Duration(seconds: 1)
        : remaining > const Duration(hours: 1)
        ? const Duration(hours: 1)
        : remaining;
    retentionTimer = Timer(delay, () async {
      try {
        await ref.read(libraryProvider.notifier).maintainRetention();
      } catch (_) {
        if (mounted) {
          setState(
            () => syncMessage = 'Local information could not be refreshed. Please restart the app.',
          );
        }
      } finally {
        if (mounted) scheduleRetention();
      }
    });
  }

  String? syncMessage;
  bool syncing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(sync);
    timer = Timer.periodic(const Duration(minutes: 30), (_) => sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  Future<void> sync() async {
    if (!mounted || syncing) return;
    setState(() => syncing = true);
    try {
      await ref.read(libraryProvider.future);
      final report = await ref.read(libraryProvider.notifier).sync();
      if (mounted) {
        setState(
          () => syncMessage = report.errors.isNotEmpty ? report.message : null,
        );
      }
    } catch (e) {
      if (mounted) setState(() => syncMessage = publicError(e));
    } finally {
      if (mounted) setState(() => syncing = false);
      scheduleRetention();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    retentionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEXT EPISODE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: neonCyan,
            ),
          ),
          const SizedBox(height: 4),
          Text(['My library', 'Discover', 'To watch', 'Calendar'][tab]),
        ],
      ),
      actions: [
        if (syncing)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => openScreen(context, const SettingsScreen()),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        if (const bool.fromEnvironment('DEMO'))
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('DEMO • Sample data • Progress resets on exit'),
          ),
        if (syncMessage != null)
          MaterialBanner(
            content: Text(syncMessage!),
            actions: [
              TextButton(
                onPressed: () => setState(() => syncMessage = null),
                child: const Text('Close'),
              ),
            ],
          ),
        Expanded(
          child: IndexedStack(
            index: tab,
            children: [
              const LibraryScreen(),
              SearchScreen(active: tab == 1),
              const EpisodeFeed(calendar: false),
              const EpisodeFeed(calendar: true),
            ],
          ),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) => setState(() => tab = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.video_library_outlined),
          label: 'Library',
        ),
        NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        NavigationDestination(
          icon: Icon(Icons.play_circle_outline),
          label: 'To watch',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month),
          label: 'Calendar',
        ),
      ],
    ),
  );
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String query = '', filter = 'All', sort = 'Date added';
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final db = ref.read(databaseProvider);
      final savedFilter = await db.preference('library.filter');
      final savedSort = await db.preference('library.sort');
      // Accept preferences saved by the previous Romanian interface.
      const legacyLabels = {
        'Toate': 'All',
        'Seriale': 'Shows',
        'Filme': 'Movies',
        'Cu episoade nevăzute': 'With unwatched episodes',
        'Terminate': 'Completed',
        'Data adăugării': 'Date added',
        'Titlu': 'Title',
        'Progres': 'Progress',
      };
      if (mounted) {
        setState(() {
          final restoredFilter = legacyLabels[savedFilter] ?? savedFilter;
          final restoredSort = legacyLabels[savedSort] ?? savedSort;
          if ([
            'All',
            'Shows',
            'Movies',
            'With unwatched episodes',
            'Completed',
          ].contains(restoredFilter)) {
            filter = restoredFilter!;
          }
          if ([
            'Date added',
            'Title',
            'Rating',
            'Progress',
          ].contains(restoredSort)) {
            sort = restoredSort!;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final supportsMovies = ref.watch(apiProvider).capabilities.movies;
    final activeFilter = !supportsMovies && filter == 'Movies' ? 'All' : filter;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search your library',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                setState(() => query = value.toLowerCase().trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: LibraryFilter(
                  label: 'Filter',
                  icon: Icons.tune_rounded,
                  accent: neonCyan,
                  value: activeFilter,
                  options: [
                    'All',
                    'Shows',
                    if (supportsMovies) 'Movies',
                    'With unwatched episodes',
                    'Completed',
                  ],
                  onSelected: (value) {
                    setState(() => filter = value);
                    perform(
                      context,
                      () => ref
                          .read(databaseProvider)
                          .setPreference('library.filter', value),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LibraryFilter(
                  label: 'Sort by',
                  icon: Icons.sort_rounded,
                  accent: neonViolet,
                  value: sort,
                  options: const ['Date added', 'Title', 'Rating', 'Progress'],
                  onSelected: (value) {
                    setState(() => sort = value);
                    perform(
                      context,
                      () => ref
                          .read(databaseProvider)
                          .setPreference('library.sort', value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ref
              .watch(libraryProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) =>
                    FailureView(e, () => ref.invalidate(libraryProvider)),
                data: (snapshot) {
                  double fraction(LibraryEntry entry) => entry.title.isTv
                      ? (snapshot.series.containsKey(entry.title.id)
                            ? snapshot.progress(entry.title.id).fraction
                            : 0)
                      : (snapshot.watched.containsKey(entry.title.key) ? 1 : 0);
                  String state(LibraryEntry entry) => entry.title.isTv
                      ? (snapshot.series.containsKey(entry.title.id)
                            ? snapshot.progress(entry.title.id).state
                            : 'Incomplete data')
                      : (snapshot.watched.containsKey(entry.title.key)
                            ? 'Completed'
                            : 'Not started');
                  final entries =
                      snapshot.entries.where((e) {
                        if (!'${e.title.title} ${e.title.originalTitle}'
                            .toLowerCase()
                            .contains(query)) {
                          return false;
                        }
                        return switch (activeFilter) {
                          'Shows' => e.title.isTv,
                          'Movies' => !e.title.isTv,
                          'With unwatched episodes' =>
                            e.title.isTv &&
                                snapshot.series.containsKey(e.title.id) &&
                                snapshot.progress(e.title.id).unseen.isNotEmpty,
                          'Completed' => state(e) == 'Completed',
                          _ => true,
                        };
                      }).toList()..sort(
                        (a, b) => switch (sort) {
                          'Title' => a.title.title.toLowerCase().compareTo(
                            b.title.title.toLowerCase(),
                          ),
                          'Rating' => b.title.rating.compareTo(a.title.rating),
                          'Progress' => fraction(b).compareTo(fraction(a)),
                          _ => b.addedAt.compareTo(a.addedAt),
                        },
                      );
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        snapshot.entries.isEmpty
                            ? 'Your library is empty. Add a title from Search.'
                            : 'No titles match your filters.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return MediaTile(
                        title: entry.title,
                        progress: fraction(entry),
                        subtitle:
                            '${state(entry)} • ${(fraction(entry) * 100).round()}%\n${entry.title.statusLabel}',
                        onTap: () => openTitle(context, entry.title),
                      );
                    },
                  );
                },
              ),
        ),
      ],
    );
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  final bool active;
  const SearchScreen({super.key, this.active = true});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final input = TextEditingController();
  String? _providerId;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void search() => ref.read(searchProvider.notifier).search(input.text, null);
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final library = ref.watch(libraryProvider).asData?.value;
    final catalog = ref.watch(apiProvider);
    if (widget.active && _providerId != catalog.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && _providerId != catalog.id) {
          _providerId = catalog.id;
          search();
        }
      });
    }
    // Temporary diagnostic requested for testing administrative transitions.
    final searchLabel = catalog.id == 'tvmaze'
        ? 'Search shows · TVmaze'
        : catalog.id == 'tmdb'
        ? 'Search shows and movies · TMDB'
        : 'Search shows and movies · ${catalog.label}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: input,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => search(),
            onChanged: (value) =>
                ref.read(searchProvider.notifier).queryChanged(value),
            decoration: InputDecoration(
              labelText: 'Search shows and movies', //searchLabel,
              helperText: 'Type at least 3 characters to search',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        if (state.query.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                catalog.capabilities.movies
                    ? 'Popular shows & movies'
                    : 'Popular shows',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        if (state.loading) const LinearProgressIndicator(),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(publicError(state.error!)),
                TextButton(
                  onPressed: () => ref
                      .read(searchProvider.notifier)
                      .search(state.query, null, more: state.page > 0),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        Expanded(
          child: state.results.isEmpty
              ? Center(
                  child: Text(
                    state.loading
                        ? (state.query.isEmpty
                              ? 'Loading popular titles…'
                              : 'Searching…')
                        : state.query.isEmpty
                        ? 'No popular titles available right now.'
                        : state.error == null
                        ? 'No results found.'
                        : '',
                  ),
                )
              : ListView.builder(
                  itemCount: state.results.length,
                  itemBuilder: (context, index) {
                    final title = state.results[index];
                    final saved = library?.contains(title.key) ?? false;
                    return MediaTile(
                      title: title,
                      onTap: () => openTitle(context, title),
                      trailing: saved
                          ? const Tooltip(
                              message: 'In library',
                              child: Icon(Icons.check_circle),
                            )
                          : ActionButton(
                              label: 'Add',
                              action: () =>
                                  ref.read(libraryProvider.notifier).add(title),
                            ),
                    );
                  },
                ),
        ),
        if (state.page < state.totalPages && !state.loading)
          TextButton(
            onPressed: () => ref
                .read(searchProvider.notifier)
                .search(state.query, null, more: true),
            child: const Text('More results'),
          ),
      ],
    );
  }
}
