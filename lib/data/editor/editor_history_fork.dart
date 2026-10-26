part of 'editor_history.dart';

/// A change that only this fork records.
///
/// These are kept out of `editor_history.dart` so that upstream changes
/// to it merge without conflicts. They are undone by `undoFork`
/// in `editor_fork_history.dart`.
sealed class HistoricFork extends Historic {
  const new();

  /// Whether the selection stays selected after undoing this change.
  bool get keepsSelection => true;
}

/// A selection was scaled by [factor] about [anchor].
class const HistoricResize({
  required final List<Stroke> strokes,
  required final List<EditorImage> images,
  required final double factor,
  required final Offset anchor,
}) extends HistoricFork {
  @override
  HistoricResize reverse() => .new(
    strokes: strokes,
    images: images,
    factor: 1 / factor,
    anchor: anchor,
  );
}

/// A selection was mirrored along [axis] about the line at [about].
class const HistoricMirror({
  required final List<Stroke> strokes,
  required final List<EditorImage> images,
  required final Axis axis,
  required final double about,
}) extends HistoricFork {
  /// Mirroring again undoes it.
  @override
  HistoricMirror reverse() => this;
}

/// A selection on the page at [pageIndex] was rotated by [angle] radians
/// about [center].
///
/// [rectangles] maps the strokes swapped in for selected rectangles
/// to the strokes to restore on undo.
class const HistoricRotate({
  required final int pageIndex,
  required final List<Stroke> strokes,
  required final List<EditorImage> images,
  required final double angle,
  required final Offset center,
  required final Map<Stroke, Stroke> rectangles,
}) extends HistoricFork {
  /// Rotates the other way and puts the plain strokes back.
  @override
  HistoricRotate reverse() => .new(
    pageIndex: pageIndex,
    strokes: strokes,
    images: images,
    angle: -angle,
    center: center,
    rectangles: {
      for (final MapEntry(:key, :value) in rectangles.entries) value: key,
    },
  );
}

/// A selection moved from page [from] to page [to],
/// shifted by [shift] from the old page's coordinates to the new page's.
class const HistoricMoveToPage({
  required final List<Stroke> strokes,
  required final List<EditorImage> images,
  required final int from,
  required final int to,
  required final Offset shift,
}) extends HistoricFork {
  @override
  bool get keepsSelection => false;

  @override
  HistoricMoveToPage reverse() =>
      .new(strokes: strokes, images: images, from: to, to: from, shift: -shift);
}

/// Some strokes' line types were changed.
class const HistoricLineTypeChange({
  required final Map<Stroke, Change<LineType>> lineTypeChanges,
}) extends HistoricFork {
  @override
  bool get keepsSelection => false;

  @override
  HistoricLineTypeChange reverse() => .new(
    lineTypeChanges: lineTypeChanges.map(
      (key, value) => MapEntry(key, value.reverse()),
    ),
  );
}
