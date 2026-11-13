import 'dart:async';

import 'package:collapsible/collapsible.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/home/home_layout_button.dart';
import 'package:saber/components/home/list_folders.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_folder_dialog.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/no_files.dart';
import 'package:saber/components/home/path_components.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/home/syncing_button.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/file_manager/note_search.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

/// What the browse page shows: the current folder, search results
/// over all notes, or the most recently edited notes.
enum BrowseMode { folder, search, latest }

class BrowsePage extends StatefulHookWidget {
  const new({super.key, String? path}) : initialPath = path;

  final String? initialPath;

  @visibleForTesting
  static DirectoryChildren? overrideChildren;

  /// All notes, used by the search and latest views in tests.
  @visibleForTesting
  static List<String>? overrideAllFiles;

  /// The edit times used by the latest view in tests.
  @visibleForTesting
  static DateTime Function(String filePath)? overrideLastModified;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  DirectoryChildren? children;

  String? path;

  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);

  var mode = BrowseMode.folder;

  /// All notes in the library, newest first,
  /// loaded when search or latest is opened.
  List<String>? allFiles;

  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();

  @override
  void initState() {
    path = widget.initialPath;

    findChildrenOfPath();
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );
    selectedFiles.addListener(_setState);

    super.initState();
  }

  @override
  void dispose() {
    selectedFiles.removeListener(_setState);
    fileWriteSubscription?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  StreamSubscription? fileWriteSubscription;
  void fileWriteListener(FileOperation event) {
    if (mode != .folder) {
      findAllFiles(fromFileListener: true);
      return;
    }
    if (!event.filePath.startsWith(path ?? '/')) return;
    findChildrenOfPath(fromFileListener: true);
  }

  Future<void> findAllFiles({bool fromFileListener = false}) async {
    if (!mounted) return;

    if (fromFileListener) {
      // don't refresh if we're not on the home page
      final location = GoRouterState.of(context).uri.toString();
      if (!location.startsWith(RoutePaths.prefixOfHome)) return;
    }

    final files =
        BrowsePage.overrideAllFiles ?? await FileManager.getAllFiles();
    allFiles = NoteSearch.newestFirst(
      files,
      BrowsePage.overrideLastModified ??
          (filePath) => FileManager.lastModified(filePath + Editor.extension),
    );
    if (mounted) setState(() {});
  }

  void setMode(BrowseMode newMode) {
    if (newMode == mode) newMode = .folder;
    selectedFiles.value = [];
    setState(() => mode = newMode);
    if (newMode == .folder) {
      searchController.clear();
      findChildrenOfPath();
    } else {
      findAllFiles();
      if (newMode == .search) searchFocusNode.requestFocus();
    }
  }

  /// The notes to show in the search or latest view.
  List<String> get modeFiles {
    final files = allFiles;
    if (files == null) return const [];
    return switch (mode) {
      .folder => const [],
      .search => NoteSearch.search(files, searchController.text),
      .latest => files.take(NoteSearch.latestLimit).toList(),
    };
  }

  void _setState() => setState(() {});

  Future findChildrenOfPath({bool fromFileListener = false}) async {
    if (!mounted) return;

    if (fromFileListener) {
      // don't refresh if we're not on the home page
      final location = GoRouterState.of(context).uri.toString();
      if (!location.startsWith(RoutePaths.prefixOfHome)) return;
    }

    children =
        BrowsePage.overrideChildren ??
        await FileManager.getChildrenOfDirectory(
          path ?? '/',
          sortMetric: stows.browseSortMetric.value,
        );

    if (mounted) setState(() {});
  }

  void onDirectoryTap(String folder) {
    selectedFiles.value = [];
    if (folder == '..') {
      path = p.dirname(path ?? '/');
      if (path == '/') path = null;
    } else {
      path = p.join(path ?? '/', folder);
    }
    context.go(HomeRoutes.browseFilePath(path ?? '/'));
    findChildrenOfPath();
  }

  void onPathComponentTap(String? newPath) {
    selectedFiles.value = [];
    if (newPath == null || newPath.isEmpty || newPath == '/') {
      newPath = null;
    }
    path = newPath;
    context.go(HomeRoutes.browseFilePath(path ?? '/'));
    findChildrenOfPath();
  }

  Future<void> createFolder(String folderName) async {
    final folderPath = '${path ?? ''}/$folderName';
    await FileManager.createFolder(folderPath);
    findChildrenOfPath();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platform = Theme.of(context).platform;
    final crossAxisCount = MediaQuery.sizeOf(context).width ~/ 300 + 1;
    useListenable(stows.homeLayout);
    useOnListenableChange(stows.browseSortMetric, findChildrenOfPath);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            collapsedHeight: kToolbarHeight,
            expandedHeight: platform.isMaterialNative ? 200 - 8 : null,
            pinned: true,
            scrolledUnderElevation: 1,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                t.home.titles.browse,
                style: TextStyle(color: colorScheme.onSurface),
              ),
              centerTitle: false,
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 8, // less than other pages for path components
              ),
            ),
            actions: [
              IconButton(
                tooltip: t.home.search.search,
                isSelected: mode == .search,
                onPressed: () => setMode(.search),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: t.home.search.latest,
                isSelected: mode == .latest,
                onPressed: () => setMode(.latest),
                icon: const Icon(Icons.history),
              ),
              if (mode == .folder) const BrowseSortButton(),
              const HomeLayoutButton(),
              const SyncingButton(),
            ],
          ),
          if (mode == .folder)
            ..._buildFolderSlivers(crossAxisCount)
          else
            ..._buildModeSlivers(crossAxisCount),
        ],
      ),
      floatingActionButton: NewNoteButton(
        cupertino: platform.isCupertino,
        path: path,
      ),
      persistentFooterButtons: selectedFiles.value.isEmpty
          ? null
          : [
              Collapsible(
                axis: .vertical,
                collapsed: selectedFiles.value.length != 1,
                child: RenameNoteButton(
                  existingPath: selectedFiles.value.isEmpty
                      ? ''
                      : selectedFiles.value.first,
                  unselectNotes: () => selectedFiles.value = [],
                ),
              ),
              MoveNoteButton(
                filesToMove: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              DeleteNoteButton(
                filesToDelete: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              ExportNoteButton(selectedFiles: selectedFiles.value),
            ],
    );
  }

  List<Widget> _buildModeSlivers(int crossAxisCount) {
    final files = modeFiles;
    final isSearch = mode == .search;
    final hasQuery = searchController.text.trim().isNotEmpty;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const .symmetric(horizontal: 16),
          child: isSearch
              ? TextField(
                  key: const ValueKey('browseSearchField'),
                  controller: searchController,
                  focusNode: searchFocusNode,
                  autofocus: true,
                  textInputAction: .search,
                  decoration: InputDecoration(
                    hintText: t.home.search.hint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: t.home.search.close,
                      onPressed: () => setMode(.folder),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                )
              : ListTile(
                  contentPadding: .zero,
                  leading: const Icon(Icons.history),
                  title: Text(t.home.search.latestTitle),
                  trailing: IconButton(
                    tooltip: t.home.search.close,
                    onPressed: () => setMode(.folder),
                    icon: const Icon(Icons.close),
                  ),
                ),
        ),
      ),
      if (allFiles == null) ...[
        // loading
      ] else if (files.isEmpty) ...[
        if (!isSearch || hasQuery)
          SliverSafeArea(
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const .all(32),
                child: Text(
                  isSearch ? t.home.search.noResults : t.home.noFiles,
                  textAlign: .center,
                ),
              ),
            ),
          ),
      ] else ...[
        SliverSafeArea(
          top: false,
          minimum: const .only(
            top: 8,
            // Allow space for the FloatingActionButton
            bottom: 70,
          ),
          sliver: MasonryFiles(
            crossAxisCount: crossAxisCount,
            files: files,
            selectedFiles: selectedFiles,
            showFolders: true,
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildFolderSlivers(int crossAxisCount) {
    return [
      SliverToBoxAdapter(
        child: PathComponents(path, onPathComponentTap: onPathComponentTap),
      ),
      const SliverPadding(padding: .only(bottom: 16)),
      GridFolders(
        isAtRoot: path?.isEmpty ?? true,
        crossAxisCount: crossAxisCount,
        onTap: onDirectoryTap,
        createFolder: createFolder,
        doesFolderExist: (String folderName) {
          return children?.directories.contains(folderName) ?? false;
        },
        renameFolder: (String oldName, String newName) async {
          final oldPath = '${path ?? ''}/$oldName';
          await FileManager.renameDirectory(oldPath, newName);
          findChildrenOfPath();
        },
        isFolderEmpty: (String folderName) async {
          final folderPath = '${path ?? ''}/$folderName';
          final children = await FileManager.getChildrenOfDirectory(folderPath);
          return children?.isEmpty ?? true;
        },
        deleteFolder: (String folderName) async {
          final folderPath = '${path ?? ''}/$folderName';
          await FileManager.deleteDirectory(folderPath);
          findChildrenOfPath();
        },
        moveFolder: (String folderName) async {
          final moved = await showMoveFolderDialog(
            context,
            folderPath: '${path ?? ''}/$folderName',
          );
          if (moved) findChildrenOfPath();
        },
        folders: [
          for (final directoryPath in children?.directories ?? const [])
            directoryPath,
        ],
      ).orListLayout, // Fork: folder rows in the List layout.
      if (children == null) ...[
        // loading
      ] else if (children!.isEmpty) ...[
        const SliverSafeArea(sliver: SliverToBoxAdapter(child: NoFiles())),
      ] else ...[
        SliverSafeArea(
          top: false,
          minimum: const .only(
            top: 8,
            // Allow space for the FloatingActionButton
            bottom: 70,
          ),
          sliver: MasonryFiles(
            crossAxisCount: crossAxisCount,
            files: [
              for (final filePath in children?.files ?? const [])
                "${path ?? ""}/$filePath",
            ],
            selectedFiles: selectedFiles,
          ),
        ),
      ],
    ];
  }
}
