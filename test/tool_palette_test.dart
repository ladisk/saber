import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/tool_palette.dart';
import 'package:saber/data/flavor_config.dart';

void main() {
  setUpAll(FlavorConfig.setup);

  late List<String> picked;
  setUp(() => picked = []);

  ToolPaletteItem item(
    String name, {
    bool isColor = false,
    bool selected = false,
  }) => ToolPaletteItem(
    icon: Text(name),
    tooltip: '$name label',
    isColor: isColor,
    selected: selected,
    onSelected: () => picked.add(name),
  );

  Widget palette(List<List<ToolPaletteGroup>> rows, {VoidCallback? onClose}) =>
      MaterialApp(
        home: Scaffold(
          body: ToolPalette(rows: rows, onClose: onClose ?? () {}),
        ),
      );

  testWidgets('ToolPalette shows its rows, picks items and closes', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      palette([
        [
          ToolPaletteGroup([item('pen'), item('eraser')]),
          ToolPaletteGroup([item('black', isColor: true)]),
        ],
        [
          ToolPaletteGroup([item('line')]),
        ],
      ], onClose: () => closed = true),
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

  testWidgets('dragging the palette anywhere moves it', (tester) async {
    await tester.pumpWidget(
      palette([
        [
          ToolPaletteGroup([item('pen')]),
          ToolPaletteGroup([item('eraser')]),
        ],
      ]),
    );
    final before = tester.getCenter(find.text('pen'));
    // start in the gap between the two groups
    final gap =
        (tester.getCenter(find.text('pen')) +
            tester.getCenter(find.text('eraser'))) /
        2;
    await tester.dragFrom(gap, const Offset(60, 120));
    await tester.pump();
    final after = tester.getCenter(find.text('pen'));
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, greaterThan(before.dy));
    expect(picked, isEmpty);
  });

  group('a collapsible group', () {
    Finder choice(String name) =>
        find.widgetWithText(MenuItemButton, '$name label');

    testWidgets('shows its current choice, the rest in a dropdown', (
      tester,
    ) async {
      await tester.pumpWidget(
        palette([
          [
            ToolPaletteGroup(collapsible: true, current: 1, [
              item('line'),
              item('arrow', selected: true),
              item('circle'),
            ]),
          ],
        ]),
      );
      expect(find.text('line'), findsNothing);
      expect(find.text('arrow'), findsOneWidget);

      // the selected choice opens the dropdown below it
      await tester.tap(find.text('arrow'));
      await tester.pumpAndSettle();
      expect(choice('line'), findsOneWidget);
      expect(
        tester.getTopLeft(choice('line')).dy,
        greaterThan(tester.getCenter(find.text('arrow').first).dy),
      );
      expect(picked, isEmpty);

      // picking closes it
      await tester.tap(choice('circle'));
      await tester.pumpAndSettle();
      expect(picked, ['circle']);
      expect(choice('line'), findsNothing);
    });

    testWidgets('picks its current choice when that is not selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        palette([
          [
            ToolPaletteGroup(collapsible: true, current: 1, [
              item('line'),
              item('arrow'),
            ]),
          ],
        ]),
      );
      await tester.tap(find.text('arrow'));
      await tester.pumpAndSettle();
      expect(picked, ['arrow']);
      expect(choice('line'), findsNothing);
    });

    testWidgets('opens when nothing is current', (tester) async {
      await tester.pumpWidget(
        palette([
          [
            ToolPaletteGroup(collapsible: true, current: -1, [
              item('thin'),
              item('thick'),
            ]),
          ],
        ]),
      );
      expect(find.text('thick'), findsNothing);
      await tester.tap(find.text('thin'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      expect(choice('thick'), findsOneWidget);
    });
  });
}
