import 'dart:math';
import 'dart:ui';

/// Which ends of a line stroke get an arrowhead.
///
/// Saved only when not [none], so the official app
/// shows these strokes as plain lines.
enum Arrowheads {
  none,
  end,
  both;

  static Arrowheads fromJson(Object? name) => values.asNameMap()[name] ?? .none;

  static double _headLength(double strokeSize) => max(strokeSize * 3, 10.0);

  /// How far into a head its line stops: far enough that the line's
  /// square end is hidden, as the head is wider than the line there.
  static const _shaftOverlap = 0.6;

  /// The filled triangles for a line from [start] to [end]
  /// drawn [strokeSize] wide, with their tips on the line's ends.
  List<List<Offset>> triangles(Offset start, Offset end, double strokeSize) {
    if (this == none) return const [];
    final line = end - start;
    if (line.distance == 0) return const [];
    final direction = line / line.distance;
    final length = _headLength(strokeSize);
    final halfWidth = length * 0.45;

    List<Offset> head(Offset tip, Offset forwards) {
      final across = Offset(-forwards.dy, forwards.dx) * halfWidth;
      final base = tip - forwards * length;
      return [tip, base + across, base - across];
    }

    return [head(end, direction), if (this == both) head(start, -direction)];
  }

  /// The line from [start] to [end], shortened to end inside its heads,
  /// so its ends don't poke out past the tips.
  List<Offset> shaft(Offset start, Offset end, double strokeSize) {
    final line = end - start;
    if (this == none || line.distance == 0) return [start, end];
    final direction = line / line.distance;
    final heads = this == both ? 2 : 1;
    final trim = min(
      _headLength(strokeSize) * _shaftOverlap,
      line.distance / (heads + 1),
    );
    return [
      if (this == both) start + direction * trim else start,
      end - direction * trim,
    ];
  }
}
