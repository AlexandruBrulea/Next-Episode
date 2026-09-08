import 'dart:convert';
import 'dart:io';

import 'package:next_episode/data/catalog/admin_migration.dart';
import 'package:next_episode/data/catalog/catalog_router.dart';
import 'package:next_episode/data/catalog/tmdb_provider.dart';
import 'package:next_episode/data/catalog/tvmaze_provider.dart';
import 'package:next_episode/data/database.dart';

const usage = '''Administrative catalog migration (close the app first).
dart run tool/catalog_admin.dart prepare --database PATH --deployment ID --target tmdb --generation 2 [--matches matches.json] [--env .env]
dart run tool/catalog_admin.dart activate --database PATH --deployment ID
dart run tool/catalog_admin.dart report --database PATH --deployment ID
dart run tool/catalog_admin.dart rollback --database PATH --deployment ID --generation 3
Matches: {"tv:INTERNAL_ID": EXTERNAL_TITLE_ID}. Output is a JSON admin report.
Prepare is resumable; activate is atomic. Rollback preserves user actions since activation.
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    stdout.write(usage);
    return;
  }
  final options = <String, String>{};
  for (var i = 1; i < args.length; i += 2) {
    if (!args[i].startsWith('--') || i + 1 >= args.length) {
      stderr.write(usage);
      exitCode = 64;
      return;
    }
    options[args[i].substring(2)] = args[i + 1];
  }
  final path = options['database'], deployment = options['deployment'];
  if (path == null ||
      deployment == null ||
      !['prepare', 'activate', 'report', 'rollback'].contains(args.first)) {
    stderr.write(usage);
    exitCode = 64;
    return;
  }
  // Never create a fresh database because an administrator mistyped its path.
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('Database file does not exist.');
    exitCode = 66;
    return;
  }
  final env = <String, String>{...Platform.environment};
  final envFile = File(options['env'] ?? '.env');
  if (await envFile.exists()) {
    for (final line in await envFile.readAsLines()) {
      final trimmed = line.trim();
      final split = trimmed.indexOf('=');
      if (trimmed.startsWith('#') || split < 1) continue;
      var value = trimmed.substring(split + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      env[trimmed.substring(0, split).trim()] = value;
    }
  }
  final db = AppDatabase.file(file);
  final router = CatalogRouter(
    db: db,
    active: env['CONTENT_PROVIDER'] ?? env['CATALOG_PROVIDER'] ?? 'tvmaze',
    modules: {
      'tvmaze': TvmazeProvider(
        baseUrl: env['TVMAZE_BASE_URL'] ?? 'https://api.tvmaze.com',
      ),
      'tmdb': TmdbProvider(
        token: env['TMDB_TOKEN'] ?? '',
        baseUrl: env['TMDB_BASE_URL'] ?? 'https://api.themoviedb.org/3',
      ),
    },
  );
  try {
    final admin = AdminMigration(router);
    switch (args.first) {
      case 'prepare':
        final target = options['target'];
        final generation = int.tryParse(options['generation'] ?? '');
        if (target == null || generation == null || generation < 1) {
          throw const FormatException(
            'Target and positive generation required',
          );
        }
        final matches = options['matches'] == null
            ? <String, int>{}
            : Map<String, int>.from(
                jsonDecode(await File(options['matches']!).readAsString())
                    as Map,
              );
        await admin.prepare(
          deploymentId: deployment,
          target: target,
          generation: generation,
          approvedTitles: matches,
        );
      case 'activate':
        await admin.activate(deployment);
      case 'rollback':
        final generation = int.tryParse(options['generation'] ?? '');
        if (generation == null) {
          throw const FormatException('Generation required');
        }
        await admin.rollback(deployment, generation: generation);
      case 'report':
        break;
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ')
          .convert((await admin.report(deployment)).toJson()),
    );
  } catch (_) {
    // Provider exceptions can contain request headers; never print credentials.
    stderr.writeln(
      'Operation failed. Verify arguments, credentials, deployment status and generation. Previous committed data is retained.',
    );
    exitCode = 1;
  } finally {
    router.close();
    await db.close();
  }
}
