import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/pins/pin_view.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/pin.dart';

/// The pins of a note (LADISK fork), each in a window fixed over the
/// editor while the pages scroll and zoom underneath.
///
/// Drag a window by its top strip and resize it by its bottom right corner;
/// the cross closes it. Touches on a window never reach the page.
/// Place it in a [Stack] over the canvas, filling it.
class PinLayer extends StatefulWidget {
  const new({super.key, required this.coreInfo, required this.onChanged});

  final EditorCoreInfo coreInfo;

  /// Called after a pin was moved, resized or closed, to save the note.
  final VoidCallback onChanged;

  @override
  State<PinLayer> createState() => _PinLayerState();
}

class _PinLayerState extends State<PinLayer> {
  void _close(NotePin pin) {
    setState(() => widget.coreInfo.ladiskPins.remove(pin));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        if (!area.isFinite || area.isEmpty) return const SizedBox.shrink();
        return Stack(
          children: [
            for (final pin in widget.coreInfo.visibleLadiskPins)
              PinWindow(
                key: ObjectKey(pin),
                pin: pin,
                coreInfo: widget.coreInfo,
                area: area,
                onChanged: widget.onChanged,
                onClose: () => _close(pin),
              ),
          ],
        );
      },
    );
  }
}

/// One pin's window, positioned in an editor of size [area].
class PinWindow extends StatefulWidget {
  const new({
    super.key,
    required this.pin,
    required this.coreInfo,
    required this.area,
    required this.onChanged,
    required this.onClose,
  });

  final NotePin pin;
  final EditorCoreInfo coreInfo;
  final Size area;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  /// The height of the strip with the grip and the cross.
  static const stripHeight = 28.0;

  /// The size of the resize handle in the bottom right corner.
  static const handleSize = 28.0;

  /// The narrowest a window gets, unless the editor is narrower.
  static const minWidth = 96.0;

  /// The window's rectangle in the editor, kept on screen.
  static Rect frameOf(NotePin pin, Size area) {
    final aspect = pin.rect.height / pin.rect.width;
    final maxWidth = max(
      0.0,
      min(area.width, (area.height - stripHeight) / aspect),
    );
    final width = (pin.width * area.width)
        .clamp(min(minWidth, maxWidth), maxWidth)
        .toDouble();
    final height = width * aspect + stripHeight;
    return Rect.fromLTWH(
      (pin.x * area.width).clamp(0.0, max(0.0, area.width - width)).toDouble(),
      (pin.y * area.height)
          .clamp(0.0, max(0.0, area.height - height))
          .toDouble(),
      width,
      height,
    );
  }

  @override
  State<PinWindow> createState() => _PinWindowState();
}

class _PinWindowState extends State<PinWindow> {
  NotePin get pin => widget.pin;
  Size get area => widget.area;

  void _move(DragUpdateDetails details) {
    final frame = PinWindow.frameOf(pin, area);
    setState(() {
      pin.x = (frame.left + details.delta.dx) / area.width;
      pin.y = (frame.top + details.delta.dy) / area.height;
      // store the position it is shown at, not one off screen
      final moved = PinWindow.frameOf(pin, area);
      pin.x = moved.left / area.width;
      pin.y = moved.top / area.height;
    });
  }

  void _resize(DragUpdateDetails details) {
    final frame = PinWindow.frameOf(pin, area);
    final aspect = pin.rect.height / pin.rect.width;
    // follow whichever direction the corner was dragged further
    final byHeight = details.delta.dy / aspect;
    final grow = details.delta.dx.abs() >= byHeight.abs()
        ? details.delta.dx
        : byHeight;
    setState(() {
      pin.width = (frame.width + grow) / area.width;
      final resized = PinWindow.frameOf(pin, area);
      pin.width = resized.width / area.width;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final frame = PinWindow.frameOf(pin, area);

    return Positioned.fromRect(
      rect: frame,
      // don't let touches fall through to the page
      child: Listener(
        behavior: .opaque,
        child: Material(
          elevation: 3,
          color: colorScheme.surfaceContainer.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: .circular(12),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: .antiAlias,
          child: Column(
            children: [
              GestureDetector(
                behavior: .opaque,
                onPanUpdate: _move,
                onPanEnd: (_) => widget.onChanged(),
                child: SizedBox(
                  height: PinWindow.stripHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: 6),
                      Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: widget.onClose,
                        // English only: this fork doesn't regenerate translations.
                        tooltip: 'Close pin',
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: .compact,
                        padding: .zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  fit: .expand,
                  children: [
                    IgnorePointer(
                      child: PinView(
                        coreInfo: widget.coreInfo,
                        pin: pin,
                        scale: frame.width / pin.rect.width,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: PinWindow.handleSize,
                      height: PinWindow.handleSize,
                      child: GestureDetector(
                        behavior: .opaque,
                        onPanUpdate: _resize,
                        onPanEnd: (_) => widget.onChanged(),
                        child: Tooltip(
                          // English only: this fork doesn't regenerate translations.
                          message: 'Resize',
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainer.withValues(
                                alpha: 0.8,
                              ),
                              borderRadius: const .only(topLeft: .circular(8)),
                            ),
                            // arrows from top left to bottom right
                            child: RotatedBox(
                              quarterTurns: 1,
                              child: Icon(
                                Icons.open_in_full,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
