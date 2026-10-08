import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/line_type.dart';
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

  /// Whether to select by touching elements, like an eraser,
  /// instead of drawing a lasso around them.
  var touchMode = false;

  /// Whether a [touchMode] drag is picking elements.
  ///
  /// The selection is usable while picking, because a tap
  /// only starts a drag: it never ends it.
  var isPicking = false;

  /// How far from a stroke's edge, in page pixels, a touch still hits it.
  static const touchTolerance = 10.0;

  /// The gap between touched elements and the selection outline.
  static const _touchSelectionPadding = 8.0;

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
    rotateCenter = null;
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

  /// The line type of the selected strokes, if they all share one.
  LineType? getCommonLineType() {
    if (!doneSelecting) return null;
    final lineTypes = selectResult.strokes.map((s) => s.lineType).toSet();
    return lineTypes.length == 1 ? lineTypes.single : null;
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

  /// How far above the selection the rotate handle is, in screen pixels.
  static const rotateHandleDistance = 32.0;

  /// Rotations snap to multiples of this angle.
  static const rotateStep = pi / 12;

  /// Where the rotate handle is, above the middle of the selection.
  ///
  /// [scale] is the canvas zoom level, so that the handle
  /// is the same distance away on screen regardless of zoom.
  Offset rotateHandle(double scale) =>
      selectResult.path.getBounds().topCenter -
      Offset(0, rotateHandleDistance / scale);

  /// Whether [position] is on the rotate handle.
  bool rotateHandleAt(Offset position, double scale) =>
      doneSelecting &&
      (rotateHandle(scale) - position).distance <= handleHitRadius / scale;

  /// The point the selection is being rotated about,
  /// or null if it isn't being rotated.
  Offset? rotateCenter;

  /// The total angle of the current rotation so far, in radians.
  var rotateAngle = 0.0;

  /// The pointer's direction from [rotateCenter] when the rotation started.
  var _rotateStartDirection = 0.0;

  /// The selected rectangles, keyed by the plain strokes
  /// that replace them while rotating.
  var _rotatedRectangles = <Stroke, RectangleStroke>{};

  bool get isRotating => rotateCenter != null;

  /// Starts rotating the selection with the pointer at [position].
  ///
  /// Selected rectangles are replaced in [pageStrokes] by plain strokes,
  /// because only upright rectangles can be saved.
  void onRotateStart(Offset position, List<Stroke> pageStrokes) {
    final center = rotateCenter = selectResult.path.getBounds().center;
    _rotateStartDirection = (position - center).direction;
    rotateAngle = 0;
    _rotatedRectangles = {
      for (final stroke in selectResult.strokes)
        if (stroke is RectangleStroke) stroke.toPolygonStroke(): stroke,
    };
    replaceStrokes(
      _rotatedRectangles.map((polygon, rect) => MapEntry(rect, polygon)),
      pageStrokes,
    );
  }

  /// Rotates the selection so it follows [position],
  /// in steps of [rotateStep].
  void onRotateUpdate(Offset position) {
    final center = rotateCenter!;
    if (position == center) return;
    final turned = (position - center).direction - _rotateStartDirection;
    // between -pi and pi, so the recorded angle is the shortest way round
    final angle =
        (atan2(sin(turned), cos(turned)) / rotateStep).round() * rotateStep;
    if (angle == rotateAngle) return;
    final step = angle - rotateAngle;
    rotateItems(selectResult.strokes, selectResult.images, step, center);
    selectResult.path = selectResult.path.rotateAbout(step, center);
    rotateAngle = angle;
  }

  /// Ends the rotation and returns its angle, the point it was
  /// rotated about, and the rectangles that were replaced,
  /// keyed by their replacements.
  ///
  /// Returns null if the selection ended up unrotated,
  /// putting any rectangles back into [pageStrokes].
  ({double angle, Offset center, Map<Stroke, Stroke> rectangles})?
  onRotateEnd(List<Stroke> pageStrokes) {
    final result = (
      angle: rotateAngle,
      center: rotateCenter!,
      rectangles: _rotatedRectangles,
    );
    rotateCenter = null;
    rotateAngle = 0;
    _rotatedRectangles = {};
    if (result.angle != 0) return result;
    replaceStrokes(result.rectangles, pageStrokes);
    return null;
  }

  /// Rotates [strokes] and [images] by [angle] radians about [center].
  ///
  /// Images move to their rotated place but stay upright.
  static void rotateItems(
    List<Stroke> strokes,
    List<EditorImage> images,
    double angle,
    Offset center,
  ) {
    for (final stroke in strokes) {
      stroke.rotate(angle, center);
    }
    for (final image in images) {
      image.dstRect = .fromCenter(
        center: image.dstRect.center.rotateAbout(angle, center),
        width: image.dstRect.width,
        height: image.dstRect.height,
      );
    }
  }

  /// Replaces each key of [replacements] with its value
  /// in [pageStrokes] and in the selection.
  ///
  /// The selection gets a new list, since history items
  /// may share the old one.
  void replaceStrokes(
    Map<Stroke, Stroke> replacements,
    List<Stroke> pageStrokes,
  ) {
    if (replacements.isEmpty) return;
    for (int i = 0; i < pageStrokes.length; i++) {
      pageStrokes[i] = replacements[pageStrokes[i]] ?? pageStrokes[i];
    }
    selectResult = selectResult.copyWith(
      strokes: [
        for (final stroke in selectResult.strokes)
          replacements[stroke] ?? stroke,
      ],
    );
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
    isPicking = touchMode;
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
    if (touchMode) return;
    selectResult.path.lineTo(position.dx, position.dy);
  }

  /// Adds the indices of any [strokes] that are inside the selection area
  /// to [selectResult.indices].
  void onDragEnd(List<Stroke> strokes, List<EditorImage> images) {
    selectResult.path.close();
    doneSelecting = true;

    if (touchMode) {
      isPicking = false;
      return _finishTouch();
    }

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

  /// Adds any [strokes] or [images] under [position] to the selection,
  /// like an eraser picks strokes to erase.
  /// Used in [touchMode] while dragging.
  void touchAt(
    Offset position,
    List<Stroke> strokes,
    List<EditorImage> images,
  ) {
    for (final stroke in strokes) {
      if (selectResult.strokes.contains(stroke)) continue;
      if (strokeHit(stroke, position)) selectResult.strokes.add(stroke);
    }
    // only pick images when tapping or dragging directly over them
    for (final image in images) {
      if (selectResult.images.contains(image)) continue;
      if (image.dstRect.contains(position)) selectResult.images.add(image);
    }
    if (selectResult.isEmpty) return;
    doneSelecting = true;
    _finishTouch();
  }

  /// Whether [position] is on a selected stroke or image,
  /// so a drag from there moves the selection in [touchMode].
  bool touchesSelection(Offset position) =>
      selectResult.strokes.any((stroke) => strokeHit(stroke, position)) ||
      selectResult.images.any((image) => image.dstRect.contains(position));

  /// Puts a rectangle around everything picked in [touchMode].
  void _finishTouch() {
    if (selectResult.isEmpty) return;
    final bounds = [
      for (final stroke in selectResult.strokes)
        stroke.highQualityPath.getBounds(),
      for (final image in selectResult.images) image.dstRect,
    ].reduce((a, b) => a.expandToInclude(b));
    selectResult.path = Path()..addRect(bounds.inflate(_touchSelectionPadding));
  }

  /// Whether a touch at [position] hits [stroke]:
  /// on its ink or within [touchTolerance] of it.
  /// Touches inside a circle or rectangle outline don't count.
  @visibleForTesting
  static bool strokeHit(Stroke stroke, Offset position) {
    if (stroke.isEmpty) return false;
    final polygon = stroke.highQualityPolygon;
    if (polygon.isEmpty) return false;
    if (!stroke.highQualityPath
        .getBounds()
        .inflate(touchTolerance)
        .contains(position)) {
      return false;
    }

    final isOutline = stroke is CircleStroke || stroke is RectangleStroke;
    if (!isOutline && stroke.highQualityPath.contains(position)) return true;

    // outlines are drawn centred on the polygon, so allow for their width
    final tolerance =
        touchTolerance + (isOutline ? stroke.options.size / 2 : 0);
    for (int i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if (_distanceToSegment(position, a, b) <= tolerance) return true;
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.distanceSquared;
    if (lengthSquared == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
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
