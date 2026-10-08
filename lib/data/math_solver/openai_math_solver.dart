import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:saber/data/math_solver/math_solver.dart';

export 'package:saber/data/math_solver/math_solver.dart';

/// A [MathSolver] that uses any service with an OpenAI-compatible
/// chat completions API, such as OpenRouter.
///
/// The model works out the results itself: nothing is computed in a
/// sandbox, so the results should be checked.
class OpenAiMathSolver implements MathSolver {
  new({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;

  /// The API's base URL, e.g. `https://openrouter.ai/api/v1`.
  final String baseUrl;
  final String model;
  final http.Client _http;

  static final log = Logger('OpenAiMathSolver');

  static const defaultBaseUrl = 'https://openrouter.ai/api/v1';
  static const defaultModel = 'google/gemini-3.8-flash';

  static const timeout = Duration(minutes: 3);

  Uri get endpoint => Uri.parse(
    '${baseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
  );

  static const _recognizeSystem = '''
You transcribe handwritten mathematics from an engineering notes app into LaTeX.
- Return one entry per separate expression, equation or line, in reading order.
- Keep every number, symbol and unit exactly as written. Do not solve, simplify or correct anything.
- Write units upright with a thin space, e.g. 9.81\\,\\mathrm{m/s^2} or 3\\,\\mathrm{kN}. Do not use siunitx (\\SI, \\si, \\qty).
- Use only LaTeX that KaTeX can render. Do not wrap entries in \$ or \\[ \\].
- If nothing mathematical is readable, return an empty list.
Reply with only this JSON object:
{"expressions": ["<LaTeX>", ...]}''';

  static const _solveSystem = '''
You solve handwritten mathematics for an engineering notes app. The input is a numbered list of LaTeX expressions that the user has checked.
- Treat the list as one worksheet in order: a later expression may use quantities defined earlier (e.g. m = 2\\,\\mathrm{kg}, then F = m \\cdot 9.81\\,\\mathrm{m/s^2}).
- Work carefully: convert units to SI first, do the arithmetic step by step, and check each result before giving it.
- An expression without unknowns is evaluated. An equation (or several equations sharing unknowns) is solved for its unknowns. A definition such as a = 3 just records a value; repeat it as the result.
- Give results with units in a sensible SI unit (e.g. N, kN, m/s, MPa), numbers to 4 significant digits unless the result is exact.
- Results are LaTeX that KaTeX can render: units upright with a thin space (12.5\\,\\mathrm{m/s}), no siunitx, no \$ delimiters. For an evaluated expression give the value only; for a solved equation give the unknowns, e.g. x = 2,\\; y = -1.
- If an expression is ambiguous, make the most likely reading and say so in note; if it cannot be solved, say why in note and leave result empty.
You may work through the calculation first. End your reply with only this JSON object and nothing after it:
{"results": [{"input": "<the LaTeX input>", "result": "<LaTeX result>", "note": "<short remark or empty>"}]}''';

  @override
  Future<List<String>> recognize(Uint8List png) async {
    final reply = await _complete([
      {'role': 'system', 'content': _recognizeSystem},
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': 'Transcribe the handwritten mathematics to LaTeX.',
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,${base64Encode(png)}'},
          },
        ],
      },
    ]);

    final expressions = decodeJson(reply, key: 'expressions')['expressions'];
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
    final reply = await _complete([
      {'role': 'system', 'content': _solveSystem},
      {
        'role': 'user',
        'content': [
          for (var i = 0; i < expressions.length; i++)
            '${i + 1}. ${expressions[i]}',
        ].join('\n'),
      },
    ]);

    final results = decodeJson(reply, key: 'results')['results'];
    if (results is! List) {
      throw const MathSolverException('The reply had no results.');
    }
    return [
      for (final r in results)
        if (r is Map<String, dynamic>) SolvedExpression.fromJson(r),
    ];
  }

  /// Sends [messages] and returns the text of the reply.
  Future<String> _complete(List<Map<String, dynamic>> messages) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({'model': model, 'messages': messages}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const MathSolverException('The service took too long to reply.');
    } on Exception catch (e) {
      log.warning('Request failed', e);
      throw MathSolverException('Could not reach $baseUrl: $e');
    }

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw MathSolverException(
        'Unexpected reply from the service (HTTP ${response.statusCode}).',
      );
    }
    final error = json is Map<String, dynamic> ? json['error'] : null;
    if (response.statusCode != 200 ||
        json is! Map<String, dynamic> ||
        error != null) {
      final message = error is Map<String, dynamic> ? error['message'] : error;
      log.warning('HTTP ${response.statusCode}: $message');
      throw MathSolverException(switch (response.statusCode) {
        401 => 'The API key was not accepted.',
        402 => 'Not enough credit on this API key.',
        404 => 'Model "$model" was not found: $message',
        429 => 'Too many requests. Try again in a minute.',
        _ => 'Service error (HTTP ${response.statusCode}): $message',
      });
    }

    final choice = switch (json['choices']) {
      [final Map<String, dynamic> choice, ...] => choice,
      _ => throw const MathSolverException('The reply was empty.'),
    };
    switch (choice['finish_reason']) {
      case 'length':
        throw const MathSolverException('The reply was cut off.');
      case 'content_filter':
        throw const MathSolverException('The model declined this request.');
    }
    final content = (choice['message'] as Map?)?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const MathSolverException('The reply was empty.');
    }
    return content;
  }

  /// Decodes the last JSON object in [text] that has [key], ignoring
  /// anything around it such as working or a Markdown code fence.
  static Map<String, dynamic> decodeJson(String text, {required String key}) {
    final end = text.lastIndexOf('}');
    for (
      var start = end < 0 ? -1 : text.lastIndexOf('{', end);
      start >= 0;
      start = start == 0 ? -1 : text.lastIndexOf('{', start - 1)
    ) {
      try {
        final json = jsonDecode(text.substring(start, end + 1));
        if (json is Map<String, dynamic> && json.containsKey(key)) return json;
      } on FormatException {
        // try an earlier brace
      }
    }
    log.warning('No JSON in reply: $text');
    throw const MathSolverException('Could not understand the reply.');
  }
}
