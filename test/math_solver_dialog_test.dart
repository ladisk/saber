import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/toolbar/math_solver_dialog.dart';
import 'package:saber/data/math_solver/claude_math_solver.dart';
import 'package:saber/data/math_solver/selection_image.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

class _FakeSolver implements MathSolver {
  final solved = <List<String>>[];

  @override
  Future<List<String>> recognize(Uint8List png) async => [r'2 \cdot 3', 'y'];

  @override
  Future<List<SolvedExpression>> solve(List<String> expressions) async {
    solved.add(expressions);
    return [
      for (final e in expressions) SolvedExpression(input: e, result: '6'),
    ];
  }
}

Stroke _stroke(ToolId toolId, List<Offset> points) => Stroke(
  color: Colors.red,
  pressureEnabled: false,
  options: StrokeOptions(size: 4),
  pageIndex: 0,
  page: const HasSize(Size(1000, 1400)),
  toolId: toolId,
)..addPoints(points);

void main() {
  testWidgets('SelectionImage renders the writing, without highlighting', (
    tester,
  ) async {
    final pen = _stroke(.fountainPen, [
      const Offset(100, 100),
      const Offset(200, 150),
    ]);
    final highlight = _stroke(.highlighter, [
      Offset.zero,
      const Offset(900, 900),
    ]);

    final writing = SelectionImage.writing([pen, highlight]);
    expect(writing, [pen]);

    final png = (await tester.runAsync(() => SelectionImage.render(writing)))!;
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      return (await codec.getNextFrame()).image;
    });
    final bounds = SelectionImage.boundsOf(writing)
        .inflate(SelectionImage.padding);
    // small handwriting is enlarged 3 times
    expect(image!.width, (bounds.width * 3).ceil());
    expect(image.height, (bounds.height * 3).ceil());
  });

  testWidgets('asks for a key, reads, lets the user edit, solves, inserts', (
    tester,
  ) async {
    final solver = _FakeSolver();
    String? savedKey;
    String? solverKey;
    Size? insertedSize;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathSolverDialog(
            selectionPng: Uint8List(0),
            apiKey: '',
            onApiKeyChanged: (key) => savedKey = key,
            createSolver: (key) {
              solverKey = key;
              return solver;
            },
            onInsert: (png, size) {
              expect(png, isNotEmpty);
              insertedSize = size;
            },
          ),
        ),
      ),
    );

    // no key saved yet
    await tester.enterText(find.byType(TextField), ' sk-ant-test ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedKey, 'sk-ant-test');
    expect(solverKey, 'sk-ant-test');

    // the recognised expressions can be edited or removed before solving
    expect(find.text('Check what was read, and fix it if needed:'), findsOne);
    await tester.enterText(find.byKey(const ValueKey('expression 0')), '2 * 3');
    await tester.tap(find.byTooltip('Remove').last);
    await tester.pump();
    await tester.tap(find.text('Solve'));
    await tester.pumpAndSettle();
    expect(solver.solved, [
      ['2 * 3'],
    ]);

    expect(find.text('Insert'), findsOne);
    await tester.runAsync(() async {
      await tester.tap(find.text('Insert'));
      // let the result be rendered to an image
      for (var i = 0; i < 20 && insertedSize == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(insertedSize, isNotNull);
    expect(insertedSize!.isEmpty, isFalse);
  });

  test('a bare value is written as the answer', () {
    expect(resultForNote(r'24.53\,\mathrm{N}'), r'= 24.53\,\mathrm{N}');
    expect(resultForNote('x = 2'), 'x = 2');
  });

  testWidgets('shows errors and offers a retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathSolverDialog(
            selectionPng: Uint8List(0),
            apiKey: 'saved',
            onApiKeyChanged: (_) {},
            createSolver: (_) => _FailingOnceSolver(() => attempts++),
            onInsert: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The Anthropic API key was not accepted.'), findsOne);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Check what was read, and fix it if needed:'), findsOne);
  });
}

class _FailingOnceSolver extends _FakeSolver {
  new(this.onAttempt);

  final VoidCallback onAttempt;
  static var _failed = false;

  @override
  Future<List<String>> recognize(Uint8List png) async {
    onAttempt();
    if (!_failed) {
      _failed = true;
      throw const MathSolverException(
        'The Anthropic API key was not accepted.',
      );
    }
    return super.recognize(png);
  }
}
