import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';

/// One button on the [ToolPalette].
class ToolPaletteItem {
  const new({
    required this.icon,
    required this.tooltip,
    required this.onSelected,
    this.selected = false,
    this.isColor = false,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback onSelected;
  final bool selected;

  /// Color buttons are drawn smaller, with a ring when selected.
  final bool isColor;
}

/// A small panel of tools and colors that floats over the canvas.
///
/// Drag the grip to move it; tap the grip to turn it
/// between horizontal and vertical. The cross hides it.
/// Its position is saved as a fraction of the canvas area.
class ToolPalette extends StatefulWidget {
  const new({super.key, required this.rows, required this.onClose});

  /// Rows of button groups, with a small gap between groups.
  /// When the palette is vertical, rows become columns.
  final List<List<List<ToolPaletteItem>>> rows;
  final VoidCallback onClose;

  static const toolSize = 34.0;
  static const colorSize = 28.0;
  static const _gripSize = 26.0;

  @override
  State<ToolPalette> createState() => _ToolPaletteState();
}

class _ToolPaletteState extends State<ToolPalette> {
  final _paletteKey = GlobalKey();

  void _drag(DragUpdateDetails details, Size areaSize) {
    final paletteSize = _paletteKey.currentContext?.size;
    if (paletteSize == null) return;
    final freeWidth = areaSize.width - paletteSize.width;
    final freeHeight = areaSize.height - paletteSize.height;
    setState(() {
      if (freeWidth > 0) {
        stows.toolPaletteX.value =
            (stows.toolPaletteX.value + details.delta.dx / freeWidth).clamp(
              0.0,
              1.0,
            );
      }
      if (freeHeight > 0) {
        stows.toolPaletteY.value =
            (stows.toolPaletteY.value + details.delta.dy / freeHeight).clamp(
              0.0,
              1.0,
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final vertical = stows.toolPaletteVertical.value;
    final Axis direction = vertical ? .vertical : .horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final grip = GestureDetector(
          behavior: .opaque,
          onPanUpdate: (details) => _drag(details, constraints.biggest),
          onTap: () => setState(() {
            stows.toolPaletteVertical.value = !vertical;
          }),
          child: SizedBox.square(
            dimension: ToolPalette._gripSize,
            child: Icon(
              vertical ? Icons.drag_handle : Icons.drag_indicator,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        );
        final close = IconButton(
          onPressed: widget.onClose,
          // English only: this fork doesn't regenerate translations.
          tooltip: 'Hide (show again from the ⋮ menu)',
          icon: const Icon(Icons.close, size: 16),
          visualDensity: .compact,
          padding: .zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        );

        return Align(
          alignment: Alignment(
            stows.toolPaletteX.value * 2 - 1,
            stows.toolPaletteY.value * 2 - 1,
          ),
          // shrinks on screens too small for it
          child: FittedBox(
            key: _paletteKey,
            fit: .scaleDown,
            child: Material(
              elevation: 3,
              color: colorScheme.surfaceContainer.withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(borderRadius: .circular(18)),
              child: Padding(
                padding: const .all(2),
                child: Flex(
                  direction: direction == .horizontal ? .vertical : .horizontal,
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    for (final (index, row) in widget.rows.indexed)
                      Flex(
                        direction: direction,
                        mainAxisSize: .min,
                        children: [
                          if (index == 0)
                            grip
                          else
                            const SizedBox.square(
                              dimension: ToolPalette._gripSize,
                            ),
                          for (final (index, group) in row.indexed) ...[
                            if (index > 0) const SizedBox.square(dimension: 6),
                            for (final item in group)
                              SizedBox.square(
                                dimension: item.isColor
                                    ? ToolPalette.colorSize
                                    : ToolPalette.toolSize,
                                child: _Button(item: item),
                              ),
                          ],
                          if (index == 0) close,
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Button extends StatelessWidget {
  const new({required this.item});

  final ToolPaletteItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Tooltip(
      message: item.tooltip,
      child: Material(
        shape: CircleBorder(
          side: item.selected && item.isColor
              ? BorderSide(color: colorScheme.primary, width: 3)
              : BorderSide.none,
        ),
        color: item.selected && !item.isColor
            ? colorScheme.primaryContainer
            : Colors.transparent,
        clipBehavior: .antiAlias,
        child: InkWell(
          onTap: item.onSelected,
          child: IconTheme.merge(
            data: IconThemeData(color: colorScheme.onSurface, size: 20),
            child: Center(child: item.icon),
          ),
        ),
      ),
    );
  }
}
