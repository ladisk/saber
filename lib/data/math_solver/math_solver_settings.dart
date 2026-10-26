import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';

/// Keeps the Maths solver settings in a file next to the notes,
/// so they sync (encrypted) to every device on the same account.
///
/// The file is synced like a note: the newest version wins,
/// so the last change made on any device is used everywhere.
abstract final class MathSolverSettings {
  static final log = Logger('MathSolverSettings');

  /// Hidden from the browse page because it isn't a note.
  static const filePath = '/_math_solver.json';

  /// Settings saved before syncing existed get the oldest date the syncer
  /// keeps, so a change made on another device always wins over them,
  /// and two such devices keep their own settings until one is changed.
  static DateTime get migratedDate => stows.fileSyncResyncEverythingDate.value;

  static var _listening = false;

  /// Applies the synced settings and applies them again
  /// whenever another device changes them.
  static Future<void> init() async {
    await _waitUntilRead();
    if (!_listening) {
      _listening = true;
      FileManager.fileWriteStream.stream
          .where((op) => op.type == .write && op.filePath == filePath)
          .listen((_) => load());
    }

    if (FileManager.doesFileExist(filePath)) {
      await load();
    } else if (!_allDefault) {
      await stows.fileSyncResyncEverythingDate.waitUntilRead();
      await save(lastModified: migratedDate);
    }
  }

  /// Writes the current settings to [filePath] and uploads them.
  static Future<void> save({DateTime? lastModified}) => FileManager.writeFile(
    filePath,
    utf8.encode(jsonEncode(toJson())),
    awaitWrite: true,
    lastModified: lastModified,
  );

  /// Applies the settings in [filePath], if it exists.
  static Future<void> load() async {
    final bytes = await FileManager.readFile(filePath);
    if (bytes == null) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      await _waitUntilRead();
      fromJson(json);
    } on FormatException catch (e) {
      log.warning('Ignoring invalid $filePath: $e');
    }
  }

  static Map<String, dynamic> toJson() => {
    'baseUrl': stows.mathApiBaseUrl.value,
    'model': stows.mathModel.value,
    'solveModel': stows.mathSolveModel.value,
    'setReasoningEffort': stows.mathSetReasoningEffort.value,
    'apiKey': stows.mathApiKey.value,
  };

  static void fromJson(Map<String, dynamic> json) {
    if (json['baseUrl'] case final String value)
      stows.mathApiBaseUrl.value = value;
    if (json['model'] case final String value) stows.mathModel.value = value;
    if (json['solveModel'] case final String value)
      stows.mathSolveModel.value = value;
    if (json['setReasoningEffort'] case final bool value)
      stows.mathSetReasoningEffort.value = value;
    if (json['apiKey'] case final String value) stows.mathApiKey.value = value;
  }

  static bool get _allDefault =>
      stows.mathApiBaseUrl.value == stows.mathApiBaseUrl.defaultValue &&
      stows.mathModel.value == stows.mathModel.defaultValue &&
      stows.mathSolveModel.value == stows.mathSolveModel.defaultValue &&
      stows.mathSetReasoningEffort.value ==
          stows.mathSetReasoningEffort.defaultValue &&
      stows.mathApiKey.value == stows.mathApiKey.defaultValue;

  static Future<void> _waitUntilRead() => Future.wait([
    stows.mathApiBaseUrl.waitUntilRead(),
    stows.mathModel.waitUntilRead(),
    stows.mathSolveModel.waitUntilRead(),
    stows.mathSetReasoningEffort.waitUntilRead(),
    stows.mathApiKey.waitUntilRead(),
  ]);
}
