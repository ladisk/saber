import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saber/data/math_solver/openai_math_solver.dart';

void main() {
  late List<http.Request> requests;
  setUp(() => requests = []);

  /// A solver whose API replies are taken from [replies] in turn.
  OpenAiMathSolver solver(
    List<(int, Object)> replies, {
    String? solveModel,
    bool setReasoningEffort = false,
  }) {
    var i = 0;
    return OpenAiMathSolver(
      apiKey: 'test-key',
      baseUrl: 'https://example.com/api/v1/',
      model: 'some/model',
      solveModel: solveModel,
      setReasoningEffort: setReasoningEffort,
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

  Map<String, dynamic> reply(String content, {String finish = 'stop'}) => {
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
        'finish_reason': finish,
      },
    ],
  };
  Map<String, dynamic> body(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  test('recognize sends the image and reads the expressions', () async {
    final png = Uint8List.fromList([1, 2, 3]);
    final expressions = await solver([
      (200, reply(r'{"expressions": ["F = 3\\,\\mathrm{kg} \\cdot 2", " "]}')),
    ]).recognize(png);

    expect(expressions, [r'F = 3\,\mathrm{kg} \cdot 2']);

    final request = requests.single;
    expect(
      request.url,
      Uri.parse('https://example.com/api/v1/chat/completions'),
    );
    expect(request.headers['authorization'], 'Bearer test-key');
    final json = body(request);
    expect(json['model'], 'some/model');
    expect(json.containsKey('reasoning_effort'), isFalse);
    final content = (json['messages'] as List).last['content'] as List;
    expect(
      content.last['image_url']['url'],
      'data:image/png;base64,${base64Encode(png)}',
    );
  });

  test('solve reads the JSON after the working', () async {
    final results = await solver([
      (
        200,
        reply('''
m = 2 kg, so F = 2 \\cdot 9.81 = 19.62\\,\\mathrm{N} and \\frac{1}{2}.
```json
{"results": [{"input": "F = m g", "result": "19.62\\\\,\\\\mathrm{N}", "note": ""}]}
```'''),
      ),
    ]).solve(['m = 2', 'F = m g']);

    expect(results.single.input, 'F = m g');
    expect(results.single.result, r'19.62\,\mathrm{N}');
    expect(results.single.note, isNull);
    final messages = body(requests.single)['messages'] as List;
    expect(messages.last['content'], '1. m = 2\n2. F = m g');
  });

  test('solving uses its own model and effort when set', () async {
    final s = solver(
      [
        (200, reply('{"expressions": ["1 + 1"]}')),
        (200, reply('{"results": [{"input": "1 + 1", "result": "2"}]}')),
      ],
      solveModel: ' strong/model ',
      setReasoningEffort: true,
    );
    await s.recognize(Uint8List(0));
    await s.solve(['1 + 1']);

    final [read, solve] = requests.map(body).toList();
    expect(read['model'], 'some/model');
    expect(read['reasoning_effort'], OpenAiMathSolver.recognizeEffort);
    expect(solve['model'], 'strong/model');
    expect(solve['reasoning_effort'], OpenAiMathSolver.solveEffort);
  });

  test('an empty solving model falls back to the model', () async {
    await solver([
      (200, reply('{"results": []}')),
    ], solveModel: '  ').solve(['1']);

    expect(body(requests.single)['model'], 'some/model');
  });

  test('errors are reported in plain words', () async {
    Future<String> failure(int status, Object body) async {
      try {
        await solver([(status, body)]).solve(['1']);
      } on MathSolverException catch (e) {
        return e.message;
      }
      fail('no exception');
    }

    expect(
      await failure(401, {
        'error': {'message': 'bad key'},
      }),
      'The API key was not accepted.',
    );
    expect(
      await failure(402, {
        'error': {'message': 'no credit'},
      }),
      'Not enough credit on this API key.',
    );
    // OpenRouter can report errors with HTTP 200
    expect(
      await failure(200, {
        'error': {'message': 'provider down'},
      }),
      contains('provider down'),
    );
    expect(
      await failure(200, reply('{"results": [', finish: 'length')),
      'The reply was cut off.',
    );
    expect(
      await failure(200, reply('I cannot read that.')),
      'Could not understand the reply.',
    );
  });
}
