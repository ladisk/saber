import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

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

/// A [MathSolver] that uses the Claude API.
///
/// Reading is one request with the selection as an image. Solving lets
/// Claude run Python (SymPy, with its units module) in Anthropic's code
/// execution sandbox, so the numbers are computed rather than guessed.
class ClaudeMathSolver implements MathSolver {
  new({required this.apiKey, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _http;

  static final log = Logger('ClaudeMathSolver');

  static final endpoint = Uri.parse('https://api.anthropic.com/v1/messages');
  static const model = 'claude-opus-5-5';

  /// If Claude's safety classifiers decline a request, the API re-runs it on
  /// a fallback model chosen by the refusal category.
  static const _fallbackBeta = 'server-side-fallback-2026-07-01';

  /// How many times a solve that hits the server-side tool loop limit
  /// (`pause_turn`) is resumed before giving up.
  static const _maxContinuations = 5;

  static const _recognizeSystem = '''
You transcribe handwritten mathematics from an engineering notes app into LaTeX.
- Return one entry per separate expression, equation or line, in reading order.
- Keep every number, symbol and unit exactly as written. Do not solve, simplify or correct anything.
- Write units upright with a thin space, e.g. 9.81\\,\\mathrm{m/s^2} or 3\\,\\mathrm{kN}. Do not use siunitx (\\SI, \\si, \\qty).
- Use only LaTeX that KaTeX can render. Do not wrap entries in \$ or \\[ \\].
- If nothing mathematical is readable, return an empty list.''';

  static const _solveSystem = '''
You solve handwritten mathematics for an engineering notes app. The input is a numbered list of LaTeX expressions that the user has checked.
- Treat the list as one worksheet in order: a later expression may use quantities defined earlier (e.g. m = 2\\,\\mathrm{kg}, then F = m \\cdot 9.81\\,\\mathrm{m/s^2}).
- Compute every result with Python in the code execution tool, using SymPy (sympy.physics.units for units). Do not do arithmetic in your head.
- An expression without unknowns is evaluated. An equation (or several equations sharing unknowns) is solved for its unknowns. A definition such as a = 3 just records a value; repeat it as the result.
- Give results with units in a sensible SI unit (e.g. N, kN, m/s, MPa), numbers to 4 significant digits unless the result is exact.
- Results are LaTeX that KaTeX can render: units upright with a thin space (12.5\\,\\mathrm{m/s}), no siunitx, no \$ delimiters. For an evaluated expression give the value only; for a solved equation give the unknowns, e.g. x = 2,\\; y = -1.
- If an expression is ambiguous, make the most likely reading and say so in note; if it cannot be solved, say why in note and leave result empty.
Finish with only this JSON object and nothing after it:
{"results": [{"input": "<the LaTeX input>", "result": "<LaTeX result>", "note": "<short remark or empty>"}]}''';

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    'anthropic-beta': _fallbackBeta,
  };

  @override
  Future<List<String>> recognize(Uint8List png) async {
    final response = await _post({
      'model': model,
      'max_tokens': 16000,
      'fallbacks': 'default',
      'system': _recognizeSystem,
      'output_config': {
        'effort': 'medium',
        'format': {
          'type': 'json_schema',
          'schema': {
            'type': 'object',
            'properties': {
              'expressions': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
            'required': ['expressions'],
            'additionalProperties': false,
          },
        },
      },
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/png',
                'data': base64Encode(png),
              },
            },
            {
              'type': 'text',
              'text': 'Transcribe the handwritten mathematics to LaTeX.',
            },
          ],
        },
      ],
    });
    _checkStopReason(response);

    final json = _decodeJson(_text(response));
    final expressions = json['expressions'];
    if (expressions is! List) {
      throw const MathSolverException('The reply had no expressions.');
    }
    return [
      for (final e in expressions)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  }

  @override
  Future<List<SolvedExpression>> solve(List<String> expressions) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': [
          for (var i = 0; i < expressions.length; i++)
            '${i + 1}. ${expressions[i]}',
        ].join('\n'),
      },
    ];

    Map<String, dynamic> response;
    var continuations = 0;
    while (true) {
      response = await _post({
        'model': model,
        'max_tokens': 16000,
        'fallbacks': 'default',
        'system': _solveSystem,
        'output_config': {'effort': 'medium'},
        'tools': [
          {'type': 'code_execution_20260521', 'name': 'code_execution'},
        ],
        'messages': messages,
      });
      if (response['stop_reason'] != 'pause_turn') break;
      if (++continuations > _maxContinuations) {
        throw const MathSolverException('Solving took too many steps.');
      }
      // Resume where the server-side loop stopped: send the paused turn
      // back as is, without a new user message.
      messages.add({'role': 'assistant', 'content': response['content']});
    }
    _checkStopReason(response);

    final json = _decodeJson(_text(response, lastOnly: true));
    final results = json['results'];
    if (results is! List) {
      throw const MathSolverException('The reply had no results.');
    }
    return [
      for (final r in results)
        if (r is Map<String, dynamic>) SolvedExpression.fromJson(r),
    ];
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final http.Response response;
    try {
      response = await _http.post(
        endpoint,
        headers: _headers,
        body: jsonEncode(body),
      );
    } on Exception catch (e) {
      log.warning('Request failed', e);
      throw MathSolverException('Could not reach the Claude API: $e');
    }

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw MathSolverException(
        'Unexpected reply from the Claude API (HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode != 200 || json is! Map<String, dynamic>) {
      final error = json is Map<String, dynamic> ? json['error'] : null;
      final message = error is Map<String, dynamic> ? error['message'] : null;
      log.warning('HTTP ${response.statusCode}: $message');
      throw MathSolverException(switch (response.statusCode) {
        401 => 'The Anthropic API key was not accepted.',
        429 => 'Too many requests to the Claude API. Try again in a minute.',
        _ => 'Claude API error (HTTP ${response.statusCode}): $message',
      });
    }
    return json;
  }

  static void _checkStopReason(Map<String, dynamic> response) {
    switch (response['stop_reason']) {
      case 'refusal':
        throw const MathSolverException('Claude declined this request.');
      case 'max_tokens':
        throw const MathSolverException('The reply was cut off.');
    }
  }

  /// The text of the reply, or only of its last text block when tool calls
  /// and commentary come before the answer.
  static String _text(Map<String, dynamic> response, {bool lastOnly = false}) {
    final texts = [
      for (final block in response['content'] as List? ?? const [])
        if (block is Map && block['type'] == 'text') block['text'] as String,
    ];
    if (texts.isEmpty) throw const MathSolverException('The reply was empty.');
    return lastOnly ? texts.last : texts.join();
  }

  /// Decodes the JSON object in [text], ignoring anything around it
  /// such as a Markdown code fence.
  static Map<String, dynamic> _decodeJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final json = jsonDecode(text.substring(start, end + 1));
        if (json is Map<String, dynamic>) return json;
      } on FormatException {
        // reported below
      }
    }
    log.warning('No JSON in reply: $text');
    throw const MathSolverException('Could not understand the reply.');
  }
}
