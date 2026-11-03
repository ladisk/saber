import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/select.dart';

/// Renders a selection to a PNG, so it can be pasted into other apps.
///
/// Strokes are drawn with the editor's own painter, so they look the same
/// as on the page, on a white background so dark ink stays readable
/// wherever it is pasted.
abstract final class SelectionExport {
  /// The margin around the items, in page units.
  static const padding = 8.0;

  /// Pixels per page unit, for a sharp image.
  static const scale = 2.0;

  /// The longest side of the image, in pixels.
  static const maxSide = 4096.0;

  /// The bounds of [selection]'s strokes and images on the page,
  /// or null if there is nothing to draw.
  static Rect? boundsOf(SelectResult selection) {
    Rect? bounds;
    for (final stroke in selection.strokes) {
      if (stroke.isEmpty) continue;
      // outlined shapes are drawn half their width outside the path
      final rect = stroke.highQualityPath.getBounds().inflate(
        stroke.options.size / 2,
      );
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }
    for (final image in selection.images) {
      bounds = bounds?.expandToInclude(image.dstRect) ?? image.dstRect;
    }
    return bounds;
  }

  static Future<Uint8List?> renderPng(
    SelectResult selection,
    EditorPage page,
  ) async {
    final bounds = boundsOf(selection)?.inflate(padding);
    if (bounds == null || bounds.isEmpty) return null;

    final scale = min(SelectionExport.scale, maxSide / bounds.longestSide);
    final width = max(1, (bounds.width * scale).ceil());
    final height = max(1, (bounds.height * scale).ceil());

    // load the images before recording, since drawing can't wait
    final images = <(EditorImage, Object)>[];
    for (final image in selection.images) {
      try {
        final drawable = await _load(image);
        if (drawable != null) images.add((image, drawable));
      } catch (_) {
        // an image that can't be loaded is left out
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = Colors.white,
      )
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);

    // images are below the strokes, as on the page
    for (final (image, drawable) in images) {
      _drawImage(canvas, image, drawable);
    }

    CanvasPainter(
      strokes: selection.strokes,
      laserStrokes: const [],
      currentStroke: null,
      currentSelection: null,
      primaryColor: Colors.black,
      page: page,
      showPageIndicator: false,
      pageIndex: selection.pageIndex,
      totalPages: 1,
      currentScale: scale,
      defaultTextStyle: const TextStyle(),
    ).paint(canvas, page.size);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    try {
      final data = await rendered.toByteData(format: .png);
      return data?.buffer.asUint8List();
    } finally {
      rendered.dispose();
      picture.dispose();
      for (final (_, drawable) in images) {
        if (drawable is ui.Image) drawable.dispose();
        if (drawable is PictureInfo) drawable.picture.dispose();
      }
    }
  }

  /// Loads [image] as a [ui.Image] or an svg [PictureInfo],
  /// or returns null for images that aren't drawn, like pdf pages.
  static Future<Object?> _load(EditorImage image) async {
    switch (image) {
      case PngEditorImage():
        final completer = Completer<ui.Image>();
        final stream = image.imageProvider.resolve(ImageConfiguration.empty);
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            if (!completer.isCompleted) completer.complete(info.image.clone());
            info.dispose();
            stream.removeListener(listener);
          },
          onError: (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
            stream.removeListener(listener);
          },
        );
        stream.addListener(listener);
        return completer.future;
      case SvgEditorImage():
        return vg.loadPicture(image.svgLoader, null);
      case PdfEditorImage():
        return null;
    }
  }

  static void _drawImage(Canvas canvas, EditorImage image, Object drawable) {
    final dst = image.dstRect;
    if (drawable is ui.Image) {
      final full = Rect.fromLTWH(
        0,
        0,
        drawable.width.toDouble(),
        drawable.height.toDouble(),
      );
      final src = image.srcRect.isEmpty ? full : image.srcRect;
      canvas.drawImageRect(drawable, src, dst, Paint()..filterQuality = .high);
    } else if (drawable is PictureInfo) {
      if (drawable.size.isEmpty) return;
      canvas
        ..save()
        ..translate(dst.left, dst.top)
        ..scale(
          dst.width / drawable.size.width,
          dst.height / drawable.size.height,
        )
        ..drawPicture(drawable.picture)
        ..restore();
    }
  }
}
