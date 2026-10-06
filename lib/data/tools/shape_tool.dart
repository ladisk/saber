import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/line_type.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:sbn/has_size.dart';

/// The shapes that [ShapeTool] can draw.
///
/// The labels are English only: this fork doesn't regenerate translations.
enum ShapeKind {
  line('Line', Symbols.diagonal_line),
  rectangle('Rectangle', Symbols.crop_square),
  circle('Circle', Symbols.circle),
  sine('Sine wave', Symbols.airwave);

  new(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Draws a [ShapeKind] by dragging from one point to another.
///
/// A line goes from the start point to the pointer,
/// a rectangle has those two points as opposite corners,
/// a circle is centred on the start point,
/// and a sine wave fills the rectangle between them with [sinePeriods].
///
/// Unlike [ShapePen], nothing is recognised from freehand drawing.
/// Strokes are saved as shape pen strokes,
/// so notes stay readable by the official app.
class ShapeTool extends Pen {
  new()
    : super(
        name: 'Shapes',
        sizeMin: 1,
        sizeMax: 25,
        sizeStep: 1,
        icon: shapesIcon,
        options: stows.lastShapePenOptions.value,
        pressureEnabled: false,
        color: Color(stows.lastShapePenColor.value),
        toolId: .shapePen,
      );

  static const shapesIcon = Symbols.interests;

  static final currentShapeTool = ShapeTool();

  /// Drags shorter than this, in page pixels, don't draw anything.
  static const minDragLength = 2.0;

  /// The choices for [sinePeriods].
  static const sinePeriodOptions = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0];
  static const _sinePointsPerPeriod = 48;

  var kind = ShapeKind.line;
  var lineType = LineType.solid;
  var sinePeriods = 2.0;

  var _start = Offset.zero;
  var _end = Offset.zero;

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) => startAt(position, page, pageIndex);

  /// Starts a drag at [position] on [page].
  ///
  /// The shape is created here and then reshaped in [onDragUpdate],
  /// because the canvas keeps the [Pen.currentStroke] it saw when
  /// the drag started and only repaints it while dragging.
  @visibleForTesting
  void startAt(Offset position, HasSize page, int pageIndex) {
    _start = position;
    _end = position;
    Pen.currentStroke = switch (kind) {
      .line => Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options.copyWith(isComplete: true),
        pageIndex: pageIndex,
        page: page,
        toolId: toolId,
      ),
      .rectangle => RectangleStroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options.copyWith(),
        pageIndex: pageIndex,
        page: page,
        toolId: toolId,
        rect: .fromPoints(position, position),
      ),
      .circle => CircleStroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options.copyWith(),
        pageIndex: pageIndex,
        page: page,
        toolId: toolId,
        center: position,
        radius: 0,
      ),
      .sine => Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        // streamline would flatten the peaks
        options: options.copyWith(isComplete: true, streamline: 0)
          ..start.taperEnabled = false
          ..end.taperEnabled = false,
        pageIndex: pageIndex,
        page: page,
        toolId: toolId,
      ),
    }..lineType = lineType;
    _reshape();
  }

  @override
  void onDragUpdate(Offset position, double? pressure) {
    _end = position;
    _reshape();
  }

  @override
  Stroke? onDragEnd() {
    final stroke = Pen.currentStroke;
    Pen.currentStroke = null;
    if (stroke == null) return null;
    if ((_end - _start).distance < minDragLength) return null;
    if (stroke.isEmpty) return null;
    return stroke;
  }

  /// Fits [Pen.currentStroke] between the drag's start and end points.
  void _reshape() {
    final stroke = Pen.currentStroke;
    if (stroke == null) return;
    switch (stroke) {
      case CircleStroke():
        stroke.radius = (_end - _start).distance;
      case RectangleStroke():
        stroke.rect = .fromPoints(_start, _end);
      case Stroke() when kind == .sine:
        stroke
          ..clearPoints()
          ..addPoints(_sinePoints());
      case Stroke():
        stroke
          ..clearPoints()
          ..addPoint(_start)
          ..addPoint(_end)
          ..convertToLine();
    }
    stroke.markPolygonNeedsUpdating();
  }

  /// [sinePeriods] of a sine wave from the left of the drag's rectangle
  /// to the right, centred vertically, touching its top and bottom.
  ///
  /// It runs from [_start] to [_end], and its first hump goes the way
  /// the drag went vertically, so dragging leftwards or upwards mirrors it.
  List<Offset> _sinePoints() {
    final numPoints = (sinePeriods * _sinePointsPerPeriod).ceil();
    final middle = (_start.dy + _end.dy) / 2;
    // signed, so the first hump follows the drag
    final amplitude = (_end.dy - _start.dy) / 2;
    return [
      for (var i = 0; i <= numPoints; i++)
        Offset(
          _start.dx + (_end.dx - _start.dx) * i / numPoints,
          middle + amplitude * sin(2 * pi * sinePeriods * i / numPoints),
        ),
    ];
  }
}
