import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../database.dart';
import '../tmdb_retention.dart';

class CatalogConflict implements Exception {
  final String code, detail;
  const CatalogConflict(this.code, this.detail);
  @override
  String toString() => '$code: $detail';
}

/// Stable entity graph. Metadata and external identifiers can change, logical
/// episode slots and user-facing internal IDs cannot.
class InternalCatalog {
  final AppDatabase db;
  InternalCatalog(this.db);
  String slot(int showId, EpisodeData e) => '$showId:${e.season}:${e.number}';
  Future<SeriesBundle?> cached(int id) async {
    final result = await db.cached('series:$id');
    return result == null ? null : SeriesBundle.fromJson(result.data);
  }

  void verify(SeriesBundle? old, SeriesBundle incoming) {
    final episodes = incoming.episodes;
    if (episodes.map((e) => e.id).toSet().length != episodes.length) {
      throw const CatalogConflict(
        'duplicate_episode',
        'Duplicate external episode IDs',
      );
    }
    if (incoming.seasons.map((s) => s.number).toSet().length !=
        incoming.seasons.length) {
      throw const CatalogConflict(
        'duplicate_season',
        'Duplicate season numbers',
      );
    }
    final numbered = episodes
        .where((e) => !e.isSpecial && e.number > 0)
        .toList();
    final keys = numbered.map((e) => '${e.season}:${e.number}').toSet();
    if (keys.length != numbered.length) {
      throw const CatalogConflict(
        'ambiguous_numbering',
        'Multiple episodes occupy the same logical slot',
      );
    }
    if (episodes.any((e) => !e.isSpecial && e.number <= 0)) {
      throw const CatalogConflict(
        'missing_number',
        'An ordinary episode has no number',
      );
    }
    if (old == null) return;
    for (final previous in old.episodes) {
      if (previous.isSpecial) {
        final matches = episodes.where(
          (e) =>
              e.isSpecial &&
              old.title.provider == incoming.title.provider &&
              integer(e.raw['source_id'], e.id) ==
                  integer(previous.raw['source_id'], previous.id),
        );
        if (matches.length != 1) {
          throw const CatalogConflict(
            'special_mapping',
            'Special episodes require an administrative mapping',
          );
        }
      } else if (!keys.contains('${previous.season}:${previous.number}')) {
        throw CatalogConflict(
          'missing_episode',
          'Missing or renumbered S${previous.season}E${previous.number}',
        );
      }
    }
    for (final season in old.seasons) {
      if (!incoming.seasons.any((s) => s.number == season.number)) {
        throw CatalogConflict(
          'season_numbering',
          'Season ${season.number} is absent or renumbered',
        );
      }
    }
  }

  Future<void> saveTitle(TitleData title, {double confidence = 1}) async {
    if (title.provider == 'tmdb') await db.requireTmdbContent();
    final conflict = await db
        .customSelect(
          'SELECT local_id FROM catalog_refs WHERE provider=? AND type=? AND remote_id=?',
          variables: [
            Variable(title.provider),
            Variable(title.type.name),
            Variable(title.sourceId),
          ],
        )
        .getSingleOrNull();
    if (conflict != null && conflict.read<int>('local_id') != title.id) {
      throw const CatalogConflict(
        'title_collision',
        'External ID already assigned to another internal title',
      );
    }
    await db.customStatement(
      'INSERT OR REPLACE INTO catalog_titles VALUES (?,?,?)',
      [
        title.type.name,
        title.id,
        jsonEncode(stampTmdb(title.raw, db.retentionClock())),
      ],
    );
    await db.customStatement(
      'INSERT INTO catalog_refs VALUES (?,?,?,?) ON CONFLICT(provider,type,remote_id) DO NOTHING',
      [title.provider, title.type.name, title.sourceId, title.id],
    );
    await db.recordLink(
      title.key,
      title.type.name,
      title.provider,
      title.sourceId,
      externalIds: title.externalIds,
      confidence: confidence,
    );
  }

  Future<SeriesBundle> bind(
    int showId,
    SeriesBundle remote, {
    double confidence = 1,
  }) async {
    final old = await cached(showId);
    verify(old, remote);
    final seasonRows = await db
        .customSelect(
          'SELECT * FROM internal_seasons WHERE series_id=?',
          variables: [Variable(showId)],
        )
        .get();
    final seasonIds = {
      for (final r in seasonRows) r.read<int>('number'): r.read<int>('id'),
    };
    var nextSeason = seasonIds.values.fold<int>(0, (a, b) => a > b ? a : b) + 1;
    final episodeRows = await db
        .customSelect(
          'SELECT * FROM internal_episodes WHERE series_id=?',
          variables: [Variable(showId)],
        )
        .get();
    final episodeIds = {
      for (final r in episodeRows)
        r.read<String>('logical_key'): r.read<int>('id'),
    };
    final knownInternalIds = episodeIds.values.toSet();
    final marks = await db
        .customSelect(
          'SELECT key FROM watched WHERE key LIKE ?',
          variables: [Variable('episode:$showId:%')],
        )
        .get();
    if (marks.any(
      (row) => !knownInternalIds.contains(
        int.tryParse(row.read<String>('key').split(':').last),
      ),
    )) {
      throw const CatalogConflict(
        'missing_internal_episode',
        'A watched episode has no logical identity; preserve cache for administrative review',
      );
    }
    final aliases = await db
        .customSelect(
          'SELECT * FROM episode_refs WHERE series_id=?',
          variables: [Variable(showId)],
        )
        .get();
    final known = {
      for (final r in aliases.where(
        (r) => r.read<String>('provider') == remote.title.provider,
      ))
        r.read<int>('remote_id'): r.read<int>('local_id'),
    };
    var nextEpisode =
        [
          ...episodeIds.values,
          ...aliases.map((r) => r.read<int>('local_id')),
        ].fold<int>(0, (a, b) => a > b ? a : b) +
        1;
    final used = <int>{};
    final translated = <int, Json>{};
    final seasons = <SeasonData>[];
    for (final season in remote.seasons) {
      final seasonId = seasonIds[season.number] ?? nextSeason++;
      final oldSeason = old?.seasons
          .where((s) => s.number == season.number)
          .firstOrNull;
      final actualSeasonId =
          seasonIds[season.number] ?? oldSeason?.id ?? seasonId;
      final normalized = <Json>[];
      await db.customStatement(
        'INSERT OR IGNORE INTO internal_seasons VALUES (?,?,?)',
        [showId, actualSeasonId, season.number],
      );
      await db.recordLink(
        'season:$showId:$actualSeasonId',
        'season',
        remote.title.provider,
        integer(season.raw['source_id'], season.id),
        confidence: confidence,
      );
      for (final episode in season.episodes) {
        final remoteId = integer(episode.raw['source_id'], episode.id);
        final logical = episode.isSpecial
            ? 'special:$showId:${known[remoteId] ?? nextEpisode}'
            : slot(showId, episode);
        final logicalId = episodeIds[logical];
        final aliasId = known[remoteId];
        if (aliasId != null) {
          final previous = episodeRows
              .where((r) => r.read<int>('id') == aliasId)
              .firstOrNull;
          if (previous != null &&
              previous.read<String>('logical_key') != logical) {
            throw const CatalogConflict(
              'renumbered_episode',
              'A known external episode moved to a different logical slot',
            );
          }
        }
        final localId = logicalId ?? aliasId ?? nextEpisode++;
        if (!used.add(localId)) {
          throw const CatalogConflict(
            'duplicate_identity',
            'Multiple episodes map to one internal identity',
          );
        }
        final aliasOwner = aliases
            .where(
              (r) =>
                  r.read<String>('provider') == remote.title.provider &&
                  r.read<int>('local_id') == localId &&
                  r.read<int>('remote_id') != remoteId,
            )
            .firstOrNull;
        if (aliasOwner != null) {
          throw const CatalogConflict(
            'external_episode_changed',
            'A provider replaced the ID in an occupied logical slot',
          );
        }
        await db.customStatement(
          'INSERT OR IGNORE INTO internal_episodes VALUES (?,?,?,?,?,?)',
          [
            showId,
            localId,
            actualSeasonId,
            episode.season,
            episode.number,
            logical,
          ],
        );
        await db.customStatement(
          'INSERT OR IGNORE INTO episode_refs VALUES (?,?,?,?)',
          [remote.title.provider, showId, remoteId, localId],
        );
        await db.recordLink(
          'episode:$showId:$localId',
          'episode',
          remote.title.provider,
          remoteId,
          confidence: confidence,
        );
        final data = {
          ...episode.raw,
          'id': localId,
          'source_id': remoteId,
          'logical_key': logical,
        };
        translated[episode.id] = data;
        normalized.add(data);
      }
      seasons.add(
        SeasonData(showId, {
          ...season.raw,
          'id': actualSeasonId,
          'source_id': integer(season.raw['source_id'], season.id),
          'episodes': normalized,
        }),
      );
    }
    final title = TitleData(MediaType.tv, {
      ...remote.title.raw,
      'id': showId,
      'source_id': remote.title.sourceId,
      'seasons': [
        for (final season in seasons)
          {
            for (final entry in season.raw.entries)
              if (entry.key != 'episodes') entry.key: entry.value,
          },
      ],
      for (final field in ['last_episode_to_air', 'next_episode_to_air'])
        if (remote.title.raw[field] is Map)
          field: translated[integer(remote.title.raw[field]['id'])],
    });
    await saveTitle(title, confidence: confidence);
    return SeriesBundle(title, seasons);
  }

  Future<void> persist(SeriesBundle bundle) async {
    await db.cache(
      'series:${bundle.title.id}',
      bundle.toJson(),
      db.retentionClock(),
    );
    await db.updateTitle(bundle.title, db.retentionClock());
  }
}
