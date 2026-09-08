import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'common.dart';

class CastCards extends StatelessWidget {
  final List<Json> cast;
  const CastCards(this.cast, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final width = box.maxWidth < 420 ? box.maxWidth : (box.maxWidth - 16) / 2;
    return Wrap(spacing: 16, runSpacing: 18, children: [
      for (final person in cast.take(12)) SizedBox(width: width, child: Row(children: [
        ClipOval(child: Poster(imageUrl(person['profile_path']), width: 54, height: 54)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(string(person['name']), style: Theme.of(context).textTheme.titleSmall),
          Text(string(person['character']), style: Theme.of(context).textTheme.bodySmall),
        ])),
      ])),
      if (cast.isEmpty) const Text('Cast information is not available yet.'),
    ]);
  });
}

class TitleInformation extends StatelessWidget {
  final TitleData title;
  const TitleInformation(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final videos = title.raw['videos'];
    final trailer = objects(videos is Map ? videos['results'] : null)
        .where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer' && string(v['key']).isNotEmpty).firstOrNull;
    final providers = title.raw['watch/providers'];
    final regions = providers is Map && providers['results'] is Map ? Json.from(providers['results']) : <String, dynamic>{};
    final services = <String, Json>{};
    var viewingUrl = '';
    for (final availability in regions.values.whereType<Map>()) {
      final link = string(availability['link']);
      if (viewingUrl.isEmpty && link.startsWith('https://')) viewingUrl = link;
      for (final category in ['flatrate', 'free', 'ads', 'rent', 'buy']) {
        for (final service in objects(availability[category])) {
          final name = string(service['provider_name']).trim();
          if (name.isEmpty) continue;
          services.putIfAbsent(name.toLowerCase(), () => service);
        }
      }
    }
    final availableServices = services.values.toList()
      ..sort((a, b) => string(a['provider_name']).toLowerCase()
          .compareTo(string(b['provider_name']).toLowerCase()));
    Widget heading(String text) => Padding(padding: const EdgeInsets.only(top: 28, bottom: 16), child: Text(text, style: Theme.of(context).textTheme.titleLarge));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('Network'),
      Text(title.networks.isEmpty ? 'Not available' : title.networks.join(', ')),
      heading('Created by'),
      Text(objects(title.raw['created_by']).isEmpty ? 'Not available' : objects(title.raw['created_by']).map((p) => string(p['name'])).join(', ')),
      heading('Top cast'),
      CastCards(title.cast),
      heading('Trailer'),
      if (trailer == null) const Text('No trailer available from this provider.')
      else Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Poster('https://i.ytimg.com/vi/${Uri.encodeComponent(string(trailer['key']))}/hqdefault.jpg', width: double.infinity, height: 220),
        SourceCredit('▶ Watch trailer', 'https://www.youtube.com/watch?v=${Uri.encodeComponent(string(trailer['key']))}'),
      ]),
      heading('Where to watch'),
      if (availableServices.isEmpty) const Text('No viewing options available yet.'),
          Wrap(spacing: 16, runSpacing: 12, children: [for (final provider in availableServices)
            SizedBox(width: 100, child: Column(children: [
              Poster(imageUrl(provider['logo_path']), width: 48, height: 48),
              const SizedBox(height: 6), Text(string(provider['provider_name']), textAlign: TextAlign.center),
            ])),
          ]),
      if (availableServices.isNotEmpty) ...[
        if (viewingUrl.isNotEmpty) SourceCredit('See viewing options', viewingUrl),
        const Text('Streaming availability powered by JustWatch.'),
      ],
      const SizedBox(height: 24),
      InfoLine('First aired', dateLabel(title.releaseDate)),
      InfoLine('Last aired', dateLabel(title.lastAirDate)),
      InfoLine('Countries', title.countries.join(', ')),
      InfoLine('Typical runtime', title.runtimes.isEmpty ? 'Not available' : '${title.runtimes.join(', ')} min'),
      InfoLine('Next announced episode', title.nextEpisode == null ? 'Not announced' : '${title.nextEpisode!.code} · ${dateLabel(title.nextEpisode!.airDate)}'),
      InfoLine('Original language', title.originalLanguage),
    ]);
  }
}
