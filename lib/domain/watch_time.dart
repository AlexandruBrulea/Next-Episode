import 'models.dart';

/// Known library content, including specials and announced episodes.
/// A watched mark counts the full runtime once, not actual playback time.
class WatchTimeSummary {
  final int watchedMinutes, totalMinutes, estimatedItems, unknownItems;
  const WatchTimeSummary(
    this.watchedMinutes,
    this.totalMinutes,
    this.estimatedItems,
    this.unknownItems,
  );

  double get fraction => totalMinutes == 0 ? 0 : watchedMinutes / totalMinutes;

  factory WatchTimeSummary.calculate(
    List<LibraryEntry> entries,
    Map<int, SeriesBundle> series,
    Map<String, DateTime> watched,
  ) {
    var total = 0, seen = 0, estimated = 0, unknown = 0;
    final counted = <String>{};
    void add(String key, int minutes, {bool estimate = false}) {
      if (!counted.add(key)) return;
      if (minutes <= 0) {
        unknown++;
        return;
      }
      total += minutes;
      if (watched.containsKey(key)) seen += minutes;
      if (estimate) estimated++;
    }

    for (final entry in entries) {
      final title = entry.title;
      if (!title.isTv) {
        add(title.key, title.runtimes.firstOrNull ?? 0);
        continue;
      }
      final bundle = series[title.id];
      if (bundle == null) {
        unknown++;
        continue;
      }
      final fallback =
          bundle.title.runtimes.where((n) => n > 0).firstOrNull ?? 0;
      for (final episode in bundle.episodes) {
        add(
          episode.key,
          episode.runtime > 0 ? episode.runtime : fallback,
          estimate: episode.runtime <= 0 && fallback > 0,
        );
      }
    }
    return WatchTimeSummary(seen, total, estimated, unknown);
  }
}
