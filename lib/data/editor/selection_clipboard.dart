import 'dart:typed_data';
import 'dart:ui';

import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/select.dart';

/// Strokes and images copied from a selection,
/// to paste into the same note or another one.
///
/// Images are kept as json with their bytes, so pasting them
/// doesn't depend on the files of the note they came from.
abstract final class SelectionClipboard {
  static var _strokes = const <Stroke>[];
  static var _images = const <Map<String, dynamic>>[];
  static var _assets = const <Uint8List>[];
  static var _path = Path();

  /// The note and page the items were copied from,
  /// or null if they were cut and are no longer there.
  static ({String filePath, int pageIndex})? _source;

  /// How many times the items were pasted onto their [_source].
  static var _pastesOnSource = 0;

  /// How far each paste onto the [_source] is moved,
  /// so it doesn't hide the original.
  static const pasteOffset = Offset(25, -25);

  static bool get isEmpty => _strokes.isEmpty && _images.isEmpty;

  /// Copies the items in [selection], which is on a page of [filePath].
  ///
  /// [cut] means the items are removed afterwards,
  /// so a paste puts them back where they were.
  static Future<void> copy(
    SelectResult selection, {
    required String filePath,
    bool cut = false,
  }) async {
    final assets = OrderedAssetCache();
    final images = [for (final image in selection.images) image.toJson(assets)];
    _assets = [
      for (var i = 0; i < assets.length; ++i)
        Uint8List.fromList(await assets.getBytes(i)),
    ];
    _images = images;
    _strokes = [for (final stroke in selection.strokes) stroke.copy()];
    _path = selection.path.shift(Offset.zero);
    _source = cut ? null : (filePath: filePath, pageIndex: selection.pageIndex);
    _pastesOnSource = 0;
  }

  /// Returns new copies of the items for page [pageIndex] of [filePath].
  ///
  /// The images still need an id and their callbacks.
  static SelectResult paste({
    required String filePath,
    required int pageIndex,
    required AssetCache assetCache,
  }) {
    var offset = Offset.zero;
    if (_source == (filePath: filePath, pageIndex: pageIndex)) {
      offset = pasteOffset * (++_pastesOnSource).toDouble();
    }

    final strokes = [
      for (final stroke in _strokes)
        stroke.copy()
          ..pageIndex = pageIndex
          ..shift(offset),
    ];
    final images = [
      for (final json in _images)
        EditorImage.fromJson(
          {
            ...json,
            'i': pageIndex,
            'x': ((json['x'] as num?) ?? 0) + offset.dx,
            'y': ((json['y'] as num?) ?? 0) + offset.dy,
          },
          inlineAssets: _assets,
          sbnPath: filePath,
          assetCache: assetCache,
        ),
    ];
    return SelectResult(
      pageIndex: pageIndex,
      strokes: strokes,
      images: images,
      path: _path.shift(offset),
    );
  }

  /// Empties the clipboard.
  static void clear() {
    _strokes = const [];
    _images = const [];
    _assets = const [];
    _path = Path();
    _source = null;
  }
}
