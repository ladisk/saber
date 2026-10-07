import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The LADISK logo, fixed in the bottom left corner of the editor.
///
/// It stays put while the page is scrolled or zoomed, and lets touches
/// through to the page underneath.
class LadiskLogo extends StatelessWidget {
  const new({super.key, this.height = 64});

  final double height;

  static const assetName = 'assets/images/ladisk_logo.svg';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Widget logo = SvgPicture.asset(
      assetName,
      height: height,
      semanticsLabel: 'LADISK',
    );
    return Positioned(
      left: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SafeArea(
          top: false,
          right: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            // the logo's grey text needs a light background in dark mode
            child: dark
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: logo,
                    ),
                  )
                : logo,
          ),
        ),
      ),
    );
  }
}
