import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';
import 'package:next_episode/data/database.dart';

import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/domain/models.dart';

import 'fixtures.dart' show episodeJson;

class CatalogFixture extends CatalogProvider {
  @override
  final String id;
  final int showId, episodeId;
  String external = 'tt1234';
  String air = '2020-01-01';
  bool match = true;
  bool fail = false;
  CatalogFixture(this.id, this.showId, this.episodeId);
  @override
  String get label => id;
  @override
  CatalogCapabilities get capabilities => CatalogCapabilities(
    movies: id == 'tmdb',
    localizedText: id == 'tmdb',
    paginatedSearch: true,
  );
  TitleData get show => TitleData(MediaType.tv, {
    'id': showId,
    'source_id': showId,
    'provider': id,
    'name': 'Same show',
    'external_ids': {'imdb_id': external},
    'status': 'Returning Series',
    'seasons': [
      {'id': 1, 'season_number': 1},
    ],
  });
  @override
  Future<SearchPage> search(String query, MediaType? type, int page) async =>
      SearchPage([show], 1, 1);
  @override
  Future<TitleData> title(MediaType type, int id) async => show;
  @override
  Future<SeasonData> season(int id, int number) async {
    if (fail) throw const ApiFailure('Offline');
    return SeasonData(showId, {
      'id': 1,
      'season_number': 1,
      'episodes': [episodeJson(episodeId, 1, air: air)],
    });
  }

  @override
  Future<TitleData?> lookup(
    MediaType type,
    Map<String, String> externalIds,
  ) async => match && externalIds['imdb_id'] == external ? show : null;
}

void main() {
  test('constructor configuration cannot bypass committed provider', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final modules = {
      'tvmaze': CatalogFixture('tvmaze', 42, 101),
      'tmdb': CatalogFixture('tmdb', 99, 9001),
    };
    final first = CatalogRouter(db: db, modules: modules, active: 'tvmaze');
    await first.initialize();
    final next = CatalogRouter(db: db, modules: modules, active: 'tmdb');
    await next.initialize();
    expect(next.active, 'tvmaze');
    expect((await next.search('show', null, 1)).results.single.sourceId, 42);
    expect(
      CatalogRouter.sameExternal(
        {'imdb_id': 'a', 'tvdb_id': '1'},
        {'imdb_id': 'a', 'tvdb_id': '2'},
      ),
      isFalse,
    );
  });
}
