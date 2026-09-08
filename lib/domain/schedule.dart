import 'models.dart';

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'];

String scheduleDate(DateTime date) => '${monthNames[date.month - 1].substring(0, 3)} ${date.day}';

class ScheduleEntry {
  final TitleData title;
  final int season;
  final List<EpisodeData> episodes;
  const ScheduleEntry(this.title, this.season, this.episodes);
  String get dateRange {
    final dates = episodes.map((e) => e.airDate).whereType<DateTime>().toList()..sort();
    if (dates.isEmpty) return 'Date TBA';
    final first = dates.first, last = dates.last;
    return day(first) == day(last) ? scheduleDate(first) : '${scheduleDate(first)} – ${scheduleDate(last)}';
  }
  String get episodeRange {
    final numbers = episodes.map((e) => e.number).toSet().toList()..sort();
    final ranges = <String>[];
    String code(int n) => 'E${n.toString().padLeft(2, '0')}';
    for (var i = 0; i < numbers.length; i++) {
      final first = numbers[i];
      var last = first;
      while (i + 1 < numbers.length && numbers[i + 1] == last + 1) {
        last = numbers[++i];
      }
      ranges.add(first == last ? code(first) : '${code(first)}–${code(last)}');
    }
    return 'S${season.toString().padLeft(2, '0')} ${ranges.join(', ')}';
  }
  bool allWatched(Map<String, DateTime> watched) =>
      episodes.isNotEmpty && episodes.every((e) => watched.containsKey(e.key));
}

class ScheduleSection {
  final String label;
  final List<ScheduleEntry> entries;
  const ScheduleSection(this.label, this.entries);
}

class ScheduleTimeline {
  final List<ScheduleSection> past, upcoming;
  const ScheduleTimeline(this.past, this.upcoming);
}

/// History precedes the current week; that week always exists as a scroll anchor.
ScheduleTimeline buildScheduleTimeline(Iterable<SeriesBundle> series, DateTime now) {
  final week = DateTime(now.year, now.month, now.day - now.weekday + 1);
  final bundles = series.toList();
  final historical = [for (final bundle in bundles) SeriesBundle(bundle.title, [
    for (final season in bundle.seasons) SeasonData(bundle.title.id, {
      ...season.raw,
      'episodes': [for (final episode in season.episodes)
        if (episode.airDate != null && day(episode.airDate!).isBefore(week)) episode.raw],
    }),
  ])];
  final years = {for (final bundle in historical)
    for (final episode in bundle.episodes)
      if (!episode.isSpecial) episode.airDate!.year}.toList()..sort();
  final past = [for (final year in years) ...buildSchedule(historical, now, year: year)];
  final upcoming = buildSchedule(bundles, week);
  final currentLabel = '${scheduleDate(week)} – ${scheduleDate(DateTime(week.year, week.month, week.day + 6))} · ${week.year}';
  if (upcoming.isEmpty || upcoming.first.label != currentLabel) {
    upcoming.insert(0, ScheduleSection(currentLabel, const []));
  }
  return ScheduleTimeline(past, upcoming);
}

/// A selected year includes past and future dates, grouped by month.
/// Upcoming begins today and groups dates by Monday–Sunday weeks.
List<ScheduleSection> buildSchedule(Iterable<SeriesBundle> series, DateTime now, {int? year}) {
  final today = day(now);
  final buckets = <DateTime, Map<String, List<EpisodeData>>>{};
  final titles = <String, TitleData>{};
  final unknown = <String, List<EpisodeData>>{};
  for (final bundle in series) {
    for (final episode in bundle.episodes) {
      if (episode.isSpecial) continue;
      final key = '${bundle.title.key}:${episode.season}';
      titles[key] = bundle.title;
      final date = episode.airDate;
      if (date == null) {
        if (year == null) unknown.putIfAbsent(key, () => []).add(episode);
        continue;
      }
      if (year != null ? date.year != year : day(date).isBefore(today)) continue;
      final bucket = year != null
          ? DateTime(date.year, date.month)
          : DateTime(date.year, date.month, date.day - date.weekday + 1);
      buckets.putIfAbsent(bucket, () => {}).putIfAbsent(key, () => []).add(episode);
    }
  }
  List<ScheduleEntry> entries(Map<String, List<EpisodeData>> groups) {
    final result = [for (final group in groups.entries)
      ScheduleEntry(titles[group.key]!, group.value.first.season, group.value..sort(episodeOrder))];
    result.sort((a, b) {
      DateTime first(ScheduleEntry e) => e.episodes.map((e) => e.airDate ?? DateTime(9999)).reduce((a, b) => a.isBefore(b) ? a : b);
      final date = first(a).compareTo(first(b));
      if (date != 0) return date;
      final title = a.title.title.compareTo(b.title.title);
      return title != 0 ? title : a.season.compareTo(b.season);
    });
    return result;
  }
  final dates = buckets.keys.toList()..sort();
  return [
    for (final date in dates) ScheduleSection(
      year != null ? '${monthNames[date.month - 1]} ${date.year}'
          : '${scheduleDate(date)} – ${scheduleDate(DateTime(date.year, date.month, date.day + 6))} · ${date.year}',
      entries(buckets[date]!),
    ),
    if (unknown.isNotEmpty) ScheduleSection('Date TBA', entries(unknown)),
  ];
}
