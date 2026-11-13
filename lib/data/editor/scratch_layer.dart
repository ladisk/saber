import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';

/// The scratch layer (LADISK fork): strokes drawn over a page for a while,
/// e.g. to explain the note while projecting it, then cleared at once.
///
/// Scratch strokes are kept here, never in [EditorPage.strokes],
/// so they are never saved, synced, exported or shown in previews.
/// They are lost when the note is closed.
class ScratchLayer {
  /// Whether new pen strokes go on the scratch layer
  /// and the eraser erases only scratch strokes.
  /// Scratch strokes are shown only while this is on.
  bool get isOn => shown;
  set isOn(bool value) => shown = value;

  /// Whether scratch strokes are painted.
  /// Only one editor is open at a time, so this is shared.
  static var shown = false;

  static final _strokes = Expando<List<Stroke>>('scratch strokes');

  /// The scratch strokes on [page], painted over everything on it.
  static List<Stroke> strokesOf(EditorPage page) => _strokes[page] ??= [];

  static bool hasStrokes(EditorPage page) =>
      _strokes[page]?.isNotEmpty ?? false;

  /// Removes the scratch strokes on all [pages].
  static void clear(Iterable<EditorPage> pages) {
    for (final page in pages) {
      final strokes = _strokes[page];
      if (strokes == null || strokes.isEmpty) continue;
      strokes.clear();
      page.redrawStrokes();
    }
  }
}
