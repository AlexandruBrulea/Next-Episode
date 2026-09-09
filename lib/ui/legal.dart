import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'common.dart';
import '../application/app_contact.dart';

class TmdbCredits extends StatelessWidget {
  const TmdbCredits({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Next Episode', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('An independent, free app for your shows, movies and watch progress. No advertising or paid subscriptions.'),
      const SizedBox(height: 24),
      SvgPicture.asset('assets/credits/tmdb.svg', width: 120,
        semanticsLabel: 'The Movie Database (TMDB)', fit: BoxFit.contain),
      const SizedBox(height: 16),
      const Text('This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.'),
      const SourceCredit('The Movie Database (TMDB)', 'https://www.themoviedb.org'),
      const Text('Movie and television information and artwork are provided through TMDB. Artwork, names and trademarks belong to their respective rights holders.'),
      const SizedBox(height: 16),
      const SourceCredit('Watch availability data: JustWatch', 'https://www.justwatch.com'),
      const Text('Availability information is supplied by JustWatch through TMDB. Listed services are independent of Next Episode.'),
      const SizedBox(height: 12),
      TextButton(onPressed: () => showLicensePage(context: context,
        applicationName: 'Next Episode'), child: const Text('Open-source licenses')),
    ]),
  );
}

class LegalScreen extends StatefulWidget {
  final bool privacy;
  const LegalScreen({super.key, required this.privacy});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late final Future<Map<String, dynamic>> document = _load();

  Future<Map<String, dynamic>> _load() async {
    final data = jsonDecode(await rootBundle.loadString(
      'assets/legal/${widget.privacy ? 'privacy' : 'terms'}.json')) as Map<String, dynamic>;
    for (final section in data['sections'] as List) {
      section['body'] = (section['body'] as String)
          .replaceAll('{{SUPPORT_EMAIL}}', supportContactLabel);
      final links = section['links'] as List?;
      links?.removeWhere((link) => supportEmail.isEmpty &&
          (link['url'] as String).contains('{{SUPPORT_EMAIL}}'));
      for (final link in links ?? const []) {
        link['url'] = (link['url'] as String)
            .replaceAll('{{SUPPORT_EMAIL}}', supportEmail);
      }
    }
    return data;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.privacy ? 'Privacy Policy' : 'Terms of Use'),
      leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context))),
    body: FutureBuilder<Map<String, dynamic>>(
      future: document,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('This document could not be loaded. Please reopen it.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        return SelectionArea(child: ListView(primary: true,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40), children: [
            Text('Next Episode', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Last updated: ${data['updated']}', style: Theme.of(context).textTheme.bodySmall),
            for (final section in data['sections'] as List) ...[
              const SizedBox(height: 24),
              Text(section['title'] as String, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(section['body'] as String,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
              for (final link in (section['links'] as List? ?? const []))
                if ((link['url'] as String).startsWith('mailto:'))
                  TextButton(onPressed: () => perform(context, () async {
                    if (!await launchUrl(Uri.parse(link['url'] as String))) {
                      throw Exception('No email app available');
                    }
                  }), child: Text(link['label'] as String))
                else
                  SourceCredit(link['label'] as String, link['url'] as String),
            ],
          ]));
      },
    ),
  );
}
