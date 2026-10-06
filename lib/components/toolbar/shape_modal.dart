import 'package:flutter/material.dart';
import 'package:saber/components/canvas/line_type.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/shape_tool.dart';

/// The options row for [ShapeTool]: its size,
/// which [ShapeKind] to draw, and its [LineType].
class ShapeModal extends StatefulWidget {
  const new({super.key});

  @override
  State<ShapeModal> createState() => _ShapeModalState();
}

class _ShapeModalState extends State<ShapeModal> {
  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final tool = ShapeTool.currentShapeTool;

    return Flex(
      direction: axis,
      mainAxisAlignment: .center,
      children: [
        SizePicker(axis: axis, pen: tool),
        for (final kind in ShapeKind.values) ...[
          const SizedBox.square(dimension: 8),
          _OptionButton(
            selected: tool.kind == kind,
            onPressed: () => setState(() => tool.kind = kind),
            tooltip: kind.label,
            icon: kind.icon,
          ),
        ],
        const SizedBox.square(dimension: 24),
        for (final lineType in LineType.values) ...[
          const SizedBox.square(dimension: 8),
          _OptionButton(
            selected: tool.lineType == lineType,
            onPressed: () => setState(() => tool.lineType = lineType),
            tooltip: lineType.label,
            icon: lineType.icon,
          ),
        ],
      ],
    );
  }
}

class _OptionButton extends StatelessWidget {
  const new({
    required this.selected,
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final bool selected;
  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return IconButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? colorScheme.secondary
            : colorScheme.onSurface,
        backgroundColor: selected
            ? colorScheme.secondary.withValues(alpha: 0.1)
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      tooltip: tooltip,
      icon: Icon(icon),
    );
  }
}
