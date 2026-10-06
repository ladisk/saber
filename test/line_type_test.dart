import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/line_type.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/shape_tool.dart';
import 'package:sbn/has_size.dart';

void main() {
  const page = HasSize(Size(500, 500));
  FlavorConfig.setup();

  Stroke draw(ShapeKind kind, LineType lineType) {
    final tool = ShapeTool()
      ..kind = kind
      ..lineType = lineType
      ..startAt(const Offset(10, 10), page, 0)
      ..onDragUpdate(const Offset(100, 80), null);
    return tool.onDragEnd()!;
  }

  for (final kind in ShapeKind.values) {
    test('${kind.name} keeps its line type through json and copy', () {
      final stroke = draw(kind, .centerline);
      expect(stroke.lineType, LineType.centerline);
      expect(stroke.copy().lineType, LineType.centerline);

      final json = stroke.toJson();
      expect(json['lt'], 'centerline');
      final loaded = Stroke.fromJson(
        json,
        fileVersion: 19,
        pageIndex: 0,
        page: page,
      );
      expect(loaded.runtimeType, stroke.runtimeType);
      expect(loaded.lineType, LineType.centerline);
    });
  }

  test('solid strokes are saved without a line type', () {
    final json = draw(.line, .solid).toJson();
    expect(json.containsKey('lt'), isFalse);
    expect(LineType.fromJson(json['lt']), LineType.solid);
  });

  test('unknown line types load as solid', () {
    expect(LineType.fromJson('wavy'), LineType.solid);
  });

  test('dash lengths scale with the stroke size', () {
    expect(LineType.dashed.intervals(5), [30, 20]);
    // thin strokes use a minimum unit so the dashes stay visible
    expect(LineType.dashed.intervals(1), [12, 8]);
    expect(LineType.dotted.intervals(4).first, greaterThan(0));
  });
}
