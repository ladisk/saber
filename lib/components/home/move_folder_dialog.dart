import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';

/// Lets the user pick a folder to move the folder at [folderPath] into,
/// e.g. `/a/b`, then moves it.
///
/// Returns whether the folder was moved.
Future<bool> showMoveFolderDialog(
  BuildContext context, {
  required String folderPath,
}) async {
  final moved = await showDialog<bool>(
    context: context,
    builder: (context) => _MoveFolderDialog(folderPath: folderPath),
  );
  return moved ?? false;
}

class _MoveFolderDialog extends StatefulWidget {
  const new({required this.folderPath});

  final String folderPath;

  @override
  State<_MoveFolderDialog> createState() => _MoveFolderDialogState();
}

class _MoveFolderDialogState extends State<_MoveFolderDialog> {
  late final folderName = widget.folderPath.substring(
    widget.folderPath.lastIndexOf('/') + 1,
  );

  /// The folder containing the folder to move, with a trailing slash.
  late final parentFolder = widget.folderPath.substring(
    0,
    widget.folderPath.lastIndexOf('/') + 1,
  );

  late String _currentFolder;

  /// The folder browsed to in the dialog, with a trailing slash.
  String get currentFolder => _currentFolder;
  set currentFolder(String folder) {
    _currentFolder = folder;
    currentFolderChildren = null;
    findChildrenOfCurrentFolder();
  }

  /// The children of [currentFolder].
  DirectoryChildren? currentFolderChildren;

  Future<void> findChildrenOfCurrentFolder() async {
    final folder = currentFolder;
    final children = await FileManager.getChildrenOfDirectory(folder);
    if (!mounted || folder != currentFolder) return;
    setState(() => currentFolderChildren = children);
  }

  /// Why the folder can't be moved into [currentFolder], if it can't.
  String? get problem {
    if (currentFolder == parentFolder) return t.home.moveFolder.sameFolder;
    if (currentFolderChildren?.directories.contains(folderName) ?? false) {
      return t.home.moveFolder.folderExists(f: folderName);
    }
    return null;
  }

  /// The subfolders of [currentFolder] that can be browsed to.
  ///
  /// The folder being moved is hidden, so it can't be moved into itself.
  List<String> get folders => [
    for (final folder in currentFolderChildren?.directories ?? const <String>[])
      if (currentFolder != parentFolder || folder != folderName) folder,
  ];

  @override
  void initState() {
    super.initState();
    currentFolder = parentFolder;
  }

  @override
  Widget build(BuildContext context) {
    final problem = this.problem;
    return AdaptiveAlertDialog(
      title: Text(t.home.moveFolder.moveName(f: folderName)),
      content: SizedBox(
        width: 300,
        height: 300,
        child: Column(
          children: [
            Text(currentFolder),
            Expanded(
              child: CustomScrollView(
                shrinkWrap: true,
                slivers: [
                  GridFolders(
                    isAtRoot: currentFolder == '/',
                    crossAxisCount: 3,
                    onTap: (String folder) {
                      setState(() {
                        if (folder == '..') {
                          currentFolder = currentFolder.substring(
                            0,
                            currentFolder.lastIndexOf(
                                  '/',
                                  currentFolder.length - 2,
                                ) +
                                1,
                          );
                        } else {
                          currentFolder = '$currentFolder$folder/';
                        }
                      });
                    },
                    createFolder: (String folderName) async {
                      await FileManager.createFolder(
                        '$currentFolder$folderName',
                      );
                      findChildrenOfCurrentFolder();
                    },
                    doesFolderExist: (String folderName) =>
                        currentFolderChildren?.directories.contains(
                          folderName,
                        ) ??
                        false,
                    renameFolder: (String oldName, String newName) async {
                      await FileManager.renameDirectory(
                        '$currentFolder$oldName',
                        newName,
                      );
                      findChildrenOfCurrentFolder();
                    },
                    isFolderEmpty: (String folderName) async {
                      final children = await FileManager.getChildrenOfDirectory(
                        '$currentFolder$folderName',
                      );
                      return children?.isEmpty ?? true;
                    },
                    deleteFolder: (String folderName) async {
                      await FileManager.deleteDirectory(
                        '$currentFolder$folderName',
                      );
                      findChildrenOfCurrentFolder();
                    },
                    folders: folders,
                  ),
                ],
              ),
            ),
            if (problem != null) Text(problem),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.common.cancel),
        ),
        CupertinoDialogAction(
          onPressed: problem != null || currentFolderChildren == null
              ? null
              : () async {
                  await FileManager.moveDirectory(
                    widget.folderPath,
                    '$currentFolder$folderName',
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop(true);
                },
          child: Text(t.home.moveFolder.move),
        ),
      ],
    );
  }
}
