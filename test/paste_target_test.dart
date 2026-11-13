import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
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

  Stroke stroke(Offset point) => Stroke(
    color: Stroke.defaultColor,
    pressureEnabled: Stroke.defaultPressureEnabled,
    options: StrokeOptions(size: 5),
    pageIndex: 0,
    page: const HasSize(EditorPage.defaultSize),
    toolId: .ballpointPen,
  )..addPoint(point);

  testWidgets('pastes onto the page in the middle of the screen, '
      'not onto the previous one still showing at the top', (tester) async {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/pasteTarget/${FileManager.appRootDirectoryPrefix}';
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);

    // two pages with something on them
    state.coreInfo.pages.first.strokes.add(stroke(const Offset(50, 60)));
    state.createPage(1);
    state.coreInfo.pages[1].strokes.add(stroke(const Offset(50, 60)));
    await tester.pump();

    final view = tester.getRect(find.byType(Editor));

    final firstPage = tester.getRect(find.byType(InnerCanvas).first);
    // scroll so that the bottom of the first page is still at the top
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: view.center,
        scrollDelta: Offset(0, firstPage.bottom - view.top - 150),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.currentPageIndex, 0, reason: 'top of the screen');

    await SelectionClipboard.copy(
      SelectResult(
        pageIndex: 0,
        pageIndexStart: 0,
        strokes: [stroke(const Offset(10, 10))],
        images: const [],
        path: Path(),
      ),
      filePath: '/elsewhere',
    );
    state.pasteSelection();
    await tester.pump();
    expect((state.currentTool as Select).selectResult.pageIndex, 1);
    expect(state.coreInfo.pages[1].strokes, hasLength(2));
    expect(state.coreInfo.pages[0].strokes, hasLength(1));
  });

  testWidgets('an image dragged onto another page moves there', (tester) async {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/imageDrop/${FileManager.appRootDirectoryPrefix}';
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);

    final bytes = await tester.runAsync(
      () => File('assets/icon/icon.png').readAsBytes(),
    );
    final pageSize = state.coreInfo.pages.first.size;
    final image =
        PngEditorImage(
            id: state.coreInfo.nextImageId++,
            extension: '.png',
            imageProvider: MemoryImage(bytes!),
            pageIndex: 0,
            pageSize: pageSize,
            onMoveImage: state.onMoveImage,
            onDeleteImage: state.onDeleteImage,
            onMiscChange: null,
            assetCache: state.coreInfo.assetCache,
          )
          ..naturalSize = const Size(100, 100)
          ..srcRect = const Rect.fromLTWH(0, 0, 100, 100)
          ..dstRect = Rect.fromLTWH(100, pageSize.height - 200, 100, 100);
    state.coreInfo.pages.first.images.add(image);
    state.createPage(1);
    state.coreInfo.pages[1].strokes.add(stroke(const Offset(50, 60)));
    state.setTool(Select.currentSelect);
    await tester.pump();

    // scroll so that the bottom of the first page is in the middle
    final view = tester.getRect(find.byType(Editor));
    final firstPage = tester.getRect(find.byType(InnerCanvas).first);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: view.center,
        scrollDelta: Offset(0, firstPage.bottom - view.center.dy),
      ),
    );
    await tester.pumpAndSettle();

    final imageFinder = find.byType(CanvasImage);
    final start = tester.getCenter(imageFinder);
    // a new image is active, so it can be dragged straight away
    final gesture = await tester.startGesture(start, kind: .mouse);
    for (var i = 0; i < 25; ++i) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.coreInfo.pages[0].images, isEmpty);
    expect(state.coreInfo.pages[1].images, [image]);
    expect(image.pageIndex, 1);
    // still under the pointer, give or take the drag's slop
    expect(
      tester.getCenter(imageFinder),
      offsetMoreOrLessEquals(start + const Offset(0, 250), epsilon: 10),
    );

    state.undo();
    await tester.pumpAndSettle();
    expect(state.coreInfo.pages[1].images, isEmpty);
    expect(state.coreInfo.pages[0].images, [image]);
    expect(image.dstRect, Rect.fromLTWH(100, pageSize.height - 200, 100, 100));

    // close the editor and let the image's delayed load out finish
    state.cancelAutosaveAndMarkSaved();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
}
