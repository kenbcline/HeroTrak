import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/models.dart';
import '../../domain/services/encounter_serializer.dart';
import '../state/turn_engine_notifier.dart';

/// Shows the Export Encounter dialog with the serialized encounter JSON.
///
/// The JSON is presented in selectable text with a Copy to Clipboard action,
/// ready to paste into a `.json` file or another tool.
Future<void> showExportEncounterDialog(BuildContext context, String jsonString) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Export Encounter'),
      content: SizedBox(
        width: 480,
        height: 320,
        child: SingleChildScrollView(
          child: SelectableText(jsonString, key: const Key('export-json')),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('copy-export-json'),
          onPressed: () => Clipboard.setData(ClipboardData(text: jsonString)),
          child: const Text('Copy to Clipboard'),
        ),
        FilledButton(
          key: const Key('close-export'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Shows the Import Encounter dialog (JSON text prompt).
Future<void> showImportEncounterDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const ImportEncounterDialog(),
  );
}

/// Text-prompt dialog that loads a JSON encounter into the tracker.
///
/// The pasted JSON is validated with [deserializeEncounter] before it is
/// applied via [TurnEngineNotifier.loadEncounter]; invalid input shows an
/// inline error and leaves the current encounter untouched.
class ImportEncounterDialog extends ConsumerStatefulWidget {
  const ImportEncounterDialog({super.key});

  @override
  ConsumerState<ImportEncounterDialog> createState() =>
      _ImportEncounterDialogState();
}

class _ImportEncounterDialogState extends ConsumerState<ImportEncounterDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final TurnState encounter;
    try {
      encounter = deserializeEncounter(_controller.text);
    } on FormatException catch (error) {
      setState(() => _error = 'Invalid encounter JSON: ${error.message}');
      return;
    }
    ref.read(turnEngineProvider.notifier).loadEncounter(encounter);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Encounter'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('import-json-field'),
              controller: _controller,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Encounter JSON',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                key: const Key('import-error'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('cancel-import'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('submit-import'),
          onPressed: _submit,
          child: const Text('Import'),
        ),
      ],
    );
  }
}