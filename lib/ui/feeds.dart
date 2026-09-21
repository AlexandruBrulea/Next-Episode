import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'common.dart';
import 'details.dart';
import 'calendar.dart';

class EpisodeFeed extends ConsumerStatefulWidget {
  final bool calendar;
  const EpisodeFeed({super.key, required this.calendar});
  @override
  ConsumerState<EpisodeFeed> createState() => _EpisodeFeedState();
}

// Lightweight row descriptions; widgets and images are built near the viewport.
typedef _FeedRow = ({
  String key,
  TitleData title,
  EpisodeData? episode,
  int? count,
});

class _EpisodeFeedState extends ConsumerState<EpisodeFeed> {
  final Map<String, int> _visibleCounts = {};

  @override
  Widget build(BuildContext context) => widget.calendar
      ? const CalendarScreen()
      : ref
            .watch(libraryProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) =>
                  FailureView(e, () => ref.invalidate(libraryProvider)),
              data: (snapshot) {
                final now = day(DateTime.now());
                final bundles = snapshot.series.values.toList()
                  ..sort((a, b) => a.title.title.compareTo(b.title.title));
                final rows = <_FeedRow>[];
                for (final bundle in bundles) {
                  final episodes =
                      bundle.episodes
                          .where(
                            (episode) =>
                                !episode.isSpecial &&
                                episode.released(now) &&
                                !snapshot.watched.containsKey(episode.key),
                          )
                          .toList()
                        ..sort(episodeOrder);
                  if (episodes.isEmpty) continue;
                  final title = bundle.title;
                  final count = _visibleCounts[title.key] ?? 5;
                  rows.add((
                    key: 'header:${title.key}',
                    title: title,
                    episode: null,
                    count: episodes.length,
                  ));
                  for (final episode in episodes.take(count)) {
                    rows.add((
                      key: episode.key,
                      title: title,
                      episode: episode,
                      count: null,
                    ));
                  }
                  if (episodes.length > count) {
                    rows.add((
                      key: 'more:${title.key}',
                      title: title,
                      episode: null,
                      count: null,
                    ));
                  }
                }
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                      'No released, unwatched episodes.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final indices = {
                  for (var i = 0; i < rows.length; i++) rows[i].key: i,
                };
                return ListView.builder(
                  // Prepare roughly one extra screen on either side of the viewport.
                  scrollCacheExtent: const ScrollCacheExtent.viewport(1),
                  itemCount: rows.length,
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indices[key.value] : null,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final key = ValueKey(row.key);
                    final episode = row.episode;
                    if (row.count != null) {
                      return Padding(
                        key: key,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${row.title.title} • ${row.count} unwatched',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      );
                    }
                    if (episode == null) {
                      return Padding(
                        key: key,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() {
                              _visibleCounts[row.title.key] =
                                  (_visibleCounts[row.title.key] ?? 5) + 3;
                            }),
                            child: const Text('Show more'),
                          ),
                        ),
                      );
                    }
                    return Card(
                      key: key,
                      child: ListTile(
                        leading: Poster(row.title.poster),
                        title: Text('${episode.code} • ${episode.title}'),
                        subtitle: Text(
                          '${dateLabel(episode.airDate)}${row.title.networks.isEmpty ? '' : '\n${row.title.networks.join(', ')}'}',
                        ),
                        onTap: () => openScreen(
                          context,
                          EpisodeScreen(title: row.title, episode: episode),
                        ),
                        trailing: IconButton(
                          tooltip: 'Mark as watched',
                          icon: const Icon(Icons.check_box_outline_blank),
                          onPressed: () => perform(
                            context,
                            () => markEpisodeWithConfirmation(
                              context,
                              ref,
                              episode,
                              true,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
}
