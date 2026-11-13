import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:sbn/has_size.dart';

void main() {
  test('Stroke.shift(offset)', () {
    final stroke = Stroke(
      color: Stroke.defaultColor,
      pressureEnabled: Stroke.defaultPressureEnabled,
      options: StrokeOptions(size: double.minPositive),
      pageIndex: 0,
      page: const HasSize(Size(100, 100)),
      toolId: .fountainPen,
    )..addPoint(const Offset(5, 5));
    expect(stroke.points, [const Offset(5, 5)]);

    var polygon = stroke.highQualityPolygon;
    var path = stroke.highQualityPath;
    expect(polygon.first.dx, moreOrLessEquals(5, epsilon: 0.01));
    expect(path.getBounds().top, moreOrLessEquals(5, epsilon: 0.01));

    stroke.shift(const Offset(-5, -5));
    polygon = stroke.highQualityPolygon;
    path = stroke.highQualityPath;
    expect(stroke.points, [Offset.zero]);
    expect(polygon.first.dx, moreOrLessEquals(0, epsilon: 0.01));
    expect(path.getBounds().top, moreOrLessEquals(0, epsilon: 0.01));
  });

  test('Stroke.scale(factor, anchor)', () {
    final stroke = Stroke(
      color: Stroke.defaultColor,
      pressureEnabled: Stroke.defaultPressureEnabled,
      options: StrokeOptions(size: 2),
      pageIndex: 0,
      page: const HasSize(Size(100, 100)),
      toolId: .fountainPen,
    );
    for (int i = 0; i < 20; i++) {
      stroke.addPoint(Offset(5.0 + i, 5.0 + i * i / 10), 0.5);
    }
    final oldPath = stroke.highQualityPath.getBounds();

    stroke.scale(3, const Offset(1, 1));
    expect(stroke.points.first, const Offset(13, 13));
    expect(stroke.options.size, 6);

    // the cached path is scaled, and matches a freshly computed one
    final scaledPath = stroke.highQualityPath.getBounds();
    expect(
      scaledPath.width,
      moreOrLessEquals(oldPath.width * 3, epsilon: 0.01),
    );
    stroke.markPolygonNeedsUpdating();
    final freshPath = stroke.highQualityPath.getBounds();
    expect(freshPath.left, moreOrLessEquals(scaledPath.left, epsilon: 0.01));
    expect(
      freshPath.bottom,
      moreOrLessEquals(scaledPath.bottom, epsilon: 0.01),
    );
  });

  test('CircleStroke and RectangleStroke scale their shape', () {
    final circle = CircleStroke(
      color: Stroke.defaultColor,
      pressureEnabled: false,
      options: StrokeOptions(),
      pageIndex: 0,
      page: const HasSize(Size(100, 100)),
      toolId: .shapePen,
      center: const Offset(10, 10),
      radius: 5,
    )..scale(2, Offset.zero);
    expect(circle.center, const Offset(20, 20));
    expect(circle.radius, 10);

    final rect = RectangleStroke(
      color: Stroke.defaultColor,
      pressureEnabled: false,
      options: StrokeOptions(),
      pageIndex: 0,
      page: const HasSize(Size(100, 100)),
      toolId: .shapePen,
      rect: const .fromLTWH(10, 10, 10, 10),
    )..scale(0.5, const Offset(10, 10));
    expect(rect.rect, const Rect.fromLTWH(10, 10, 5, 5));
  });
}
