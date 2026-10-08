import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:saber/data/math_solver/claude_math_solver.dart';

/// Inserts the rendered result into the note.
/// [size] is the result's size in logical pixels.
typedef InsertMathResult = void Function(Uint8List png, Size size);

enum _Step { apiKey, reading, confirm, solving, result, error }

/// [result] as it is written next to the handwriting: a bare value
/// gets an equals sign, so it reads as the answer to what is left of it.
String resultForNote(String result) =>
    result.contains('=') ? result : '= $result';

/// Reads the selected handwriting as LaTeX, lets the user check and edit it,
/// then solves it and offers to insert the result into the note.
///
/// English only: this fork doesn't regenerate translations.
class MathSolverDialog extends StatefulWidget {
  const new({
    super.key,
    required this.selectionPng,
    required this.apiKey,
    required this.onApiKeyChanged,
    required this.createSolver,
    required this.onInsert,
  });

  /// The selected handwriting, rendered by [SelectionImage].
  final Uint8List selectionPng;

  /// The saved Anthropic API key, or an empty string.
  final String apiKey;
  final ValueChanged<String> onApiKeyChanged;

  final MathSolver Function(String apiKey) createSolver;
  final InsertMathResult onInsert;

  @override
  State<MathSolverDialog> createState() => _MathSolverDialogState();
}

class _MathSolverDialogState extends State<MathSolverDialog> {
  late var _step = widget.apiKey.isEmpty ? _Step.apiKey : _Step.reading;
  late var _apiKey = widget.apiKey;
  late MathSolver _solver;

  final _keyController = TextEditingController();
  final _expressionControllers = <TextEditingController>[];
  var _results = const <SolvedExpression>[];

  var _error = '';
  VoidCallback? _retry;

  final _resultKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (_step == .reading) _read();
  }

  @override
  void dispose() {
    _keyController.dispose();
    for (final controller in _expressionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _saveKey() {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    _apiKey = key;
    widget.onApiKeyChanged(key);
    _read();
  }

  void _changeKey() => setState(() {
    _keyController.text = _apiKey;
    _step = .apiKey;
  });

  Future<void> _read() async {
    setState(() => _step = .reading);
    _solver = widget.createSolver(_apiKey);
    try {
      final expressions = await _solver.recognize(widget.selectionPng);
      if (!mounted) return;
      if (expressions.isEmpty) {
        return _fail('No maths found in the selection.', _read);
      }
      setState(() {
        for (final controller in _expressionControllers) {
          controller.dispose();
        }
        _expressionControllers
          ..clear()
          ..addAll(expressions.map((e) => TextEditingController(text: e)));
        _step = .confirm;
      });
    } on MathSolverException catch (e) {
      _fail(e.message, _read);
    }
  }

  Future<void> _solve() async {
    final expressions = [
      for (final controller in _expressionControllers)
        if (controller.text.trim().isNotEmpty) controller.text.trim(),
    ];
    if (expressions.isEmpty) return;
    setState(() => _step = .solving);
    try {
      final results = await _solver.solve(expressions);
      if (!mounted) return;
      if (results.isEmpty) return _fail('Nothing could be solved.', _solve);
      setState(() {
        _results = results;
        _step = .result;
      });
    } on MathSolverException catch (e) {
      _fail(e.message, _solve);
    }
  }

  void _fail(String message, VoidCallback retry) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _retry = retry;
      _step = .error;
    });
  }

  Future<void> _insert() async {
    final boundary =
        _resultKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 4);
    final Uint8List png;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      png = data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
    widget.onInsert(png, boundary.size);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(
        text: [
          for (final r in _results)
            if (r.result.isNotEmpty) resultForNote(r.result),
        ].join('\n'),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('LaTeX copied')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Solve maths'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: _content(context)),
      ),
      actions: _actions(context),
    );
  }

  Widget _content(BuildContext context) {
    final textTheme = TextTheme.of(context);
    switch (_step) {
      case .apiKey:
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            const Text(
              'Handwriting is read and solved by Claude. '
              'The selection is sent to Anthropic as an image.',
            ),
            const SizedBox(height: 8),
            Text(
              'Create an API key at console.anthropic.com. '
              'It is stored on this device only.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Anthropic API key',
                hintText: 'sk-ant-...',
              ),
              onSubmitted: (_) => _saveKey(),
            ),
          ],
        );
      case .reading:
        return const _Progress('Reading handwriting...');
      case .solving:
        return const _Progress('Solving...');
      case .error:
        return Text(
          _error,
          style: TextStyle(color: ColorScheme.of(context).error),
        );
      case .confirm:
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            const Text('Check what was read, and fix it if needed:'),
            for (final (i, controller) in _expressionControllers.indexed) ...[
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _LatexView(controller.text),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('expression $i'),
                      controller: controller,
                      style: const TextStyle(fontFamily: 'FiraMono'),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _expressionControllers.removeAt(i).dispose();
                    }),
                  ),
                ],
              ),
            ],
          ],
        );
      case .result:
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            for (final r in _results) ...[
              _LatexView(r.input),
              if (r.note != null) Text(r.note!, style: textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            const Divider(),
            Text('Inserted into the note:', style: textTheme.bodySmall),
            const SizedBox(height: 8),
            // The result as it will look on the page: black on white,
            // inverted with the note in dark mode.
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: .centerLeft,
                  child: RepaintBoundary(
                    key: _resultKey,
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        for (final r in _results)
                          if (r.result.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: _LatexView(
                                resultForNote(r.result),
                                color: Colors.black,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  List<Widget> _actions(BuildContext context) {
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );
    return switch (_step) {
      .apiKey => [
        cancel,
        FilledButton(onPressed: _saveKey, child: const Text('Save')),
      ],
      .reading || .solving => [cancel],
      .error => [
        TextButton(onPressed: _changeKey, child: const Text('API key')),
        cancel,
        FilledButton(onPressed: _retry, child: const Text('Retry')),
      ],
      .confirm => [
        cancel,
        FilledButton(
          onPressed: _expressionControllers.isEmpty ? null : _solve,
          child: const Text('Solve'),
        ),
      ],
      .result => [
        TextButton(onPressed: _copy, child: const Text('Copy LaTeX')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(onPressed: _insert, child: const Text('Insert')),
      ],
    };
  }
}

class _Progress extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      const SizedBox(width: 16),
      Text(label),
    ],
  );
}

/// Renders [latex], or shows it as text if it can't be parsed.
class _LatexView extends StatelessWidget {
  const new(this.latex, {this.color});

  final String latex;
  final Color? color;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: .horizontal,
    child: Math.tex(
      latex,
      mathStyle: .display,
      textStyle: TextStyle(fontSize: 20, color: color),
      onErrorFallback: (error) => Text(
        latex,
        style: TextStyle(
          fontFamily: 'FiraMono',
          color: ColorScheme.of(context).error,
        ),
      ),
    ),
  );
}
