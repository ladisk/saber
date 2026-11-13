import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:stow_codecs/stow_codecs.dart';

/// Fork: the List home layout, a table with one note per row.
///
/// [itemBuilder] is the same builder the grid layouts use, so the rows keep
/// the grid's selection logic (see MasonryFiles and list_note_row.dart).
/// The rows are shown in the order the table header chose.
///
/// [MasonryFiles.showFolders] is true where the notes come from several
/// folders (Recent, Search, Latest): these have a Folder column and share
/// [Stows.listSortMetric]. Browse's folder view uses
/// [Stows.browseSortMetric].
Widget listFilesSliver(
  MasonryFiles masonry,
  NullableIndexedWidgetBuilder itemBuilder,
) {
  return _ListFiles(
    files: masonry.files,
    itemBuilder: itemBuilder,
    showFolders: masonry.showFolders,
  );
}

/// The column a List layout table is sorted by.
enum ListSortColumn { name, folder, modified }

/// How the List home layout sorts its rows.
enum ListSort {
  nameAsc(.name, ascending: true),
  nameDesc(.name, ascending: false),
  folderAsc(.folder, ascending: true),
  folderDesc(.folder, ascending: false),
  modifiedAsc(.modified, ascending: true),
  modifiedDesc(.modified, ascending: false);

  new(this.column, {required this.ascending});

  final ListSortColumn column;
  final bool ascending;

  static const codec = EnumCodec(values);

  static ListSort of(ListSortColumn column, {required bool ascending}) =>
      values.firstWhere((s) => s.column == column && s.ascending == ascending);

  /// The sort after a click on the header of [clicked]: the other
  /// direction for the active column, otherwise A to Z or newest first.
  ListSort clicked(ListSortColumn clicked) => clicked == column
      ? of(column, ascending: !ascending)
      : of(clicked, ascending: clicked != .modified);

  static ListSort fromMetric(SortMetric metric) => switch (metric) {
    .nameAToZ => nameAsc,
    .nameZToA => nameDesc,
    .lastModifiedOldToNew => modifiedAsc,
    .lastModifiedNewToOld => modifiedDesc,
  };

  /// The same sort for Browse's sort button; Browse has no Folder column.
  SortMetric get metric => switch (this) {
    nameAsc || folderAsc => .nameAToZ,
    nameDesc || folderDesc => .nameZToA,
    modifiedAsc => .lastModifiedOldToNew,
    modifiedDesc => .lastModifiedNewToOld,
  };

  /// The sort chosen for a table with or without a Folder column.
  static ListSort current({required bool showFolders}) => showFolders
      ? stows.listSortMetric.value
      : fromMetric(stows.browseSortMetric.value);

  static void set(ListSort sort, {required bool showFolders}) {
    if (showFolders) {
      stows.listSortMetric.value = sort;
    } else {
      stows.browseSortMetric.value = sort.metric;
    }
  }

  static Listenable listenable({required bool showFolders}) =>
      showFolders ? stows.listSortMetric : stows.browseSortMetric;

  /// The indices of [filePaths] in this order.
  List<int> order(
    List<String> filePaths, {
    DateTime Function(String filePath)? lastModified,
  }) {
    lastModified ??= (path) =>
        FileManager.lastModified(path + Editor.extension);
    final names = [for (final path in filePaths) _nameOf(path)];
    final folders = [
      if (column == .folder)
        for (final path in filePaths) PreviewCard.folderOf(path),
    ];
    final times = [
      if (column == .modified)
        for (final path in filePaths) lastModified(path),
    ];

    int byName(int a, int b) {
      final result = compareNatural(names[a], names[b]);
      return result != 0 ? result : filePaths[a].compareTo(filePaths[b]);
    }

    final indices = List.generate(filePaths.length, (i) => i);
    indices.sort((a, b) {
      final result = switch (column) {
        .name => byName(a, b),
        .folder => compareNatural(folders[a], folders[b]),
        .modified => times[a].compareTo(times[b]),
      };
      if (result != 0) return ascending ? result : -result;
      // Ties are A to Z by name, whatever the direction.
      return byName(a, b);
    });
    return indices;
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);
}

/// Compares [a] and [b] case-insensitively, with runs of digits compared
/// as numbers, so "Week 2" comes before "Week 10".
int compareNatural(String a, String b) {
  final chunks = RegExp(r'\d+|\D+');
  final aChunks = chunks.allMatches(a.toLowerCase()).toList();
  final bChunks = chunks.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < aChunks.length && i < bChunks.length; i++) {
    final x = aChunks[i][0]!, y = bChunks[i][0]!;
    final xDigits = _isDigit(x.codeUnitAt(0));
    final yDigits = _isDigit(y.codeUnitAt(0));
    int result;
    if (xDigits && yDigits) {
      final xNumber = x.replaceFirst(RegExp('^0+(?=.)'), '');
      final yNumber = y.replaceFirst(RegExp('^0+(?=.)'), '');
      result = xNumber.length != yNumber.length
          ? xNumber.length - yNumber.length
          : xNumber.compareTo(yNumber);
      if (result == 0) result = x.length - y.length;
    } else {
      result = x.compareTo(y);
    }
    if (result != 0) return result.sign;
  }
  final result = aChunks.length - bChunks.length;
  if (result != 0) return result.sign;
  // Equal ignoring case: upper case first, so the order is stable.
  return a.compareTo(b).sign;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

class _ListFiles extends StatelessWidget {
  const new({
    required this.files,
    required this.itemBuilder,
    required this.showFolders,
  });

  final List<String> files;
  final NullableIndexedWidgetBuilder itemBuilder;
  final bool showFolders;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ListSort.listenable(showFolders: showFolders),
      builder: (context, _) {
        final sort = ListSort.current(showFolders: showFolders);
        final order = sort.order(files);
        return SliverMainAxisGroup(
          slivers: [
            if (files.isNotEmpty)
              PinnedHeaderSliver(
                child: ListTableHeader(
                  showFolders: showFolders,
                  sort: sort,
                  onSort: (column) => ListSort.set(
                    sort.clicked(column),
                    showFolders: showFolders,
                  ),
                ),
              ),
            SliverList.separated(
              itemCount: order.length,
              itemBuilder: (context, index) =>
                  itemBuilder(context, order[index]),
              separatorBuilder: (context, index) => const Divider(height: 1),
            ),
          ],
        );
      },
    );
  }
}

/// The column titles of the List layout table; a click sorts by a column.
class ListTableHeader extends StatelessWidget {
  const new({
    super.key,
    required this.showFolders,
    required this.sort,
    required this.onSort,
  });

  final bool showFolders;
  final ListSort sort;
  final ValueChanged<ListSortColumn> onSort;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Material(
      color: colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = ListColumns.of(
              constraints.maxWidth,
              showFolders: showFolders,
            );
            return Padding(
              padding: ListColumns.padding.copyWith(top: 0, bottom: 0),
              child: SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const SizedBox(
                      width: ListColumns.thumbnailWidth + ListColumns.gap,
                    ),
                    Expanded(
                      flex: ListColumns.nameFlex,
                      // English only: this fork doesn't regenerate translations.
                      child: _cell(context, .name, 'Name'),
                    ),
                    if (columns.folderColumn) ...[
                      const SizedBox(width: ListColumns.gap),
                      Expanded(
                        flex: ListColumns.folderFlex,
                        // English only: this fork doesn't regenerate translations.
                        child: _cell(context, .folder, 'Folder'),
                      ),
                    ],
                    const SizedBox(width: ListColumns.gap),
                    SizedBox(
                      width: columns.timeWidth,
                      // English only: this fork doesn't regenerate translations.
                      child: _cell(context, .modified, 'Modified'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, ListSortColumn column, String label) {
    final theme = Theme.of(context);
    final active = sort.column == column;
    final style = theme.textTheme.labelMedium?.copyWith(
      color: active
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurfaceVariant,
      fontWeight: active ? FontWeight.bold : null,
    );
    return InkWell(
      key: ValueKey('ListTableHeader${column.name}'),
      borderRadius: const .all(.circular(4)),
      onTap: () => onSort(column),
      child: Align(
        alignment: .centerLeft,
        child: Row(
          mainAxisSize: .min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: .ellipsis,
                style: style,
              ),
            ),
            if (active)
              Icon(
                sort.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                key: const ValueKey('ListTableHeaderArrow'),
                size: 14,
                color: style?.color,
              ),
          ],
        ),
      ),
    );
  }
}
