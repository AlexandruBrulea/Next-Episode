import 'package:flutter/material.dart';
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

class _EpisodeFeedState extends ConsumerState<EpisodeFeed> {
  final Map<String, int> _visibleCounts = {};
  bool get calendar => widget.calendar;

  @override
  Widget build(BuildContext context) => calendar ? const CalendarScreen() : ref
      .watch(libraryProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => FailureView(e, () => ref.invalidate(libraryProvider)),
        data: (snapshot) {
          final now = day(DateTime.now());
          final items = <({TitleData title, EpisodeData episode})>[];
          for (final bundle in snapshot.series.values) {
            for (final episode in bundle.episodes) {
              if (episode.isSpecial) continue;
              final include = calendar
                  ? episode.airDate == null ||
                        !day(episode.airDate!).isBefore(now)
                  : episode.released(now) &&
                        !snapshot.watched.containsKey(episode.key);
              if (include) items.add((title: bundle.title, episode: episode));
            }
          }
          items.sort((a, b) {
            if (calendar) {
              final byDate = (a.episode.airDate ?? DateTime(9999)).compareTo(
                b.episode.airDate ?? DateTime(9999),
              );
              if (byDate != 0) return byDate;
            }
            final byTitle = a.title.title.compareTo(b.title.title);
            return byTitle != 0 ? byTitle : episodeOrder(a.episode, b.episode);
          });
          final groups =
              <String, List<({TitleData title, EpisodeData episode})>>{};
          for (final item in items) {
            final d = item.episode.airDate;
            final key = !calendar
                ? item.title.key
                : d == null
                ? 'Date TBA'
                : day(d) == now
                ? 'Today'
                : day(d) == now.add(const Duration(days: 1))
                ? 'Tomorrow'
                : dateLabel(d);
            groups.putIfAbsent(key, () => []).add(item);
          }
          if (items.isEmpty) {
            return Center(
              child: Text(
                calendar
                    ? 'No upcoming episodes are known for your library.'
                    : 'No released, unwatched episodes.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView(
            children: [
              if (calendar)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Original air dates; availability may vary by region. Air times are not provided. Specials are listed under season 0.',
                  ),
                ),
              for (final group in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    calendar
                        ? group.key
                        : '${group.value.first.title.title} • ${group.value.length} unwatched',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final item in group.value.take(
                  calendar
                      ? group.value.length
                      : (_visibleCounts[group.key] ?? 5),
                ))
                  Card(child: ListTile(
                    leading: Poster(item.title.poster),
                    title: Text(
                      '${calendar ? '${item.title.title}\n' : ''}${item.episode.code} • ${item.episode.title}',
                    ),
                    subtitle: Text(
                      '${dateLabel(item.episode.airDate)}${item.title.networks.isEmpty ? '' : '\n${item.title.networks.join(', ')}'}',
                    ),
                    onTap: () => openScreen(
                      context,
                      EpisodeScreen(title: item.title, episode: item.episode),
                    ),
                    trailing: !calendar
                        ? IconButton(
                            tooltip: 'Mark as watched',
                            icon: const Icon(Icons.check_box_outline_blank),
                            onPressed: () => perform(
                              context,
                              () => markEpisodeWithConfirmation(
                                context,
                                ref,
                                item.episode,
                                true,
                              ),
                            ),
                          )
                        : null,
                  )),
                if (!calendar &&
                    group.value.length > (_visibleCounts[group.key] ?? 5))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() {
                          _visibleCounts[group.key] =
                              (_visibleCounts[group.key] ?? 5) + 3;
                        }),
                        child: const Text('Show more'),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      );
}
