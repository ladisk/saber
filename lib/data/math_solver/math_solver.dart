import 'dart:typed_data';

/// One solved expression from [MathSolver.solve].
class SolvedExpression {
  const new({required this.input, required this.result, this.note});

  /// The confirmed input, as LaTeX.
  final String input;

  /// The answer, as LaTeX.
  final String result;

  /// A short remark, e.g. an assumption that was made.
  final String? note;

  factory fromJson(Map<String, dynamic> json) => SolvedExpression(
    input: json['input'] as String? ?? '',
    result: json['result'] as String? ?? '',
    note: switch (json['note']) {
      final String note when note.trim().isNotEmpty => note.trim(),
      _ => null,
    },
  );
}

/// Thrown when handwriting can't be read or solved.
class MathSolverException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads handwritten maths and solves it.
abstract class MathSolver {
  /// Transcribes the handwriting in [png] to LaTeX, one entry per expression.
  Future<List<String>> recognize(Uint8List png);

  /// Solves the confirmed [expressions], given as LaTeX.
  Future<List<SolvedExpression>> solve(List<String> expressions);
}
