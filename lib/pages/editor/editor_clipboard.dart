part of 'editor.dart';

/// Marks a Saber selection on the system clipboard.
///
/// Its value is [SelectionClipboard.token], so a paste can tell whether
/// the clipboard still holds the last copy or something newer.
final _selectionFormat = CustomValueFormat<String>(
  applicationId: 'org.ladisk.saber.selection',
  onEncode: (token, _) => Uint8List.fromList(utf8.encode(token)),
  onDecode: (value, _) async => switch (value) {
    final String string => string,
    final List<int> bytes => utf8.decode(bytes),
    _ => null,
  },
);

/// Image formats that can be pasted, in order of preference,
/// mapped to their file extension.
const _pastableImages = <SimpleFileFormat, String>{
  Formats.png: '.png',
  Formats.jpeg: '.jpeg',
  Formats.webp: '.webp',
  Formats.gif: '.gif',
  Formats.svg: '.svg',
  Formats.tiff: '.tiff',
  Formats.bmp: '.bmp',
  Formats.ico: '.ico',
};

/// The PNG of the last copy, to recognise it on platforms
/// that drop [_selectionFormat].
Uint8List? _copiedPng;

/// Where the mouse is over the pages, in global coordinates,
/// or null if it is elsewhere (e.g. on the toolbar).
Offset? _mousePosition;

/// The page to paste onto and the [position] on it to paste at.
///
/// [underMouse] means [position] is under the mouse,
/// rather than the middle of what is visible of the page.
class _PasteTarget {
  const new({required this.pageIndex, required this.position, this.mouse});

  final int pageIndex;
  final Offset position;

  /// Where the mouse is on screen, if [position] is under it.
  final Offset? mouse;
  bool get underMouse => mouse != null;

  /// How far each of several pasted images is moved from the previous one.
  static const step = Offset(25, 25);
}

/// Copies to and pastes from the system clipboard.
///
/// Kept out of `editor.dart` so that upstream changes to it
/// merge without conflicts.
extension _EditorClipboard on EditorState {
  /// Puts [selection] on the system clipboard as a PNG,
  /// so it can be pasted into other apps.
  Future<void> _writeSelectionToClipboard(SelectResult selection) async {
    final clipboard = SystemClipboard.instance;
    final token = SelectionClipboard.token;
    if (clipboard == null || token == null) return;
    try {
      final png = await SelectionExport.renderPng(
        selection,
        coreInfo.pages[selection.pageIndex],
      );
      _copiedPng = png;
      final item = DataWriterItem(suggestedName: 'Saber selection.png');
      if (png != null) item.add(Formats.png(png));
      item.add(_selectionFormat(token));
      await clipboard.write([item]);
    } catch (e) {
      log.warning('Failed to write to the clipboard: $e');
    }
  }

  /// Tracks the mouse over [child], the pages, so a paste can go under it.
  Widget _trackMouse(Widget child) => MouseRegion(
    opaque: false,
    onHover: (event) => _mousePosition = event.position,
    onExit: (_) => _mousePosition = null,
    child: child,
  );

  /// Where to paste: under the mouse if it is over a page, otherwise the
  /// middle of the page in the middle of the screen. Using the page at the
  /// top of the screen ([currentPageIndex]) would paste onto the previous
  /// page whenever a strip of it is still showing.
  _PasteTarget _pasteTarget() {
    final mouse = _mousePosition;
    if (mouse != null) {
      final pageIndex = onWhichPageIsFocalPoint(mouse);
      if (pageIndex != null) {
        return _PasteTarget(
          pageIndex: pageIndex,
          position: coreInfo.pages[pageIndex].renderBox!.globalToLocal(mouse),
          mouse: mouse,
        );
      }
    }

    final view = _canvasGestureDetectorKey.currentContext?.findRenderObject();
    if (view is RenderBox && view.hasSize) {
      final viewRect = view.localToGlobal(.zero) & view.size;
      _PasteTarget? best;
      var bestArea = 0.0;
      for (var i = 0; i < coreInfo.pages.length; ++i) {
        final page = coreInfo.pages[i];
        final box = page.renderBox;
        if (box == null || !box.attached || !box.hasSize) continue;
        final pageRect = Rect.fromPoints(
          box.localToGlobal(.zero),
          box.localToGlobal(page.size.bottomRight(.zero)),
        );
        final visible = pageRect.intersect(viewRect);
        if (visible.width <= 0 || visible.height <= 0) continue;

        final target = _PasteTarget(
          pageIndex: i,
          position: box.globalToLocal(visible.center),
        );
        if (pageRect.contains(viewRect.center)) return target;
        final area = visible.width * visible.height;
        if (area > bestArea) (best, bestArea) = (target, area);
      }
      if (best != null) return best;
    }

    final pageIndex = currentPageIndex;
    return _PasteTarget(
      pageIndex: pageIndex,
      position: coreInfo.pages[pageIndex].size.center(.zero),
    );
  }

  /// Moves the just pasted [selection] so that its centre is at [centre].
  void _centreSelection(SelectResult selection, Offset centre) {
    final offset = centre - selection.path.getBounds().center;
    for (final stroke in selection.strokes) {
      stroke.shift(offset);
    }
    for (final image in selection.images) {
      image.dstRect = image.dstRect.shift(offset);
    }
    selection.path = selection.path.shift(offset);
  }

  /// Centres [image] at [centre] once it has loaded and knows its size,
  /// keeping it on its page.
  void _centreWhenLoaded(EditorImage image, Offset centre) {
    void onChange() {
      if (image.dstRect.isEmpty) return;
      image.removeListener(onChange);

      final pageSize = coreInfo.pages[image.pageIndex].size;
      final size = image.dstRect.size;
      image.dstRect =
          Offset(
            (centre.dx - size.width / 2).clamp(
              0,
              max(0, pageSize.width - size.width),
            ),
            (centre.dy - size.height / 2).clamp(
              0,
              max(0, pageSize.height - size.height),
            ),
          ) &
          size;
      autosaveAfterDelay();
    }

    image.addListener(onChange);
  }

  /// Pastes whatever was copied last, here or in another app:
  /// a Saber selection, images, a pdf, or text.
  Future<void> _pasteFromClipboard() async {
    if (coreInfo.readOnly) return;

    // decided before reading the clipboard, while the mouse is still there
    final target = _pasteTarget();

    // a text field such as the note title pastes into itself
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }
    // the text layer pastes text itself, but not images
    final typing = coreInfo.pages.any((page) => page.quill.focusNode.hasFocus);

    final reader = await SystemClipboard.instance?.read();
    if (reader == null) {
      if (!typing) _pasteSelection(target);
      return;
    }

    if (!typing && await _clipboardHasSelection(reader)) {
      return _pasteSelection(target);
    }

    final photos = await _readClipboardImages(reader);
    if (photos.isNotEmpty) {
      await _pickPhotos(photos, target);
      return;
    }
    if (typing) return;

    if (reader.canProvide(Formats.pdf) && Editor.canRasterPdf) {
      final pdf = await _readClipboardFile(reader, Formats.pdf);
      if (pdf != null) {
        final folder = await getTemporaryDirectory();
        final file = File(
          p.join(
            folder.path,
            'pasted-${DateTime.now().millisecondsSinceEpoch}.pdf',
          ),
        );
        await file.writeAsBytes(pdf);
        await importPdfFromFilePath(file.path);
        return;
      }
    }

    final text = await reader.readValue(Formats.plainText);
    if (text != null && text.trim().isNotEmpty) {
      return _pasteText(text, target);
    }

    if (!SelectionClipboard.isEmpty) return _pasteSelection(target);

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nothing to paste')));
    }
  }

  /// Whether the system clipboard still holds the last Saber selection.
  Future<bool> _clipboardHasSelection(ClipboardReader reader) async {
    final token = SelectionClipboard.token;
    if (token == null || SelectionClipboard.isEmpty) return false;

    if (reader.canProvide(_selectionFormat)) {
      return await reader.readValue(_selectionFormat) == token;
    }
    final copiedPng = _copiedPng;
    if (copiedPng == null || !reader.canProvide(Formats.png)) return false;
    final png = await _readClipboardFile(reader, Formats.png);
    return png != null && listEquals(png, copiedPng);
  }

  /// Reads one image from each clipboard item, in its preferred format.
  Future<List<_PhotoInfo>> _readClipboardImages(ClipboardReader reader) async {
    final photos = <_PhotoInfo>[];
    for (final item in reader.items) {
      final format = _pastableImages.keys.firstWhereOrNull(item.canProvide);
      if (format == null) continue;
      final (:bytes, :fileName) = await _readItemFile(item, format);
      if (bytes == null || bytes.isEmpty) continue;

      final dot = fileName?.lastIndexOf('.') ?? -1;
      photos.add((
        bytes: bytes,
        extension: dot >= 0
            ? fileName!.substring(dot).toLowerCase()
            : _pastableImages[format]!,
      ));
    }
    return photos;
  }

  Future<Uint8List?> _readClipboardFile(
    ClipboardReader reader,
    FileFormat format,
  ) async {
    final item = reader.items.firstWhereOrNull(
      (item) => item.canProvide(format),
    );
    if (item == null) return null;
    return (await _readItemFile(item, format)).bytes;
  }

  Future<({Uint8List? bytes, String? fileName})> _readItemFile(
    ClipboardDataReader item,
    FileFormat format,
  ) {
    final completer = Completer<({Uint8List? bytes, String? fileName})>();
    final progress = item.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          completer.complete((bytes: bytes, fileName: file.fileName));
        } catch (e) {
          completer.complete((bytes: null, fileName: null));
        }
      },
      onError: (e) {
        log.warning('Failed to read from the clipboard: $e');
        if (!completer.isCompleted) {
          completer.complete((bytes: null, fileName: null));
        }
      },
    );
    if (progress == null) return Future.value((bytes: null, fileName: null));
    return completer.future;
  }

  /// Adds [text] to the text of the [target] page: under the mouse,
  /// or at the end of the text.
  void _pasteText(String text, _PasteTarget target) {
    createPage(target.pageIndex);
    QuillClickToType.insertAt(
      coreInfo.pages[target.pageIndex].quill,
      text,
      target.mouse,
      lineHeight: coreInfo.lineHeight,
    );
  }
}
