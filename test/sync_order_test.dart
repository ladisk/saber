import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextcloud/webdav.dart';
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

  test('remote files are looked up by path', () async {
    WebDavFile remote(String name) => WebDavFile(
      response: WebDavResponse(
        href: '/remote.php/webdav/Saber/$name.sbe',
        propstats: const [],
      ),
    );
    final files = [for (var i = 0; i < 20000; i++) remote('f$i')];
    SaberSyncInterface.remoteFiles = {for (final f in files) f.path.path: f};
    addTearDown(() => SaberSyncInterface.remoteFiles = {});

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < files.length; i++) {
      final found = await const SaberSyncInterface().getWebDavFile(
        'Saber/f$i.sbe',
      );
      expect(found, same(files[i]));
    }
    // A linear search took seconds for this many files
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('last modified dates are compared in whole seconds', () {
    BestFile newer(DateTime local, DateTime remote) =>
        SaberSyncInterface.newerFile(
          local: local,
          remote: remote,
          onEqualFiles: .remote,
        );
    final upload = DateTime.utc(2026, 10, 25, 16, 30, 16);

    // Equal: the server dropped the milliseconds of the local file
    for (final ms in [0, 499, 611, 999]) {
      final local = upload.add(Duration(milliseconds: ms));
      expect(newer(local, upload), BestFile.remote, reason: '$ms ms');
    }
    // A change a second later is newer
    expect(
      newer(upload.add(const Duration(seconds: 1)), upload),
      BestFile.local,
    );
    expect(
      newer(upload, upload.add(const Duration(seconds: 1))),
      BestFile.remote,
    );
  });
}
