import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/application/providers.dart';
import 'package:next_episode/domain/catalog_provider.dart';
import 'package:next_episode/domain/models.dart';

import 'fixtures.dart';

class DelayedApi extends FakeApi {
  final requests = <String, Completer<SearchPage>>{};
  @override
  Future<SearchPage> search(String query, MediaType? type, int page) =>
      (requests['$query:$page'] = Completer<SearchPage>()).future;
}

class PopularApi extends DelayedApi {
  int popularCalls = 0;
  @override
  Future<SearchPage> popular(int page) async {
    popularCalls++;
    return SearchPage([tv(), movie()], 1, 1);
  }
}

void main() {
  testWidgets('typing requires three characters and debounces; clearing restores popular titles', (tester) async {
    final api = PopularApi();
    final container = ProviderContainer(overrides: [apiProvider.overrideWithValue(api)]);
    final controller = container.read(searchProvider.notifier);
    await controller.search('', null);
    expect(container.read(searchProvider).results, hasLength(2));
    controller.queryChanged('ab');
    await tester.pump();
    expect(api.requests, isEmpty);
    controller.queryChanged('abc');
    await tester.pump(const Duration(milliseconds: 200));
    controller.queryChanged('abcd');
    await tester.pump(const Duration(milliseconds: 349));
    expect(api.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(api.requests.keys, ['abcd:1']);
    // Clearing also invalidates a request already in flight.
    controller.queryChanged('');
    await tester.pump();
    api.requests['abcd:1']!.complete(const SearchPage([], 1, 1));
    await tester.pump();
    expect(container.read(searchProvider).query, '');
    expect(container.read(searchProvider).results, hasLength(2));
    container.dispose();
  });
  test('a late response cannot replace a newer search', () async {
    final api = DelayedApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final controller = container.read(searchProvider.notifier);
    final first = controller.search('old', null);
    final second = controller.search('new', null);
    api.requests['new:1']!.complete(SearchPage([movie()], 1, 1));
    await second;
    api.requests['old:1']!.complete(SearchPage([tv()], 1, 1));
    await first;
    expect(container.read(searchProvider).query, 'new');
    expect(container.read(searchProvider).results.single.key, 'movie:10');
  });
  test(
    'pagination deduplicates by type/id and can recover after failure',
    () async {
      final api = DelayedApi();
      final container = ProviderContainer(
        overrides: [apiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchProvider.notifier);
      final first = controller.search('query', null);
      api.requests['query:1']!.complete(SearchPage([tv()], 1, 2));
      await first;
      final fail = controller.search('query', null, more: true);
      api.requests['query:2']!.completeError(const ApiFailure('Offline'));
      await fail;
      expect(container.read(searchProvider).results, hasLength(1));
      expect(container.read(searchProvider).page, 1);
      final retry = controller.search('query', null, more: true);
      api.requests['query:2']!.complete(SearchPage([tv(), movie()], 2, 2));
      await retry;
      expect(container.read(searchProvider).results, hasLength(2));
      expect(container.read(searchProvider).error, isNull);
    },
  );
}
