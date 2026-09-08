typedef Json = Map<String, dynamic>;

enum MediaType { tv, movie }

int integer(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;
double decimal(dynamic value) => value is num ? value.toDouble() : 0;
String string(dynamic value) => value is String ? value : '';
List<Json> objects(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];
DateTime? date(dynamic value) => DateTime.tryParse(string(value));
String textOr(dynamic value, String fallback) =>
    string(value).trim().isEmpty ? fallback : string(value);
// Compatibility with v1 cache paths. New modules emit complete image URLs.
String imageUrl(dynamic value) => string(value).startsWith('/')
    ? 'https://image.tmdb.org/t/p/w500$value'
    : string(value);
DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);
String dateLabel(DateTime? value) => value == null
    ? 'Air date TBA'
    : '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

/// Only localized text is replaced. IDs, dates and counts remain authoritative.
Json localized(Json primary, Json english) {
  final result = Json.from(primary);
  for (final key in ['name', 'title', 'overview']) {
    if (string(primary[key]).trim().isEmpty && english[key] is String) {
      result[key] = english[key];
    }
  }
  for (final key in ['seasons', 'episodes', 'genres']) {
    if (primary[key] is List) {
      final fallback = {
        for (final item in objects(english[key])) item['id']: item,
      };
      result[key] = objects(primary[key])
          .map((item) => localized(item, fallback[item['id']] ?? {}))
          .toList();
    }
  }
  for (final key in ['last_episode_to_air', 'next_episode_to_air']) {
    if (primary[key] is Map && english[key] is Map) {
      result[key] = localized(Json.from(primary[key]), Json.from(english[key]));
    }
  }
  return result;
}

class TitleData {
  final MediaType type;
  final Json raw;
  TitleData(this.type, Json json) : raw = Map.unmodifiable(json) {
    if (integer(json['id']) <= 0) {
      throw const FormatException('Invalid title');
    }
  }
  int get id => integer(raw['id']);
  String get key => '${type.name}:$id';
  String get provider => textOr(raw['provider'], 'tmdb');
  String get providerLabel => provider == 'tvmaze'
      ? 'TVmaze'
      : provider == 'demo'
      ? 'Demo'
      : 'TMDB';
  int get sourceId => integer(raw['source_id'], id);
  String get sourceUrl => textOr(
    raw['source_url'],
    'https://www.themoviedb.org/${type.name}/$sourceId',
  );
  Map<String, String> get externalIds => {
    if (raw['external_ids'] is Map)
      for (final entry in Json.from(raw['external_ids']).entries)
        if (['imdb_id', 'tvdb_id'].contains(entry.key) &&
            entry.value != null &&
            '${entry.value}'.isNotEmpty)
          entry.key: '${entry.value}',
  };
  bool get isTv => type == MediaType.tv;
  String get title => textOr(
    raw[isTv ? 'name' : 'title'],
    textOr(raw[isTv ? 'original_name' : 'original_title'], 'Unknown title'),
  );
  String get originalTitle =>
      string(raw[isTv ? 'original_name' : 'original_title']);
  String get overview => textOr(raw['overview'], 'No description available.');
  String get poster => imageUrl(raw['poster_path']);
  String get backdrop => imageUrl(raw['backdrop_path']);
  DateTime? get releaseDate =>
      date(raw[isTv ? 'first_air_date' : 'release_date']);
  DateTime? get lastAirDate => date(raw['last_air_date']);
  double get rating => decimal(raw['vote_average']);
  int get votes => integer(raw['vote_count']);
  String get ratingLabel => raw['vote_average'] == null
      ? 'Rating unavailable'
      : '${rating.toStringAsFixed(1)}${raw['vote_count'] == null ? '' : ' • $votes votes'}';
  String get originalLanguage => string(raw['original_language']);
  String get status => string(raw['status']);
  List<String> get genres =>
      objects(raw['genres']).map((e) => string(e['name'])).toList();
  List<String> get networks =>
      objects(raw['networks']).map((e) => string(e['name'])).toList();
  List<String> get countries =>
      (raw['origin_country'] as List? ?? []).map(string).toList();
  List<int> get runtimes => isTv
      ? (raw['episode_run_time'] as List? ?? []).map((e) => integer(e)).toList()
      : [integer(raw['runtime'])];
  int get seasonCount => integer(raw['number_of_seasons']);
  int get episodeCount => integer(raw['number_of_episodes']);
  List<SeasonData> get seasons =>
      objects(raw['seasons']).map((e) => SeasonData(id, e)).toList();
  EpisodeData? get lastEpisode => raw['last_episode_to_air'] is Map
      ? EpisodeData(id, 0, Json.from(raw['last_episode_to_air']))
      : null;
  EpisodeData? get nextEpisode => raw['next_episode_to_air'] is Map
      ? EpisodeData(id, 0, Json.from(raw['next_episode_to_air']))
      : null;
  Json get credits => raw['credits'] is Map ? Json.from(raw['credits']) : {};
  List<Json> get cast => objects(credits['cast']);
  List<String> get directors =>
      objects(credits['crew'])
          .where((e) => e['job'] == 'Director')
          .map((e) => string(e['name']))
          .toSet()
          .toList();
  String get statusLabel => switch (status) {
    'Returning Series' => 'Ongoing',
    'Ended' => 'Ended',
    'Canceled' => 'Canceled',
    'In Production' => 'In production',
    'Planned' => 'Planned',
    'Released' when !isTv => 'Released',
    'Post Production' when !isTv => 'Post production',
    _ => 'Unknown status',
  };
}

class SeasonData {
  final int seriesId;
  final Json raw;
  SeasonData(this.seriesId, this.raw);
  int get id => integer(raw['id']);
  int get number => integer(raw['season_number']);
  String get title => textOr(
    raw['name'],
    number == 0 ? 'Specials' : 'Season $number',
  );
  String get overview => textOr(raw['overview'], 'No description available.');
  String get poster => imageUrl(raw['poster_path']);
  DateTime? get airDate => date(raw['air_date']);
  int get count => integer(raw['episode_count'], episodes.length);
  List<EpisodeData> get episodes =>
      objects(raw['episodes'])
          .map((e) => EpisodeData(seriesId, id, e))
          .toList();
}

class EpisodeData {
  final int seriesId, seasonId;
  final Json raw;
  EpisodeData(this.seriesId, this.seasonId, this.raw) {
    if (integer(raw['id']) <= 0) {
      throw const FormatException('Invalid episode');
    }
  }
  int get id => integer(raw['id']);
  String get key => 'episode:$seriesId:$id';
  String get logicalKey =>
      textOr(raw['logical_key'], '$seriesId:$season:$number');
  bool get isSpecial => season == 0 || raw['is_special'] == true;
  int get season => integer(raw['season_number']);
  int get number => integer(raw['episode_number']);
  String get code =>
      'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';
  String get title => textOr(raw['name'], 'Episode $number');
  String get overview => textOr(raw['overview'], 'No description available.');
  String get still => imageUrl(raw['still_path']);
  DateTime? get airDate => date(raw['air_date']);
  int get runtime => integer(raw['runtime']);
  double get rating => decimal(raw['vote_average']);
  int get votes => integer(raw['vote_count']);
  List<Json> get crew => objects(raw['crew']);
  String get ratingLabel => raw['vote_average'] == null
      ? 'Rating unavailable'
      : '${rating.toStringAsFixed(1)}${raw['vote_count'] == null ? '' : ' • $votes votes'}';
  List<Json> get cast => objects(raw['guest_stars']);
  bool released(DateTime now) =>
      airDate != null && !day(airDate!).isAfter(day(now));
}

class SeriesBundle {
  final TitleData title;
  final List<SeasonData> seasons;
  const SeriesBundle(this.title, this.seasons);
  List<EpisodeData> get episodes => seasons.expand((s) => s.episodes).toList();
  Json toJson() => {
    'title': title.raw,
    'seasons': seasons.map((s) => s.raw).toList(),
  };
  factory SeriesBundle.fromJson(Json data) {
    final title = TitleData(MediaType.tv, Json.from(data['title']));
    return SeriesBundle(
      title,
      objects(data['seasons']).map((s) => SeasonData(title.id, s)).toList(),
    );
  }
  String get outlook {
    if (title.status == 'Ended' || title.status == 'Canceled') {
      return title.statusLabel;
    }
    if (seasons.any((s) => s.number > 0 && s.episodes.isEmpty)) {
      return 'Season listed, with no episodes available yet.';
    }
    if (episodes.any((e) => e.season > 0 && e.airDate == null)) {
      return 'Episodes announced without an air date.';
    }
    if (episodes.any((e) => e.season > 0 && !e.released(DateTime.now()))) {
      return 'Upcoming episodes have announced release dates.';
    }
    return 'No new season is confirmed in the available data.';
  }
}

/// User state is independent of the TMDB cache and survives removal and refresh.
class LibraryEntry {
  final TitleData title;
  final DateTime addedAt;
  final DateTime? updatedAt;
  const LibraryEntry(this.title, this.addedAt, this.updatedAt);
}

class WatchProgress {
  final List<EpisodeData> aired, seen, unseen;
  final EpisodeData? lastWatched;
  final String state;
  const WatchProgress(
    this.aired,
    this.seen,
    this.unseen,
    this.lastWatched,
    this.state,
  );
  double get fraction => aired.isEmpty ? 0 : seen.length / aired.length;
  EpisodeData? get firstUnseen => unseen.firstOrNull;
  static WatchProgress calculate(
    SeriesBundle bundle,
    Map<String, DateTime> watched,
    DateTime now,
  ) {
    final aired =
        bundle.episodes.where((e) => !e.isSpecial && e.released(now)).toList()
          ..sort(episodeOrder);
    final seen = aired.where((e) => watched.containsKey(e.key)).toList();
    final unseen = aired.where((e) => !watched.containsKey(e.key)).toList();
    final byMarked = [...seen]
      ..sort((a, b) => watched[a.key]!.compareTo(watched[b.key]!));
    final state = seen.isEmpty
        ? 'Not started'
        : unseen.isNotEmpty
        ? 'Watching'
        : bundle.title.status == 'Ended' &&
              !bundle.episodes.any((e) => !e.isSpecial && !e.released(now))
        ? 'Completed'
        : 'Up to date';
    return WatchProgress(aired, seen, unseen, byMarked.lastOrNull, state);
  }
}

int episodeOrder(EpisodeData a, EpisodeData b) {
  final season = a.season.compareTo(b.season);
  return season != 0 ? season : a.number.compareTo(b.number);
}

class SyncChanges {
  final String titleKey;
  final List<int> newEpisodes, changedEpisodes, removedEpisodes, newSeasons;
  final bool statusChanged, metadataChanged;
  const SyncChanges(
    this.titleKey,
    this.newEpisodes,
    this.changedEpisodes,
    this.removedEpisodes,
    this.newSeasons,
    this.statusChanged,
    this.metadataChanged,
  );
  bool get hasChanges =>
      newEpisodes.isNotEmpty ||
      changedEpisodes.isNotEmpty ||
      removedEpisodes.isNotEmpty ||
      newSeasons.isNotEmpty ||
      statusChanged ||
      metadataChanged;
  Json toJson() => {
    'titleKey': titleKey,
    'newEpisodes': newEpisodes,
    'changedEpisodes': changedEpisodes,
    'removedEpisodes': removedEpisodes,
    'newSeasons': newSeasons,
    'statusChanged': statusChanged,
    'metadataChanged': metadataChanged,
  };
}
