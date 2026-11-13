import 'package:material_ui/material_ui.dart';

/// Fork: the List home layout, one note per full-width row.
///
/// [itemBuilder] is the same builder the grid layouts use, so the rows keep
/// the grid's selection logic (see MasonryFiles and list_note_row.dart).
Widget listFilesSliver(
  int childCount,
  NullableIndexedWidgetBuilder itemBuilder,
) {
  return SliverList.separated(
    itemCount: childCount,
    itemBuilder: itemBuilder,
    separatorBuilder: (context, index) => const Divider(height: 1),
  );
}
