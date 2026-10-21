import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:onenote_import/onenote_import.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:sbn/tool_id.dart';

/// A decoded image of a OneNote page.
typedef OneNoteImageData = ({Uint8List bytes, String extension, Size size});

/// Puts the contents of OneNote pages onto Saber pages.
///
/// A OneNote page is one long canvas, so it is split into
/// pages of [EditorPage.defaultSize], preferably where nothing is drawn.
abstract final class OneNoteLayout {
  /// Saber units per OneNote pixel: an A4 page (794 px at 96 dpi)
  /// is as wide as a Saber page.
  static const scale = EditorPage.defaultWidth / 793.7;

  /// The empty space around the content of each page.
  static const margin = 40.0;

  /// A page break is moved up to at most this fraction of a page
  /// to avoid cutting through a stroke or image.
  static const maxBreakShift = 0.4;

  /// Points closer than this to the previous point are dropped,
  /// because OneNote stores many more points than Saber needs.
  static const minPointDistance = 0.4;

  /// Adds the contents of [page] to [coreInfo] as one or more pages.
  ///
  /// [images] maps [OneNoteImage.path] to the image data.
  /// Images missing from [images] are skipped.
  static void addPage(
    EditorCoreInfo coreInfo,
    OneNotePage page,
    Map<String, OneNoteImageData> images,
  ) {
    final items = <_Item>[
      for (final stroke in page.strokes)
        if (stroke.points.length >= 2) _Item.stroke(stroke),
      for (final image in page.images)
        if (images[image.path] case final data?) _Item.image(image, data),
    ];
    if (items.isEmpty) return;

    final left = items.map((item) => item.bounds.left).reduce(min);
    final right = items.map((item) => item.bounds.right).reduce(max);
    final top = items.map((item) => item.bounds.top).reduce(min);

    // Wide content gets wider pages instead of being shrunk.
    final width = max(
      EditorPage.defaultWidth,
      (right - left) * scale + 2 * margin,
    );
    final pageSize = Size(
      width,
      width * EditorPage.defaultHeight / EditorPage.defaultWidth,
    );
    final usableHeight = (pageSize.height - 2 * margin) / scale;

    items.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
    var pageTop = top;
    var i = 0;
    while (i < items.length) {
      final pageBottom = _findPageBreak(items, pageTop, usableHeight);
      final onThisPage = <_Item>[];
      while (i < items.length &&
          (items[i].bounds.top < pageBottom || onThisPage.isEmpty)) {
        onThisPage.add(items[i]);
        i++;
      }

      final offset = Offset(-left * scale + margin, -pageTop * scale + margin);
      _addSaberPage(coreInfo, pageSize, onThisPage, offset);
      if (i < items.length) pageTop = items[i].bounds.top;
    }
  }

  /// Returns where the page starting at [pageTop] should end,
  /// moved up if it would cut through an item.
  static double _findPageBreak(
    List<_Item> items,
    double pageTop,
    double usableHeight,
  ) {
    final idealBreak = pageTop + usableHeight;
    final earliestBreak = pageTop + usableHeight * (1 - maxBreakShift);
    var pageBreak = idealBreak;
    while (true) {
      final cut = items.where(
        (item) => item.bounds.top < pageBreak && item.bounds.bottom > pageBreak,
      );
      if (cut.isEmpty) return pageBreak;
      final above = cut.map((item) => item.bounds.top).reduce(min);
      if (above <= earliestBreak) return idealBreak;
      pageBreak = above;
    }
  }

  static void _addSaberPage(
    EditorCoreInfo coreInfo,
    Size pageSize,
    List<_Item> items,
    Offset offset,
  ) {
    final pageIndex = coreInfo.pages.length;
    final page = EditorPage(size: pageSize);
    coreInfo.pages.add(page);

    for (final item in items) {
      if (item.stroke case final stroke?) {
        page.strokes.add(_convertStroke(stroke, page, pageIndex, offset));
      } else if (item.image case final image?) {
        page.images.add(
          _convertImage(coreInfo, image, item.imageData!, pageIndex, offset),
        );
      }
    }
  }

  static Stroke _convertStroke(
    OneNoteStroke stroke,
    EditorPage page,
    int pageIndex,
    Offset offset,
  ) {
    final highlighter = stroke.isHighlighter;
    final saberStroke = Stroke(
      color: Color.fromARGB(
        highlighter ? Highlighter.alpha : 255,
        stroke.rgb[0],
        stroke.rgb[1],
        stroke.rgb[2],
      ),
      pressureEnabled: false,
      options: Pen.ballpointPenOptions.copyWith(
        size: max(stroke.width * scale, 1),
        isComplete: true,
      ),
      pageIndex: pageIndex,
      page: page,
      toolId: highlighter ? ToolId.highlighter : ToolId.ballpointPen,
    );

    final points = stroke.points;
    Offset? previous;
    for (var i = 0; i + 1 < points.length; i += 2) {
      final point = Offset(points[i], points[i + 1]) * scale + offset;
      final isLast = i + 2 >= points.length;
      if (previous != null &&
          !isLast &&
          (point - previous).distance < minPointDistance) {
        continue;
      }
      saberStroke.addPoint(point);
      previous = point;
    }
    return saberStroke;
  }

  static EditorImage _convertImage(
    EditorCoreInfo coreInfo,
    OneNoteImage image,
    OneNoteImageData data,
    int pageIndex,
    Offset offset,
  ) {
    final size = _imageSize(image, data) * scale;
    final topLeft = Offset(image.x, image.y) * scale + offset;
    return PngEditorImage(
      id: coreInfo.nextImageId++,
      assetCache: coreInfo.assetCache,
      extension: data.extension,
      imageProvider: MemoryImage(data.bytes),
      pageIndex: pageIndex,
      pageSize: .infinite,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      newImage: false,
      dstRect: topLeft & size,
      srcRect: Offset.zero & data.size,
      naturalSize: data.size,
    );
  }

  /// The size of [image] in OneNote pixels.
  static Size _imageSize(OneNoteImage image, OneNoteImageData data) {
    final natural = data.size;
    if (image.width > 0 && image.height > 0) {
      return Size(image.width, image.height);
    } else if (image.width > 0) {
      return Size(image.width, image.width * natural.height / natural.width);
    } else if (image.height > 0) {
      return Size(image.height * natural.width / natural.height, image.height);
    } else {
      return natural;
    }
  }
}

/// A stroke or image, with its bounds in OneNote pixels.
class _Item {
  new stroke(OneNoteStroke this.stroke)
    : image = null,
      imageData = null,
      bounds = _strokeBounds(stroke);

  new image(OneNoteImage this.image, OneNoteImageData this.imageData)
    : stroke = null,
      bounds =
          Offset(image.x, image.y) & OneNoteLayout._imageSize(image, imageData);

  final OneNoteStroke? stroke;
  final OneNoteImage? image;
  final OneNoteImageData? imageData;
  final Rect bounds;

  static Rect _strokeBounds(OneNoteStroke stroke) {
    final points = stroke.points;
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (var i = 0; i + 1 < points.length; i += 2) {
      left = min(left, points[i]);
      right = max(right, points[i]);
      top = min(top, points[i + 1]);
      bottom = max(bottom, points[i + 1]);
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(stroke.width / 2);
  }
}
