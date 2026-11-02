import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupMockPathProvider();
  setupMockFlutterSecureStorage();
  FlavorConfig.setup();

  setUpAll(FileManager.init);
  setUp(() async {
    for (final dir in ['/emptied', '/kept', '/leftover', '/made here']) {
      await FileManager.deleteDirectory(dir);
    }
    stows.fileSyncAlreadyDeleted.value.clear();
    stows.fileSyncPendingDeletions.value.clear();
  });

  Future<void> write(String path) =>
      FileManager.writeFile(path, [1, 2, 3], awaitWrite: true);
  bool exists(String dir) =>
      Directory(FileManager.documentsDirectory + dir).existsSync();

  test('a downloaded deletion removes the folders it leaves empty', () async {
    await write('/emptied/course/2026/note.sbn2');
    await write('/emptied/other.sbn2');

    final syncFile = SaberSyncFile(
      remoteFile: null,
      remotePath: 'Saber/encrypted.sbe',
      localFile: FileManager.getFile('/emptied/course/2026/note.sbn2'),
    );
    await syncer.interface.writeLocalFile(syncFile, Uint8List(0));

    expect(FileManager.doesFileExist('/emptied/course/2026/note.sbn2'), false);
    expect(exists('/emptied/course/2026'), false);
    expect(exists('/emptied/course'), false);
    // still holds a note
    expect(exists('/emptied'), true);
  });

  test('folders that are not empty stay', () async {
    await write('/kept/a.sbn2');
    await write('/kept/b.sbn2');
    await FileManager.deleteFile('/kept/a.sbn2', alsoUpload: false);
    await FileManager.deleteEmptyParentDirectories('/kept/a.sbn2');
    expect(exists('/kept'), true);
  });

  test('leftover empty folders from earlier deletions are removed', () async {
    // Left behind by a deletion downloaded by an older version
    await Directory('${FileManager.documentsDirectory}/leftover/course')
        .create(recursive: true);
    stows.fileSyncAlreadyDeleted.value.add('/leftover/course/note.sbn2');
    // An empty folder made on this device
    await Directory('${FileManager.documentsDirectory}/made here')
        .create(recursive: true);

    await SaberSyncInterface.deleteLeftoverFolders();

    expect(exists('/leftover/course'), false);
    expect(exists('/leftover'), false);
    expect(exists('/made here'), true);
  });
}
