import 'dart:typed_data';

import 'package:flutter/material.dart';

extension ListExtensions<T> on List<T> {
  T? getOrNull(int index) {
    if (index < 0 || index >= length) {
      return null;
    } else {
      return this[index];
    }
  }
}

extension OffsetListExtensions on List<Offset> {
  void shift(Offset offset) {
    for (int i = 0; i < length; i++) {
      this[i] += offset;
    }
  }
}

extension OffsetListScaleExtensions on List<Offset> {
  /// Scales every point by [factor] about [anchor].
  void scaleAbout(double factor, Offset anchor) {
    for (int i = 0; i < length; i++) {
      this[i] = this[i].scaleAbout(factor, anchor);
    }
  }
}

extension OffsetScaleExtensions on Offset {
  /// Returns this point scaled by [factor] about [anchor].
  Offset scaleAbout(double factor, Offset anchor) =>
      anchor + (this - anchor) * factor;
}

extension RectScaleExtensions on Rect {
  /// Returns this rect scaled by [factor] about [anchor].
  Rect scaleAbout(double factor, Offset anchor) => .fromPoints(
    topLeft.scaleAbout(factor, anchor),
    bottomRight.scaleAbout(factor, anchor),
  );
}

extension PathScaleExtensions on Path {
  /// Returns this path scaled by [factor] about [anchor].
  Path scaleAbout(double factor, Offset anchor) {
    final matrix = Float64List(16)
      ..[0] = factor
      ..[5] = factor
      ..[10] = 1
      ..[12] = anchor.dx * (1 - factor)
      ..[13] = anchor.dy * (1 - factor)
      ..[15] = 1;
    return transform(matrix);
  }
}

/// Mirrors across the line perpendicular to [axis] at [about]:
/// [Axis.horizontal] flips left and right about the line `x = about`,
/// [Axis.vertical] flips top and bottom about the line `y = about`.
extension OffsetMirrorExtensions on Offset {
  Offset mirrorAbout(Axis axis, double about) => switch (axis) {
    .horizontal => Offset(2 * about - dx, dy),
    .vertical => Offset(dx, 2 * about - dy),
  };
}

extension RectMirrorExtensions on Rect {
  Rect mirrorAbout(Axis axis, double about) => .fromPoints(
    topLeft.mirrorAbout(axis, about),
    bottomRight.mirrorAbout(axis, about),
  );
}

extension PathMirrorExtensions on Path {
  Path mirrorAbout(Axis axis, double about) {
    final horizontal = axis == .horizontal;
    final matrix = Float64List(16)
      ..[0] = horizontal ? -1 : 1
      ..[5] = horizontal ? 1 : -1
      ..[10] = 1
      ..[12] = horizontal ? 2 * about : 0
      ..[13] = horizontal ? 0 : 2 * about
      ..[15] = 1;
    return transform(matrix);
  }
}
