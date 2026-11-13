import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/scratch_layer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/shape_pen.dart';

/// A [SizedBox] that paints the [ScratchLayer] strokes of [page]
/// over its [child], i.e. over the page's strokes, images and text.
///
/// Only the editor's pages use this, so previews, pins and exports
/// never show scratch strokes.
class ScratchLayerView extends StatelessWidget {
  const new({
    super.key,
    required this.page,
    required this.currentScale,
    required this.width,
    required this.height,
    required this.child,
  });

  final EditorPage page;
  final double currentScale;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final invert =
        stows.editorAutoInvert.value && Theme.brightnessOf(context) == .dark;
    return CustomPaint(
      foregroundPainter: _ScratchPainter(
        page: page,
        invert: invert,
        currentScale: currentScale,
      ),
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}

class _ScratchPainter extends CustomPainter {
  new({
    required this.page,
    required this.invert,
    required this.currentScale,
  }) : super(repaint: page);

  final EditorPage page;
  final bool invert;
  final double currentScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (!ScratchLayer.shown || !ScratchLayer.hasStrokes(page)) return;

    // The page's own painter already draws the shape being recognised.
    final detectedShape = ShapePen.detectedShape;
    ShapePen.detectedShape = null;
    CanvasPainter(
      invert: invert,
      strokes: ScratchLayer.strokesOf(page),
      laserStrokes: const [],
      currentStroke: null,
      currentSelection: null,
      primaryColor: Colors.transparent,
      page: page,
      showPageIndicator: false,
      pageIndex: 0,
      totalPages: 1,
      currentScale: currentScale,
      defaultTextStyle: const TextStyle(),
    ).paint(canvas, size);
    ShapePen.detectedShape = detectedShape;
  }

  /// Strokes are added and removed in place, so always repaint.
  /// Only the scratch strokes repaint: the page is behind a repaint boundary.
  @override
  bool shouldRepaint(_ScratchPainter oldDelegate) => true;
}
