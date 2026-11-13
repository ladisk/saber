import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/home_layout_button.dart';
import 'package:saber/components/home/list_files.dart';
import 'package:saber/components/home/list_folders.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/home/syncing_button.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/sentry/_sentry_init_foss.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/home/browse.dart';
import 'package:saber/pages/home/home.dart';

import 'screenshot_goldens_test.dart' show setupDemoFiles;
import 'utils/test_mock_channel_handlers.dart';

void main() {
  group('HomeLayout codec', () {
    test('old stored values keep their meaning', () {
      const codec = HomeLayout.codec;
      expect(codec.decode(0), HomeLayout.masonryGrid);
      expect(codec.decode(1), HomeLayout.simpleGrid);
      expect(codec.decode(2), HomeLayout.list);
      for (final layout in HomeLayout.values) {
        expect(codec.decode(codec.encode(layout)), layout);
      }
    });
  });

  group('List home layout', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupMockPathProvider();
    disableSentryForTesting();
    FlavorConfig.setup();
    SyncingButton.debugForceButtonActive = true;
    stows.sentryConsent.value = .granted;

    setUpAll(() async {
      await FileManager.init(shouldWatchRootDirectory: false);
      await setupDemoFiles();
    });
    setUp(() {
      stows.homeLayout.value = .list;
      BrowsePage.overrideChildren = DirectoryChildren(
        const ['subfolder1', 'subfolder2'],
        const ['Golden ratio', 'Import PDFs'],
      );
    });
    tearDown(() {
      stows.homeLayout.value = .masonryGrid;
      stows.browseSortMetric.value = .nameAToZ;
      stows.listSortMetric.value = .modifiedDesc;
      BrowsePage.overrideChildren = null;
    });

    testWidgets('Browse shows folder and note rows', (tester) async {
      await tester.pumpWidget(const _HomeApp(subpage: 'browse', path: '/a'));
      await tester.pump();

      expect(find.byType(ListFolders), findsOneWidget);
      expect(find.byKey(const ValueKey('ListFolderRow..')), findsOneWidget);
      expect(find.byKey(const ValueKey('ListFolderRowNew')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ListFolderRowsubfolder1')),
        findsOneWidget,
      );
      expect(find.byType(PreviewCard), findsNWidgets(2));
      expect(find.byKey(const ValueKey('ListNoteRowModified')), findsWidgets);
      // Browse shows one folder, so no Folder column.
      expect(find.byKey(const ValueKey('ListNoteRowFolder')), findsNothing);
      expect(find.byKey(const ValueKey('ListTableHeadername')), findsOne);
      expect(find.byKey(const ValueKey('ListTableHeadermodified')), findsOne);
      expect(find.byKey(const ValueKey('ListTableHeaderfolder')), findsNothing);

      // Folder actions on long-press
      expect(find.byIcon(Icons.drive_file_move), findsNothing);
      await tester.longPress(find.text('subfolder1'));
      await tester.pump();
      expect(find.byIcon(Icons.drive_file_move), findsOneWidget);
    });

    testWidgets('Browse folder row tap opens the folder', (tester) async {
      await tester.pumpWidget(const _HomeApp(subpage: 'browse', path: '/a'));
      await tester.pump();
      await tester.tap(find.text('subfolder1'));
      await tester.pumpAndSettle();
      // Now two levels deep: the back row is still there.
      expect(find.byKey(const ValueKey('ListFolderRow..')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ListFolderRow..')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ListFolderRow..')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ListFolderRow..')), findsNothing);
    });

    testWidgets('long-press selects a note row', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(const _HomeApp(subpage: 'browse', path: '/a'));
      await tester.pump();

      expect(find.byType(MoveNoteButton), findsNothing);
      await tester.longPress(find.text('Golden ratio'));
      await tester.pump();
      expect(find.byType(MoveNoteButton), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // While selecting, tap toggles another row.
      await tester.tap(find.text('Import PDFs'));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });

    testWidgets('Recent shows note rows with folders', (tester) async {
      await tester.pumpWidget(const _HomeApp(subpage: 'recent'));
      await tester.pumpAndSettle();

      expect(find.byType(PreviewCard), findsWidgets);
      expect(find.byKey(const ValueKey('ListTableHeaderfolder')), findsOne);
      final folder = tester.widget<Text>(
        find.byKey(const ValueKey('ListNoteRowFolder')).first,
      );
      expect(folder.data, '/');

      await tester.longPress(find.byType(PreviewCard).first);
      await tester.pump();
      expect(find.byType(MoveNoteButton), findsOneWidget);
    });

    testWidgets('tap on a note row opens the editor', (tester) async {
      await tester.pumpWidget(const _HomeApp(subpage: 'recent'));
      await tester.pumpAndSettle();

      expect(find.byType(Editor), findsNothing);
      await tester.tap(find.byType(PreviewCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Editor), findsOneWidget);
    });

    testWidgets('layout dialog offers List', (tester) async {
      await tester.pumpWidget(const _HomeApp(subpage: 'recent'));
      await tester.pumpAndSettle();
      stows.homeLayout.value = .masonryGrid;
      await tester.pump();

      await tester.tap(find.byType(HomeLayoutButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(stows.homeLayout.value, HomeLayout.list);
    });

    testWidgets('Browse sorts by name, folders first', (tester) async {
      _tallView(tester);
      BrowsePage.overrideChildren = DirectoryChildren(
        const ['f10', 'F2'],
        const ['Week 10', 'week 2', 'Alpha'],
      );
      await tester.pumpWidget(const _HomeApp(subpage: 'browse', path: '/a'));
      await tester.pump();

      // Default: A to Z, natural and case-insensitive.
      expect(_order(tester, ['F2', 'f10', 'Alpha', 'week 2', 'Week 10']), true);
      expect(find.byKey(const ValueKey('ListTableHeaderArrow')), findsOne);

      await tester.tap(find.byKey(const ValueKey('ListTableHeadername')));
      await tester.pump();
      expect(stows.browseSortMetric.value, SortMetric.nameZToA);
      expect(_order(tester, ['f10', 'F2', 'Week 10', 'week 2', 'Alpha']), true);
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('ListTableHeaderArrow')))
            .icon,
        Icons.arrow_downward,
      );

      // Selecting still works on the sorted rows.
      await tester.longPress(find.text('week 2'));
      await tester.pump();
      expect(find.byType(MoveNoteButton), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Modified: folders go back to A to Z.
      await tester.tap(find.byKey(const ValueKey('ListTableHeadermodified')));
      await tester.pump();
      expect(stows.browseSortMetric.value, SortMetric.lastModifiedNewToOld);
      expect(_order(tester, ['F2', 'f10']), true);
    });

    testWidgets('Recent sorts and keeps the sort', (tester) async {
      final now = DateTime.now();
      FileManager.getFile('/Import PDFs${Editor.extension}')
          .setLastModifiedSync(now.add(const Duration(minutes: 2)));
      FileManager.getFile('/Golden ratio${Editor.extension}')
          .setLastModifiedSync(now.add(const Duration(minutes: 1)));
      FileManager.getFile('/Annotate images and diagrams${Editor.extension}')
          .setLastModifiedSync(now.subtract(const Duration(days: 400)));

      await tester.pumpWidget(const _HomeApp(subpage: 'recent'));
      await tester.pumpAndSettle();

      // Default: newest first.
      expect(_order(tester, ['Import PDFs', 'Golden ratio']), true);
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('ListTableHeaderArrow')))
            .icon,
        Icons.arrow_downward,
      );

      await tester.tap(find.byKey(const ValueKey('ListTableHeadermodified')));
      await tester.pumpAndSettle();
      expect(stows.listSortMetric.value, ListSort.modifiedAsc);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('ListNoteRowModified')).first,
            )
            .data,
        startsWith('${now.subtract(const Duration(days: 400)).year}-'),
      );

      await tester.tap(find.byKey(const ValueKey('ListTableHeadername')));
      await tester.pumpAndSettle();
      expect(stows.listSortMetric.value, ListSort.nameAsc);

      // A new page starts with the stored sort.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const _HomeApp(subpage: 'recent'));
      await tester.pumpAndSettle();
      expect(
        _order(tester, ['Annotate images and diagrams', 'CM Welcome Back']),
        true,
      );

      await tester.longPress(find.text('CM Welcome Back'));
      await tester.pump();
      expect(find.byType(MoveNoteButton), findsOneWidget);
    });
  });

  group('ListSort', () {
    test('natural, case-insensitive name order', () {
      final names = ['Week 10', 'week 2', 'Week 1', 'alpha', 'Beta', 'week 02'];
      names.sort(compareNatural);
      expect(names, [
        'alpha',
        'Beta',
        'Week 1',
        'week 2',
        'week 02',
        'Week 10',
      ]);
    });

    test('order by each column', () {
      final files = ['/b/Week 10', '/a/week 2', '/c/Alpha'];
      final times = {
        '/b/Week 10': DateTime(2026, 1, 3),
        '/a/week 2': DateTime(2026, 1, 1),
        '/c/Alpha': DateTime(2026, 1, 2),
      };
      List<String> sorted(ListSort sort) => [
        for (final i in sort.order(files, lastModified: (p) => times[p]!))
          files[i],
      ];
      expect(sorted(.nameAsc), ['/c/Alpha', '/a/week 2', '/b/Week 10']);
      expect(sorted(.nameDesc), ['/b/Week 10', '/a/week 2', '/c/Alpha']);
      expect(sorted(.folderAsc), ['/a/week 2', '/b/Week 10', '/c/Alpha']);
      expect(sorted(.modifiedDesc), ['/b/Week 10', '/c/Alpha', '/a/week 2']);
      expect(sorted(.modifiedAsc), ['/a/week 2', '/c/Alpha', '/b/Week 10']);
    });

    test('header clicks', () {
      expect(ListSort.modifiedDesc.clicked(.name), ListSort.nameAsc);
      expect(ListSort.nameAsc.clicked(.name), ListSort.nameDesc);
      expect(ListSort.nameAsc.clicked(.modified), ListSort.modifiedDesc);
      expect(ListSort.modifiedDesc.clicked(.modified), ListSort.modifiedAsc);
      for (final metric in SortMetric.values) {
        expect(ListSort.fromMetric(metric).metric, metric);
      }
    });
  });
}

/// A window tall enough to show every row of the Browse tests.
void _tallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(tester.view.reset);
}

/// Whether the texts are shown top to bottom in this order.
bool _order(WidgetTester tester, List<String> texts) {
  final ys = [for (final text in texts) tester.getTopLeft(find.text(text)).dy];
  for (var i = 1; i < ys.length; i++) {
    if (ys[i] <= ys[i - 1]) return false;
  }
  return true;
}

class _HomeApp extends StatelessWidget {
  const new({required this.subpage, this.path});
  final String subpage;
  final String? path;
  @override
  Widget build(BuildContext context) {
    final theme = SaberTheme.createThemeFromSeed(
      Colors.yellow,
      .light,
      .android,
    );
    final router = GoRouter(
      initialLocation: subpage == 'browse'
          ? HomeRoutes.browseFilePath(path ?? '')
          : HomeRoutes.routes[0].path,
      routes: [
        GoRoute(
          path: RoutePaths.home,
          builder: (context, state) => HomePage(
            subpage: state.pathParameters['subpage'] ?? HomePage.recentSubpage,
            path: state.uri.queryParameters['path'],
          ),
        ),
      ],
    );
    return TranslationProvider(
      child: ExplicitlyThemedApp(
        title: 'Saber',
        router: router,
        themeMode: ThemeMode.light,
        theme: theme,
        darkTheme: theme,
      ),
    );
  }
}
