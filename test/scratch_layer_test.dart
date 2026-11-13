import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/save_indicator.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/scratch_layer.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    setupMockWindowManager();
    setupMockPrinting();
    await FileManager.init();
  });

  Future<EditorState> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(child: MaterialApp(home: Editor())),
    );
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    return state;
  }

  /// Draws a short horizontal stroke at [y] on page [pageIndex].
  void draw(EditorState state, double y, {int pageIndex = 0, Pen? pen}) {
    pen ??= Pen.currentPen;
    state.currentTool = pen;
    state.dragPageIndex = pageIndex;
    final page = state.coreInfo.pages[pageIndex];
    pen.onDragStart(Offset(100, y), page, pageIndex, null);
    for (var x = 110.0; x <= 200; x += 10) {
      pen.onDragUpdate(Offset(x, y), null);
    }
    state.onDrawEnd(.new());
  }

  /// Drags the eraser across x = 150 on page 0, through every stroke.
  Future<void> erase(WidgetTester tester, EditorState state) async {
    state.currentTool = Eraser(size: 20);
    state.dragPageIndex = 0;
    final box = state.coreInfo.pages[0].renderBox!;
    state.onDrawStart(
      .new(focalPoint: box.localToGlobal(const Offset(150, 0))),
    );
    for (var y = 10.0; y <= 400; y += 10) {
      state.onDrawUpdate(.new(focalPoint: box.localToGlobal(Offset(150, y))));
    }
    state.onDrawEnd(.new());
    await tester.pump();
  }

  SavingState savingState(WidgetTester tester) => tester
      .widget<SaveIndicator>(find.byType(SaveIndicator))
      .savingState
      .value;

  testWidgets('scratch strokes are not on the page or saved', (tester) async {
    final state = await openEditor(tester);
    final page = state.coreInfo.pages[0];

    state.setScratchMode(true);
    draw(state, 100);
    draw(state, 150, pen: Highlighter.currentHighlighter);
    await tester.pump();

    expect(page.strokes, isEmpty);
    expect(ScratchLayer.strokesOf(page), hasLength(2));
    expect(state.hasScratchStrokes, isTrue);
    expect(state.history.isCurrentStateSaved, isTrue);
    expect(savingState(tester), SavingState.saved);

    // a page stroke is saved, the scratch strokes still aren't
    state.setScratchMode(false);
    draw(state, 300);
    expect(page.strokes, hasLength(1));
    expect(savingState(tester), SavingState.waitingToSave);

    final (bson, _) = state.coreInfo.saveToBinary(currentPageIndex: null);
    final reloaded = await EditorCoreInfo.loadFromFileContents(
      bsonBytes: bson,
      path: state.coreInfo.filePath,
      onlyFirstPage: false,
    );
    expect(reloaded.pages[0].strokes, hasLength(1));
    expect(ScratchLayer.hasStrokes(reloaded.pages[0]), isFalse);
    final (json, _) = state.coreInfo.toJson();
    expect((json['z'] as List).first['s'], hasLength(1));
  });

  testWidgets('the eraser erases only scratch strokes in scratch mode', (
    tester,
  ) async {
    final state = await openEditor(tester);
    final page = state.coreInfo.pages[0];
    draw(state, 100);
    state.setScratchMode(true);
    draw(state, 200);
    state.cancelAutosaveAndMarkSaved();
    await tester.pump();

    await erase(tester, state);
    expect(page.strokes, hasLength(1));
    expect(ScratchLayer.strokesOf(page), isEmpty);
    expect(state.history.isCurrentStateSaved, isTrue);
    expect(savingState(tester), SavingState.saved);

    // and undoing the erase brings the scratch stroke back
    state.undo();
    expect(ScratchLayer.strokesOf(page), hasLength(1));
    expect(page.strokes, hasLength(1));
  });

  testWidgets('the eraser leaves scratch strokes outside scratch mode', (
    tester,
  ) async {
    final state = await openEditor(tester);
    final page = state.coreInfo.pages[0];
    state.setScratchMode(true);
    draw(state, 100);
    state.setScratchMode(false);
    draw(state, 200);
    await tester.pump();

    await erase(tester, state);
    expect(page.strokes, isEmpty);
    expect(ScratchLayer.strokesOf(page), hasLength(1));
  });

  testWidgets('undo and redo scratch strokes without saving', (tester) async {
    final state = await openEditor(tester);
    final page = state.coreInfo.pages[0];
    draw(state, 100);
    state.cancelAutosaveAndMarkSaved();

    state.setScratchMode(true);
    draw(state, 200);
    state.undo();
    await tester.pump();
    expect(ScratchLayer.strokesOf(page), isEmpty);
    expect(page.strokes, hasLength(1));
    expect(savingState(tester), SavingState.saved);

    state.redo();
    await tester.pump();
    expect(ScratchLayer.strokesOf(page), hasLength(1));
    expect(savingState(tester), SavingState.saved);

    // the next undo after the scratch stroke undoes the page stroke
    state.undo();
    state.undo();
    await tester.pump();
    expect(page.strokes, isEmpty);
    expect(savingState(tester), SavingState.waitingToSave);
  });

  testWidgets('clear removes scratch strokes on all pages', (tester) async {
    final state = await openEditor(tester);
    state.setScratchMode(true);
    draw(state, 100);
    // drawing on the last page adds an empty page after it
    state.setScratchMode(false);
    draw(state, 300);
    state.setScratchMode(true);
    draw(state, 100, pageIndex: 1);
    await tester.pump();
    expect(state.coreInfo.pages.where(ScratchLayer.hasStrokes), hasLength(2));

    state.clearScratch();
    await tester.pump();
    expect(state.hasScratchStrokes, isFalse);
    expect(state.coreInfo.pages[0].strokes, hasLength(1));

    // clearing forgot the scratch history: undo goes to the page stroke
    state.undo();
    expect(state.coreInfo.pages[0].strokes, isEmpty);
    expect(state.hasScratchStrokes, isFalse);
  });

  testWidgets('the palette toggles scratch mode and clears', (tester) async {
    final state = await openEditor(tester);
    // the palette shows once the note has loaded
    await tester.pumpAndSettle();
    expect(state.scratch.isOn, isFalse);

    await tester.tap(find.byTooltip('Scratch layer'));
    await tester.pump();
    expect(state.scratch.isOn, isTrue);

    // nothing to clear yet
    await tester.tap(find.byTooltip('Clear scratch'));
    draw(state, 100);
    await tester.pump();
    expect(state.hasScratchStrokes, isTrue);

    // turning the layer off hides its strokes but keeps them
    await tester.tap(
      find.byTooltip('Scratch layer: on (drawing is not saved)'),
    );
    await tester.pump();
    expect(state.scratch.isOn, isFalse);
    expect(ScratchLayer.shown, isFalse);
    expect(state.hasScratchStrokes, isTrue);

    await tester.tap(find.byTooltip('Scratch layer: hidden'));
    await tester.pump();
    expect(ScratchLayer.shown, isTrue);
    expect(state.hasScratchStrokes, isTrue);

    await tester.tap(find.byTooltip('Clear scratch'));
    await tester.pump();
    expect(state.hasScratchStrokes, isFalse);
    // clearing also leaves the layer, so notes go on the page again
    expect(state.scratch.isOn, isFalse);
  });
}
