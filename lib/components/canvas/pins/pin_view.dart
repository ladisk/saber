import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/pin.dart';

/// A live view of a pin's area of its page (LADISK fork), filling its box.
///
/// It draws the page with [InnerCanvas], the same widget as the editor,
/// so strokes, images, text, the background and dark mode look the same.
/// Strokes redraw with the page; text follows it shortly after typing.
///
/// The page's text editor can't be shown in two places, so the view
/// draws a copy of the page that shares its strokes and images
/// but has its own copy of the text.
class PinView extends StatefulWidget {
  const new({
    super.key,
    required this.coreInfo,
    required this.pin,
    required this.scale,
  });

  final EditorCoreInfo coreInfo;
  final NotePin pin;

  /// Screen pixels per page unit, to pick the stroke quality.
  final double scale;

  /// How long typing pauses before the view shows the new text.
  static const textDelay = Duration(milliseconds: 300);

  @override
  State<PinView> createState() => _PinViewState();
}

class _PinViewState extends State<PinView> {
  /// The copy of the page that is drawn.
  EditorPage? _copy;

  EditorPage get page => widget.pin.page;

  Timer? _textTimer;

  @override
  void initState() {
    super.initState();
    page.quill.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(PinView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pin.page != page) {
      oldWidget.pin.page.quill.controller.removeListener(_onTextChanged);
      page.quill.controller.addListener(_onTextChanged);
      _dropCopy();
    }
  }

  void _onTextChanged() {
    _textTimer?.cancel();
    _textTimer = Timer(PinView.textDelay, () {
      if (mounted) setState(_dropCopy);
    });
  }

  /// Makes [build] copy the page again, and frees the old copy
  /// once nothing draws it.
  void _dropCopy() {
    final old = _copy;
    _copy = null;
    if (old == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => old.disposeClonedData(),
    );
  }

  EditorPage _pageCopy() {
    final copy = _copy;
    if (copy != null && copy.backgroundImage == page.backgroundImage) {
      return copy;
    }
    _dropCopy();
    return _copy = page.copyWith(quill: page.quill.cloneForScreenshot());
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    page.quill.controller.removeListener(_onTextChanged);
    _copy?.disposeClonedData();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _pageCopy();
    final rect = widget.pin.rect;
    final coreInfo = widget.coreInfo.copyWith(
      pages: [copy],
      readOnlyReason: .placeholder,
    );

    return FittedBox(
      fit: .fill,
      alignment: .topLeft,
      child: SizedBox.fromSize(
        size: rect.size,
        child: Stack(
          clipBehavior: .hardEdge,
          children: [
            Positioned(
              left: -rect.left,
              top: -rect.top,
              width: copy.size.width,
              height: copy.size.height,
              child: InnerCanvas(
                key: ObjectKey(copy),
                pageIndex: 0,
                redrawPageListenable: page,
                width: copy.size.width,
                height: copy.size.height,
                showPageIndicator: false,
                coreInfo: coreInfo,
                currentStroke: null,
                currentStrokeDetectedShape: null,
                currentSelection: null,
                currentToolIsSelect: false,
                currentScale: widget.scale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
