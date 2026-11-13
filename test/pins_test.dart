import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/pins/pin_layer.dart';
import 'package:saber/components/canvas/pins/pin_view.dart';
import 'package:saber/components/canvas/save_indicator.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pin.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    FlavorConfig.setup();
    setupMockPathProvider();
    setupMockWindowManager();
    setupMockPrinting();
  });

  Stroke stroke(Offset point, {int pageIndex = 0}) => Stroke(
    color: Stroke.defaultColor,
    pressureEnabled: Stroke.defaultPressureEnabled,
    options: StrokeOptions(size: 5),
    pageIndex: pageIndex,
    page: const HasSize(EditorPage.defaultSize),
    toolId: .ballpointPen,
  )..addPoint(point);

  EditorCoreInfo note(int pages) =>
      EditorCoreInfo(filePath: '/pins')
        ..pages.addAll([for (var i = 0; i < pages; ++i) EditorPage()]);

  NotePin pinOn(EditorPage page) => NotePin(
    page: page,
    rect: const Rect.fromLTWH(10, 20, 300, 150),
    x: 0.6,
    y: 0.1,
    width: 0.3,
  );

  Future<EditorCoreInfo> reload(EditorCoreInfo coreInfo) {
    final (bson, _) = coreInfo.saveToBinary(currentPageIndex: null);
    return EditorCoreInfo.loadFromFileContents(
      bsonBytes: bson,
      path: coreInfo.filePath,
      onlyFirstPage: false,
    );
  }

  group('pins in the note file', () {
    test('a note without pins is saved as before', () {
      final (json, _) = note(2).toJson();
      expect(json.keys, ['v', 'ni', 'b', 'p', 'l', 'lt', 'z', 'c']);
    });

    test('pins survive saving and loading', () async {
      final coreInfo = note(3);
      coreInfo.ladiskPins.add(pinOn(coreInfo.pages[1]));

      final (json, _) = coreInfo.toJson();
      expect(json[NotePin.jsonKey], [
        {
          'page': 1,
          'rect': [10.0, 20.0, 300.0, 150.0],
          'x': 0.6,
          'y': 0.1,
          'w': 0.3,
        },
      ]);

      final loaded = await reload(coreInfo);
      expect(loaded.ladiskPins, hasLength(1));
      final pin = loaded.ladiskPins.single;
      expect(pin.page, same(loaded.pages[1]));
      expect(pin.rect, const Rect.fromLTWH(10, 20, 300, 150));
      expect((pin.x, pin.y, pin.width), (0.6, 0.1, 0.3));
    });

    test('the collapsed state is saved only when set', () async {
      final coreInfo = note(1);
      final pin = pinOn(coreInfo.pages.first);
      coreInfo.ladiskPins.add(pin);
      expect(pin.toJson(0).containsKey('c'), isFalse);

      pin.collapsed = true;
      final loaded = await reload(coreInfo);
      expect(loaded.ladiskPins.single.collapsed, isTrue);

      // a pin saved before collapsing existed loads expanded
      final old = NotePin.fromJson({
        'page': 0,
        'rect': [0, 0, 10, 10],
        'x': 0,
        'y': 0,
        'w': 0.3,
      }, coreInfo.pages);
      expect(old!.collapsed, isFalse);
    });

    test('an old note loads without pins', () async {
      final coreInfo = note(1);
      final loaded = await reload(coreInfo);
      expect(loaded.ladiskPins, isEmpty);
    });

    test('malformed pins and pins past the last page are skipped', () {
      final pages = [EditorPage(), EditorPage()];
      final pins = NotePin.listFromJson([
        {
          'page': 5,
          'rect': [0, 0, 10, 10],
          'x': 0,
          'y': 0,
          'w': 0.3,
        },
        {
          'page': 0,
          'rect': [0, 0, 10],
          'x': 0,
          'y': 0,
          'w': 0.3,
        },
        {
          'page': 0,
          'rect': [0, 0, 0, 10],
          'x': 0,
          'y': 0,
          'w': 0.3,
        },
        'nonsense',
        {
          'page': Int64(1),
          'rect': [1, 2, 3, 4],
          'x': 0,
          'y': 1,
          'w': 1,
        },
      ], pages);
      expect(pins, hasLength(1));
      expect(pins.single.page, same(pages[1]));
      expect(pins.single.rect, const Rect.fromLTWH(1, 2, 3, 4));
      expect(NotePin.listFromJson(null, pages), isEmpty);
    });
  });

  group('pins follow page edits', () {
    test('pages inserted or deleted before the pinned page', () {
      final coreInfo = note(3);
      final page = coreInfo.pages[1];
      coreInfo.ladiskPins.add(pinOn(page));
      int savedIndex() =>
          (coreInfo.toJson().$1[NotePin.jsonKey] as List).single['page'] as int;

      coreInfo.pages.insert(0, EditorPage());
      expect(savedIndex(), 2);
      coreInfo.pages.removeAt(0);
      coreInfo.pages.removeAt(0);
      expect(savedIndex(), 0);
      // moved to the end
      coreInfo.pages
        ..remove(page)
        ..add(page);
      expect(savedIndex(), 1);
    });

    test('a deleted page drops its pins', () async {
      final coreInfo = note(3);
      final page = coreInfo.pages[1];
      coreInfo.ladiskPins.addAll([pinOn(page), pinOn(coreInfo.pages[2])]);

      coreInfo.pages.removeAt(1);
      expect(coreInfo.visibleLadiskPins.map((pin) => pin.page), [
        coreInfo.pages[1],
      ]);
      final loaded = await reload(coreInfo);
      expect(loaded.ladiskPins, hasLength(1));
      expect(loaded.ladiskPins.single.page, same(loaded.pages[1]));

      // the last pin's page is deleted too: the note has no pins left
      coreInfo.pages.removeAt(1);
      expect(coreInfo.toJson().$1.containsKey(NotePin.jsonKey), isFalse);
    });
  });

  test('a pin covers the selected items plus padding, inside the page', () {
    final page = EditorPage();
    final selection = SelectResult(
      pageIndex: 0,
      pageIndexStart: 0,
      strokes: [stroke(const Offset(5, 100)), stroke(const Offset(200, 300))],
      images: const [],
      path: Path(),
    );
    final pin = NotePin.forSelection(selection, page)!;
    expect(pin.rect.left, 0, reason: 'clipped to the page');
    expect(pin.rect.top, lessThan(100 - NotePin.padding));
    expect(pin.rect.top, greaterThan(100 - NotePin.padding - 10));
    expect(pin.rect.right, greaterThan(200 + NotePin.padding));
    expect(pin.rect.bottom, greaterThan(300 + NotePin.padding));
    expect(pin.rect.bottom, lessThan(300 + NotePin.padding + 10));
    expect(pin.page, same(page));
  });

  test('a window stays on screen and keeps the aspect ratio', () {
    final pin = pinOn(EditorPage())
      ..x = 0.95
      ..y = -1
      ..width = 3;
    const area = Size(800, 600);
    final frame = PinWindow.frameOf(pin, area);
    expect(frame.left, greaterThanOrEqualTo(0));
    expect(frame.top, 0);
    expect(frame.right, lessThanOrEqualTo(area.width));
    expect(frame.bottom, lessThanOrEqualTo(area.height));
    expect(
      (frame.height - PinWindow.stripHeight) / frame.width,
      closeTo(pin.rect.height / pin.rect.width, 1e-9),
    );
  });

  testWidgets('pinning a selection shows a window that is saved', (
    tester,
  ) async {
    FlavorConfig.setup();
    setupMockPathProvider();
    FileManager.documentsDirectory =
        '$tmpDir/pins/${FileManager.appRootDirectoryPrefix}';
    const path = '/pinned';
    // the tool palette would cover the window in this small test screen
    stows.toolPaletteVisible.value = false;
    addTearDown(() => stows.toolPaletteVisible.value = true);
    await tester.runAsync(
      () => FileManager.deleteFile(path + Editor.extension),
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: Editor(path: path)),
      ),
    );
    await tester.pumpAndSettle();
    var state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(() => state.cancelAutosaveAndMarkSaved());

    final page = state.coreInfo.pages.first;
    final original = stroke(const Offset(100, 120));
    page.strokes.add(original);
    final select = Select.currentSelect
      ..selectResult = SelectResult(
        pageIndex: 0,
        pageIndexStart: 0,
        strokes: [original],
        images: const [],
        path: Path(),
      )
      ..doneSelecting = true;
    state.setTool(select);
    state.cancelAutosaveAndMarkSaved();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Pin (keep this area in view)'));
    await tester.pump();
    expect(find.byType(PinWindow), findsOneWidget);
    expect(state.coreInfo.ladiskPins.single.page, same(page));
    // the window draws the page with the editor's own canvas,
    // redrawn whenever the page's strokes change
    final pinCanvas = tester.widget<InnerCanvas>(
      find.descendant(
        of: find.byType(PinWindow),
        matching: find.byType(InnerCanvas),
      ),
    );
    expect(pinCanvas.redrawPageListenable, same(page));
    expect(pinCanvas.coreInfo.pages.single.strokes, same(page.strokes));
    SavingState savingState() => tester
        .widget<SaveIndicator>(find.byType(SaveIndicator))
        .savingState
        .value;
    expect(savingState(), SavingState.waitingToSave);

    // dragging the window moves it, and doesn't draw on the page
    state.setTool(Pen.currentPen);
    await tester.pumpAndSettle();
    state.cancelAutosaveAndMarkSaved();
    final strokesBefore = page.strokes.length;
    final pin = state.coreInfo.ladiskPins.single;
    final xBefore = pin.x;
    final yBefore = pin.y;
    await tester.drag(
      find.descendant(
        of: find.byType(PinWindow),
        matching: find.byIcon(Icons.drag_indicator),
      ),
      const Offset(-100, 80),
    );
    await tester.pump();
    expect(pin.x, lessThan(xBefore));
    expect(pin.y, greaterThan(yBefore));
    expect(page.strokes, hasLength(strokesBefore));
    expect(savingState(), SavingState.waitingToSave);

    // dragging from the middle moves it too
    final xMid = pin.x;
    final yMid = pin.y;
    await tester.dragFrom(
      tester.getCenter(find.byType(PinWindow)),
      const Offset(20, -10),
    );
    await tester.pump();
    expect(pin.x, greaterThan(xMid));
    expect(pin.y, lessThan(yMid));
    expect(page.strokes, hasLength(strokesBefore));

    // the corner handle resizes instead of moving
    final widthBefore = pin.width;
    final xCorner = pin.x;
    final yCorner = pin.y;
    final corner =
        tester.getBottomRight(find.byType(PinWindow)) - const Offset(14, 14);
    final gesture = await tester.startGesture(corner);
    await gesture.moveBy(const Offset(-30, -30));
    await gesture.moveBy(const Offset(-20, -20));
    await gesture.up();
    await tester.pump();
    expect(pin.width, lessThan(widthBefore));
    expect((pin.x, pin.y), (xCorner, yCorner));

    // collapsing leaves a small tab at the same place; a tap expands it
    final frameBefore = tester.getRect(find.byType(PinWindow));
    state.cancelAutosaveAndMarkSaved();
    await tester.tap(find.byTooltip('Collapse pin'));
    await tester.pump();
    expect(pin.collapsed, isTrue);
    expect(find.byType(PinView), findsNothing);
    expect(tester.getRect(find.byType(PinWindow)).topLeft, frameBefore.topLeft);
    expect(tester.getSize(find.byType(PinWindow)), const Size(40, 40));
    expect(savingState(), SavingState.waitingToSave);

    // the tab can be dragged
    final xTab = pin.x;
    await tester.drag(find.byType(PinWindow), const Offset(-30, 0));
    await tester.pump();
    expect(pin.x, lessThan(xTab));
    expect(pin.collapsed, isTrue);
    final tabTopLeft = tester.getRect(find.byType(PinWindow)).topLeft;

    await tester.tap(find.byType(PinWindow));
    await tester.pump();
    expect(pin.collapsed, isFalse);
    expect(find.byType(PinView), findsOneWidget);
    final expanded = tester.getRect(find.byType(PinWindow));
    expect(expanded.topLeft, tabTopLeft);
    expect(expanded.width, closeTo(frameBefore.width, 1e-6));
    expect(expanded.height, closeTo(frameBefore.height, 1e-6));

    // writing on the window doesn't write on the page beneath
    // (the view itself ignores touches, the window takes them)
    await tester.drag(
      find.byType(PinView),
      const Offset(30, 20),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(page.strokes, hasLength(strokesBefore));

    // reopen the note: the pin is back
    final (bson, _) = state.coreInfo.saveToBinary(currentPageIndex: 0);
    await tester.runAsync(
      () => FileManager.writeFile(
        path + Editor.extension,
        bson,
        awaitWrite: true,
        alsoUpload: false,
      ),
    );
    state.cancelAutosaveAndMarkSaved();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: Editor(path: path)),
      ),
    );
    state = tester.state<EditorState>(find.byType(Editor));
    // wait for the file to load
    for (var i = 0; i < 50 && state.coreInfo.filePath != path; ++i) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(state.coreInfo.ladiskPins, hasLength(1));
    expect(state.coreInfo.ladiskPins.single.x, closeTo(pin.x, 1e-9));
    expect(find.byType(PinWindow), findsOneWidget);

    // closing removes it
    await tester.tap(find.byTooltip('Close pin'));
    await tester.pump();
    expect(find.byType(PinWindow), findsNothing);
    expect(state.coreInfo.ladiskPins, isEmpty);
    expect(savingState(), SavingState.waitingToSave);
  });
}
