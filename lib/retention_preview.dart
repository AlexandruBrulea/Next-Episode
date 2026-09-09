// Isolated visual fixture. Never opens the user's on-disk database or calls APIs.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers.dart';
import 'data/database.dart';
import 'data/demo_source.dart';
import 'data/tmdb_retention.dart';
import 'domain/catalog_provider.dart';
import 'domain/models.dart';
import 'main.dart' show NextEpisodeApp;

class PreviewOfflineSource extends DemoSource {
  @override
  String get id => 'tmdb';
  @override
  Future<TitleData> title(MediaType type, int id) async =>
      throw const ApiFailure('Offline preview: network access is disabled.');
  @override
  Future<SeasonData> season(int seriesId, int number) async =>
      throw const ApiFailure('Offline preview: network access is disabled.');
  @override
  Future<SearchPage> popular(int page) async => const SearchPage([], 1, 1);
  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async =>
      const SearchPage([], 1, 1);
}

Future<AppDatabase> createRetentionPreview() async {
  final db = AppDatabase.memory();
  final now = DateTime.now().toUtc();
  final old = now.subtract(const Duration(days: 220));
  final demo = DemoSource();
  for (final expired in [true, false]) {
    final obtained = expired ? old : now;
    db.retentionClock = () => obtained;
    final id = expired ? 900001 : 900003;
    final title = TitleData(MediaType.tv, {
      ...demo.demoSeries.raw,
      'id': id,
      'provider': 'tmdb',
      'name': expired ? 'Sample island show' : 'Sample space show',
      'original_name': '',
      tmdbObtainedKey: obtained.toIso8601String(),
    });
    final season = await demo.season(id, 1);
    final bundle = SeriesBundle(title, [season]);
    await db.add(title, obtained);
    await db.cache('series:$id', bundle.toJson(), obtained);
    await db.mark(season.episodes.first.key, true, now);
  }
  db.retentionClock = DateTime.now;
  await db.enforceTmdbRetention();
  return db;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await createRetentionPreview();
  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      apiProvider.overrideWithValue(PreviewOfflineSource()),
    ],
    child: const NextEpisodeApp(),
  ));
}
