import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/settings/settings_button.dart';
import 'package:saber/data/prefs.dart';

/// Sets or removes the Anthropic API key used by Solve maths.
///
/// English only: this fork doesn't regenerate translations.
class SettingsAnthropicApiKey extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: stows.anthropicApiKey,
      builder: (context, key, _) => SettingsButton(
        title: 'Anthropic API key',
        subtitle: key.isEmpty
            ? 'Not set. Needed for Solve maths in the selection bar.'
            : 'Set (…${key.substring(max(0, key.length - 4))}). '
                  'Used for Solve maths in the selection bar.',
        icon: Icons.key,
        onPressed: () => showDialog(
          context: context,
          builder: (context) => _ApiKeyDialog(initial: key),
        ),
      ),
    );
  }
}

class _ApiKeyDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(String key) {
    stows.anthropicApiKey.value = key.trim();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Anthropic API key'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            const Text(
              'Create a key at console.anthropic.com. '
              'It is stored on this device only. '
              'Selections you solve are sent to Anthropic.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'API key',
                hintText: 'sk-ant-...',
              ),
              onSubmitted: _save,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initial.isNotEmpty)
          TextButton(onPressed: () => _save(''), child: const Text('Remove')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _save(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
