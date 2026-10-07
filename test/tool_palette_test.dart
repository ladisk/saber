import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/tool_palette.dart';
import 'package:saber/data/flavor_config.dart';

void main() {
  setUpAll(FlavorConfig.setup);

  testWidgets('ToolPalette shows its rows, picks items and closes', (
    tester,
  ) async {
    final picked = <String>[];
    var closed = false;

    ToolPaletteItem item(String name, {bool isColor = false}) =>
        ToolPaletteItem(
          icon: Text(name),
          tooltip: name,
          isColor: isColor,
          onSelected: () => picked.add(name),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolPalette(
            rows: [
              [
                [item('pen'), item('eraser')],
                [item('black', isColor: true)],
              ],
              [
                [item('line')],
              ],
            ],
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    // the second row sits below the first
    expect(
      tester.getCenter(find.text('line')).dy,
      greaterThan(tester.getCenter(find.text('pen')).dy),
    );

    await tester.tap(find.text('eraser'));
    await tester.tap(find.text('line'));
    expect(picked, ['eraser', 'line']);

    await tester.tap(find.byIcon(Icons.close));
    expect(closed, isTrue);
  });
}
