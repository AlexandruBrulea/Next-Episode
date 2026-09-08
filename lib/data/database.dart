import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../domain/models.dart';

/// Explicit SQL keeps the small schema reviewable without generated code.
/// All writes are parameterized; schemaVersion owns future migrations.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.file(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());
  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE library (key TEXT PRIMARY KEY, type TEXT NOT NULL, data TEXT NOT NULL, added_at TEXT NOT NULL, updated_at TEXT)',
      );
      await customStatement(
        'CREATE TABLE watched (key TEXT PRIMARY KEY, marked_at TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE cache (key TEXT PRIMARY KEY, data TEXT NOT NULL, fetched_at TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE sync_events (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL, detected_at TEXT NOT NULL)',
      );
      await _createCatalogTables();
      await _createAdministrativeTables();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _createCatalogTables();
        await _importLegacyIdentities();
      }
      if (from < 3) {
        await _createAdministrativeTables();
        await _importInternalEntities();
      }
    },
  );

  Future<void> _createAdministrativeTables() async {
    await customStatement(
      'CREATE TABLE internal_seasons (series_id INTEGER NOT NULL, id INTEGER NOT NULL, number INTEGER NOT NULL, PRIMARY KEY(series_id,id), UNIQUE(series_id,number))',
    );
    await customStatement(
      'CREATE TABLE internal_episodes (series_id INTEGER NOT NULL, id INTEGER NOT NULL, season_id INTEGER NOT NULL, season_number INTEGER NOT NULL, episode_number INTEGER NOT NULL, logical_key TEXT NOT NULL, PRIMARY KEY(series_id,id), UNIQUE(series_id,logical_key))',
    );
    await customStatement(
      'CREATE TABLE entity_links (entity_key TEXT NOT NULL, entity_type TEXT NOT NULL, provider TEXT NOT NULL, provider_id INTEGER NOT NULL, external_imdb_id TEXT, external_tvdb_id TEXT, last_verified_at TEXT NOT NULL, match_confidence REAL NOT NULL, PRIMARY KEY(entity_key,provider))',
    );
    await customStatement(
      'CREATE TABLE content_state (singleton INTEGER PRIMARY KEY CHECK(singleton=1), provider TEXT NOT NULL, generation INTEGER NOT NULL, deployment_id TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE admin_migrations (id TEXT PRIMARY KEY, target TEXT NOT NULL, generation INTEGER NOT NULL, status TEXT NOT NULL, report TEXT NOT NULL, backup TEXT NOT NULL, scope TEXT NOT NULL, created_at TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE admin_migration_items (migration_id TEXT NOT NULL, entity_key TEXT NOT NULL, status TEXT NOT NULL, fingerprint TEXT NOT NULL, staged TEXT, detail TEXT NOT NULL, PRIMARY KEY(migration_id,entity_key))',
    );
    await customStatement(
      'CREATE TABLE admin_conflicts (id INTEGER PRIMARY KEY AUTOINCREMENT, entity_key TEXT NOT NULL, detail TEXT NOT NULL, recorded_at TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE user_history (id INTEGER PRIMARY KEY AUTOINCREMENT, entity_key TEXT NOT NULL, action TEXT NOT NULL, occurred_at TEXT NOT NULL)',
    );
  }

  Future<void> _importInternalEntities() async {
    for (final row in await customSelect(
      "SELECT * FROM cache WHERE key LIKE 'series:%'",
    ).get()) {
      final bundle = SeriesBundle.fromJson(
        Json.from(jsonDecode(row.read<String>('data'))),
      );
      for (final season in bundle.seasons) {
        await customStatement(
          'INSERT OR IGNORE INTO internal_seasons VALUES (?,?,?)',
          [bundle.title.id, season.id, season.number],
        );
        await recordLink(
          'season:${bundle.title.id}:${season.id}',
          'season',
          bundle.title.provider,
          integer(season.raw['source_id'], season.id),
        );
        for (final e in season.episodes) {
          final logical = e.number > 0 && !e.isSpecial
              ? '${bundle.title.id}:${e.season}:${e.number}'
              : 'special:${bundle.title.id}:${e.id}';
          // Duplicate legacy numbering is kept under a separate identity for admin review.
          final duplicate = await customSelect(
            'SELECT id FROM internal_episodes WHERE series_id=? AND logical_key=?',
            variables: [Variable(bundle.title.id), Variable(logical)],
          ).getSingleOrNull();
          await customStatement(
            'INSERT OR IGNORE INTO internal_episodes VALUES (?,?,?,?,?,?)',
            [
              bundle.title.id,
              e.id,
              season.id,
              e.season,
              e.number,
              duplicate == null ? logical : 'legacy:${bundle.title.id}:${e.id}',
            ],
          );
          await recordLink(
            e.key,
            'episode',
            bundle.title.provider,
            integer(e.raw['source_id'], e.id),
          );
        }
      }
    }
    for (final row in await customSelect(
      'SELECT * FROM catalog_titles',
    ).get()) {
      final title = TitleData(
        MediaType.values.byName(row.read<String>('type')),
        Json.from(jsonDecode(row.read<String>('data'))),
      );
      for (final link in await customSelect(
        'SELECT * FROM catalog_refs WHERE type=? AND local_id=?',
        variables: [Variable(title.type.name), Variable(title.id)],
      ).get()) {
        await recordLink(
          title.key,
          title.type.name,
          link.read<String>('provider'),
          link.read<int>('remote_id'),
          externalIds: title.externalIds,
        );
      }
    }
  }

  Future<void> recordLink(
    String key,
    String type,
    String provider,
    int remoteId, {
    Map<String, String> externalIds = const {},
    double confidence = 1,
  }) => customStatement(
    'INSERT INTO entity_links VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(entity_key,provider) DO UPDATE SET provider_id=excluded.provider_id, external_imdb_id=COALESCE(excluded.external_imdb_id,entity_links.external_imdb_id), external_tvdb_id=COALESCE(excluded.external_tvdb_id,entity_links.external_tvdb_id), last_verified_at=excluded.last_verified_at, match_confidence=excluded.match_confidence',
    [
      key,
      type,
      provider,
      remoteId,
      externalIds['imdb_id'],
      externalIds['tvdb_id'],
      DateTime.now().toIso8601String(),
      confidence,
    ],
  );
  Future<void> administrativeConflict(String key, String detail) =>
      customStatement(
        'INSERT INTO admin_conflicts (entity_key,detail,recorded_at) VALUES (?,?,?)',
        [key, detail, DateTime.now().toIso8601String()],
      );

  Future<void> _createCatalogTables() async {
    await customStatement(
      'CREATE TABLE catalog_titles (type TEXT NOT NULL, local_id INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(type,local_id))',
    );
    await customStatement(
      'CREATE TABLE catalog_refs (provider TEXT NOT NULL, type TEXT NOT NULL, remote_id INTEGER NOT NULL, local_id INTEGER NOT NULL, PRIMARY KEY(provider,type,remote_id), UNIQUE(provider,type,local_id))',
    );
    await customStatement(
      'CREATE TABLE episode_refs (provider TEXT NOT NULL, series_id INTEGER NOT NULL, remote_id INTEGER NOT NULL, local_id INTEGER NOT NULL, PRIMARY KEY(provider,series_id,remote_id), UNIQUE(provider,series_id,local_id))',
    );
  }

  Future<void> _importLegacyIdentities() async {
    for (final row in await customSelect('SELECT * FROM library').get()) {
      await importIdentity(
        TitleData(
          MediaType.values.byName(row.read<String>('type')),
          Json.from(jsonDecode(row.read<String>('data'))),
        ),
      );
    }
    for (final row in await customSelect('SELECT * FROM cache').get()) {
      final key = row.read<String>('key');
      final data = Json.from(jsonDecode(row.read<String>('data')));
      if (key.startsWith('series:')) {
        final bundle = SeriesBundle.fromJson(data);
        await importIdentity(bundle.title);
        for (final e in bundle.episodes) {
          await customStatement(
            'INSERT OR IGNORE INTO episode_refs VALUES (?,?,?,?)',
            [
              bundle.title.provider,
              bundle.title.id,
              integer(e.raw['source_id'], e.id),
              e.id,
            ],
          );
        }
      } else if (key.startsWith('movie:')) {
        await importIdentity(TitleData(MediaType.movie, data));
      }
    }
    // Even orphaned marks reserve their old IDs; never attach them to a new show.
    for (final row in await customSelect('SELECT key FROM watched').get()) {
      final parts = row.read<String>('key').split(':');
      if (parts.length == 3 && parts[0] == 'episode') {
        final seriesId = int.parse(parts[1]);
        final episodeId = int.parse(parts[2]);
        await importIdentity(TitleData(MediaType.tv, {'id': seriesId}));
        await customStatement(
          'INSERT OR IGNORE INTO episode_refs VALUES (?,?,?,?)',
          ['tmdb', seriesId, episodeId, episodeId],
        );
      } else if (parts.length == 2 && parts[0] == 'movie') {
        await importIdentity(
          TitleData(MediaType.movie, {'id': int.parse(parts[1])}),
        );
      }
    }
  }

  Future<void> importIdentity(TitleData title) async {
    await customStatement(
      'INSERT OR IGNORE INTO catalog_titles VALUES (?,?,?)',
      [title.type.name, title.id, jsonEncode(title.raw)],
    );
    await customStatement(
      'INSERT OR IGNORE INTO catalog_refs VALUES (?,?,?,?)',
      [title.provider, title.type.name, title.sourceId, title.id],
    );
  }

  Future<List<LibraryEntry>> library() async =>
      (await customSelect('SELECT * FROM library ORDER BY added_at DESC').get())
          .map(
            (row) => LibraryEntry(
              TitleData(
                MediaType.values.byName(row.read<String>('type')),
                Json.from(jsonDecode(row.read<String>('data'))),
              ),
              DateTime.parse(row.read<String>('added_at')),
              DateTime.tryParse(row.readNullable<String>('updated_at') ?? ''),
            ),
          )
          .toList();
  Future<void> add(TitleData title, DateTime now) => transaction(() async {
    await customStatement(
      'INSERT OR IGNORE INTO library (key,type,data,added_at) VALUES (?,?,?,?)',
      [
        title.key,
        title.type.name,
        jsonEncode(title.raw),
        now.toIso8601String(),
      ],
    );
    await _history(title.key, 'library_added', now);
  });
  Future<void> remove(String key) => transaction(() async {
    await customStatement('DELETE FROM library WHERE key = ?', [key]);
    await _history(key, 'library_removed', DateTime.now());
  });
  Future<void> _history(String key, String action, DateTime now) async {
    if (schemaVersion < 3) return;
    final changed = await customSelect('SELECT changes() AS n').getSingle();
    if (changed.read<int>('n') == 0) return;
    await customStatement(
      'INSERT INTO user_history (entity_key,action,occurred_at) VALUES (?,?,?)',
      [key, action, now.toIso8601String()],
    );
  }

  Future<void> updateTitle(TitleData title, DateTime now) => customStatement(
    'UPDATE library SET data = ?, updated_at = ? WHERE key = ?',
    [jsonEncode(title.raw), now.toIso8601String(), title.key],
  );
  Future<Map<String, DateTime>> watched() async => {
    for (final row in await customSelect('SELECT * FROM watched').get())
      row.read<String>('key'): DateTime.parse(row.read<String>('marked_at')),
  };
  Future<void> mark(String key, bool seen, DateTime now) =>
      transaction(() async {
        if (seen) {
          await customStatement(
            'INSERT OR IGNORE INTO watched (key,marked_at) VALUES (?,?)',
            [key, now.toIso8601String()],
          );
        } else {
          await customStatement('DELETE FROM watched WHERE key = ?', [key]);
        }
        await _history(key, seen ? 'watched' : 'unwatched', now);
      });

  Future<({Json data, DateTime fetchedAt})?> cached(String key) async {
    final row = await customSelect(
      'SELECT * FROM cache WHERE key = ?',
      variables: [Variable(key)],
    ).getSingleOrNull();
    if (row == null) return null;
    return (
      data: Json.from(jsonDecode(row.read<String>('data'))),
      fetchedAt: DateTime.parse(row.read<String>('fetched_at')),
    );
  }

  Future<void> cache(String key, Json data, DateTime now) => customStatement(
    'INSERT OR REPLACE INTO cache (key,data,fetched_at) VALUES (?,?,?)',
    [key, jsonEncode(data), now.toIso8601String()],
  );
  Future<String?> preference(String key) async => (await customSelect(
    'SELECT value FROM preferences WHERE key = ?',
    variables: [Variable(key)],
  ).getSingleOrNull())?.read<String>('value');
  Future<void> setPreference(String key, String value) => customStatement(
    'INSERT OR REPLACE INTO preferences (key,value) VALUES (?,?)',
    [key, value],
  );
  Future<void> saveChanges(SyncChanges changes, DateTime now) async {
    if (changes.hasChanges) {
      await customStatement(
        'INSERT INTO sync_events (data,detected_at) VALUES (?,?)',
        [jsonEncode(changes.toJson()), now.toIso8601String()],
      );
    }
  }
}
