part of 'preview_card.dart';

/// Fork: one row of the List home layout (see list_files.dart).
///
/// Uses the same state as the grid card, so tapping, selecting,
/// the thumbnail refresh and opening the editor work the same way.
extension _ListNoteRow on _PreviewCardState {
  /// Height of the page-1 thumbnail in a row.
  static const thumbnailHeight = 64.0;

  /// Width of the thumbnail: close to an A4 page in portrait.
  static const thumbnailWidth = 46.0;

  /// The last-modified time as `yyyy-MM-dd HH:mm`, or only `HH:mm` today.
  static String formatTime(DateTime time, {DateTime? now}) {
    now ??= DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(time.hour)}:${two(time.minute)}';
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return hm;
    }
    return '${time.year}-${two(time.month)}-${two(time.day)} $hm';
  }

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
      width: thumbnailWidth,
      height: thumbnailHeight,
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
              padding: const .symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  thumbnailBox,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      children: [
                        Text(title, maxLines: 1, overflow: .ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          [
                            formatTime(modified),
                            if (widget.showFolder)
                              PreviewCard.folderOf(widget.filePath),
                          ].join('  ·  '),
                          key: const ValueKey('ListNoteRowSubtitle'),
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: secondaryStyle,
                        ),
                      ],
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle, color: colorScheme.primary),
                  ],
                ],
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
