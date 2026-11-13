part of 'editor.dart';

/// The scratch layer (LADISK fork): see [ScratchLayer].
///
/// Kept out of `editor.dart` so that upstream changes to it merge
/// without conflicts.
extension EditorScratch on EditorState {
  static final _layers = Expando<ScratchLayer>('scratch layer');

  /// This editor's scratch layer, off when the note is opened.
  ScratchLayer get scratch => _layers[this] ??= (ScratchLayer()..isOn = false);

  bool get hasScratchStrokes => coreInfo.pages.any(ScratchLayer.hasStrokes);

  void setScratchMode(bool isOn) {
    if (scratch.isOn == isOn) return;
    scratch.isOn = isOn;
    // Turning the layer off hides its strokes until it is turned on again.
    for (final page in coreInfo.pages) {
      if (ScratchLayer.hasStrokes(page)) page.redrawStrokes();
    }
    _setState();
  }

  /// Puts a finished pen stroke on the scratch layer of [page].
  void _addScratchStroke(EditorPage page, Stroke stroke) {
    ScratchLayer.strokesOf(page).add(stroke);
    history.recordChange(
      HistoricScratch(strokes: [(page, stroke)], added: true),
    );
    page.redrawStrokes();
  }

  /// Erases the scratch strokes of [page] under the eraser at [position].
  void _eraseScratch(Offset position, EditorPage page) {
    final strokes = ScratchLayer.strokesOf(page);
    final erased = (currentTool as Eraser).checkForOverlappingStrokes(
      position,
      strokes,
    );
    if (erased.isEmpty) return;
    for (final stroke in erased) {
      strokes.remove(stroke);
    }
    page.redrawStrokes();
  }

  /// Records the scratch strokes erased during one drag.
  void _recordScratchErase(EditorPage page, List<Stroke> erased) {
    history.recordChange(
      HistoricScratch(
        strokes: [for (final stroke in erased) (page, stroke)],
        added: false,
      ),
    );
  }

  /// Removes all scratch strokes on all pages.
  /// This can't be undone, and drawing them can't be redone afterwards.
  void clearScratch() {
    ScratchLayer.clear(coreInfo.pages);
    history.removeScratchHistory();
    _setState();
  }

  // English only: this fork doesn't regenerate translations.
  ToolPaletteGroup _scratchPaletteGroup() => ToolPaletteGroup(divided: true, [
    ToolPaletteItem(
      icon: const Icon(Symbols.layers),
      tooltip: scratch.isOn
          ? 'Scratch layer: on (drawing is not saved)'
          : hasScratchStrokes
          ? 'Scratch layer: hidden'
          : 'Scratch layer',
      selected: scratch.isOn,
      onSelected: () => setScratchMode(!scratch.isOn),
    ),
    ToolPaletteItem(
      icon: const Icon(Symbols.layers_clear),
      tooltip: 'Clear scratch',
      enabled: hasScratchStrokes,
      onSelected: clearScratch,
    ),
  ]);

  /// A frame around the pages while drawing goes on the scratch layer.
  Widget _scratchFrame() {
    if (!scratch.isOn) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: ColorScheme.of(context).tertiary,
              width: 4,
            ),
          ),
        ),
      ),
    );
  }
}
