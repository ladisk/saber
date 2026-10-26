import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:onenote_import/onenote_import.dart';
import 'package:saber/data/onenote/onenote_importer.dart';
import 'package:saber/data/routes.dart';

/// Imports a OneNote file into [parentDir] while showing its progress,
/// then opens the folder with the imported notes.
///
/// [parentDir] must start and end with a slash.
Future<void> importOneNote(
  BuildContext context, {
  required String filePath,
  required String parentDir,
}) async {
  final progress = ValueNotifier<(int, int)?>(null);
  final dialogContext = Completer<BuildContext>();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      if (!dialogContext.isCompleted) dialogContext.complete(context);
      return _OneNoteImportDialog(progress: progress);
    },
  );

  OneNoteImportSummary? summary;
  String? error;
  try {
    summary = await OneNoteImporter.importFile(
      filePath,
      parentDir: parentDir,
      onProgress: (done, total) => progress.value = (done, total),
    );
  } on OneNoteImportException catch (e) {
    error = e.message;
  } catch (e) {
    error = '$e';
  } finally {
    final dialog = await dialogContext.future;
    if (dialog.mounted) Navigator.of(dialog).pop();
    progress.dispose();
  }

  if (!context.mounted) return;
  if (summary == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not import the OneNote file: $error')),
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(_describe(summary)),
      duration: const Duration(seconds: 8),
    ),
  );
  if (summary.notes > 0) {
    context.go(HomeRoutes.browseFilePath(summary.folder));
  }
}

String _describe(OneNoteImportSummary summary) {
  final notes = summary.notes == 1 ? '1 note' : '${summary.notes} notes';
  return [
    'Imported $notes from OneNote.',
    if (summary.emptyPages > 0) '${summary.emptyPages} pages were empty.',
    if (summary.skipped > 0) '${summary.skipped} other items were skipped.',
  ].join(' ');
}

class _OneNoteImportDialog extends StatelessWidget {
  const new({required this.progress});

  final ValueNotifier<(int, int)?> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importing from OneNote'),
      content: ValueListenableBuilder(
        valueListenable: progress,
        builder: (context, progress, _) {
          final (done, total) = progress ?? (0, 0);
          return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              LinearProgressIndicator(value: total == 0 ? null : done / total),
              const SizedBox(height: 12),
              Text(
                progress == null
                    ? 'Reading the notebook...'
                    : 'Page $done of $total',
              ),
            ],
          );
        },
      ),
    );
  }
}
