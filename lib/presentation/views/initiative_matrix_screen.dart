import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/models.dart';
import '../../domain/services/encounter_file_service.dart';
import '../state/matrix_ui_state.dart';
import '../state/turn_engine_notifier.dart';
import '../widgets/active_combatant_panel.dart';
import '../widgets/add_combatant_dialog.dart';
import '../widgets/hotkey_wrapper.dart';
import '../widgets/matrix_grid.dart';
import '../widgets/target_combatant_panel.dart';
import '../widgets/turn_advance.dart';

/// Primary desktop/tablet screen: top control bar (Turn & Segment counter,
/// Prev/Next Phase controls), the [MatrixGrid], and the dual bottom panels
/// ([ActiveCombatantPanel] for the Actor, [TargetCombatantPanel] for the
/// Actee).
///
/// The body is wrapped in [HotkeyWrapper] for keyboard-first navigation and
/// action dispatch. All state changes go through [TurnEngineNotifier].
class InitiativeMatrixScreen extends ConsumerWidget {
  const InitiativeMatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(turnEngineProvider);

    return Scaffold(
      body: HotkeyWrapper(
        child: Column(
          children: <Widget>[
            _ControlBar(state: state),
            const Expanded(child: MatrixGrid()),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: ActiveCombatantPanel()),
                Expanded(child: TargetCombatantPanel()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlBar extends ConsumerWidget {
  const _ControlBar({required this.state});

  final TurnState state;

  /// Confirmed "New Encounter...": clears the encounter back to Turn 1,
  /// Segment 1 with no combatants. Declining keeps the current encounter.
  Future<void> _newEncounter(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Encounter'),
        content: const Text(
          'Clear current encounter? All unsaved combatants will be removed.',
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('cancel-new-encounter'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            key: const Key('confirm-new-encounter'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The clean slate clears the Post-12 column selection along with state.
    ref.read(selectedColumnProvider.notifier).state = null;
    ref.read(turnEngineProvider.notifier).resetEncounter();
  }

  Future<void> _saveEncounter(BuildContext context, WidgetRef ref) async {
    // Captured up front so feedback is safe after the async dialog gap.
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(encounterFileServiceProvider);
    try {
      final path =
          await service.saveEncounterToFile(ref.read(turnEngineProvider));
      if (path == null) return; // Cancelled.
      messenger.showSnackBar(
        SnackBar(content: Text('Encounter saved to $path')),
      );
    } on PlatformException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'File dialog failed: ${error.message ?? error.code}',
          ),
        ),
      );
    } on FileSystemException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save encounter file')),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Unexpected error: $error')),
      );
    }
  }

  /// Shows the loaded encounter's file details with the
  /// "Reset to Turn 1, Segment 1 on load" option (checked by default).
  ///
  /// Returns the reset choice (`true`/`false`), or `null` when the load is
  /// cancelled.
  Future<bool?> _confirmLoadEncounter(BuildContext context, TurnState encounter) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        var resetToStart = true;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Load Encounter'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Turn ${encounter.turnNumber} · Segment ${encounter.activeSegment}'
                  ' · ${encounter.combatants.length} combatants',
                  key: const Key('load-encounter-details'),
                ),
                CheckboxListTile(
                  key: const Key('reset-on-load'),
                  value: resetToStart,
                  onChanged: (value) =>
                      setState(() => resetToStart = value ?? true),
                  title: const Text('Reset to Turn 1, Segment 1 on load'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('cancel-load-encounter'),
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm-load-encounter'),
                onPressed: () => Navigator.of(context).pop(resetToStart),
                child: const Text('Load'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadEncounter(BuildContext context, WidgetRef ref) async {
    // Captured up front so feedback is safe after the async dialog gap.
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(encounterFileServiceProvider);
    final notifier = ref.read(turnEngineProvider.notifier);
    try {
      final encounter = await service.loadEncounterFromFile();
      if (encounter == null) return; // Cancelled.
      if (!context.mounted) return;

      final resetToStart = await _confirmLoadEncounter(context, encounter);
      if (resetToStart == null) return; // Cancelled.

      notifier.loadEncounter(encounter);
      if (resetToStart) {
        notifier.resetTimeline();
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Encounter loaded')),
      );
    } on FormatException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Invalid encounter JSON: ${error.message}')),
      );
    } on PlatformException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'File dialog failed: ${error.message ?? error.code}',
          ),
        ),
      );
    } on FileSystemException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read encounter file')),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Unexpected error: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PopupMenuButton<String>(
                key: const Key('brand-menu'),
                tooltip: 'HeroTrak menu',
                onSelected: (value) async {
                  // Every action is awaited so exceptions from the async
                  // service calls surface in these handlers, never as
                  // unhandled zone errors.
                  switch (value) {
                    case 'new':
                      await _newEncounter(context, ref);
                    case 'save':
                      await _saveEncounter(context, ref);
                    case 'load':
                      await _loadEncounter(context, ref);
                  }
                },
                itemBuilder: (context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'new',
                    child: Text('New Encounter...'),
                  ),
                  PopupMenuItem<String>(
                    value: 'save',
                    child: Text('Save Encounter...'),
                  ),
                  PopupMenuItem<String>(
                    value: 'load',
                    child: Text('Load Encounter...'),
                  ),
                ],
                child: const Text(
                  'HeroTrak',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 24),
            Text(
              'Turn ${state.turnNumber}',
              key: const Key('turn-counter'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 16),
            Text(
              'Segment ${state.activeSegment}',
              key: const Key('segment-counter'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 16),
            Tooltip(
              message: 'Previous Phase',
              child: OutlinedButton(
                key: const Key('previous-step-button'),
                onPressed: () => ref
                    .read(turnEngineProvider.notifier)
                    .selectPreviousPhaseSlot(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(56, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Prev',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    Text('Phase', style: TextStyle(fontSize: 11, height: 1.1)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Next Phase',
              child: ElevatedButton(
                key: const Key('next-step-button'),
                onPressed: () => requestNextPhaseSlot(context, ref),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(56, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Next',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    Text('Phase', style: TextStyle(fontSize: 11, height: 1.1)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Builder(
              builder: (context) => OutlinedButton(
                key: const Key('add-combatant-button'),
                onPressed: () => showAddCombatantDialog(context),
                child: const Text('[N]ew Combatant'),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}