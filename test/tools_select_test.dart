import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/line_type.dart';
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

    group('touch mode', () {
      const page = HasSize(Size(100, 100));
      late Stroke line;
      late CircleStroke circle;
      late TestImage image;

      setUp(() {
        line = Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: false,
          options: StrokeOptions(size: 2, isComplete: true),
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )..addPoints(const [Offset(10, 20), Offset(90, 20)]);
        circle = CircleStroke(
          color: Stroke.defaultColor,
          pressureEnabled: false,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
          center: const Offset(50, 60),
          radius: 20,
        );
        image = TestImage(dstRect: const .fromLTWH(70, 70, 20, 20));
      });

      tearDown(() => Select.currentSelect.touchMode = false);

      void tap(Offset position) {
        Select.currentSelect
          ..touchMode = true
          ..onDragStart(position, 0)
          ..touchAt(position, [line, circle], [image])
          ..onDragEnd([line, circle], [image]);
      }

      test('selects a stroke near the tap', () {
        tap(const Offset(50, 26));
        final result = Select.currentSelect.selectResult;
        expect(result.strokes, [line]);
        expect(result.images, isEmpty);
        expect(result.path.getBounds().contains(const Offset(10, 20)), isTrue);
      });

      test('selects a circle on its outline but not inside it', () {
        tap(const Offset(71, 60));
        expect(Select.currentSelect.selectResult.strokes, [circle]);
        tap(const Offset(50, 60));
        expect(Select.currentSelect.selectResult.isEmpty, isTrue);
      });

      test('selects an image under the tap', () {
        tap(const Offset(85, 85));
        final result = Select.currentSelect.selectResult;
        expect(result.strokes, isEmpty);
        expect(result.images, [image]);
      });

      test('selects everything touched while dragging', () {
        final select = Select.currentSelect
          ..touchMode = true
          ..onDragStart(const Offset(50, 25), 0);
        for (final position in const [
          Offset(50, 25),
          Offset(70, 60),
          Offset(80, 80),
        ]) {
          select
            ..onDragUpdate(position)
            ..touchAt(position, [line, circle], [image]);
        }
        select.onDragEnd([line, circle], [image]);
        expect(select.selectResult.strokes, [line, circle]);
        expect(select.selectResult.images, [image]);
        expect(select.touchesSelection(const Offset(30, 21)), isTrue);
        expect(select.touchesSelection(const Offset(50, 60)), isFalse);
      });

      test('a tap selects without the drag ending', () {
        final select = Select.currentSelect
          ..touchMode = true
          ..onDragStart(const Offset(50, 25), 0)
          ..touchAt(const Offset(50, 25), [line, circle], [image]);
        expect(select.doneSelecting, isTrue);
        expect(select.selectResult.strokes, [line]);
        expect(select.resizeHandles, isNotEmpty);
      });

      test('reports the common line type', () {
        line.lineType = .dashed;
        tap(const Offset(50, 21));
        expect(Select.currentSelect.getCommonLineType(), LineType.dashed);
      });
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

    group('rotate', () {
      late Stroke stroke;
      late RectangleStroke rect;
      late TestImage image;
      late List<Stroke> pageStrokes;

      setUp(() {
        final select = Select.currentSelect;
        stroke = Stroke(
          color: Stroke.defaultColor,
          pressureEnabled: Stroke.defaultPressureEnabled,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: const HasSize(Size(100, 100)),
          toolId: .fountainPen,
        )..addPoint(const Offset(40, 30));
        rect = RectangleStroke(
          color: Stroke.defaultColor,
          pressureEnabled: false,
          options: StrokeOptions(size: 2),
          pageIndex: 0,
          page: const HasSize(Size(100, 100)),
          toolId: .shapePen,
          rect: const .fromLTWH(25, 25, 10, 10),
        );
        image = TestImage(dstRect: const .fromLTWH(12, 20, 10, 10));
        pageStrokes = [stroke, rect];

        // Drag gesture in a 40x40 square shape, centred on (30, 30)
        select.onDragStart(const Offset(10, 10), 0);
        select.onDragUpdate(const Offset(10, 50));
        select.onDragUpdate(const Offset(50, 50));
        select.onDragUpdate(const Offset(50, 10));
        select.onDragEnd(pageStrokes, [image]);
      });

      test('finds the handle above the selection', () {
        final select = Select.currentSelect;
        expect(select.rotateHandle(1), const Offset(30, 10 - 32));
        expect(select.rotateHandleAt(const Offset(30, -20), 1), isTrue);
        expect(select.rotateHandleAt(const Offset(30, 30), 1), isFalse);
      });

      test('rotates about the centre, keeping images upright', () {
        final select = Select.currentSelect;
        select
          ..onRotateStart(select.rotateHandle(1), pageStrokes)
          ..onRotateUpdate(const Offset(62, 30)); // a quarter turn
        final rotate = select.onRotateEnd(pageStrokes)!;

        expect(rotate.angle, moreOrLessEquals(pi / 2));
        expect(rotate.center, const Offset(30, 30));
        expect(select.isRotating, isFalse);
        expect(stroke.points.single.dx, moreOrLessEquals(30));
        expect(stroke.points.single.dy, moreOrLessEquals(40));
        expect(image.dstRect.center.dx, moreOrLessEquals(35));
        expect(image.dstRect.center.dy, moreOrLessEquals(17));
        expect(image.dstRect.size, const Size(10, 10));
      });

      test('snaps to steps of 15°', () {
        final select = Select.currentSelect;
        select.onRotateStart(select.rotateHandle(1), pageStrokes);
        // 50° clockwise from straight up
        select.onRotateUpdate(
          const Offset(30, 30) + Offset.fromDirection(-pi / 2 + pi * 50 / 180),
        );
        expect(select.rotateAngle, moreOrLessEquals(pi / 4));
      });

      test('swaps rectangles for plain strokes while rotated', () {
        final select = Select.currentSelect;
        select
          ..onRotateStart(select.rotateHandle(1), pageStrokes)
          ..onRotateUpdate(const Offset(62, 30));
        final rotate = select.onRotateEnd(pageStrokes)!;

        final polygon = pageStrokes[1];
        expect(polygon, isNot(isA<RectangleStroke>()));
        expect(select.selectResult.strokes, contains(polygon));
        expect(rotate.rectangles, {polygon: rect});
        expect(
          polygon.centerlinePath.getBounds().center.dx,
          moreOrLessEquals(30),
        );
      });

      test('an unrotated selection keeps its rectangles', () {
        final select = Select.currentSelect;
        final handle = select.rotateHandle(1);
        select
          ..onRotateStart(handle, pageStrokes)
          ..onRotateUpdate(const Offset(62, 30))
          ..onRotateUpdate(handle);
        expect(select.onRotateEnd(pageStrokes), isNull);
        expect(pageStrokes, [stroke, rect]);
        expect(select.selectResult.strokes, contains(rect));
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
