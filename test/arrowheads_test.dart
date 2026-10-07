import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/arrowheads.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/shape_tool.dart';
import 'package:sbn/has_size.dart';

void main() {
  const page = HasSize(Size(500, 500));
  FlavorConfig.setup();

  Stroke draw(ShapeKind kind) {
    final tool = ShapeTool()
      ..kind = kind
      ..startAt(const Offset(10, 10), page, 0)
      ..onDragUpdate(const Offset(110, 60), null);
    return tool.onDragEnd()!;
  }

  test('arrows get arrowheads, plain lines none', () {
    expect(draw(.line).arrowheads, Arrowheads.none);
    expect(draw(.arrow).arrowheads, Arrowheads.end);
    expect(draw(.doubleArrow).arrowheads, Arrowheads.both);
  });

  test('arrowheads survive json and copy', () {
    final stroke = draw(.doubleArrow);
    expect(stroke.copy().arrowheads, Arrowheads.both);

    final json = stroke.toJson();
    expect(json['ah'], 'both');
    final loaded = Stroke.fromJson(
      json,
      fileVersion: 19,
      pageIndex: 0,
      page: page,
    );
    expect(loaded.arrowheads, Arrowheads.both);
  });

  test('strokes without points have no arrowheads', () {
    for (final kind in ShapeKind.values) {
      expect(
        draw(kind).arrowheadTriangles,
        kind.arrowheads == .none ? isEmpty : isNotEmpty,
      );
    }
  });

  test('plain lines are saved without arrowheads', () {
    expect(draw(.line).toJson().containsKey('ah'), isFalse);
    expect(Arrowheads.fromJson('sideways'), Arrowheads.none);
  });

  test('an arrowhead points along the line, tip on its end', () {
    final triangles = Arrowheads.end.triangles(
      const Offset(0, 0),
      const Offset(100, 0),
      4,
    );
    expect(triangles, hasLength(1));
    final [tip, left, right] = triangles.single;
    expect(tip, const Offset(100, 0));
    expect(left.dx, lessThan(tip.dx));
    expect(left.dx, right.dx);
    expect(left.dy, -right.dy);
  });

  test('a double arrow has a head at each end', () {
    final triangles = Arrowheads.both.triangles(
      const Offset(0, 0),
      const Offset(100, 0),
      4,
    );
    expect(triangles.map((triangle) => triangle.first), [
      const Offset(100, 0),
      const Offset(0, 0),
    ]);
    expect(Arrowheads.both.triangles(.zero, .zero, 4), isEmpty);
  });

  test('the line stops inside its heads', () {
    const start = Offset(0, 0), end = Offset(200, 0);
    expect(Arrowheads.none.shaft(start, end, 15), [start, end]);

    final [shaftStart, shaftEnd] = Arrowheads.end.shaft(start, end, 15);
    expect(shaftStart, start);
    // inside the 45 long head, but not past its base
    expect(shaftEnd.dx, inExclusiveRange(200 - 45, 200 - 15 / 2));

    final both = Arrowheads.both.shaft(start, end, 15);
    expect(both.first.dx, greaterThan(0));
    expect(both.last.dx, lessThan(200));
  });

  test('a short arrow keeps some line', () {
    final [shaftStart, shaftEnd] = Arrowheads.both.shaft(
      .zero,
      const Offset(30, 0),
      15,
    );
    expect(shaftEnd.dx, greaterThan(shaftStart.dx));
  });
}
