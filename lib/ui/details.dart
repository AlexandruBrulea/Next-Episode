import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../data/tmdb_retention.dart';
import 'common.dart';
import 'title_sections.dart';

void openTitle(BuildContext context, TitleData title) => openScreen(
  context,
  title.isTv ? SeriesScreen(id: title.id) : MovieScreen(id: title.id),
);

class LibraryAction extends ConsumerWidget {
  final TitleData title;
  const LibraryAction(this.title, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(libraryProvider).asData?.value;
    final saved = snapshot?.contains(title.key) ?? false;
    return ActionButton(
      label: saved ? 'Remove from library' : 'Add to library',
      action: () async {
        final controller = ref.read(libraryProvider.notifier);
        if (!saved) {
          await controller.add(title);
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Remove “${title.title}”?'),
            content: const Text(
              'Your watch history and dates are kept if you add this title again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed == true) await controller.remove(title.key);
      },
    );
  }
}

class TitleHeader extends StatelessWidget {
  final TitleData title;
  const TitleHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 320,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Poster(
                title.backdrop.isNotEmpty ? title.backdrop : title.poster,
                width: double.infinity,
                height: 320,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD101522)],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(label: Text(title.isTv ? 'TV SHOW' : 'MOVIE')),
                    Text(
                      title.title,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (string(title.raw['tagline']).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            string(title.raw['tagline']),
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          Text('★ ${title.ratingLabel}'),
          Text(dateLabel(title.releaseDate)),
          if (integer(title.raw['vote_count']) > 0)
            Text('${integer(title.raw['vote_count'])} votes'),
        ],
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text(title.statusLabel)),
          if (title.isTv) ...[
            Chip(label: Text('${title.seasonCount} seasons')),
            Chip(label: Text('${title.episodeCount} episodes')),
          ],
          for (final genre in title.genres) Chip(label: Text(genre)),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        title.overview,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
      ),
      const SizedBox(height: 20),
      LibraryAction(title),
      const SizedBox(height: 28),
    ],
  );
}

class SeriesScreen extends ConsumerStatefulWidget {
  final int id;
  const SeriesScreen({super.key, required this.id});
  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  int? selectedSeason;
  bool details = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text('Show details'),
    ),
    body: ref
        .watch(seriesDetailsProvider(widget.id))
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => FailureView(
            e,
            () => ref.invalidate(seriesDetailsProvider(widget.id)),
          ),
          data: (loaded) {
            final snapshot = ref.watch(libraryProvider).asData?.value;
            final bundle = snapshot?.series[widget.id] ?? loaded.value;
            final title = bundle.title;
            final watched = snapshot?.watched ?? <String, DateTime>{};
            final saved = snapshot?.contains(title.key) ?? false;
            final seasons = [...bundle.seasons]
              ..sort((a, b) => a.number.compareTo(b.number));
            final season =
                seasons.where((s) => s.number == selectedSeason).firstOrNull ??
                seasons.where((s) => s.number > 0).firstOrNull ??
                seasons.firstOrNull;
            final progress = WatchProgress.calculate(
              bundle,
              watched,
              DateTime.now(),
            );
            return ListView(
              primary: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                if (loaded.offline)
                  const Text('Offline: showing the last saved version.'),
                TitleHeader(title),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Episodes'),
                      icon: Icon(Icons.play_circle_outline),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Details'),
                      icon: Icon(Icons.info_outline),
                    ),
                  ],
                  selected: {details},
                  onSelectionChanged: (value) =>
                      setState(() => details = value.single),
                ),
                const SizedBox(height: 24),
                if (details)
                  TitleInformation(title)
                else ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in seasons)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ChoiceChip(
                              label: Text(
                                item.number == 0
                                    ? 'Specials'
                                    : 'S${item.number}',
                              ),
                              selected: season?.number == item.number,
                              onSelected: (_) =>
                                  setState(() => selectedSeason = item.number),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${progress.unseen.length} episodes to watch',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: progress.fraction),
                  const SizedBox(height: 20),
                  if (season == null)
                    const Text('No seasons available.')
                  else ...[
                    Text(
                      season.overview,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    if (saved) SeasonActions(season: season),
                    if (season.episodes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Episodes have not been announced yet.'),
                      ),
                    for (final episode in [
                      ...season.episodes,
                    ]..sort(episodeOrder)) ...[
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: IconButton(
                          tooltip: watched.containsKey(episode.key)
                              ? 'Mark as unwatched'
                              : 'Mark as watched',
                          icon: Icon(
                            watched.containsKey(episode.key)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          onPressed:
                              saved &&
                                  (episode.released(DateTime.now()) ||
                                      watched.containsKey(episode.key))
                              ? () => perform(
                                  context,
                                  () => markEpisodeWithConfirmation(
                                    context,
                                    ref,
                                    episode,
                                    !watched.containsKey(episode.key),
                                  ),
                                )
                              : null,
                        ),
                        title: Text(episode.title),
                        subtitle: Text(
                          '${episode.code} · ${dateLabel(episode.airDate)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openScreen(
                          context,
                          EpisodeScreen(
                            title: title,
                            episode: episode,
                            fromSeries: true,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ],
              ],
            );
          },
        ),
  );
}

class SeasonActions extends ConsumerStatefulWidget {
  final SeasonData season;
  const SeasonActions({super.key, required this.season});
  @override
  ConsumerState<SeasonActions> createState() => _SeasonActionsState();
}

class _SeasonActionsState extends ConsumerState<SeasonActions> {
  bool? running;
  Future<void> mark(bool seen) async {
    setState(() => running = seen);
    await perform(
      context,
      () => ref.read(libraryProvider.notifier).markSeason(widget.season, seen),
    );
    if (mounted) setState(() => running = null);
  }

  @override
  Widget build(BuildContext context) {
    Widget button(bool seen) => Expanded(
      child: Tooltip(
        message: seen ? 'Mark season as watched' : 'Mark season as unwatched',
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            foregroundColor: seen
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            backgroundColor: seen
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
          ),
          onPressed: running == null ? () => mark(seen) : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (running == seen)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  seen
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  seen ? 'Watched' : 'Unwatched',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mark season as',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                button(true),
                const SizedBox(width: 10),
                button(false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SeasonScreen extends ConsumerWidget {
  final int seriesId, seasonNumber;
  const SeasonScreen({
    super.key,
    required this.seriesId,
    required this.seasonNumber,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(seasonNumber == 0 ? 'Specials' : 'Season $seasonNumber'),
    ),
    body: ref
        .watch(seriesDetailsProvider(seriesId))
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => FailureView(
            e,
            () => ref.invalidate(seriesDetailsProvider(seriesId)),
          ),
          data: (loaded) {
            final snapshot = ref.watch(libraryProvider).asData?.value;
            final bundle = snapshot?.series[seriesId] ?? loaded.value;
            final season = bundle.seasons
                .where((s) => s.number == seasonNumber)
                .firstOrNull;
            if (season == null) {
              return const Center(
                child: Text(
                  'This season is no longer available in the catalog.',
                ),
              );
            }
            final watched = snapshot?.watched ?? <String, DateTime>{};
            final released = season.episodes
                .where((e) => e.released(DateTime.now()))
                .toList();
            final seen = released
                .where((e) => watched.containsKey(e.key))
                .length;
            final saved = snapshot?.contains(bundle.title.key) ?? false;
            return ListView(
              primary: true,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  season.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Poster(season.poster, width: 100, height: 150),
                Text(season.overview),
                InfoLine('Release date', dateLabel(season.airDate)),
                InfoLine('Episodes in season', '${season.episodes.length}'),
                Text(
                  '$seen/${released.length} released watched • ${released.length - seen} unwatched • ${released.isEmpty ? 0 : (seen / released.length * 100).round()}%',
                ),
                if (seasonNumber == 0)
                  const Text(
                    'This season does not count toward the main progress.',
                  ),
                if (!saved) LibraryAction(bundle.title),
                if (saved) SeasonActions(season: season),
                const Text('Only released episodes will be marked as watched.'),
                if (season.episodes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Season announced, with no episodes available yet.',
                    ),
                  ),
                for (final episode in [...season.episodes]..sort(episodeOrder))
                  ListTile(
                    title: Text('${episode.code} • ${episode.title}'),
                    subtitle: Text(
                      '${dateLabel(episode.airDate)}${episode.released(DateTime.now()) ? '' : ' • Upcoming / TBA'}',
                    ),
                    onTap: () => openScreen(
                      context,
                      EpisodeScreen(title: bundle.title, episode: episode),
                    ),
                    trailing: Checkbox(
                      value: watched.containsKey(episode.key),
                      onChanged:
                          saved &&
                              (episode.released(DateTime.now()) ||
                                  watched.containsKey(episode.key))
                          ? (value) => perform(
                              context,
                              () => markEpisodeWithConfirmation(
                                context,
                                ref,
                                episode,
                                value ?? false,
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
  );
}

class EpisodeScreen extends ConsumerWidget {
  final TitleData title;
  final EpisodeData episode;
  final bool fromSeries;
  const EpisodeScreen({
    super.key,
    required this.title,
    required this.episode,
    this.fromSeries = false,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(libraryProvider).asData?.value;
    final title = snapshot?.series[this.title.id]?.title ?? this.title;
    final obtained = DateTime.tryParse(string(title.raw[tmdbObtainedKey]));
    final expired = title.provider == 'tmdb' && obtained != null &&
        !DateTime.now().toUtc().isBefore(tmdbExpiry(obtained));
    final current =
        snapshot?.series[title.id]?.episodes
            .where((e) => e.id == episode.id)
            .firstOrNull ??
        episode;
    final entry = snapshot?.entries
        .where((e) => e.title.key == title.key)
        .firstOrNull;
    if (expired || entry?.title.raw['content_unavailable'] == true ||
        (title.provider == 'tmdb' &&
            ref.watch(tmdbAllowedProvider).asData?.value != true)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Episode details')),
        body: const Center(
          child: Text(
            'Details temporarily unavailable. Your watch progress is saved.',
          ),
        ),
      );
    }
    final markedAt = snapshot?.watched[current.key];
    final saved = snapshot?.contains(title.key) ?? false;
    final guestStars = current.cast
        .where((person) => string(person['name']).trim().isNotEmpty)
        .toList();
    final crew = current.crew
        .where((person) => string(person['name']).trim().isNotEmpty)
        .map((person) {
          final name = string(person['name']).trim();
          final job = string(person['job']).trim();
          return job.isEmpty ? name : '$name • $job';
        })
        .join(', ');
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        primary: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            current.title,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Season ${current.season}, Episode ${current.number}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextButton(
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            onPressed: () {
              if (fromSeries) {
                Navigator.pop(context);
              } else {
                openTitle(context, title);
              }
            },
            child: Text('${title.title} ›'),
          ),

          const SizedBox(height: 24),
          Text(current.overview),
          InfoLine('Air date', dateLabel(current.airDate)),
          if (!current.released(DateTime.now()))
            const Text('Upcoming episode or air date not yet announced.'),
          InfoLine(
            'Runtime',
            current.runtime == 0 ? 'Unavailable' : '${current.runtime} min',
          ),
          InfoLine('Rating', current.ratingLabel),
          InfoLine('Network', title.networks.join(', ')),
          const SizedBox(height: 24),
          if (current.still.isNotEmpty)
            Poster(current.still, width: double.infinity, height: 240),
          const SizedBox(height: 24),
          if (guestStars.isNotEmpty) ...[
            Text('Guest stars', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            CastCards(guestStars),
            const SizedBox(height: 24),
          ],
          Text('Top cast', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          CastCards((snapshot?.series[title.id]?.title ?? title).cast),
          if (crew.isNotEmpty) InfoLine('Crew', crew),
          InfoLine(
            'Watch status',
            markedAt == null ? 'Unwatched' : 'Watched • ${dateLabel(markedAt)}',
          ),
          if (!saved) LibraryAction(title),
          if (saved && (current.released(DateTime.now()) || markedAt != null))
            ActionButton(
              label: markedAt == null ? 'Mark as watched' : 'Mark as unwatched',
              action: () => markEpisodeWithConfirmation(
                context,
                ref,
                current,
                markedAt == null,
              ),
            ),
        ],
      ),
    );
  }
}

class MovieScreen extends ConsumerWidget {
  final int id;
  const MovieScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Movie details')),
    body: ref
        .watch(movieDetailsProvider(id))
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) =>
              FailureView(e, () => ref.invalidate(movieDetailsProvider(id))),
          data: (loaded) {
            final title = loaded.value;
            final snapshot = ref.watch(libraryProvider).asData?.value;
            final markedAt = snapshot?.watched[title.key];
            return ListView(
              primary: true,
              padding: const EdgeInsets.all(16),
              children: [
                if (loaded.offline)
                  const Text('Offline: showing the last saved version.'),
                TitleHeader(title),
                InfoLine(
                  'Runtime',
                  title.runtimes.first == 0
                      ? 'Unavailable'
                      : '${title.runtimes.first} min',
                ),
                InfoLine('Director', title.directors.join(', ')),
                InfoLine(
                  'Cast',
                  title.cast
                      .map(
                        (e) =>
                            '${string(e['name'])} (${string(e['character'])})',
                      )
                      .join(', '),
                ),
                InfoLine(
                  'Watch status',
                  markedAt == null
                      ? 'Unwatched'
                      : 'Watched • ${dateLabel(markedAt)}',
                ),
                if (snapshot?.contains(title.key) ?? false)
                  ActionButton(
                    label: markedAt == null
                        ? 'Mark as watched'
                        : 'Mark as unwatched',
                    action: () => ref
                        .read(libraryProvider.notifier)
                        .markMovie(id, markedAt == null),
                  ),
              ],
            );
          },
        ),
  );
}
