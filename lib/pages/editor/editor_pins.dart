part of 'editor.dart';

/// Pins (LADISK fork): live views of page areas in windows over the editor.
///
/// Kept out of `editor.dart` so that upstream changes to it merge
/// without conflicts. See [NotePin] and [PinLayer].
extension _EditorPins on EditorState {
  /// The pins, over the pages and under the tool palette.
  Widget _pinLayer() => Positioned.fill(
    child: PinLayer(coreInfo: coreInfo, onChanged: _onPinsChanged),
  );

  /// Pins aren't in the undo history, but are saved with the note.
  void _onPinsChanged() {
    if (coreInfo.readOnly) return;
    history.markUnsaved();
    autosaveAfterDelay();
  }

  /// Pins the area around the current selection.
  void _pinSelection() {
    if (coreInfo.readOnly) return;
    final select = currentTool;
    if (select is! Select || !select.doneSelecting) return;
    final selection = select.selectResult;
    final page = coreInfo.pages.elementAtOrNull(selection.pageIndex);
    if (page == null) return;
    final pin = NotePin.forSelection(
      selection,
      page,
      existingPins: coreInfo.visibleLadiskPins.length,
    );
    if (pin == null) return;
    coreInfo.ladiskPins.add(pin);
    _setState();
    _onPinsChanged();
  }
}
