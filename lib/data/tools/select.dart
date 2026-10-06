import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

class Select extends Tool {
  new _();

  static final _currentSelect = Select._();
  static Select get currentSelect => _currentSelect;

  /// The minimum ratio of points inside a stroke or image
  /// for it to be selected.
  static const minPercentInside = 0.7;

  var selectResult = SelectResult(
    pageIndex: -1,
    strokes: const [],
    images: const [],
    path: Path(),
  );
  var doneSelecting = false;

  @override
  ToolId get toolId => .select;

  void unselect() {
    doneSelecting = false;
    resizeAnchor = null;
    selectResult.pageIndex = -1;
  }

  Color? getDominantStrokeColor() {
    if (!doneSelecting) return null;
    if (selectResult.strokes.isEmpty) return null;

    final colorDistribution = <Color, int>{};
    for (final stroke in selectResult.strokes) {
      colorDistribution.update(
        stroke.color,
        (value) => value + stroke.length,
        ifAbsent: () => stroke.length,
      );
    }
    assert(colorDistribution.isNotEmpty);

    return colorDistribution.entries.reduce((a, b) {
      return a.value > b.value ? a : b;
    }).key;
  }

  /// The radius of a resize handle, in screen pixels.
  static const handleRadius = 7.0;

  /// How far from a resize handle a touch still grabs it,
  /// in screen pixels.
  static const handleHitRadius = 24.0;

  /// The smallest side length, in page pixels, that a selection
  /// can be shrunk to.
  static const minResizeSize = 10.0;

  /// The four corners of the selection's bounding box,
  /// clockwise from the top left.
  List<Offset> get resizeHandles {
    final bounds = selectResult.path.getBounds();
    return [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];
  }

  /// Returns the index into [resizeHandles] of the handle
  /// under [position], or null if there isn't one.
  ///
  /// [scale] is the canvas zoom level, so that handles
  /// are the same size on screen regardless of zoom.
  int? resizeHandleAt(Offset position, double scale) {
    if (!doneSelecting) return null;
    final hitRadius = handleHitRadius / scale;
    final handles = resizeHandles;
    int? closest;
    var closestDistance = hitRadius;
    for (int i = 0; i < handles.length; i++) {
      final distance = (handles[i] - position).distance;
      if (distance <= closestDistance) {
        closest = i;
        closestDistance = distance;
      }
    }
    return closest;
  }

  /// The fixed corner that the selection is being scaled about,
  /// or null if the selection isn't being resized.
  Offset? resizeAnchor;

  /// The vector from [resizeAnchor] to the grabbed corner,
  /// at the start of the resize.
  var _resizeStartVector = Offset.zero;

  /// The total scale factor of the current resize so far.
  var resizeFactor = 1.0;

  /// The smallest allowed [resizeFactor],
  /// so the selection and its images don't get too small.
  var _minResizeFactor = 0.0;

  bool get isResizing => resizeAnchor != null;

  void onResizeStart(int handleIndex) {
    final handles = resizeHandles;
    resizeAnchor = handles[(handleIndex + 2) % 4];
    _resizeStartVector = handles[handleIndex] - resizeAnchor!;
    resizeFactor = 1;

    final bounds = selectResult.path.getBounds();
    _minResizeFactor = minResizeSize / bounds.shortestSide;
    for (final image in selectResult.images) {
      _minResizeFactor = max(
        _minResizeFactor,
        CanvasImage.minImageSize / image.dstRect.shortestSide,
      );
    }
  }

  /// Scales the selection so the grabbed corner follows [position],
  /// keeping the aspect ratio.
  void onResizeUpdate(Offset position) {
    final anchor = resizeAnchor!;
    final lengthSquared = _resizeStartVector.distanceSquared;
    if (lengthSquared == 0) return;

    // project the pointer onto the diagonal through the anchor
    final delta = position - anchor;
    final newFactor = max(
      _minResizeFactor,
      (delta.dx * _resizeStartVector.dx + delta.dy * _resizeStartVector.dy) /
          lengthSquared,
    );

    final step = newFactor / resizeFactor;
    scaleItems(selectResult.strokes, selectResult.images, step, anchor);
    selectResult.path = selectResult.path.scaleAbout(step, anchor);
    resizeFactor = newFactor;
  }

  /// Ends the resize and returns the total scale factor
  /// and the anchor it was applied about.
  ({double factor, Offset anchor}) onResizeEnd() {
    final result = (factor: resizeFactor, anchor: resizeAnchor!);
    resizeAnchor = null;
    resizeFactor = 1;
    return result;
  }

  /// Scales [strokes] and [images] by [factor] about [anchor].
  static void scaleItems(
    List<Stroke> strokes,
    List<EditorImage> images,
    double factor,
    Offset anchor,
  ) {
    for (final stroke in strokes) {
      stroke.scale(factor, anchor);
    }
    for (final image in images) {
      image.dstRect = image.dstRect.scaleAbout(factor, anchor);
    }
  }

  /// Mirrors the selection across its centre line
  /// and returns where that line is.
  ///
  /// Images move to their mirrored place but aren't flipped themselves.
  double mirror(Axis axis) {
    final center = selectResult.path.getBounds().center;
    final about = axis == .horizontal ? center.dx : center.dy;
    mirrorItems(selectResult.strokes, selectResult.images, axis, about);
    selectResult.path = selectResult.path.mirrorAbout(axis, about);
    return about;
  }

  /// Mirrors [strokes] and [images] across the line
  /// perpendicular to [axis] at [about].
  static void mirrorItems(
    List<Stroke> strokes,
    List<EditorImage> images,
    Axis axis,
    double about,
  ) {
    for (final stroke in strokes) {
      stroke.mirror(axis, about);
    }
    for (final image in images) {
      image.dstRect = image.dstRect.mirrorAbout(axis, about);
    }
  }

  void onDragStart(Offset position, int pageIndex) {
    doneSelecting = false;
    selectResult = SelectResult(
      pageIndex: pageIndex,
      strokes: [],
      images: [],
      path: Path(),
    );
    selectResult.path.moveTo(position.dx, position.dy);
    onDragUpdate(position);
  }

  void onDragUpdate(Offset position) {
    selectResult.path.lineTo(position.dx, position.dy);
  }

  /// Adds the indices of any [strokes] that are inside the selection area
  /// to [selectResult.indices].
  void onDragEnd(List<Stroke> strokes, List<EditorImage> images) {
    selectResult.path.close();
    doneSelecting = true;

    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final percentInside = polygonPercentInside(
        selectResult.path,
        stroke.lowQualityPolygon,
      );
      if (percentInside > minPercentInside) {
        selectResult.strokes.add(stroke);
      }
    }

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      final percentInside = rectPercentInside(selectResult.path, image.dstRect);
      if (percentInside >= minPercentInside) {
        selectResult.images.add(image);
      }
    }
  }

  static double rectPercentInside(Path selection, Rect rect) {
    const int gridSize = 5;
    final gridCellWidth = rect.width / (gridSize - 1);
    final gridCellHeight = rect.height / (gridSize - 1);

    int pointsInside = 0;
    for (int x = 0; x < gridSize; x++) {
      for (int y = 0; y < gridSize; y++) {
        if (selection.contains(
          Offset(rect.left + gridCellWidth * x, rect.top + gridCellHeight * y),
        )) {
          pointsInside++;
        }
      }
    }

    // times 1.25 because the grid is not very accurate
    return pointsInside / (gridSize * gridSize) * 1.25;
  }

  static double polygonPercentInside(Path selection, List<Offset> polygon) {
    int pointsInside = 0;
    for (final point in polygon) {
      if (selection.contains(point)) {
        pointsInside++;
      }
    }
    return pointsInside / polygon.length;
  }
}

class SelectResult {
  int pageIndex;
  final List<Stroke> strokes;
  final List<EditorImage> images;
  Path path;

  new({
    required this.pageIndex,
    required this.strokes,
    required this.images,
    required this.path,
  });

  bool get isEmpty {
    return strokes.isEmpty && images.isEmpty;
  }

  SelectResult copyWith({
    int? pageIndex,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    Path? path,
  }) {
    return SelectResult(
      pageIndex: pageIndex ?? this.pageIndex,
      strokes: strokes ?? this.strokes,
      images: images ?? this.images,
      path: path ?? this.path,
    );
  }
}
