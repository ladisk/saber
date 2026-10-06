import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// How a stroke's line is broken up: solid, dashed, dotted or centerline.
///
/// The labels are English only: this fork doesn't regenerate translations.
enum LineType {
  solid('Solid', Symbols.horizontal_rule, []),
  dashed('Dashed', Symbols.line_style, [6, 4]),
  dotted('Dotted', Symbols.more_horiz, [0, 2.5]),
  centerline('Centerline', Symbols.linear_scale, [12, 3, 2, 3]);

  new(this.label, this.icon, this.pattern);

  final String label;
  final IconData icon;

  /// Alternating dash and gap lengths, in multiples of the stroke size.
  ///
  /// A zero-length dash is drawn as a dot by the round line cap.
  final List<double> pattern;

  /// Dashes for thin strokes are sized as if the stroke had this size,
  /// so the pattern stays visible.
  static const _minPatternUnit = 2.0;

  /// [pattern] in page pixels for a stroke of [strokeSize].
  List<double> intervals(double strokeSize) {
    final unit = max(strokeSize, _minPatternUnit);
    return [
      // Skia drops zero-length dashes, so make them tiny instead.
      for (final length in pattern) max(length * unit, 0.01),
    ];
  }

  StrokeCap get cap => this == dotted ? .round : .butt;

  static LineType fromJson(Object? name) => values.asNameMap()[name] ?? .solid;
}
