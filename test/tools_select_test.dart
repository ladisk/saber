import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/select.dart';
import 'package:sbn/has_size.dart';

void main() {
  group('Select tool', () {
    test('selects the right strokes', () async {
      final select = Select.currentSelect;
      final options = StrokeOptions(size: 9);

      // Drag gesture in a 10x10 square shape, on page 0
      select.onDragStart(Offset.zero, 0);
      select.onDragUpdate(const Offset(0, 10));
      select.onDragUpdate(const Offset(10, 10));
      select.onDragUpdate(const Offset(10, 0));

      expect(
        select.selectResult.pageIndex,
        0,
        reason: 'The page index should be 0',
      );

      const page = HasSize(Size(100, 100));

      final strokes = <Stroke>[
        // index 0 is inside
        Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: options,
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoint(const Offset(5, 5)),
        // index > 0 is outside
        Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: options,
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoint(const Offset(10, 10)),
        Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: options,
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoint(const Offset(15, 15)),
      ];

      select.onDragEnd(strokes, const []);

      expect(
        select.selectResult.strokes,
        hasLength(1),
        reason: 'Only one stroke should be selected',
      );
      expect(
        select.selectResult.strokes.first,
        strokes[0],
        reason: 'The first stroke should be selected',
      );
      expect(
        select.selectResult.images,
        isEmpty,
        reason: 'No images should be selected',
      );
    });

    test('selects the right images', () async {
      final select = Select.currentSelect;

      // Drag gesture in a 10x10 square shape, on page 0
      select.onDragStart(Offset.zero, 0);
      select.onDragUpdate(const Offset(0, 10));
      select.onDragUpdate(const Offset(10, 10));
      select.onDragUpdate(const Offset(10, 0));

      expect(
        select.selectResult.pageIndex,
        0,
        reason: 'The page index should be 0',
      );

      final List<EditorImage> images = [
        // index 0 is inside (100% in the selection)
        TestImage(dstRect: const .fromLTWH(0, 0, 10, 10)),
        // index 1 is inside (> 70% in the selection)
        TestImage(dstRect: const .fromLTWH(0, 0, 10 / 0.75, 10 / 0.75)),
        // index 2 is outside (< 70% in the selection)
        TestImage(dstRect: const .fromLTWH(0, 0, 10 / 0.6, 10 / 0.6)),
      ];

      select.onDragEnd(const [], images);

      expect(
        select.selectResult.images,
        hasLength(2),
        reason: 'Two images should be selected',
      );
      expect(
        select.selectResult.images,
        contains(images[0]),
        reason: 'The first image should be selected',
      );
      expect(
        select.selectResult.images,
        contains(images[1]),
        reason: 'The second image should be selected',
      );
      expect(
        select.selectResult.strokes,
        isEmpty,
        reason: 'No strokes should be selected',
      );
    });

    group('mirror', () {
      late Stroke stroke;
      late TestImage image;

      setUp(() {
        final select = Select.currentSelect;
        stroke = Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: const HasSize(Size(100, 100)),
          toolId: .fountainPen,
        )..addPoints(const [Offset(15, 20), Offset(30, 30)]);
        image = TestImage(dstRect: const .fromLTWH(12, 20, 10, 10));

        // Drag gesture in a 40x40 square shape, centred on (30, 30)
        select.onDragStart(const Offset(10, 10), 0);
        select.onDragUpdate(const Offset(10, 50));
        select.onDragUpdate(const Offset(50, 50));
        select.onDragUpdate(const Offset(50, 10));
        select.onDragEnd([stroke], [image]);
      });

      test('mirrors horizontally about the centre', () {
        expect(Select.currentSelect.mirror(.horizontal), 30);
        final bounds = stroke.centerlinePath.getBounds();
        expect(bounds, const Rect.fromLTRB(30, 20, 45, 30));
        expect(image.dstRect, const Rect.fromLTRB(38, 20, 48, 30));
      });

      test('mirrors vertically about the centre', () {
        expect(Select.currentSelect.mirror(.vertical), 30);
        final bounds = stroke.centerlinePath.getBounds();
        expect(bounds, const Rect.fromLTRB(15, 30, 30, 40));
        expect(image.dstRect, const Rect.fromLTRB(12, 30, 22, 40));
      });

      test('mirroring twice restores the selection', () {
        final select = Select.currentSelect;
        final path = select.selectResult.path.getBounds();
        select
          ..mirror(.horizontal)
          ..mirror(.horizontal);
        expect(
          stroke.centerlinePath.getBounds(),
          const Rect.fromLTRB(15, 20, 30, 30),
        );
        expect(image.dstRect, const Rect.fromLTWH(12, 20, 10, 10));
        expect(select.selectResult.path.getBounds(), path);
      });
    });

    group('resize', () {
      late Stroke stroke;
      late TestImage image;

      setUp(() {
        final select = Select.currentSelect;
        stroke = Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: const HasSize(Size(100, 100)),
          toolId: .fountainPen,
        )..addPoint(const Offset(30, 30));
        image = TestImage(dstRect: const .fromLTWH(20, 20, 20, 20));

        // Drag gesture in a 40x40 square shape, on page 0
        select.onDragStart(const Offset(10, 10), 0);
        select.onDragUpdate(const Offset(10, 50));
        select.onDragUpdate(const Offset(50, 50));
        select.onDragUpdate(const Offset(50, 10));
        select.onDragEnd([stroke], [image]);
        expect(select.selectResult.strokes, [stroke]);
        expect(select.selectResult.images, [image]);
      });

      test('finds the handle under the pointer', () {
        final select = Select.currentSelect;
        expect(select.resizeHandleAt(const Offset(51, 49), 1), 2);
        expect(select.resizeHandleAt(const Offset(30, 30), 1), isNull);
        // hit radius shrinks in page pixels when zoomed in
        expect(select.resizeHandleAt(const Offset(60, 60), 1), 2);
        expect(select.resizeHandleAt(const Offset(60, 60), 4), isNull);
      });

      test('scales about the opposite corner', () {
        final select = Select.currentSelect;
        select.onResizeStart(2); // bottom right, anchored at top left
        expect(select.resizeAnchor, const Offset(10, 10));

        select.onResizeUpdate(const Offset(70, 95)); // ignore off-diagonal
        select.onResizeUpdate(const Offset(90, 90));
        final resize = select.onResizeEnd();

        expect(resize.factor, moreOrLessEquals(2));
        expect(select.isResizing, isFalse);
        expect(stroke.points.single, const Offset(50, 50));
        expect(stroke.options.size, moreOrLessEquals(4));
        expect(image.dstRect, const Rect.fromLTWH(30, 30, 40, 40));
        expect(
          select.selectResult.path.getBounds(),
          const Rect.fromLTRB(10, 10, 90, 90),
        );
      });

      test('does not shrink below the minimum size', () {
        final select = Select.currentSelect;
        select.onResizeStart(2);
        select.onResizeUpdate(const Offset(10, 10));
        final resize = select.onResizeEnd();
        expect(resize.factor, greaterThan(0));
        expect(
          image.dstRect.shortestSide,
          moreOrLessEquals(CanvasImage.minImageSize),
        );
      });
    });

    group('getDominantStrokeColor', () {
      test('not done selecting', () {
        final select = Select.currentSelect;
        select.unselect();
        expect(select.getDominantStrokeColor(), isNull);
      });

      test('with no selected strokes', () {
        final select = Select.currentSelect;
        select.selectResult = SelectResult(
          pageIndex: 0,
          strokes: const [],
          images: const [],
          path: Path(),
        );
        expect(select.getDominantStrokeColor(), isNull);
      });

      test('with selected strokes', () {
        final select = Select.currentSelect;
        select.selectResult = SelectResult(
          pageIndex: 0,
          strokes: [
            _strokeWithColor(Colors.red),
            _strokeWithColor(Colors.blue),
            _strokeWithColor(Colors.blue),
            _strokeWithColor(Colors.blue),
            _strokeWithColor(Colors.red),
          ],
          images: const [],
          path: Path(),
        );
        select.doneSelecting = true;
        expect(select.getDominantStrokeColor(), Colors.blue);
      });
    });
  });
}

// ignore: missing_override_of_must_be_overridden
class TestImage extends PngEditorImage {
  static final _assetCache = AssetCache();

  new({required super.dstRect})
    : super(
        id: -1,
        extension: '.png',
        imageProvider: null,
        pageIndex: 0,
        pageSize: const Size(100, 100),
        onMoveImage: null,
        onDeleteImage: null,
        onMiscChange: null,
        assetCache: _assetCache,
      );

  @override
  Future<void> firstLoad() async {
    // do nothing
  }
}

Stroke _strokeWithColor(Color color) {
  return Stroke(
    color: color,
    pressureEnabled: false,
    options: StrokeOptions(),
    pageIndex: 0,
    page: const HasSize(Size.zero),
    toolId: .fountainPen,
  );
}
