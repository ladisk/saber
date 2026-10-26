import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/selection_clipboard.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  setUp(SelectionClipboard.clear);

  Stroke stroke(Offset point, {int pageIndex = 0}) => Stroke(
    color: Stroke.defaultColor,
    pressureEnabled: Stroke.defaultPressureEnabled,
    options: StrokeOptions(size: 5),
    pageIndex: pageIndex,
    page: const HasSize(EditorPage.defaultSize),
    toolId: .ballpointPen,
  )..addPoint(point);

  Future<PngEditorImage> image(AssetCache assetCache) async => PngEditorImage(
    id: 0,
    extension: '.png',
    imageProvider: MemoryImage(
      await File('assets/icon/icon.png').readAsBytes(),
    ),
    pageIndex: 0,
    pageSize: EditorPage.defaultSize,
    onMoveImage: null,
    onDeleteImage: null,
    onMiscChange: null,
    assetCache: assetCache,
  )..dstRect = const Rect.fromLTWH(10, 20, 30, 40);

  test('pastes into another note and page unmoved, with image bytes', () async {
    final assetCache = AssetCache();
    final png = await image(assetCache);
    await SelectionClipboard.copy(
      SelectResult(
        pageIndex: 0,
        pageIndexStart: 0,
        strokes: [stroke(const Offset(50, 60))],
        images: [png],
        path: Path()..addRect(const Rect.fromLTWH(0, 0, 100, 100)),
      ),
      filePath: '/a',
    );
    expect(SelectionClipboard.isEmpty, isFalse);

    final pasted = SelectionClipboard.paste(
      filePath: '/b',
      pageIndex: 2,
      assetCache: AssetCache(),
    );
    expect(pasted.pageIndex, 2);
    expect(pasted.strokes.single.pageIndex, 2);
    expect(pasted.strokes.single.points.first.x, 50);
    final pastedImage = pasted.images.single as PngEditorImage;
    expect(pastedImage.pageIndex, 2);
    expect(pastedImage.dstRect, png.dstRect);
    expect(
      (pastedImage.imageProvider as MemoryImage).bytes,
      (png.imageProvider as MemoryImage).bytes,
    );
  });

  test('each paste onto the source page moves further', () async {
    await SelectionClipboard.copy(
      SelectResult(
        pageIndex: 0,
        pageIndexStart: 0,
        strokes: [stroke(const Offset(50, 60))],
        images: const [],
        path: Path(),
      ),
      filePath: '/a',
    );
    double pastedX() => SelectionClipboard.paste(
      filePath: '/a',
      pageIndex: 0,
      assetCache: AssetCache(),
    ).strokes.single.points.first.x;

    expect(pastedX(), 50 + SelectionClipboard.pasteOffset.dx);
    expect(pastedX(), 50 + 2 * SelectionClipboard.pasteOffset.dx);
  });

  testWidgets('cut and paste in the editor', (tester) async {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/selectionClipboard/${FileManager.appRootDirectoryPrefix}';
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);

    final page = state.coreInfo.pages.first;
    final original = stroke(const Offset(50, 60));
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

    await tester.runAsync(state.cutSelection);
    await tester.pump();
    expect(page.strokes, isNot(contains(original)));

    state.pasteSelection();
    await tester.pump();
    // a cut is pasted back where it was
    expect(page.strokes.single.points.first.x, 50);
    expect(state.currentTool, select);
    expect(select.selectResult.strokes, page.strokes);

    state.undo();
    expect(page.strokes, isEmpty);
  });
}
