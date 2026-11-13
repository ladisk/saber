import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/quill_click_to_type.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  Future<EditorState> openEditor(WidgetTester tester, String name) async {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/$name/${FileManager.appRootDirectoryPrefix}';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Editor(),
      ),
    );
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    state.setTool(Tool.textEditing);
    state.coreInfo.pages.first.quill.focusNode.requestFocus();
    await tester.pump();
    return state;
  }

  /// Where the cursor of the first page is on screen.
  Offset caretOnScreen(EditorState state) {
    final quill = state.coreInfo.pages.first.quill;
    final editor = QuillClickToType.editorKeyOf(quill)
        .currentState!
        .renderEditor;
    final caret = editor.getLocalRectForCaret(
      quill.controller.selection.extent,
    );
    return editor.localToGlobal(caret.centerLeft);
  }

  testWidgets('a tap below the text starts typing there', (tester) async {
    final state = await openEditor(tester, 'clickToType');
    final quill = state.coreInfo.pages.first.quill;
    final lineHeight = state.coreInfo.lineHeight;
    final page = tester.getRect(find.byType(InnerCanvas).first);
    final scale = page.width / state.coreInfo.pages.first.size.width;

    final tap = page.topLeft + const Offset(300, 300);
    await tester.tapAt(tap);
    await tester.pumpAndSettle();
    expect(quill.controller.document.toPlainText(), startsWith('\n\n'));
    expect(
      caretOnScreen(state),
      offsetMoreOrLessEquals(tap, epsilon: lineHeight * scale),
    );

    // a tap elsewhere without typing takes the padding back
    final higher = page.topLeft + const Offset(100, 150);
    await tester.tapAt(higher);
    await tester.pumpAndSettle();
    expect(caretOnScreen(state), offsetMoreOrLessEquals(higher, epsilon: 25));
    final padding = quill.controller.document.toPlainText();

    // typed text stays where it was typed
    quill.controller.replaceText(
      quill.controller.selection.baseOffset,
      0,
      'Hello',
      const TextSelection.collapsed(offset: 0),
    );
    await tester.tapAt(tap);
    await tester.pumpAndSettle();
    expect(
      quill.controller.document.toPlainText(),
      startsWith('${padding.substring(0, padding.length - 1)}Hello\n'),
    );
  });

  testWidgets('pasted text goes where the mouse is, lines indented', (
    tester,
  ) async {
    final state = await openEditor(tester, 'pasteTextAtMouse');
    final quill = state.coreInfo.pages.first.quill;
    final page = tester.getRect(find.byType(InnerCanvas).first);

    final mouse = page.topLeft + const Offset(200, 250);
    QuillClickToType.insertAt(
      quill,
      'first\r\nsecond',
      mouse,
      lineHeight: state.coreInfo.lineHeight,
    );
    await tester.pumpAndSettle();

    final lines = quill.controller.document.toPlainText().split('\n');
    final first = lines.indexWhere((line) => line.endsWith('first'));
    expect(first, greaterThan(2));
    final indent = lines[first].length - 'first'.length;
    expect(indent, greaterThan(3));
    expect(lines[first + 1], '${' ' * indent}second');
  });
}
