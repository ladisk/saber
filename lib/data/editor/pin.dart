import 'package:material_ui/material_ui.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/selection_export.dart';
import 'package:saber/data/tools/select.dart';

/// A pin (LADISK fork): a window that floats over the editor and shows
/// a live view of [rect] on [page], e.g. an earlier sketch that should
/// stay visible while writing further down.
///
/// The pin keeps the page itself rather than its index, so it follows
/// the page when pages are inserted, deleted or moved before it.
/// A pin whose page is no longer in the note is hidden and not saved.
class NotePin {
  new({
    required this.page,
    required this.rect,
    required this.x,
    required this.y,
    required this.width,
  });

  /// The key in the note file. It is absent when a note has no pins,
  /// so such notes are saved exactly as before.
  static const jsonKey = 'ladiskPins';

  final EditorPage page;

  /// The pinned area, in page coordinates.
  final Rect rect;

  /// The window's left and top edges, as fractions of the editor's
  /// width and height.
  double x, y;

  /// The window's width, as a fraction of the editor's width.
  /// Its height follows from the aspect ratio of [rect].
  double width;

  /// The margin around the selected items, in page units.
  static const padding = 16.0;

  /// A new window's width, as a fraction of the editor's width.
  static const initialWidth = 0.3;

  /// A pin of the area around [selection] on [page], or null if the
  /// selection has no area.
  ///
  /// The window goes near the top right corner, below where the tool
  /// palette starts out, and a little lower for each of the [existingPins]
  /// so that new windows don't hide each other.
  static NotePin? forSelection(
    SelectResult selection,
    EditorPage page, {
    int existingPins = 0,
  }) {
    final bounds =
        SelectionExport.boundsOf(selection) ?? selection.path.getBounds();
    final rect = bounds.inflate(padding).intersect(Offset.zero & page.size);
    if (rect.width <= 0 || rect.height <= 0) return null;
    return NotePin(
      page: page,
      rect: rect,
      x: 1 - initialWidth - 0.02,
      y: 0.12 + 0.05 * (existingPins % 8),
      width: initialWidth,
    );
  }

  Map<String, dynamic> toJson(int pageIndex) => {
    'page': pageIndex,
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'x': x,
    'y': y,
    'w': width,
  };

  /// Reads a pin, or returns null if [json] is malformed
  /// or points to a page that [pages] doesn't have.
  static NotePin? fromJson(Object? json, List<EditorPage> pages) {
    if (json is! Map) return null;
    final pageIndex = _toDouble(json['page'])?.toInt();
    final rect = json['rect'];
    final x = _toDouble(json['x']);
    final y = _toDouble(json['y']);
    final width = _toDouble(json['w']);
    if (pageIndex == null ||
        pageIndex < 0 ||
        pageIndex >= pages.length ||
        rect is! List ||
        rect.length != 4 ||
        x == null ||
        y == null ||
        width == null) {
      return null;
    }
    final [left, top, w, h] = rect.map(_toDouble).toList();
    if (left == null || top == null || w == null || h == null) return null;
    if (w <= 0 || h <= 0) return null;
    return NotePin(
      page: pages[pageIndex],
      rect: Rect.fromLTWH(left, top, w, h),
      x: x,
      y: y,
      width: width,
    );
  }

  /// Reads the pins saved under [jsonKey], skipping malformed ones.
  static List<NotePin> listFromJson(Object? json, List<EditorPage> pages) => [
    if (json is List)
      for (final item in json) ?NotePin.fromJson(item, pages),
  ];

  /// Accepts any number, including BSON's [Int64].
  static double? _toDouble(Object? value) => switch (value) {
    final num n => n.toDouble(),
    null => null,
    _ => double.tryParse(value.toString()),
  };
}

/// Saving and loading [EditorCoreInfo.ladiskPins].
extension NotePins on EditorCoreInfo {
  /// Reads the pins from the note's json value at [NotePin.jsonKey].
  void loadLadiskPins(Object? json) {
    ladiskPins = NotePin.listFromJson(json, pages);
  }

  /// The pins to add to the note's json: empty when there are none,
  /// so a note without pins is saved byte for byte as before.
  ///
  /// Pins on pages that were deleted are left out.
  Map<String, dynamic> ladiskPinsToJson() {
    final json = [
      for (final pin in ladiskPins)
        if (pages.indexOf(pin.page) case final pageIndex when pageIndex >= 0)
          pin.toJson(pageIndex),
    ];
    if (json.isEmpty) return const {};
    return {NotePin.jsonKey: json};
  }

  /// The pins whose page is still in the note.
  Iterable<NotePin> get visibleLadiskPins =>
      ladiskPins.where((pin) => pages.contains(pin.page));
}
