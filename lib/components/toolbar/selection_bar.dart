import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/line_type.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;
  final ValueChanged<Axis> mirrorSelection;
  final ValueChanged<LineType> setLineType;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.mirrorSelection,
    required this.setLineType,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final commonLineType = Select.currentSelect.getCommonLineType();
    return Row(
      mainAxisAlignment: .center,
      children: [
        IconButton(
          onPressed: duplicateSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.duplicate,
          icon: const AdaptiveIcon(
            icon: Icons.content_copy,
            cupertinoIcon: CupertinoIcons.doc_on_clipboard,
          ),
        ),
        IconButton(
          onPressed: deleteSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.delete,
          icon: const AdaptiveIcon(
            icon: Icons.delete,
            cupertinoIcon: CupertinoIcons.delete,
          ),
        ),
        // English only: this fork doesn't regenerate translations.
        IconButton(
          onPressed: () => mirrorSelection(.horizontal),
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: 'Mirror horizontally',
          icon: const Icon(Icons.flip),
        ),
        IconButton(
          onPressed: () => mirrorSelection(.vertical),
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: 'Mirror vertically',
          icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
        ),
        const SizedBox(width: 16),
        for (final lineType in LineType.values)
          IconButton(
            onPressed: () => setLineType(lineType),
            style: TextButton.styleFrom(
              foregroundColor: lineType == commonLineType
                  ? colorScheme.secondary
                  : colorScheme.onSurface,
              backgroundColor: lineType == commonLineType
                  ? colorScheme.secondary.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: const CircleBorder(),
            ),
            tooltip: lineType.label,
            icon: Icon(lineType.icon),
          ),
      ],
    );
  }
}
