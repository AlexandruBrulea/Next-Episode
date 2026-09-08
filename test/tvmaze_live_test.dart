import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/tvmaze_provider.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/data/repositories.dart';

void main() {
  test(
    'live TVmaze search, complete catalog and local tracking without a token',
    () async {
      final api = TvmazeProvider();
      final db = AppDatabase.memory();
      final router = CatalogRouter(
        db: db,
        modules: {'tvmaze': api},
        active: 'tvmaze',
      );
      try {
        final search = await router.search('Breaking Bad', null, 1);
        final title = search.results.firstWhere(
          (t) => t.externalIds['imdb_id'] == 'tt0903747',
        );
        final loaded = await SeriesRepository(router, db).load(title.id);
        expect(loaded.value.episodes, isNotEmpty);
        expect(loaded.value.title.provider, 'tvmaze');
        expect(loaded.value.title.poster, startsWith('https://'));
        expect(loaded.value.title.overview, isNot(contains('<p>')));
        await db.add(loaded.value.title, DateTime.now());
        final e = loaded.value.episodes.firstWhere(
          (e) => !e.isSpecial && e.released(DateTime.now()),
        );
        await ProgressRepository(db).episode(e, true);
        expect((await db.watched()).containsKey(e.key), isTrue);
        final reloaded = await SeriesRepository(router, db).load(title.id);
        expect(reloaded.value.episodes.map((e) => e.key), contains(e.key));
      } finally {
        router.close();
        await db.close();
      }
    },
    skip: !const bool.fromEnvironment('LIVE_TVMAZE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
