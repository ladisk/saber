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
    stows.fileSyncPendingDeletions.value.clear();
    // Left over from an earlier run
    for (final dir in [
      '/deletions',
      '/old folder',
      '/new folder',
      '/back',
      '/away',
    ]) {
      await FileManager.deleteDirectory(dir);
    }
    stows.fileSyncPendingDeletions.value.clear();
  });

  Future<void> write(String path) =>
      FileManager.writeFile(path, [1, 2, 3], awaitWrite: true);

  test('a deleted note and its assets wait to be uploaded', () async {
    await write('/deletions/note.sbn2');
    await write('/deletions/note.sbn2.0');
    await write('/deletions/note.sbn2.p');

    await FileManager.deleteFile('/deletions/note.sbn2');

    expect(
      SaberSyncInterface.pendingDeletions(),
      unorderedEquals([
        '/deletions/note.sbn2',
        '/deletions/note.sbn2.0',
        '/deletions/note.sbn2.p',
      ]),
    );
    expect(
      SaberSyncInterface.isPendingDeletion('/deletions/note.sbn2'),
      isTrue,
    );
  });

  test('a moved folder deletes the old paths', () async {
    await write('/old folder/a.sbn2');
    await write('/old folder/sub/b.sbn2');

    await FileManager.moveDirectory('/old folder', '/new folder');

    expect(
      SaberSyncInterface.pendingDeletions(),
      unorderedEquals(['/old folder/a.sbn2', '/old folder/sub/b.sbn2']),
    );
    expect(SaberSyncInterface.isPendingDeletion('/new folder/a.sbn2'), isFalse);
  });

  test('a file that exists again is no longer a deletion', () async {
    await write('/back/note.sbn2');
    await FileManager.moveFile('/back/note.sbn2', '/away/note.sbn2');
    expect(SaberSyncInterface.pendingDeletions(), ['/back/note.sbn2']);

    await FileManager.moveFile('/away/note.sbn2', '/back/note.sbn2');

    expect(SaberSyncInterface.isPendingDeletion('/back/note.sbn2'), isFalse);
    expect(SaberSyncInterface.pendingDeletions(), ['/away/note.sbn2']);
  });
}
