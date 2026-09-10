import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';
import '../application/providers.dart';
import 'app_theme.dart';

Future<void> markEpisodeWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  EpisodeData episode,
  bool seen,
) async {
  final controller = ref.read(libraryProvider.notifier);
  if (!seen || episode.isSpecial) {
    await controller.markEpisode(episode, seen);
    return;
  }
  final bundle = await ref
      .read(seriesRepositoryProvider)
      .cached(episode.seriesId);
  final watched = await ref.read(progressRepositoryProvider).all();
  final now = DateTime.now();
  final previous =
      (bundle?.episodes ?? <EpisodeData>[])
          .where(
            (e) =>
                !e.isSpecial &&
                e.released(now) &&
                episodeOrder(e, episode) < 0 &&
                !watched.containsKey(e.key),
          )
          .toList()
        ..sort(episodeOrder);
  if (!context.mounted) return;
  if (previous.isEmpty || watched.containsKey(episode.key)) {
    await controller.markEpisode(episode, true);
    return;
  }
  final includePrevious = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Mark earlier episodes as watched?'),
      content: Text(
        'You have ${previous.length} earlier unwatched episodes in this show. Mark them as watched along with ${episode.code}?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('No, only this episode'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes, include earlier episodes'),
        ),
      ],
    ),
  );
  if (includePrevious == null || !context.mounted) return;
  await controller.markEpisodesSeen([
    if (includePrevious) ...previous,
    episode,
  ]);
}

String publicError(Object error) =>
    'Information is temporarily unavailable. Your saved data is safe. Please try again.';

void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
Future<void> perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) message(context, publicError(e));
  }
}

void openScreen(BuildContext context, Widget screen) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints.tightFor(
      width: MediaQuery.sizeOf(context).width,
    ),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.94,
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            removeRight: true,
            child: SafeArea(
              top: true,
              bottom: true,
              left: false,
              right: false,
              child: screen,
            ),
          ),
        ),
      ),
    ),
  );
}

class Poster extends StatelessWidget {
  final String path;
  final double width, height;
  const Poster(this.path, {super.key, this.width = 48, this.height = 72});
  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(
      width: width,
      height: height,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF213A54), Color(0xFF292044)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(Icons.movie_outlined, color: neonViolet),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: path.isEmpty
          ? placeholder
          : Image.network(
              path,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => placeholder,
            ),
    );
  }
}

class SourceCredit extends StatelessWidget {
  final String label, url;
  const SourceCredit(this.label, this.url, {super.key});
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => perform(context, () async {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('The link could not be opened.');
      }
    }),
    child: Text(label),
  );
}

class FailureView extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const FailureView(this.error, this.retry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(publicError(error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class ActionButton extends StatefulWidget {
  final Future<void> Function() action;
  final String label;
  const ActionButton({super.key, required this.action, required this.label});
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: busy
        ? null
        : () async {
            setState(() => busy = true);
            await perform(context, widget.action);
            if (mounted) setState(() => busy = false);
          },
    child: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(widget.label),
  );
}

class MediaTile extends StatelessWidget {
  final TitleData title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final double? progress;
  const MediaTile({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.progress,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(title.poster, width: 68, height: 102),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: (title.isTv ? neonCyan : neonViolet)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (title.isTv ? neonCyan : neonViolet)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  title.isTv
                                      ? Icons.tv_rounded
                                      : Icons.local_movies_rounded,
                                  size: 14,
                                  color: title.isTv ? neonCyan : neonViolet,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  title.isTv ? 'SHOW' : 'MOVIE',
                                  style: TextStyle(
                                    color: title.isTv ? neonCyan : neonViolet,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${title.releaseDate?.year ?? '—'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF3CC7A),
                            size: 17,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            title.ratingLabel,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0).toDouble(),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class InfoLine extends StatelessWidget {
  final String label, value;
  const InfoLine(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          TextSpan(
            text: value.isEmpty ? 'Unavailable' : value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );
}
