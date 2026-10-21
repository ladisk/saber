import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote_import/onenote_import.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/onenote/onenote_importer.dart';
import 'package:saber/data/onenote/onenote_layout.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/tool_id.dart';

import 'utils/test_mock_channel_handlers.dart';

/// Set to a `.one` file with ink, e.g. `Schnelle Notizen.one`
/// from the tests of https://github.com/msiemens/onenote.rs.
final _sample = Platform.environment['ONENOTE_SAMPLE'];

void main() {
  FlavorConfig.setup();

  group('OneNoteLayout', () {
    test('converts strokes to Saber units', () {
      final coreInfo = EditorCoreInfo(filePath: '');
      OneNoteLayout.addPage(
        coreInfo,
        _page([
          _stroke([100, 100, 200, 100], rgb: [255, 0, 0], width: 2),
        ]),
        const {},
      );

      expect(coreInfo.pages, hasLength(1));
      final page = coreInfo.pages.single;
      expect(page.size, EditorPage.defaultSize);
      final stroke = page.strokes.single;
      expect(stroke.toolId, ToolId.ballpointPen);
      expect(stroke.color, const Color(0xFFFF0000));
      expect(stroke.options.size, closeTo(2 * OneNoteLayout.scale, 1e-9));
      // The edge of the stroke, half its width out, is at the page margin.
      const left = OneNoteLayout.margin + OneNoteLayout.scale;
      expect(_bounds(stroke).left, closeTo(left, 1e-6));
      expect(
        _bounds(stroke).right,
        closeTo(left + 100 * OneNoteLayout.scale, 1e-6),
      );
    });

    test('imports translucent strokes as highlighter', () {
      final coreInfo = EditorCoreInfo(filePath: '');
      OneNoteLayout.addPage(
        coreInfo,
        _page([
          _stroke([0, 0, 50, 0], alpha: 128, tip: 1),
        ]),
        const {},
      );
      expect(coreInfo.pages.single.strokes.single.toolId, ToolId.highlighter);
    });

    test('splits a long page between strokes', () {
      // 30 lines of handwriting, 100 px apart: about 3 Saber pages.
      final coreInfo = EditorCoreInfo(filePath: '');
      OneNoteLayout.addPage(
        coreInfo,
        _page([
          for (var line = 0; line < 30; line++)
            _stroke([50, line * 100.0, 300, line * 100.0 + 40]),
        ]),
        const {},
      );

      expect(coreInfo.pages.length, greaterThanOrEqualTo(3));
      var strokes = 0;
      for (final page in coreInfo.pages) {
        for (final stroke in page.strokes) {
          strokes++;
          expect(_bounds(stroke).top, greaterThanOrEqualTo(0));
          expect(_bounds(stroke).bottom, lessThanOrEqualTo(page.size.height));
        }
      }
      expect(strokes, 30);
    });

    test('makes the page wider for wide content', () {
      final coreInfo = EditorCoreInfo(filePath: '');
      OneNoteLayout.addPage(
        coreInfo,
        _page([
          _stroke([0, 0, 2000, 0]),
        ]),
        const {},
      );
      final page = coreInfo.pages.single;
      expect(page.size.width, greaterThan(EditorPage.defaultWidth));
      expect(
        page.size.height / page.size.width,
        closeTo(EditorPage.defaultHeight / EditorPage.defaultWidth, 1e-9),
      );
      expect(
        _bounds(page.strokes.single).right,
        lessThanOrEqualTo(page.size.width),
      );
    });

    test('adds nothing for a page without ink or images', () {
      final coreInfo = EditorCoreInfo(filePath: '');
      OneNoteLayout.addPage(coreInfo, _page(const []), const {});
      expect(coreInfo.pages, isEmpty);
    });
  });

  test('rejects a file that is not OneNote', () async {
    setupMockPathProvider();
    await FileManager.init();
    final dir = await Directory.systemTemp.createTemp('onenote_import_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/note.one')..writeAsStringSync('not onenote');

    await expectLater(
      OneNoteImporter.importFile(file.path, parentDir: '/'),
      throwsA(isA<OneNoteImportException>()),
    );
  });

  testWidgets('imports a OneNote section as notes', (tester) async {
    setupMockPathProvider();
    await tester.runAsync(() async {
      await FileManager.init();
      final summary = await OneNoteImporter.importFile(
        _sample!,
        parentDir: '/onenote_import_test/',
      );
      addTearDown(
        () =>
            Directory('${FileManager.documentsDirectory}/onenote_import_test')
                .delete(recursive: true),
      );

      expect(summary.notes, greaterThan(0));
      final notes =
          Directory('${FileManager.documentsDirectory}${summary.folder}')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith(Editor.extension));
      expect(notes, hasLength(summary.notes));

      // The notes can be opened again.
      for (final note in notes) {
        final path = note.path
            .substring(FileManager.documentsDirectory.length)
            .replaceAll(Editor.extension, '');
        final coreInfo = await EditorCoreInfo.loadFromFilePath(path);
        expect(coreInfo.pages, isNotEmpty);
        expect(
          coreInfo.pages.any((p) => p.strokes.isNotEmpty),
          isTrue,
          reason: 'every sample note has handwriting',
        );
      }
    });
  }, skip: _sample == null);
}

OneNotePage _page(List<Map<String, dynamic>> strokes) => OneNotePage.fromJson({
  'title': 'Test',
  'level': 1,
  'created': 0,
  'updated': 0,
  'strokes': strokes,
  'images': const [],
  'texts': const [],
  'skipped': 0,
}, '');

Map<String, dynamic> _stroke(
  List<double> points, {
  List<int> rgb = const [0, 0, 0],
  int alpha = 255,
  double width = 1,
  int tip = 0,
}) => {
  'rgb': rgb,
  'alpha': alpha,
  'width': width,
  'tip': tip,
  'points': points,
};

/// The bounds of the stroke's points, ignoring its thickness.
Rect _bounds(Stroke stroke) {
  // ignore: invalid_use_of_protected_member
  final points = stroke.points;
  return Rect.fromLTRB(
    points.map((p) => p.x).reduce(min),
    points.map((p) => p.y).reduce(min),
    points.map((p) => p.x).reduce(max),
    points.map((p) => p.y).reduce(max),
  );
}
