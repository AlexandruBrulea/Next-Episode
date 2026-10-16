import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/domain/models.dart';
import 'package:next_episode/ui/common.dart';
import 'package:next_episode/ui/title_sections.dart';

void main() {
  for (final type in MediaType.values) {
    testWidgets(
      'viewing services use compact logos with accessible names for $type',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final services = List.generate(
          20,
          (i) => <String, dynamic>{
            'provider_name': 'Long streaming service $i Amazon Channel',
            'logo_path': '',
          },
        );
        final title = TitleData(type, {
          'id': 1,
          'name': 'Test show',
          'watch/providers': {
            'results': {
              'US': {
                'flatrate': services,
                'link': 'https://www.themoviedb.org/tv/1/watch',
              },
              'RO': {'flatrate': services},
            },
          },
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: 320, child: TitleInformation(title)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final service in services) {
          expect(find.text(service['provider_name'] as String), findsNothing);
          expect(
            find.byTooltip(service['provider_name'] as String),
            findsOneWidget,
          );
        }
        final logos = find.byWidgetPredicate(
          (w) => w is Poster && w.width == 48 && w.height == 48,
        );
        expect(logos, findsNWidgets(20));
        final logoWrap = find.ancestor(
          of: logos.first,
          matching: find.byType(Wrap),
        );
        // Five logos per row at 320px: four compact rows, independent of names.
        expect(tester.getSize(logoWrap).height, 228);
        expect(find.text('See viewing options'), findsOneWidget);
        expect(
          find.text('Availability data by JustWatch, via TMDB'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
