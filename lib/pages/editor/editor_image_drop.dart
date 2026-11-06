part of 'editor.dart';

/// Moves an image dragged onto another page to that page.
///
/// Kept out of `editor.dart` so that upstream changes to it
/// merge without conflicts.
extension _EditorImageDrop on EditorState {
  /// Moves [image], dragged from [startRect] with the pointer going from
  /// [grabbedAt] to [droppedAt], to the page it was dropped on.
  /// Returns false if it was dropped on its own page or between pages.
  bool _dropImage(
    EditorImage image,
    Rect startRect,
    Offset grabbedAt,
    Offset droppedAt,
  ) {
    if (coreInfo.readOnly) return false;
    final from = image.pageIndex;
    final to = onWhichPageIsFocalPoint(droppedAt);
    if (to == null || to == from) return false;
    final sourceBox = coreInfo.pages[from].renderBox;
    final targetBox = coreInfo.pages[to].renderBox;
    if (sourceBox == null || targetBox == null) return false;

    // keep the image under the pointer where it was grabbed
    final grab = sourceBox.globalToLocal(grabbedAt) - startRect.topLeft;
    final dropped = targetBox.globalToLocal(droppedAt) - grab;

    // like a drag on one page, keep at least 5% of the image on the page
    final pageSize = coreInfo.pages[to].size;
    final fivePercent = min(pageSize.width * 0.05, pageSize.height * 0.05);
    final topLeft = Offset(
      dropped.dx.clamp(
        fivePercent - startRect.width,
        pageSize.width - fivePercent,
      ),
      dropped.dy.clamp(
        fivePercent - startRect.height,
        pageSize.height - fivePercent,
      ),
    );
    final shift = topLeft - startRect.topLeft;

    final select = Select.currentSelect;
    if (select.selectResult.images.contains(image)) select.unselect();

    image
      ..dstRect = startRect
      // keeps the image active (draggable) on its new page
      ..newImage = true;
    transferItems(const [], [image], from, to, shift);
    _setState();
    history.recordChange(
      HistoricMoveToPage(
        strokes: const [],
        images: [image],
        from: from,
        to: to,
        shift: shift,
      ),
    );
    autosaveAfterDelay();
    return true;
  }
}
