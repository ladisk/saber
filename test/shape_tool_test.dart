import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_tool.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

void main() {
  group('ShapeTool', () {
    const page = HasSize(Size(500, 500));
    late ShapeTool tool;

    FlavorConfig.setup();
    setUp(() => tool = ShapeTool());

    test('draws a straight line between the two points', () {
      tool
        ..kind = .line
        ..startAt(const Offset(10, 10), page, 0)
        ..onDragUpdate(const Offset(50, 80), null)
        ..onDragUpdate(const Offset(100, 200), null);
      expect(Pen.currentStroke, isNotNull);

      final stroke = tool.onDragEnd()!;
      expect(Pen.currentStroke, isNull);
      expect(stroke.toolId, ToolId.shapePen);
      expect(stroke.lowQualityPolygon, isNotEmpty);
      final bounds = stroke.highQualityPath.getBounds();
      expect(bounds.left, lessThan(11));
      expect(bounds.bottom, greaterThan(199));
    });

    test('draws a rectangle with the points as opposite corners', () {
      tool
        ..kind = .rectangle
        ..startAt(const Offset(60, 40), page, 0)
        ..onDragUpdate(const Offset(10, 90), null);
      final stroke = tool.onDragEnd();
      expect(stroke, isA<RectangleStroke>());
      expect(
        (stroke! as RectangleStroke).rect,
        const Rect.fromLTRB(10, 40, 60, 90),
      );
    });

    test('draws a circle centred on the start point', () {
      tool
        ..kind = .circle
        ..startAt(const Offset(100, 100), page, 2)
        ..onDragUpdate(const Offset(130, 140), null);
      final stroke = tool.onDragEnd()! as CircleStroke;
      expect(stroke.center, const Offset(100, 100));
      expect(stroke.radius, 50);
      expect(stroke.pageIndex, 2);
    });

    test('draws a sine wave that fills the dragged rectangle', () {
      tool
        ..kind = .sine
        ..startAt(const Offset(10, 20), page, 0)
        ..onDragUpdate(const Offset(110, 80), null);
      final stroke = tool.onDragEnd()!;
      expect(stroke.length, 2 * 48 + 1);
      final bounds = stroke.centerlinePath.getBounds();
      expect(bounds.left, closeTo(10, 0.01));
      expect(bounds.right, closeTo(110, 0.01));
      expect(bounds.top, closeTo(20, 0.1));
      expect(bounds.bottom, closeTo(80, 0.1));
    });

    test('draws half a sine period as a single hump', () {
      tool
        ..kind = .sine
        ..sinePeriods = 0.5
        ..startAt(const Offset(10, 20), page, 0)
        ..onDragUpdate(const Offset(110, 80), null);
      // dragged down, so the hump goes down
      final bounds = tool.onDragEnd()!.centerlinePath.getBounds();
      expect(bounds.top, closeTo(50, 0.1));
      expect(bounds.bottom, closeTo(80, 0.1));
    });

    test('dragging upwards flips the sine wave', () {
      tool
        ..kind = .sine
        ..sinePeriods = 0.5
        ..startAt(const Offset(10, 80), page, 0)
        ..onDragUpdate(const Offset(110, 20), null);
      final bounds = tool.onDragEnd()!.centerlinePath.getBounds();
      expect(bounds.top, closeTo(20, 0.1));
      expect(bounds.bottom, closeTo(50, 0.1));
    });

    test('reshapes one preview stroke while dragging', () {
      tool
        ..kind = .line
        ..startAt(const Offset(10, 10), page, 0);
      // the canvas keeps this object from the start of the drag
      final preview = Pen.currentStroke;
      expect(preview, isNotNull);

      tool.onDragUpdate(const Offset(110, 210), null);
      expect(Pen.currentStroke, same(preview));
      expect(preview!.highQualityPath.getBounds().bottom, greaterThan(200));

      tool.onDragUpdate(const Offset(60, 110), null);
      expect(Pen.currentStroke, same(preview));
      expect(preview.highQualityPath.getBounds().bottom, lessThan(120));
    });

    test('draws nothing for a tap', () {
      tool
        ..kind = .circle
        ..startAt(const Offset(100, 100), page, 0)
        ..onDragUpdate(const Offset(100.5, 100), null);
      expect(tool.onDragEnd(), isNull);
    });
  });
}
