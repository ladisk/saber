import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/theming/adaptive_icon.dart';

/// The selection bar's button that pins the selected area (LADISK fork),
/// see [NotePin](package:saber/data/editor/pin.dart).
class PinButton extends StatelessWidget {
  const new({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ColorScheme.of(context).secondary,
        backgroundColor: Colors.transparent,
        shape: const CircleBorder(),
      ),
      // English only: this fork doesn't regenerate translations.
      tooltip: 'Pin (keep this area in view)',
      icon: const AdaptiveIcon(
        icon: Icons.push_pin,
        cupertinoIcon: CupertinoIcons.pin,
      ),
    );
  }
}
