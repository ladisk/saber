import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/math_solver/math_solver_settings.dart';
import 'package:saber/data/prefs.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupMockPathProvider();
  setupMockFlutterSecureStorage();
  FlavorConfig.setup();

  const path = MathSolverSettings.filePath;

  setUpAll(() async {
    await FileManager.init();
    final file = FileManager.getFile(path);
    if (file.existsSync()) file.deleteSync();
  });

  test('existing settings are written with an old date', () async {
    stows.mathModel.value = 'device/model';
    stows.mathApiKey.value = 'key-1';

    await MathSolverSettings.init();

    final file = FileManager.getFile(path);
    expect(file.existsSync(), isTrue);
    expect(
      file.lastModifiedSync().isAtSameMomentAs(MathSolverSettings.migratedDate),
      isTrue,
    );
    final json = jsonDecode(file.readAsStringSync());
    expect(json['model'], 'device/model');
    expect(json['apiKey'], 'key-1');
  });

  test('saving writes all settings to the synced file', () async {
    stows.mathApiBaseUrl.value = 'https://example.com/v1';
    stows.mathModel.value = 'reader';
    stows.mathSolveModel.value = 'solver';
    stows.mathSetReasoningEffort.value = true;
    stows.mathApiKey.value = 'key-2';

    await MathSolverSettings.save();

    final file = FileManager.getFile(path);
    expect(
      file.lastModifiedSync().isAfter(MathSolverSettings.migratedDate),
      isTrue,
    );
    expect(jsonDecode(file.readAsStringSync()), {
      'baseUrl': 'https://example.com/v1',
      'model': 'reader',
      'solveModel': 'solver',
      'setReasoningEffort': true,
      'apiKey': 'key-2',
    });
  });

  test('a downloaded file is applied', () async {
    // The syncer writes downloads like this
    await FileManager.writeFile(
      path,
      utf8.encode(
        jsonEncode({
          'baseUrl': 'https://other.example/v1',
          'model': 'other-reader',
          'solveModel': '',
          'setReasoningEffort': false,
          'apiKey': 'key-3',
        }),
      ),
      awaitWrite: true,
      alsoUpload: false,
    );
    await pumpEventQueue();

    expect(stows.mathApiBaseUrl.value, 'https://other.example/v1');
    expect(stows.mathModel.value, 'other-reader');
    expect(stows.mathSolveModel.value, '');
    expect(stows.mathSetReasoningEffort.value, isFalse);
    expect(stows.mathApiKey.value, 'key-3');
  });

  test('the file is not shown as a note', () async {
    final children = await FileManager.getChildrenOfDirectory('/');
    expect(children!.files, isNot(contains('_math_solver.json')));
    expect(await FileManager.getRecentlyAccessed(), isNot(contains(path)));
  });
}
