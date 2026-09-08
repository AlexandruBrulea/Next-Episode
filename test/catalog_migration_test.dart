import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';

import 'fixtures.dart';
import 'catalog_router_test.dart' show CatalogFixture;

class LegacyDatabase extends AppDatabase {
  LegacyDatabase(File file) : super(NativeDatabase(file));
  @override
  int get schemaVersion => 1;
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
    },
  );
}

void main() {
  test('v1 upgrade retains library/cache/timestamps and reserves removed title identities', () async {
    final directory = await Directory.systemTemp.createTemp(
      'catalog_migration_',
    );
    final file = File('${directory.path}/legacy.sqlite');
    final legacy = LegacyDatabase(file);
    await legacy.add(tv(), now);
    await legacy.add(movie(), now);
    await legacy.cache('series:10', bundle().toJson(), now);
    await legacy.mark('episode:10:1', true, now);
    await legacy.mark('episode:99:900', true, now);
    await legacy.setPreference('library.sort', 'Title');
    await legacy.close();
    final db = AppDatabase.file(file);
    try {
      expect(await db.library(), hasLength(2));
      expect((await db.watched())['episode:10:1'], now);
      expect(await db.preference('library.sort'), 'Title');
      final aliases = await db
          .customSelect("SELECT * FROM catalog_refs WHERE provider='tmdb'")
          .get();
      expect(
        aliases
            .map((r) => '${r.read<String>('type')}:${r.read<int>('local_id')}')
            .toSet(),
        {'tv:10', 'movie:10', 'tv:99'},
      );
      final router = CatalogRouter(
        db: db,
        modules: {'tvmaze': CatalogFixture('tvmaze', 10, 1)},
        active: 'tvmaze',
      );
      final newTitle = (await router.search(
        'different',
        null,
        1,
      )).results.single;
      expect(newTitle.id, greaterThan(99));
      expect((await db.watched()).keys, contains('episode:99:900'));
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
