import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  setUpAll(() {
    FlavorConfig.setup();
    setupMockPathProvider();
    FileManager.documentsDirectory =
        '$tmpDir/saveUnchangedAssets/${FileManager.appRootDirectoryPrefix}';
  });

  test('an image is only written when it changed', () async {
    const path = '/note.sbn2.0';
    expect(await EditorState.writeAssetIfChanged(path, [1, 2, 3]), isTrue);
    expect(await EditorState.writeAssetIfChanged(path, [1, 2, 3]), isFalse);
    expect(await EditorState.writeAssetIfChanged(path, [1, 2, 4]), isTrue);
    expect(await EditorState.writeAssetIfChanged(path, [1, 2]), isTrue);
    expect(FileManager.getFile(path).readAsBytesSync(), [1, 2]);
  });
}
