import 'dart:io';

import 'package:onenote_import/onenote_import.dart';
import 'package:test/test.dart';

/// Set to a `.one` file with ink, e.g. `Schnelle Notizen.one`
/// from the tests of https://github.com/msiemens/onenote.rs.
final _sample = Platform.environment['ONENOTE_SAMPLE'];

void main() {
  test('rejects a file that is not OneNote', () async {
    final dir = await Directory.systemTemp.createTemp('onenote_import_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/note.one')..writeAsStringSync('not onenote');

    expect(
      readOneNoteFile(file.path, imageDir: dir.path),
      throwsA(isA<OneNoteImportException>()),
    );
  });

  test('reads strokes and images', () async {
    final dir = await Directory.systemTemp.createTemp('onenote_import_test');
    addTearDown(() => dir.delete(recursive: true));

    final sections = await readOneNoteFile(_sample!, imageDir: dir.path);

    final pages = sections.expand((s) => s.pages).toList();
    expect(pages, isNotEmpty);
    final strokes = pages.expand((p) => p.strokes).toList();
    expect(strokes, isNotEmpty);
    for (final stroke in strokes) {
      expect(stroke.points.length, isNonZero);
      expect(stroke.points.length.isEven, isTrue);
      expect(stroke.width, greaterThan(0));
    }
    for (final image in pages.expand((p) => p.images)) {
      expect(File(image.path).existsSync(), isTrue);
    }
  }, skip: _sample == null ? 'ONENOTE_SAMPLE is not set' : false);
}
