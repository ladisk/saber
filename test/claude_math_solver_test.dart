import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saber/data/math_solver/claude_math_solver.dart';

void main() {
  late List<http.Request> requests;
  setUp(() => requests = []);

  /// A solver whose API replies are taken from [replies] in turn.
  ClaudeMathSolver solver(List<(int, Object)> replies) {
    var i = 0;
    return ClaudeMathSolver(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        final (status, body) = replies[i++];
        return http.Response.bytes(
          utf8.encode(body is String ? body : jsonEncode(body)),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  Map<String, dynamic> message(List<Object> content, {String? stop}) => {
    'type': 'message',
    'role': 'assistant',
    'content': content,
    'stop_reason': stop ?? 'end_turn',
  };
  Map<String, String> text(String text) => {'type': 'text', 'text': text};
  Map<String, dynamic> body(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  test('recognize sends the image and reads the expressions', () async {
    final png = Uint8List.fromList([1, 2, 3]);
    final expressions = await solver([
      (
        200,
        message([
          text(r'{"expressions": ["F = 3\\,\\mathrm{kg} \\cdot 2", " "]}'),
        ]),
      ),
    ]).recognize(png);

    expect(expressions, [r'F = 3\,\mathrm{kg} \cdot 2']);

    final request = requests.single;
    expect(request.url, ClaudeMathSolver.endpoint);
    expect(request.headers['x-api-key'], 'test-key');
    expect(request.headers['anthropic-version'], '2023-06-01');
    expect(
      request.headers['anthropic-beta'],
      'server-side-fallback-2026-07-01',
    );

    final json = body(request);
    expect(json['model'], 'claude-opus-5-5');
    expect(json['fallbacks'], 'default');
    expect(json['output_config']['format']['type'], 'json_schema');
    final image = json['messages'][0]['content'][0];
    expect(image['type'], 'image');
    expect(image['source']['media_type'], 'image/png');
    expect(image['source']['data'], base64Encode(png));
  });

  test('solve uses code execution and resumes a paused turn', () async {
    final paused = message([
      {
        'type': 'server_tool_use',
        'id': 'srvtoolu_1',
        'name': 'bash_code_execution',
        'input': {'command': 'python3 -c "print(6)"'},
      },
    ], stop: 'pause_turn');
    final results = await solver([
      (200, paused),
      (
        200,
        message([
          text('Done.'),
          text(
            '```json\n'
            r'{"results": [{"input": "3 \\cdot 2", "result": "6", "note": ""},'
            r' {"input": "x^2 = 4", "result": "x = \\pm 2", "note": "real"}]}'
            '\n```',
          ),
        ]),
      ),
    ]).solve([r'3 \cdot 2', 'x^2 = 4']);

    expect(results.map((r) => r.result), ['6', r'x = \pm 2']);
    expect(results.map((r) => r.note), [null, 'real']);

    expect(requests, hasLength(2));
    final first = body(requests[0]);
    expect(first['tools'], [
      {'type': 'code_execution_20260521', 'name': 'code_execution'},
    ]);
    expect(first['messages'][0]['content'], '1. 3 \\cdot 2\n2. x^2 = 4');
    // the paused turn is sent back unchanged, with no new user message
    final second = body(requests[1])['messages'] as List;
    expect(second, hasLength(2));
    expect(second.last, {'role': 'assistant', 'content': paused['content']});
  });

  test('API errors become readable messages', () async {
    expect(
      () => solver([
        (
          401,
          {
            'type': 'error',
            'error': {'type': 'authentication_error', 'message': 'bad key'},
          },
        ),
      ]).recognize(Uint8List(0)),
      throwsA(
        isA<MathSolverException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
  });

  test('a refusal is reported, not parsed', () async {
    expect(
      () => solver([(200, message([], stop: 'refusal'))]).solve(['1 + 1']),
      throwsA(
        isA<MathSolverException>().having(
          (e) => e.message,
          'message',
          contains('declined'),
        ),
      ),
    );
  });

  test('a reply without JSON is reported', () async {
    expect(
      () => solver([
        (200, message([text('I cannot read this.')])),
      ]).recognize(Uint8List(0)),
      throwsA(isA<MathSolverException>()),
    );
  });
}
