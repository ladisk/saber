import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// Renders selected handwriting to a PNG for reading it.
///
/// Every stroke is drawn black on white, whatever its color, so ink color
/// and dark mode don't affect how well it can be read.
abstract final class SelectionImage {
  /// The margin around the strokes, in page units.
  static const padding = 16.0;

  /// The longest side of the image, in pixels.
  static const maxSide = 1568.0;

  /// The strokes that are rendered: highlighter strokes aren't writing.
  static List<Stroke> writing(Iterable<Stroke> strokes) => [
    for (final stroke in strokes)
      if (stroke.toolId != .highlighter && !stroke.isEmpty) stroke,
  ];

  /// The bounds of [strokes] on the page.
  static Rect boundsOf(Iterable<Stroke> strokes) => strokes
      .map((stroke) => stroke.highQualityPath.getBounds())
      .reduce((a, b) => a.expandToInclude(b));

  static Future<Uint8List> render(List<Stroke> strokes) async {
    final bounds = boundsOf(strokes).inflate(padding);
    // enlarge small handwriting, but keep the image within [maxSide]
    final scale = min(3.0, maxSide / bounds.longestSide);
    final width = max(1, (bounds.width * scale).ceil());
    final height = max(1, (bounds.height * scale).ceil());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = Colors.white,
      )
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);

    final fill = Paint()..color = Colors.black;
    for (final stroke in strokes) {
      final outline = Paint()
        ..color = Colors.black
        ..style = .stroke
        ..strokeWidth = stroke.options.size
        ..strokeCap = .round
        ..strokeJoin = .round;
      if (stroke is CircleStroke) {
        canvas.drawCircle(stroke.center, stroke.radius, outline);
      } else if (stroke is RectangleStroke) {
        canvas.drawRect(stroke.rect, outline);
      } else if (stroke.drawnAsCenterline) {
        canvas.drawPath(stroke.centerlinePath, outline);
      } else {
        canvas.drawPath(stroke.highQualityPath, fill);
      }
    }

    final image = await recorder.endRecording().toImage(width, height);
    try {
      final data = await image.toByteData(format: .png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
