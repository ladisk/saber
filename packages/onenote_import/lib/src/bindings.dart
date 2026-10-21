import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Parses a OneNote file and writes its images to a directory.
/// Returns JSON that must be freed with [onenoteImportFree].
@Native<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>(
  symbol: 'onenote_import_file',
)
external Pointer<Utf8> onenoteImportFile(
  Pointer<Utf8> path,
  Pointer<Utf8> imageDir,
);

@Native<Void Function(Pointer<Utf8>)>(symbol: 'onenote_import_free')
external void onenoteImportFree(Pointer<Utf8> json);
