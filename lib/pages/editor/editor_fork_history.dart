import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';

/// Undoes the changes that only this fork records.
///
/// Kept out of `editor.dart` so that upstream changes to
/// [EditorState.undo] merge without conflicts.
extension EditorForkHistory on EditorState {
  void undoFork(HistoricFork historic) {
    switch (historic) {
      case (final HistoricResize historic):
        Select.scaleItems(
          historic.strokes,
          historic.images,
          1 / historic.factor,
          historic.anchor,
        );
        final select = Select.currentSelect;
        if (select.doneSelecting) {
          select.selectResult.path = select.selectResult.path.scaleAbout(
            1 / historic.factor,
            historic.anchor,
          );
        }

      case (final HistoricMirror historic):
        // mirroring again undoes it
        Select.mirrorItems(
          historic.strokes,
          historic.images,
          historic.axis,
          historic.about,
        );
        final select = Select.currentSelect;
        if (select.doneSelecting) {
          select.selectResult.path = select.selectResult.path.mirrorAbout(
            historic.axis,
            historic.about,
          );
        }

      case (final HistoricRotate historic):
        Select.rotateItems(
          historic.strokes,
          historic.images,
          -historic.angle,
          historic.center,
        );
        final select = Select.currentSelect;
        if (select.doneSelecting) {
          select.selectResult.path = select.selectResult.path.rotateAbout(
            -historic.angle,
            historic.center,
          );
        }
        select.replaceStrokes(
          historic.rectangles,
          coreInfo.pages[historic.pageIndex].strokes,
        );

      case (final HistoricMoveToPage historic):
        transferItems(
          historic.strokes,
          historic.images,
          historic.to,
          historic.from,
          -historic.shift,
        );

      case (final HistoricLineTypeChange historic):
        for (final MapEntry(key: stroke, value: change)
            in historic.lineTypeChanges.entries) {
          stroke.lineType = change.previous;
        }
    }
  }
}
