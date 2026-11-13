import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/delete_folder_button.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/home/list_files.dart';
import 'package:saber/components/home/new_folder_dialog.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/components/home/rename_folder_button.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

extension GridFoldersListLayout on GridFolders {
  /// Fork: these folders as rows when the List home layout is chosen,
  /// otherwise the grid itself.
  Widget get orListLayout =>
      stows.homeLayout.value == .list ? ListFolders(grid: this) : this;
}

/// Fork: the folders of the List home layout, one per row.
///
/// Takes its folders and callbacks from [grid], so the "go up" and
/// new folder rows and the rename, move and delete actions work the same.
/// The folders are sorted by name, in the direction of the table's Name
/// column when that is the active one, otherwise A to Z.
class ListFolders extends StatelessWidget {
  const new({super.key, required this.grid});

  final GridFolders grid;

  /// [folders] in the order shown for [sort].
  static List<String> sorted(List<String> folders, SortMetric sort) {
    final descending = sort == .nameZToA;
    return [...folders]..sort((a, b) {
      final result = compareNatural(a, b);
      return descending ? -result : result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stows.browseSortMetric,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return SliverPadding(
      padding: const .symmetric(horizontal: 16, vertical: 4),
      sliver: SliverList.list(
        children: [
          if (!grid.isAtRoot)
            _ListFolderRow(
              key: const ValueKey('ListFolderRow..'),
              icon: Icons.folder_open,
              cupertinoIcon: CupertinoIcons.folder_open,
              title: t.home.backFolder,
              onTap: () => grid.onTap('..'),
            ),
          _ListFolderRow(
            key: const ValueKey('ListFolderRowNew'),
            icon: Icons.create_new_folder,
            cupertinoIcon: CupertinoIcons.folder_fill_badge_plus,
            title: t.home.newFolder.newFolder,
            onTap: () => showDialog(
              context: context,
              builder: (context) => NewFolderDialog(
                createFolder: grid.createFolder,
                doesFolderExist: grid.doesFolderExist,
              ),
            ),
          ),
          for (final folder in sorted(
            grid.folders,
            stows.browseSortMetric.value,
          ))
            _ListFolderRow(
              key: ValueKey('ListFolderRow$folder'),
              icon: Icons.folder,
              cupertinoIcon: CupertinoIcons.folder_fill,
              title: folder,
              onTap: () => grid.onTap(folder),
              grid: grid,
            ),
        ],
      ),
    );
  }
}

class _ListFolderRow extends StatefulWidget {
  const new({
    super.key,
    required this.icon,
    required this.cupertinoIcon,
    required this.title,
    required this.onTap,
    this.grid,
  });

  final IconData icon;
  final IconData cupertinoIcon;
  final String title;
  final VoidCallback onTap;

  /// Set for real folders, which have the rename, move and delete actions.
  final GridFolders? grid;

  @override
  State<_ListFolderRow> createState() => _ListFolderRowState();
}

class _ListFolderRowState extends State<_ListFolderRow> {
  /// Whether the folder actions are shown (long-press or right-click).
  var expanded = false;

  void toggle() => setState(() => expanded = !expanded);

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final folderName = widget.title;
    return GestureDetector(
      onSecondaryTap: grid == null ? null : toggle,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: const RoundedRectangleBorder(borderRadius: .all(.circular(8))),
        selected: expanded,
        // Line the names up with the Name column of the notes.
        contentPadding: .symmetric(horizontal: ListColumns.padding.left),
        horizontalTitleGap: ListColumns.gap,
        leading: SizedBox(
          width: ListColumns.thumbnailWidth,
          child: AdaptiveIcon(
            icon: widget.icon,
            cupertinoIcon: widget.cupertinoIcon,
            size: 28,
          ),
        ),
        title: Text(widget.title, maxLines: 1, overflow: .ellipsis),
        onTap: expanded ? toggle : widget.onTap,
        onLongPress: grid == null ? null : toggle,
        trailing: grid == null
            ? null
            : Row(
                mainAxisSize: .min,
                children: [
                  if (expanded) ...[
                    RenameFolderButton(
                      folderName: folderName,
                      doesFolderExist: grid.doesFolderExist,
                      renameFolder: (newName) async {
                        await grid.renameFolder(folderName, newName);
                        if (mounted) setState(() => expanded = false);
                      },
                    ),
                    if (grid.moveFolder case final moveFolder?)
                      IconButton(
                        padding: .zero,
                        tooltip: t.home.moveFolder.moveFolder,
                        onPressed: () async {
                          setState(() => expanded = false);
                          await moveFolder(folderName);
                        },
                        icon: const Icon(Icons.drive_file_move),
                      ),
                    DeleteFolderButton(
                      folderName: folderName,
                      deleteFolder: (folderName) async {
                        await grid.deleteFolder(folderName);
                        if (mounted) setState(() => expanded = false);
                      },
                      isFolderEmpty: grid.isFolderEmpty,
                    ),
                  ],
                  IconButton(
                    key: const ValueKey('ListFolderRowMore'),
                    // English only: this fork doesn't regenerate translations.
                    tooltip: expanded ? 'Close' : 'Folder actions',
                    onPressed: toggle,
                    icon: Icon(expanded ? Icons.close : Icons.more_vert),
                  ),
                ],
              ),
      ),
    );
  }
}
