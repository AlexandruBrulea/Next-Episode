import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';
import 'package:next_episode/data/catalog/internal_catalog.dart';
import 'package:next_episode/data/database.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/domain/catalog_provider.dart';

import 'fixtures.dart';

class ChangingCatalog extends FakeApi {
  @override
  String get id => 'tvmaze';
  List<Json> episodes = [episodeJson(101, 1), episodeJson(102, 2)];
  @override
  Future<SeriesBundle> series(int id) async => SeriesBundle(
    TitleData(MediaType.tv, {...tv().raw, 'provider': 'tvmaze'}),
    [
      SeasonData(10, {'id': 100, 'season_number': 1, 'episodes': episodes}),
    ],
  );
  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async =>
      SearchPage([(await series(10)).title], 1, 1);
}

void main() {
  test('routine removal preserves marks and identities, reappearance restores progress', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final api = ChangingCatalog();
    final router = CatalogRouter(
      db: db,
      modules: {'tvmaze': api},
      active: 'tvmaze',
    );
    final title = (await router.search('show', null, 1)).results.single;
    await db.add(title, now);
    final initial = await router.series(title.id);
    final removed = initial.episodes.last;
    await db.mark(removed.key, true, now);
    api.episodes = [episodeJson(101, 1), episodeJson(103, 3)];
    final fresh = await router.series(title.id);
    expect(fresh.episodes.map((e) => e.number), [1, 3]);
    expect(fresh.episodes.first.id, initial.episodes.first.id);
    expect(fresh.episodes.last.id, isNot(removed.id));
    expect((await db.watched())[removed.key], now);
    final repeat = await router.series(title.id);
    expect(repeat.episodes.map((e) => e.id), fresh.episodes.map((e) => e.id));
    api.episodes = [
      episodeJson(101, 1),
      episodeJson(102, 2),
      episodeJson(103, 3),
    ];
    final returned = await router.series(title.id);
    expect(returned.episodes[1].key, removed.key);
    expect((await db.watched())[returned.episodes[1].key], now);

    for (final unsafe in [
      <Json>[],
      [episodeJson(101, 1), episodeJson(102, 4)],
      [episodeJson(101, 1), episodeJson(999, 2)],
    ]) {
      api.episodes = unsafe;
      await expectLater(router.series(title.id), throwsA(isA<ApiFailure>()));
      final cached = await InternalCatalog(db).cached(title.id);
      expect(
        cached!.episodes.map((e) => e.key),
        returned.episodes.map((e) => e.key),
      );
      expect((await db.watched())[removed.key], now);
    }
  });

  test('strict migration validation still rejects missing episodes', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final api = ChangingCatalog();
    final old = await api.series(10);
    api.episodes = [episodeJson(101, 1)];
    final remote = await api.series(10);
    expect(
      () => InternalCatalog(db).verify(old, remote),
      throwsA(
        isA<CatalogConflict>().having((e) => e.code, 'code', 'missing_episode'),
      ),
    );
  });
}
