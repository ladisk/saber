import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_tool.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  const red = Color(0xFFFF0000);

  Future<EditorState> pumpEditor(WidgetTester tester, String name) async {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/paletteColor/$name/${FileManager.appRootDirectoryPrefix}';
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    return state;
  }

  group('palette color', () {
    testWidgets('picks the pen from the highlighter', (tester) async {
      final state = await pumpEditor(tester, 'highlighter');
      final highlighter = Highlighter.currentHighlighter;
      final highlighterColor = highlighter.color;
      state.setTool(highlighter);

      state.pickPaletteColor(red);
      await tester.pump();

      expect(state.currentTool, isA<Pen>());
      expect(state.currentTool, isNot(isA<Highlighter>()));
      expect((state.currentTool as Pen).color, red);
      expect(highlighter.color, highlighterColor);
    });

    testWidgets('picks the pen from the eraser and select', (tester) async {
      final state = await pumpEditor(tester, 'eraser');
      for (final tool in [Eraser(), Select.currentSelect]) {
        state.setTool(tool);
        state.pickPaletteColor(red);
        await tester.pump();
        expect(state.currentTool, isA<Pen>());
      }
    });

    testWidgets('keeps the shape tool', (tester) async {
      final state = await pumpEditor(tester, 'shape');
      state.setTool(ShapeTool.currentShapeTool);

      state.pickPaletteColor(red);
      await tester.pump();

      expect(state.currentTool, same(ShapeTool.currentShapeTool));
      expect(ShapeTool.currentShapeTool.color, red);
    });
  });
}
