import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/home_layout_button.dart';
import 'package:saber/components/home/list_folders.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/preview_card.dart';
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
      expect(find.byKey(const ValueKey('ListNoteRowSubtitle')), findsWidgets);

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
      final subtitle = tester.widget<Text>(
        find.byKey(const ValueKey('ListNoteRowSubtitle')).first,
      );
      expect(subtitle.data, contains('·'));

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
  });
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
