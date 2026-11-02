import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/file_manager/note_search.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/pages/home/browse.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  group('NoteSearch', () {
    const files = [
      '/Predavanja/Tehniška mehanika 2/Uvod',
      '/Predavanja/Dinamika strojev',
      '/Zapiski/Sestanek dinamika',
      '/Čas in prostor',
    ];

    test('matches titles ignoring case and diacritics', () {
      expect(NoteSearch.search(files, 'cas'), ['/Čas in prostor']);
      expect(NoteSearch.search(files, 'ČAS'), ['/Čas in prostor']);
    });

    test('matches only the title, not the folder', () {
      expect(NoteSearch.search(files, 'predavanja'), isEmpty);
      expect(NoteSearch.search(files, 'mehanika'), isEmpty);
    });

    test('needs every word, in any order', () {
      expect(NoteSearch.search(files, 'strojev dinamika'), [
        '/Predavanja/Dinamika strojev',
      ]);
    });

    test('keeps the order of the notes it is given', () {
      expect(NoteSearch.search(files.reversed, 'dinamika'), [
        '/Zapiski/Sestanek dinamika',
        '/Predavanja/Dinamika strojev',
      ]);
    });

    test('folder under the title', () {
      expect(
        PreviewCard.folderOf('/Predavanja/Dinamika/Uvod'),
        'Predavanja/Dinamika',
      );
      expect(PreviewCard.folderOf('/Čas in prostor'), '/');
    });

    test('finds nothing for an empty query', () {
      expect(NoteSearch.search(files, '  '), isEmpty);
    });

    test('sorts the newest edits first', () {
      final dates = {
        for (var i = 0; i < files.length; i++) files[i]: DateTime(2026, 1, i),
      };
      expect(
        NoteSearch.newestFirst(files, (f) => dates[f]!),
        files.reversed.toList(),
      );
    });
  });

  group('BrowsePage search and latest', () {
    FlavorConfig.setup();
    setupMockPathProvider();

    setUp(() async {
      await FileManager.init(shouldWatchRootDirectory: false);
      BrowsePage.overrideChildren = DirectoryChildren(const ['Mapa'], const []);
      BrowsePage.overrideAllFiles = const [
        '/Mapa/Vaje 1 mapa',
        '/Mapa/Izpit mapa',
        '/Drugo',
      ];
      BrowsePage.overrideLastModified = (f) => switch (f) {
        '/Drugo' => DateTime(2026, 3),
        '/Mapa/Izpit mapa' => DateTime(2026, 2),
        _ => DateTime(2026, 1),
      };
    });
    tearDown(() {
      BrowsePage.overrideChildren = null;
      BrowsePage.overrideAllFiles = null;
      BrowsePage.overrideLastModified = null;
    });

    Future<void> pumpBrowse(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SaberTheme.createThemeFromSeed(
            Colors.yellow,
            .light,
            .android,
          ),
          home: const BrowsePage(),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> shownNotes(WidgetTester tester) => [
      for (final card in tester.widgetList<PreviewCard>(
        find.byType(PreviewCard),
      ))
        card.filePath,
    ];

    testWidgets('search finds notes in subfolders by title', (tester) async {
      await pumpBrowse(tester);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('browseSearchField')),
        'mapa',
      );
      await tester.pumpAndSettle();
      // newest first
      expect(shownNotes(tester), ['/Mapa/Izpit mapa', '/Mapa/Vaje 1 mapa']);

      await tester.enterText(
        find.byKey(const ValueKey('browseSearchField')),
        'vaje',
      );
      await tester.pumpAndSettle();
      expect(shownNotes(tester), ['/Mapa/Vaje 1 mapa']);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('PreviewCardFolder')))
            .data,
        'Mapa',
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('browseSearchField')), findsNothing);
      expect(find.text('Mapa'), findsOneWidget);
    });

    testWidgets('latest lists recently edited notes', (tester) async {
      await pumpBrowse(tester);
      await tester.tap(find.byIcon(Icons.history).first);
      await tester.pumpAndSettle();
      expect(shownNotes(tester), [
        '/Drugo',
        '/Mapa/Izpit mapa',
        '/Mapa/Vaje 1 mapa',
      ]);
    });
  });
}
