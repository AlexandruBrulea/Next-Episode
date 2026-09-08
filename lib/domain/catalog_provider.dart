import 'models.dart';

class ApiFailure implements Exception {
  final String message;
  const ApiFailure(this.message);
  @override
  String toString() => message;
}

class SearchPage {
  final List<TitleData> results;
  final int page, totalPages;
  const SearchPage(this.results, this.page, this.totalPages);
}

class CatalogCapabilities {
  final bool movies, localizedText, paginatedSearch;
  const CatalogCapabilities({
    required this.movies,
    required this.localizedText,
    required this.paginatedSearch,
  });
}

/// Modules return the application's normalized model, never HTTP payloads to UI.
/// IDs at a module boundary are remote. CatalogRouter converts to local IDs.
abstract class CatalogProvider {
  String get id;
  String get label;
  CatalogCapabilities get capabilities;
  Future<SearchPage> search(String query, MediaType? type, int page);
  Future<SearchPage> popular(int page) async => const SearchPage([], 1, 1);
  Future<TitleData> title(MediaType type, int id);
  Future<SeasonData> season(int seriesId, int number);
  Future<SeriesBundle> series(int id) async {
    final data = await title(MediaType.tv, id);
    final seasons = <SeasonData>[];
    for (final summary in data.seasons) {
      seasons.add(await season(id, summary.number));
    }
    return SeriesBundle(data, seasons);
  }

  /// Exact external identity only. Never select a title by fuzzy name matching.
  Future<TitleData?> lookup(
    MediaType type,
    Map<String, String> externalIds,
  ) async => null;
  void close() {}
}
