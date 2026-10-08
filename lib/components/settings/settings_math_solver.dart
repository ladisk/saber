import 'package:flutter/material.dart';
import 'package:saber/components/settings/settings_button.dart';
import 'package:saber/data/math_solver/openai_math_solver.dart';
import 'package:saber/data/prefs.dart';

/// Sets the service, model and API key used by Solve maths.
///
/// English only: this fork doesn't regenerate translations.
class SettingsMathSolver extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([stows.mathApiKey, stows.mathModel]),
      builder: (context, _) => SettingsButton(
        title: 'Maths solver',
        subtitle: stows.mathApiKey.value.isEmpty
            ? 'No API key set. Used by Solve maths in the selection bar.'
            : '${stows.mathModel.value}. '
                  'Used by Solve maths in the selection bar.',
        icon: Icons.functions,
        onPressed: () => showDialog(
          context: context,
          builder: (context) => const _MathSolverSettingsDialog(),
        ),
      ),
    );
  }
}

class _MathSolverSettingsDialog extends StatefulWidget {
  const new();

  @override
  State<_MathSolverSettingsDialog> createState() =>
      _MathSolverSettingsDialogState();
}

class _MathSolverSettingsDialogState extends State<_MathSolverSettingsDialog> {
  final _baseUrl = TextEditingController(text: stows.mathApiBaseUrl.value);
  final _model = TextEditingController(text: stows.mathModel.value);
  final _key = TextEditingController(text: stows.mathApiKey.value);

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _save() {
    String orDefault(String value, String fallback) =>
        value.trim().isEmpty ? fallback : value.trim();
    stows.mathApiBaseUrl.value = orDefault(
      _baseUrl.text,
      OpenAiMathSolver.defaultBaseUrl,
    );
    stows.mathModel.value = orDefault(
      _model.text,
      OpenAiMathSolver.defaultModel,
    );
    stows.mathApiKey.value = _key.text.trim();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Maths solver'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              const Text(
                'Any service with an OpenAI-compatible API works, '
                'e.g. OpenRouter, OpenAI or a local server. '
                'The model must accept images. '
                'Selections you solve are sent to the service.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'Service URL',
                  hintText: OpenAiMathSolver.defaultBaseUrl,
                ),
              ),
              TextField(
                controller: _model,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  hintText: OpenAiMathSolver.defaultModel,
                ),
              ),
              TextField(
                controller: _key,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  helperText: 'Stored on this device only.',
                ),
                onSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
