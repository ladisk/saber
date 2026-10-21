import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:onenote_import/onenote_import.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/onenote/onenote_layout.dart';
import 'package:saber/pages/editor/editor.dart';

/// What [OneNoteImporter.importFile] did.
class OneNoteImportSummary {
  /// The folder containing the imported notes.
  var folder = '/';
  var notes = 0;

  /// OneNote pages that had nothing Saber can show, e.g. only typed text.
  var emptyPages = 0;

  /// Paragraphs of typed text, which Saber can't place on a page.
  var texts = 0;

  /// Images Saber can't show (e.g. EMF) and other skipped content.
  var skipped = 0;
}

/// Imports OneNote notebooks as Saber notes.
///
/// Each OneNote page becomes a note in a folder named after its section.
/// Handwriting and images are imported; typed text is not.
abstract final class OneNoteImporter {
  static final log = Logger('OneNoteImporter');

  /// The file extensions that [importFile] accepts.
  ///
  /// A `.zip` is a notebook downloaded from OneDrive or SharePoint.
  static const extensions = [...oneNoteExtensions, '.zip'];

  static bool canImport(String path) =>
      extensions.contains(p.extension(path).toLowerCase());

  /// Imports the OneNote file at [path] into [parentDir],
  /// which must start and end with a slash.
  ///
  /// [onProgress] is called with the number of pages done and the total.
  /// Throws a [OneNoteImportException] if the file can't be read.
  static Future<OneNoteImportSummary> importFile(
    String path, {
    required String parentDir,
    void Function(int done, int total)? onProgress,
  }) async {
    assert(parentDir.startsWith('/') && parentDir.endsWith('/'));

    final tempRoot = await getTemporaryDirectory();
    await tempRoot.create(recursive: true);
    final tempDir = await tempRoot.createTemp('onenote_import');
    try {
      final summary = OneNoteImportSummary();
      final extension = p.extension(path).toLowerCase();
      // A .onetoc2 is always called e.g. "Open Notebook",
      // so use its folder's name instead.
      final notebookName = _sanitize(
        extension == '.onetoc2'
            ? p.basename(p.dirname(path))
            : p.basenameWithoutExtension(path),
      );

      final List<String> files;
      final String rootFolder;
      if (extension == '.zip') {
        files = await _extractZip(path, tempDir);
        rootFolder = '$parentDir$notebookName/';
      } else if (extension == '.one') {
        files = [path];
        rootFolder = parentDir;
      } else {
        files = [path];
        rootFolder = '$parentDir$notebookName/';
      }

      final sections = <OneNoteSection>[];
      for (final (i, file) in files.indexed) {
        final imageDir = await Directory('${tempDir.path}/images$i').create();
        sections.addAll(await readOneNoteFile(file, imageDir: imageDir.path));
      }
      summary.folder = files.length == 1 && extension == '.one'
          ? '$rootFolder${_sanitize(sections.firstOrNull?.name ?? '')}'
          : rootFolder.substring(0, rootFolder.length - 1);

      final total = sections.fold(0, (sum, s) => sum + s.pages.length);
      var done = 0;
      onProgress?.call(done, total);
      for (final section in sections) {
        final folder = [
          rootFolder.substring(0, rootFolder.length - 1),
          for (final group in section.groups) _sanitize(group),
          _sanitize(section.name),
        ].join('/');
        for (final page in section.pages) {
          await _importPage(page, folder, summary);
          onProgress?.call(++done, total);
        }
      }
      return summary;
    } finally {
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
    }
  }

  /// Extracts the zip at [path] and returns the files to read:
  /// the notebook's `.onetoc2` if there is one, or else its sections.
  static Future<List<String>> _extractZip(
    String path,
    Directory tempDir,
  ) async {
    final zipDir = '${tempDir.path}/zip';
    await extractFileToDisk(path, zipDir);
    final files = await Directory(zipDir)
        .list(recursive: true)
        .where((entity) => entity is File)
        .map((entity) => entity.path)
        .toList();
    files.sort();

    final notebooks = files.where((f) => f.toLowerCase().endsWith('.onetoc2'));
    if (notebooks.isNotEmpty) return notebooks.toList();

    final sections = files.where((f) => f.toLowerCase().endsWith('.one'));
    if (sections.isNotEmpty) return sections.toList();

    throw const OneNoteImportException('The zip contains no OneNote files');
  }

  static Future<void> _importPage(
    OneNotePage page,
    String folder,
    OneNoteImportSummary summary,
  ) async {
    summary.texts += page.texts.length;
    summary.skipped += page.skipped;

    final images = <String, OneNoteImageData>{};
    for (final image in page.images) {
      final data = await _readImage(image.path);
      if (data == null) {
        summary.skipped++;
      } else {
        images[image.path] = data;
      }
    }

    final title = _sanitize(page.title);
    final filePath = await FileManager.suffixFilePathToMakeItUnique(
      '$folder/${title.isEmpty ? 'Untitled' : title}',
    );
    final coreInfo = EditorCoreInfo(filePath: filePath)
      ..backgroundPattern = .none;
    try {
      OneNoteLayout.addPage(coreInfo, page, images);
      if (coreInfo.pages.isEmpty) {
        summary.emptyPages++;
        return;
      }
      await _save(coreInfo, lastModified: page.updated);
      summary.notes++;
    } finally {
      coreInfo.dispose();
    }
  }

  /// Returns null if Flutter can't decode the image.
  static Future<OneNoteImageData?> _readImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      if (size.isEmpty) return null;
      return (bytes: bytes, extension: p.extension(path), size: size);
    } catch (e) {
      log.warning('Skipping image $path: $e');
      return null;
    }
  }

  /// Saves the note and its preview, like [EditorState.saveToFile].
  static Future<void> _save(
    EditorCoreInfo coreInfo, {
    required DateTime lastModified,
  }) async {
    final filePath = coreInfo.filePath + Editor.extension;
    final (bson, assets) = coreInfo.saveToBinary(currentPageIndex: 0);
    await Future.wait([
      FileManager.writeFile(
        filePath,
        bson,
        awaitWrite: true,
        lastModified: lastModified,
      ),
      for (var i = 0; i < assets.length; ++i)
        assets
            .getBytes(i)
            .then(
              (bytes) => FileManager.writeFile(
                '$filePath.$i',
                bytes,
                awaitWrite: true,
              ),
            ),
    ]);

    try {
      final page = coreInfo.pages.first;
      final previewHeight = page.previewHeight(lineHeight: coreInfo.lineHeight);
      final thumbnail = await EditorExporter.screenshotPage(
        coreInfo: coreInfo,
        pageIndex: 0,
        rasterizeAllStrokes: true,
        targetSize: Size(720, 720 * previewHeight / page.size.width),
        cropHeight: previewHeight,
        pixelRatio: 1,
      );
      final thumbnailPng = await thumbnail.toByteData(format: .png);
      thumbnail.dispose();
      await FileManager.writeFile(
        '$filePath.p',
        thumbnailPng!.buffer.asUint8List(),
        awaitWrite: true,
      );
    } catch (e, st) {
      // The note is still usable; the editor makes a preview when it saves.
      log.warning('Failed to make a preview of $filePath', e, st);
    }
  }

  /// Makes [name] safe to use as a file or folder name.
  static String _sanitize(String name) {
    name = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^\.+'), '');
    if (name.length > maxNameLength) {
      name = name.substring(0, maxNameLength).trimRight();
    }
    return name;
  }

  /// Long page titles are cut to this many characters.
  static const maxNameLength = 80;
}
