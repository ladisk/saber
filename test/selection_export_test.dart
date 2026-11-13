import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/selection_export.dart';
import 'package:saber/data/tools/select.dart';
import 'package:sbn/has_size.dart';

void main() {
  Stroke stroke(List<Offset> points) {
    final stroke = Stroke(
      color: Colors.red,
      pressureEnabled: false,
      options: StrokeOptions(size: 4),
      pageIndex: 0,
      page: const HasSize(EditorPage.defaultSize),
      toolId: .ballpointPen,
    );
    return stroke..addPoints(points);
  }

  SelectResult selection({
    List<Stroke> strokes = const [],
    List<EditorImage> images = const [],
  }) => SelectResult(
    pageIndex: 0,
    pageIndexStart: 0,
    strokes: strokes,
    images: images,
    path: Path(),
  );

  test('nothing to draw gives no image', () async {
    expect(
      await SelectionExport.renderPng(selection(), EditorPage()),
      isNull,
    );
  });

  testWidgets('renders strokes and images to a padded png', (tester) async {
    await tester.runAsync(() async {
      final image = PngEditorImage(
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
        assetCache: AssetCache(),
      )..dstRect = const Rect.fromLTWH(200, 100, 50, 50);
      final line = stroke(const [Offset(100, 100), Offset(150, 120)]);
      final result = selection(strokes: [line], images: [image]);

      final bounds = SelectionExport.boundsOf(result)!;
      expect(bounds.right, 250);
      expect(bounds.bottom, 150);

      final png = await SelectionExport.renderPng(result, EditorPage());
      expect(png, isNotNull);
      final codec = await ui.instantiateImageCodec(png!);
      final decoded = (await codec.getNextFrame()).image;
      final padded = bounds.inflate(SelectionExport.padding);
      expect(decoded.width, (padded.width * SelectionExport.scale).ceil());
      expect(decoded.height, (padded.height * SelectionExport.scale).ceil());
    });
  });
}
