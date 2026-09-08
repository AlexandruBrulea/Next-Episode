import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'application/providers.dart';
import 'data/database.dart';
import 'data/demo_source.dart';
import 'data/repositories.dart';
import 'data/catalog/content_configuration.dart';
import 'ui/home.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (const bool.fromEnvironment('DEMO')) {
      final db = AppDatabase.memory();
      final api = DemoSource();
      await SeriesRepository(api, db).load(api.demoSeries.id);
      await MoviesRepository(api, db).load(api.film.id);
      await db.add(api.demoSeries, DateTime.now());
      await db.add(api.film, DateTime.now());
      runApp(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            apiProvider.overrideWithValue(api),
          ],
          child: const NextEpisodeApp(),
        ),
      );
      return;
    }
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final db = AppDatabase.file(File('${directory.path}/next_episode.sqlite'));
    await db.library();
    final catalog = await initializeCatalog(db);
    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          apiProvider.overrideWithValue(catalog),
        ],
        child: const NextEpisodeApp(),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'The local database could not be opened. Restart the app and check available storage.',
            ),
          ),
        ),
      ),
    );
  }
}

class NextEpisodeApp extends StatelessWidget {
  const NextEpisodeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Next Episode',
    locale: const Locale('en', 'US'),
    debugShowCheckedModeBanner: false,
    theme: nextEpisodeTheme(),
    builder: (context, child) => AppBackdrop(child: child ?? const SizedBox()),
    home: const HomeScreen(),
  );
}
