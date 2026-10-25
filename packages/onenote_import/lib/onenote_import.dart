/// Reads OneNote notebooks with the Rust `onenote_parser` crate.
///
/// Positions are in CSS pixels (96 dpi) from the top left of the OneNote page.
library;

import 'dart:convert';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:onenote_import/src/bindings.dart';

/// The file extensions that [readOneNoteFile] accepts.
const oneNoteExtensions = ['.one', '.onepkg', '.onetoc2'];

/// Reads the OneNote file at [path] in a background isolate.
///
/// `.one` files are sections, `.onepkg` files are exported notebooks
/// and `.onetoc2` files are notebooks whose sections lie next to them.
///
/// Images are written to [imageDir], which must exist.
/// Throws a [OneNoteImportException] if the file can't be read.
Future<List<OneNoteSection>> readOneNoteFile(
  String path, {
  required String imageDir,
}) async {
  final json = await Isolate.run(() => _readJson(path, imageDir));
  final map = jsonDecode(json) as Map<String, dynamic>;
  if (map['error'] case final String error) {
    throw OneNoteImportException(error);
  }
  return [
    for (final section in map['sections'] as List)
      OneNoteSection.fromJson(section as Map<String, dynamic>, imageDir),
  ];
}

String _readJson(String path, String imageDir) {
  final pathPtr = path.toNativeUtf8();
  final imageDirPtr = imageDir.toNativeUtf8();
  try {
    final jsonPtr = onenoteImportFile(pathPtr, imageDirPtr);
    try {
      return jsonPtr.toDartString();
    } finally {
      onenoteImportFree(jsonPtr);
    }
  } finally {
    malloc.free(pathPtr);
    malloc.free(imageDirPtr);
  }
}

class OneNoteImportException implements Exception {
  const new(this.message);
  final String message;

  @override
  String toString() => 'OneNoteImportException: $message';
}

class OneNoteSection {
  new fromJson(Map<String, dynamic> json, String imageDir)
    : name = json['name'] as String,
      groups = (json['groups'] as List).cast<String>(),
      pages = [
        for (final page in json['pages'] as List)
          OneNotePage.fromJson(page as Map<String, dynamic>, imageDir),
      ];

  final String name;

  /// The names of the section groups that contain this section.
  final List<String> groups;
  final List<OneNotePage> pages;
}

class OneNotePage {
  new fromJson(Map<String, dynamic> json, String imageDir)
    : title = json['title'] as String,
      level = json['level'] as int,
      created = _fromUnixSeconds(json['created'] as int),
      updated = _fromUnixSeconds(json['updated'] as int),
      strokes = [
        for (final stroke in json['strokes'] as List)
          OneNoteStroke.fromJson(stroke as Map<String, dynamic>),
      ],
      images = [
        for (final image in json['images'] as List)
          OneNoteImage.fromJson(image as Map<String, dynamic>, imageDir),
      ],
      texts = [
        for (final text in json['texts'] as List)
          OneNoteText.fromJson(text as Map<String, dynamic>),
      ],
      skipped = json['skipped'] as int;

  final String title;

  /// 1 for pages, 2 or more for subpages.
  final int level;
  final DateTime created, updated;
  final List<OneNoteStroke> strokes;
  final List<OneNoteImage> images;
  final List<OneNoteText> texts;

  /// The number of items that have no counterpart in Saber, e.g. tables.
  final int skipped;

  bool get isEmpty => strokes.isEmpty && images.isEmpty && texts.isEmpty;
}

DateTime _fromUnixSeconds(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

class OneNoteStroke {
  new fromJson(Map<String, dynamic> json)
    : rgb = (json['rgb'] as List).cast<int>(),
      alpha = json['alpha'] as int,
      width = (json['width'] as num).toDouble(),
      tip = json['tip'] as int,
      points = [
        for (final coordinate in json['points'] as List)
          (coordinate as num).toDouble(),
      ];

  /// Red, green and blue, each 0 to 255.
  final List<int> rgb;

  /// 255 is opaque.
  final int alpha;

  /// The pen width in pixels.
  final double width;

  /// 0 is a round pen tip, anything else is a rectangle.
  final int tip;

  /// Absolute points as `[x0, y0, x1, y1, ...]`.
  final List<double> points;

  /// Whether this stroke was drawn with a highlighter.
  bool get isHighlighter => tip != 0 || alpha < 255;
}

class OneNoteImage {
  new fromJson(Map<String, dynamic> json, String imageDir)
    : x = (json['x'] as num).toDouble(),
      y = (json['y'] as num).toDouble(),
      width = (json['width'] as num).toDouble(),
      height = (json['height'] as num).toDouble(),
      path = '$imageDir/${json['file']}';

  final double x, y;

  /// Zero if unknown; the image's own size is then used.
  final double width, height;

  /// The image file.
  final String path;
}

class OneNoteText {
  new fromJson(Map<String, dynamic> json)
    : x = (json['x'] as num).toDouble(),
      y = (json['y'] as num).toDouble(),
      width = (json['width'] as num? ?? 0).toDouble(),
      text = json['text'] as String;

  final double x, y;

  /// The width of the outline the text is in, or 0 if unknown.
  final double width;

  /// One paragraph, which may contain line breaks.
  final String text;
}
