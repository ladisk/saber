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

  /// Pastes whatever was copied last, here or in another app:
  /// a Saber selection, images, a pdf, or text.
  Future<void> _pasteFromClipboard() async {
    if (coreInfo.readOnly) return;

    // a text field such as the note title pastes into itself
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }
    // the text layer pastes text itself, but not images
    final typing = coreInfo.pages.any((page) => page.quill.focusNode.hasFocus);

    final reader = await SystemClipboard.instance?.read();
    if (reader == null) {
      if (!typing) pasteSelection();
      return;
    }

    if (!typing && await _clipboardHasSelection(reader)) {
      return pasteSelection();
    }

    final photos = await _readClipboardImages(reader);
    if (photos.isNotEmpty) {
      await _pickPhotos(photos);
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
    if (text != null && text.trim().isNotEmpty) return _pasteText(text);

    if (!SelectionClipboard.isEmpty) return pasteSelection();

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

  /// Adds [text] to the end of the current page's text.
  void _pasteText(String text) {
    final pageIndex = currentPageIndex;
    createPage(pageIndex);
    final controller = coreInfo.pages[pageIndex].quill.controller;

    // the document always ends with a newline
    final end = controller.document.length - 1;
    final insert = end > 0 ? '\n$text' : text;
    controller.replaceText(
      end,
      0,
      insert,
      TextSelection.collapsed(offset: end + insert.length),
    );
  }
}
