import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../../domain/catalog_provider.dart';
import '../database.dart';
import 'admin_migration.dart';
import 'catalog_router.dart';
import 'tmdb_provider.dart';
import 'tvmaze_provider.dart';

class ContentRelease {
  final String provider, deploymentId, phase;
  final int generation;
  const ContentRelease(
    this.provider,
    this.deploymentId,
    this.generation, {
    this.phase = 'committed',
  });
  factory ContentRelease.fromJson(Json data) {
    if (data['provider'] is! String ||
        data.keys.any(
          (key) => ![
            'provider',
            'deploymentId',
            'generation',
            'phase',
          ].contains(key),
        ) ||
        data['deploymentId'] is! String ||
        string(data['deploymentId']).isEmpty ||
        data['generation'] is! int ||
        integer(data['generation']) < 1 ||
        !['prepared', 'committed'].contains(data['phase'])) {
      throw const FormatException('Invalid global content release');
    }
    return ContentRelease(
      data['provider'],
      data['deploymentId'],
      data['generation'],
      phase: data['phase'],
    );
  }
}

abstract class ContentConfigurationSource {
  Future<ContentRelease?> fetch();

  /// A backend can collect readiness before publishing its global commit.
  Future<void> ready(AdministrativeReport report) async {}
}

class FixedContentConfiguration extends ContentConfigurationSource {
  final ContentRelease release;
  FixedContentConfiguration(this.release);
  @override
  Future<ContentRelease> fetch() async => release;
}

class RemoteContentConfiguration extends ContentConfigurationSource {
  final Dio client;
  final Uri uri;
  RemoteContentConfiguration(String url, {Dio? dio})
    : uri = Uri.parse(url),
      client =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
            ),
          ) {
    if (uri.scheme != 'https') {
      throw ArgumentError('Administrative configuration requires HTTPS');
    }
  }
  @override
  Future<ContentRelease> fetch() async {
    final data = (await client.getUri<dynamic>(uri)).data;
    if (data is! Map) {
      throw const FormatException('Invalid global configuration');
    }
    // A single global manifest: no user/device targeting or random assignment.
    if (data.containsKey('users') || data.containsKey('percentage')) {
      throw const FormatException('Per-user provider rollout is not supported');
    }
    return ContentRelease.fromJson(Json.from(data));
  }
}

class ContentCoordinator {
  final CatalogRouter router;
  final ContentConfigurationSource source;
  bool _busy = false;
  ContentCoordinator(this.router, this.source);
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      await router.initialize();
      final release = await source.fetch();
      if (release == null) return;
      final state = await router.db
          .customSelect('SELECT * FROM content_state WHERE singleton=1')
          .getSingle();
      if (release.generation <= state.read<int>('generation')) return;
      final admin = AdminMigration(router);
      final report = await admin.prepare(
        deploymentId: release.deploymentId,
        target: release.provider,
        generation: release.generation,
      );
      if (report.status != 'prepared') return;
      await source.ready(report);
      if (release.phase == 'committed') {
        await admin.activate(release.deploymentId);
      }
    } catch (_) {
      // Operational detail stays in the admin plane; users keep their library.
      await router.db.administrativeConflict(
        'configuration',
        'Configuration or preparation failed; previous committed catalog retained.',
      );
    } finally {
      _busy = false;
    }
  }
}

const configuredProvider = String.fromEnvironment(
  'CONTENT_PROVIDER',
  defaultValue: String.fromEnvironment(
    'CATALOG_PROVIDER',
    defaultValue: 'tvmaze',
  ),
);
Map<String, CatalogProvider> configuredModules() => {
  'tvmaze': TvmazeProvider(
    baseUrl: const String.fromEnvironment(
      'TVMAZE_BASE_URL',
      defaultValue: 'https://api.tvmaze.com',
    ),
  ),
  'tmdb': TmdbProvider(
    token: const String.fromEnvironment('TMDB_TOKEN'),
    baseUrl: const String.fromEnvironment(
      'TMDB_BASE_URL',
      defaultValue: 'https://api.themoviedb.org/3',
    ),
  ),
};
Future<CatalogRouter> initializeCatalog(AppDatabase db) async {
  final modules = configuredModules();
  final router = CatalogRouter(
    db: db,
    modules: modules,
    active: modules.containsKey(configuredProvider)
        ? configuredProvider
        : 'tvmaze',
  );
  await router.initialize();
  const remoteUrl = String.fromEnvironment('CONTENT_CONFIG_URL');
  const generation = int.fromEnvironment('CONTENT_GENERATION', defaultValue: 1);
  try {
    final ContentConfigurationSource source = remoteUrl.isEmpty
        ? FixedContentConfiguration(
            const ContentRelease(
              configuredProvider,
              'configured:$generation:$configuredProvider',
              generation,
            ),
          )
        : RemoteContentConfiguration(remoteUrl);
    router.refreshConfiguration = ContentCoordinator(router, source).refresh;
  } catch (_) {
    await db.administrativeConflict(
      'configuration',
      'Invalid administrative configuration; previous catalog retained.',
    );
  }
  return router;
}
