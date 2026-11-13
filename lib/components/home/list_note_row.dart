part of 'preview_card.dart';

/// Fork: the columns of the List home layout's table, shared by the
/// header (list_files.dart) and the rows.
class ListColumns {
  const new _({
    required this.showFolders,
    required this.folderColumn,
    required this.compactTime,
  });

  /// The columns for a table [width] wide.
  ///
  /// [showFolders] is true where the notes come from several folders.
  /// On narrow screens the folder moves under the name and the time
  /// shows only the date (or only the time today).
  factory of(double width, {required bool showFolders}) => ListColumns._(
    showFolders: showFolders,
    folderColumn: showFolders && width >= 560,
    compactTime: width < 440,
  );

  final bool showFolders;

  /// Whether the folder has its own column, otherwise it is under the name.
  final bool folderColumn;

  /// Whether the Modified column is narrow.
  final bool compactTime;

  static const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
  static const gap = 12.0;
  static const nameFlex = 3;
  static const folderFlex = 2;

  /// Height of the page-1 thumbnail in a row.
  static const thumbnailHeight = 64.0;

  /// Width of the thumbnail: close to an A4 page in portrait.
  static const thumbnailWidth = 46.0;

  double get timeWidth => compactTime ? 76 : 124;

  /// The last-modified time as `yyyy-MM-dd HH:mm`, or only `HH:mm` today.
  /// With [compactTime], `yyyy-MM-dd` before today.
  String formatTime(DateTime time, {DateTime? now}) {
    now ??= DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(time.hour)}:${two(time.minute)}';
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return hm;
    }
    final date = '${time.year}-${two(time.month)}-${two(time.day)}';
    return compactTime ? date : '$date $hm';
  }
}

/// Fork: one row of the List home layout (see list_files.dart).
///
/// Uses the same state as the grid card, so tapping, selecting,
/// the thumbnail refresh and opening the editor work the same way.
extension _ListNoteRow on _PreviewCardState {
  Widget buildListRow(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final invert = theme.brightness == .dark && stows.editorAutoInvert.value;
    final borderWidth = MediaQuery.highContrastOf(context)
        ? kSaberBorderWidthAccessible
        : kSaberBorderWidthInaccessible;

    final title = widget.filePath.substring(
      widget.filePath.lastIndexOf('/') + 1,
    );
    final modified = FileManager.lastModified(
      widget.filePath + Editor.extension,
    );
    final secondaryStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    final thumbnailBox = Container(
      width: ListColumns.thumbnailWidth,
      height: ListColumns.thumbnailHeight,
      decoration: BoxDecoration(
        color: InnerCanvas.defaultBackgroundColor.withInversion(invert),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.12),
          width: borderWidth,
        ),
        borderRadius: const .all(.circular(4)),
      ),
      clipBehavior: .antiAlias,
      child: ListenableBuilder(
        listenable: thumbnail,
        builder: (context, _) => InvertWidget(
          key: ValueKey(thumbnail.updateCount),
          invert: invert,
          child: thumbnail.doesImageExist
              ? Image(
                  image: thumbnail.image!,
                  alignment: .topCenter,
                  fit: .cover,
                )
              : const SizedBox.expand(),
        ),
      ),
    );

    Widget cells(ListColumns columns, bool expanded) {
      final folder = PreviewCard.folderOf(widget.filePath);
      return Row(
        children: [
          Stack(
            alignment: .center,
            children: [
              thumbnailBox,
              if (expanded)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle, color: colorScheme.primary),
                ),
            ],
          ),
          const SizedBox(width: ListColumns.gap),
          Expanded(
            flex: ListColumns.nameFlex,
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(title, maxLines: 1, overflow: .ellipsis),
                if (columns.showFolders && !columns.folderColumn) ...[
                  const SizedBox(height: 2),
                  Text(
                    folder,
                    key: const ValueKey('ListNoteRowFolder'),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: secondaryStyle,
                  ),
                ],
              ],
            ),
          ),
          if (columns.folderColumn) ...[
            const SizedBox(width: ListColumns.gap),
            Expanded(
              flex: ListColumns.folderFlex,
              child: Text(
                folder,
                key: const ValueKey('ListNoteRowFolder'),
                maxLines: 1,
                overflow: .ellipsis,
                style: secondaryStyle,
              ),
            ),
          ],
          const SizedBox(width: ListColumns.gap),
          SizedBox(
            width: columns.timeWidth,
            child: Text(
              columns.formatTime(modified),
              key: const ValueKey('ListNoteRowModified'),
              maxLines: 1,
              overflow: .ellipsis,
              style: secondaryStyle,
            ),
          ),
        ],
      );
    }

    Widget row(bool expanded) => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: .opaque,
        onTap: widget.isAnythingSelected ? _toggleCardSelection : null,
        onSecondaryTap: _toggleCardSelection,
        onLongPress: _toggleCardSelection,
        child: Stack(
          children: [
            Padding(
              padding: ListColumns.padding,
              child: LayoutBuilder(
                builder: (context, constraints) => cells(
                  ListColumns.of(
                    // The header measures the width outside the padding.
                    constraints.maxWidth + ListColumns.padding.horizontal,
                    showFolders: widget.showFolder,
                  ),
                  expanded,
                ),
              ),
            ),
            SyncIndicator(filePath: widget.filePath),
          ],
        ),
      ),
    );

    return ValueListenableBuilder(
      valueListenable: expanded,
      builder: (context, expanded, _) {
        return SizedBox(
          width: double.infinity,
          child: OpenContainer(
            closedColor: expanded
                ? Color.alphaBlend(
                    colorScheme.primary.withValues(alpha: 0.12),
                    colorScheme.surface,
                  )
                : colorScheme.surface,
            closedShape: const RoundedRectangleBorder(
              borderRadius: .all(.circular(8)),
            ),
            closedElevation: 0,
            closedBuilder: (context, action) => row(expanded),
            openColor: colorScheme.surface,
            openBuilder: (context, action) => Editor(path: widget.filePath),
            transitionDuration: Duration(
              milliseconds: disableAnimations ? 0 : 300,
            ),
            routeSettings: RouteSettings(
              name: RoutePaths.editFilePath(widget.filePath),
            ),
            onClosed: (_) => _refreshThumbnailAfterDelay(),
          ),
        );
      },
    );
  }
}
