import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import 'app_theme.dart';
import 'common.dart';
import 'details.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  LibrarySnapshot? _snapshot;
  DateTime? _timelineDay;
  ScheduleTimeline? _timeline;
  final currentWeekKey = GlobalKey();
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void scrollToToday() {
    if (scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(libraryProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            FailureView(error, () => ref.invalidate(libraryProvider)),
        data: (snapshot) {
          final today = day(DateTime.now());
          if (!identical(snapshot, _snapshot) || today != _timelineDay) {
            _snapshot = snapshot;
            _timelineDay = today;
            _timeline = buildScheduleTimeline(snapshot.series.values, today);
          }
          final timeline = _timeline!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Past & upcoming',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: scrollToToday,
                      icon: const Icon(Icons.today_outlined),
                      label: const Text('Today'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 140)
                        .floor()
                        .clamp(2, 6)
                        .toInt();
                    final cardWidth =
                        (constraints.maxWidth - 32 - (columns - 1) * 12) /
                        columns;
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    Widget section(ScheduleSection section) {
                      final entries = groupReleasesByDay(section.entries);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section.label,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            if (section.entries.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 24),
                                child: Text('No episodes scheduled this week.'),
                              )
                            else
                              GridView.builder(
                                shrinkWrap: true,
                                primary: false,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 16,
                                      mainAxisExtent:
                                          cardWidth * 1.5 + 86 * textScale,
                                    ),
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  return _SchedulePoster(
                                    entry: entry,
                                    watched: entry.allWatched(snapshot.watched),
                                    onTap: () => openScreen(
                                      context,
                                      entry.episodes.length == 1
                                          ? EpisodeScreen(
                                              title: entry.title,
                                              episode: entry.episodes.single,
                                            )
                                          : ReleaseEpisodesScreen(entry: entry),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    }

                    // The center is the current week. History grows upward at negative
                    // offsets; future weeks grow downward. Today always means offset zero,
                    // independent of poster sizes, screen width or the length of history.
                    return CustomScrollView(
                      controller: scroll,
                      center: currentWeekKey,
                      slivers: [
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => section(
                              timeline.past[timeline.past.length - 1 - index],
                            ),
                            childCount: timeline.past.length,
                          ),
                        ),
                        SliverList(
                          key: currentWeekKey,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                section(timeline.upcoming[index]),
                            childCount: timeline.upcoming.length,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
}

class ReleaseEpisodesScreen extends ConsumerWidget {
  final ScheduleEntry entry;
  const ReleaseEpisodesScreen({super.key, required this.entry});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(libraryProvider).asData?.value.watched ?? {};
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title.title),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: entry.episodes.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${entry.dateRange} · ${entry.episodeRange}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            );
          }
          final episode = entry.episodes[index - 1];
          return ListTile(
            title: Text('${episode.code} · ${episode.title}'),
            leading: Icon(
              watched.containsKey(episode.key)
                  ? Icons.check_circle
                  : Icons.play_circle_outline,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openScreen(
              context,
              EpisodeScreen(title: entry.title, episode: episode),
            ),
          );
        },
      ),
    );
  }
}

class _SchedulePoster extends StatelessWidget {
  final ScheduleEntry entry;
  final bool watched;
  final VoidCallback onTap;
  const _SchedulePoster({
    required this.entry,
    required this.watched,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${entry.title.title}, ${entry.dateRange}, ${entry.episodeRange}${watched ? ', watched' : ''}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Poster(
                    entry.title.poster,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF204E61),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          'TV',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (watched)
                    const Positioned(
                      top: 7,
                      right: 7,
                      child: Tooltip(
                        message: 'Episode watched',
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: neonCyan,
                          child: Icon(
                            Icons.check,
                            color: Color(0xFF042A30),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.title.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              entry.dateRange,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: neonCyan),
            ),
            Tooltip(
              message: entry.episodeRange,
              child: Text(
                entry.episodeRange,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
