import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/editor/page.dart';
import 'package:sbn/quill_styles.dart';

/// Lets text be typed or pasted anywhere on a page.
///
/// A page's text is one document flowing from the top of the page,
/// so to start typing lower down or further right, the document is
/// padded with empty lines and spaces up to that point.
///
/// Kept out of upstream files so that changes to them merge without
/// conflicts.
abstract final class QuillClickToType {
  static final _editorKeys = Expando<GlobalKey<EditorState>>();

  /// The key of the [QuillEditor] showing [quill],
  /// to find where its text is on screen.
  static GlobalKey<EditorState> editorKeyOf(QuillStruct quill) =>
      _editorKeys[quill] ??= GlobalKey<EditorState>();

  /// The padding added by the last [moveCursorTo], removed again
  /// if nothing was typed after it before the next one.
  static _Padding? _lastPadding;

  /// The width of a space in the text's font.
  static double spaceWidth(int lineHeight) {
    final style = SaberQuillStyles.get(
      invert: false,
      secondary: Colors.black,
      lineHeight: lineHeight,
    ).paragraph!.style;
    final painter = TextPainter(
      text: TextSpan(text: ' ' * 10, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width / 10;
    painter.dispose();
    return width;
  }

  /// Where typing would have to start for the text to appear at [global],
  /// a position on screen, and the empty lines and spaces to insert there
  /// first. [indent] is the number of spaces the typing starts after,
  /// for indenting further lines of pasted text.
  ///
  /// Returns null if [quill] is not on screen, or if [global] is on the
  /// text already there, where the editor puts the cursor itself.
  static ({int offset, String padding, int indent})? paddingFor(
    QuillStruct quill,
    Offset global, {
    required int lineHeight,
  }) {
    final editor = editorKeyOf(quill).currentState?.renderEditor;
    if (editor == null || !editor.attached || !editor.hasSize) return null;

    final document = quill.controller.document;
    final local = editor.globalToLocal(global);
    final space = spaceWidth(lineHeight);
    final lineStart = editor.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );
    int spacesFrom(double left) => ((local.dx - left) / space).round();

    // below the text: add lines, then spaces
    final end = document.length - 1;
    final endCaret = editor.getLocalRectForCaret(TextPosition(offset: end));
    if (local.dy >= endCaret.bottom) {
      final lines = ((local.dy - endCaret.bottom) / lineHeight).floor() + 1;
      final spaces = spacesFrom(lineStart.left).clamp(0, 1000);
      return (
        offset: end,
        padding: '\n' * lines + ' ' * spaces,
        indent: spaces,
      );
    }

    // to the right of the end of a line: add spaces
    final position = editor.getPositionForOffset(local);
    final caret = editor.getLocalRectForCaret(position);
    final atLineEnd = document.toPlainText()[position.offset] == '\n';
    final onCaretsLine =
        local.dy >= caret.top - 1 && local.dy <= caret.bottom + 1;
    final spaces = spacesFrom(caret.left);
    if (atLineEnd && onCaretsLine && spaces > 0) {
      return (
        offset: position.offset,
        padding: ' ' * spaces,
        indent: spacesFrom(lineStart.left).clamp(0, 1000),
      );
    }
    return null;
  }

  /// Puts the cursor of [quill] at [global], a position on screen,
  /// padding the text if needed. Does nothing if [global] is on the
  /// text already there, where the editor has put the cursor itself.
  static void moveCursorTo(
    QuillStruct quill,
    Offset global, {
    required int lineHeight,
  }) => _afterRemovingUnusedPadding(() {
    final selection = quill.controller.selection;
    if (!selection.isCollapsed) return;
    final padding = paddingFor(quill, global, lineHeight: lineHeight);
    if (padding == null) return;

    final cursor = padding.offset + padding.padding.length;
    quill.controller.replaceText(
      padding.offset,
      0,
      padding.padding,
      TextSelection.collapsed(offset: cursor),
    );
    _lastPadding = _Padding(
      quill: quill,
      offset: padding.offset,
      text: padding.padding,
      documentAfter: quill.controller.document.toPlainText(),
    );
  });

  /// Runs [then] once the text is laid out again
  /// after [removeUnusedPadding], or now if there was none.
  static void _afterRemovingUnusedPadding(VoidCallback then) {
    if (!removeUnusedPadding()) return then();
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => then())
      ..scheduleFrame();
  }

  /// Removes the padding added by the last [moveCursorTo]
  /// if nothing has been typed since, and returns whether it did.
  static bool removeUnusedPadding() {
    final last = _lastPadding;
    _lastPadding = null;
    if (last == null) return false;
    final controller = last.quill.controller;
    if (controller.document.toPlainText() != last.documentAfter) return false;

    // keep the cursor where it is in the rest of the text
    final end = last.offset + last.text.length;
    int moved(int offset) => offset <= last.offset
        ? offset
        : offset >= end
        ? offset - last.text.length
        : last.offset;
    final selection = controller.selection;
    controller.replaceText(
      last.offset,
      last.text.length,
      '',
      selection.copyWith(
        baseOffset: moved(selection.baseOffset),
        extentOffset: moved(selection.extentOffset),
      ),
    );
    return true;
  }

  /// Inserts [text] into [quill] so that it starts at [global],
  /// a position on screen, or at the end of the text if that is
  /// on the text already there or the page is not on screen.
  static void insertAt(
    QuillStruct quill,
    String text,
    Offset? global, {
    required int lineHeight,
  }) => _afterRemovingUnusedPadding(() {
    final controller = quill.controller;
    final padding = global == null
        ? null
        : paddingFor(quill, global, lineHeight: lineHeight);

    text = text.replaceAll('\r\n', '\n');
    final onText = global == null ? null : _positionAt(quill, global);

    final String insert;
    final int offset;
    if (padding != null) {
      // further lines start below the first one
      final indent = '\n${' ' * padding.indent}';
      insert = padding.padding + text.replaceAll('\n', indent);
      offset = padding.offset;
    } else if (onText != null) {
      insert = text;
      offset = onText;
    } else {
      // the document always ends with a newline
      offset = controller.document.length - 1;
      insert = offset > 0 ? '\n$text' : text;
    }
    controller.replaceText(
      offset,
      0,
      insert,
      TextSelection.collapsed(offset: offset + insert.length),
    );
  });
}

/// The offset in the text of [quill] at [global], a position on screen,
/// or null if [quill] is not on screen.
int? _positionAt(QuillStruct quill, Offset global) {
  final editor = QuillClickToType.editorKeyOf(quill).currentState?.renderEditor;
  if (editor == null || !editor.attached || !editor.hasSize) return null;
  return editor.getPositionForOffset(editor.globalToLocal(global)).offset;
}

class _Padding {
  const new({
    required this.quill,
    required this.offset,
    required this.text,
    required this.documentAfter,
  });

  final QuillStruct quill;
  final int offset;
  final String text;
  final String documentAfter;
}
