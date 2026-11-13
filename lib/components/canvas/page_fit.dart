import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:saber/data/prefs.dart';

/// "Fit page width" (LADISK fork).
///
/// Every place that needs the on-screen width of a page at 1.0x zoom goes
/// through [fittedPageWidth], so the drawn pages, scrolling and the current
/// page index always agree.

/// The width a page of [pageSize] is drawn at, at 1.0x zoom, in a canvas
/// [containerWidth] wide.
///
/// Off (upstream): the page is only scaled down, never up.
/// On: the page always fills the container width.
double fittedPageWidth(Size pageSize, double containerWidth) {
  if (stows.fitPageWidth.value && containerWidth.isFinite)
    return containerWidth;
  return min(pageSize.width, containerWidth);
}

/// The width used for page positions outside the canvas layout.
///
/// Off: the screen width, as upstream. On: the canvas width from
/// [containerBounds] when it is known, since the toolbar can sit beside
/// the canvas and a page then fills less than the screen width.
double pageAreaWidth(BuildContext context, BoxConstraints? containerBounds) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  if (!stows.fitPageWidth.value) return screenWidth;
  final width = containerBounds?.maxWidth ?? double.infinity;
  return width.isFinite ? width : screenWidth;
}

/// Scales [page] to [width] when "Fit page width" is on.
///
/// The page widget centres itself and only scales down, so it is first given
/// its own size and then scaled as a whole. Off: [page] is returned as is.
Widget fitPageToWidth({
  required Widget page,
  required Size pageSize,
  required double width,
}) {
  if (!stows.fitPageWidth.value || !width.isFinite) return page;
  return SizedBox(
    width: width,
    height: pageSize.height * width / pageSize.width,
    child: FittedBox(
      child: SizedBox.fromSize(size: pageSize, child: page),
    ),
  );
}
