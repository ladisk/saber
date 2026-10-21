import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';

void main() {
  SaberSyncFile file(String path) =>
      SaberSyncFile(remoteFile: null, remotePath: path, localFile: File(path));

  test('notes are synced after their images', () {
    final files = [
      file('/a.sbn2'),
      file('/a.sbn2.0'),
      file('/b.sbn2'),
      file('/a.sbn2.1'),
      file('/b.sbn2.p'),
    ];
    expect(SaberSyncInterface.notesLast(files).map((f) => f.remotePath), [
      '/a.sbn2.0',
      '/a.sbn2.1',
      '/b.sbn2.p',
      '/a.sbn2',
      '/b.sbn2',
    ]);
  });

  test('isAsset matches numbered note files only', () {
    expect(SaberSyncInterface.isAsset('/a.sbn2.0'), isTrue);
    expect(SaberSyncInterface.isAsset('/a.sbn2.12'), isTrue);
    expect(SaberSyncInterface.isAsset('/a.sbn2'), isFalse);
    expect(SaberSyncInterface.isAsset('/a.sbn2.p'), isFalse);
  });
}
