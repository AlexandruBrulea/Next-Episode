import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/watch_time.dart';
import 'app_theme.dart';
import 'common.dart';

class LibraryWatchTime extends StatelessWidget {
  final WatchTimeSummary summary;
  const LibraryWatchTime(this.summary, {super.key});
  String hours(int minutes) =>
      (minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: panelColor,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: edgeColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.timelapse_rounded, size: 18, color: neonCyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'YOUR WATCH TIME',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1.5, color: neonCyan),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${hours(summary.watchedMinutes)} h watched of ${hours(summary.totalMinutes)} h',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: summary.fraction,
          semanticsLabel: 'Library watch time',
          semanticsValue: '${(summary.fraction * 100).round()}%',
        ),
        const SizedBox(height: 8),
        Text(
          'Across your library'
          '${summary.estimatedItems > 0 ? ' · Estimated runtimes' : ''}'
          '${summary.unknownItems > 0 ? ' · Missing durations excluded' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class LibraryPosterCard extends StatelessWidget {
  final TitleData title;
  final double progress;
  final VoidCallback onTap;
  const LibraryPosterCard({
    super.key,
    required this.title,
    required this.progress,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${title.title}, ${(progress * 100).round()}% watched',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Poster(
                    title.poster,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE610182A),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        title.isTv ? 'SHOW' : 'MOVIE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: title.isTv ? neonCyan : neonViolet,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              semanticsLabel: '${title.title} watch progress',
            ),
            const SizedBox(height: 7),
            Text(
              title.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 3),
            if (title.releaseDate != null)
              Text(
                '${title.releaseDate!.year}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (title.status.isNotEmpty &&
                title.statusLabel != 'Unknown status')
              Text(
                title.statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: neonCyan),
              ),
          ],
        ),
      ),
    ),
  );
}
