import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/actions.dart';
import '../state/turn_engine_notifier.dart';
import 'add_combatant_dialog.dart';
import 'turn_advance.dart';

/// Advances the tracker one segment (Space).
class NextStepIntent extends Intent {
  const NextStepIntent();
}

/// Selects the next combatant row (Down Arrow).
class NextCombatantIntent extends Intent {
  const NextCombatantIntent();
}

/// Selects the previous combatant row (Up Arrow).
class PreviousCombatantIntent extends Intent {
  const PreviousCombatantIntent();
}

/// Selects the next phase on the combat timeline (Right Arrow).
class NextPhaseSlotIntent extends Intent {
  const NextPhaseSlotIntent();
}

/// Selects the previous phase on the combat timeline (Left Arrow).
class PreviousPhaseSlotIntent extends Intent {
  const PreviousPhaseSlotIntent();
}

/// Opens the Add Combatant dialog (KeyN).
class AddCombatantIntent extends Intent {
  const AddCombatantIntent();
}

/// Executes **[A]bort to Defensive Action** (KeyA).
class AbortActionIntent extends Intent {
  const AbortActionIntent();
}

/// Executes **[H]old Action** (KeyH): declares a hold, or resolves an
/// active held action via `Use [H]old`.
class HoldActionIntent extends Intent {
  const HoldActionIntent();
}

/// Executes **Declare Hay[M]aker** (KeyM).
class HaymakerActionIntent extends Intent {
  const HaymakerActionIntent();
}

/// Clears the Active Combatant's Hold/Haymaker action state (KeyC).
class ClearActionIntent extends Intent {
  const ClearActionIntent();
}

/// Global keyboard control layer for the tracker.
///
/// Wraps the main matrix view in a focused [Shortcuts]/[Actions] listener:
///
/// | Key               | Action                          |
/// |-------------------|---------------------------------|
/// | Space             | [TurnEngineNotifier.nextStep]   |
/// | Down Arrow        | Select next combatant row       |
/// | Up Arrow          | Select previous combatant row   |
/// | Right Arrow       | Next phase on the timeline      |
/// | Left Arrow        | Previous phase on the timeline  |
/// | A                 | [A]bort to Defensive Action     |
/// | H                 | [H]old Action                     |
/// | M                 | Declare Hay[M]aker              |
/// | N                 | Add Combatant dialog            |
///
/// Invalid action executions are ignored non-modally (state is unchanged,
/// since [TurnEngineNotifier.executeAction] is atomic).
class HotkeyWrapper extends ConsumerWidget {
  const HotkeyWrapper({super.key, required this.child});

  /// The wrapped view (e.g. the initiative matrix screen body).
  final Widget child;

  static void _execute(
    WidgetRef ref,
    ActionDefinition action, {
    String? targetId,
  }) {
    try {
      ref
          .read(turnEngineProvider.notifier)
          .executeAction(action, targetId: targetId);
    } on StateError {
      // Non-modal UX: an invalid action is a silent no-op (no dialogs).
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): NextStepIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): NextCombatantIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousCombatantIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): NextPhaseSlotIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousPhaseSlotIntent(),
        SingleActivator(LogicalKeyboardKey.keyA): AbortActionIntent(),
        SingleActivator(LogicalKeyboardKey.keyH): HoldActionIntent(),
        SingleActivator(LogicalKeyboardKey.keyM): HaymakerActionIntent(),
        SingleActivator(LogicalKeyboardKey.keyC): ClearActionIntent(),
        SingleActivator(LogicalKeyboardKey.keyN): AddCombatantIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NextStepIntent: CallbackAction<NextStepIntent>(
            onInvoke: (intent) {
              requestNextStep(context, ref);
              return null;
            },
          ),
          NextCombatantIntent: CallbackAction<NextCombatantIntent>(
            onInvoke: (intent) {
              // Target (Actee) cursor — never touches the timeline clock.
              ref.read(turnEngineProvider.notifier).selectNextTarget();
              return null;
            },
          ),
          PreviousCombatantIntent: CallbackAction<PreviousCombatantIntent>(
            onInvoke: (intent) {
              ref.read(turnEngineProvider.notifier).selectPreviousTarget();
              return null;
            },
          ),
          NextPhaseSlotIntent: CallbackAction<NextPhaseSlotIntent>(
            onInvoke: (intent) {
              requestNextPhaseSlot(context, ref);
              return null;
            },
          ),
          PreviousPhaseSlotIntent: CallbackAction<PreviousPhaseSlotIntent>(
            onInvoke: (intent) {
              ref.read(turnEngineProvider.notifier).selectPreviousPhaseSlot();
              return null;
            },
          ),
          AbortActionIntent: CallbackAction<AbortActionIntent>(
            onInvoke: (intent) {
              // [A]bort is a Target (Actee) reaction.
              _execute(ref, ActionDefinition.abortToDefensiveAction);
              return null;
            },
          ),
          HoldActionIntent: CallbackAction<HoldActionIntent>(
            onInvoke: (intent) {
              // Initiative actions bind to the Active Combatant (Actor).
              final actorId =
                  ref.read(turnEngineProvider).activeCombatantId;
              if (actorId != null) {
                _execute(
                  ref,
                  ActionDefinition.interruptWithHold,
                  targetId: actorId,
                );
              }
              return null;
            },
          ),
          HaymakerActionIntent: CallbackAction<HaymakerActionIntent>(
            onInvoke: (intent) {
              final actorId =
                  ref.read(turnEngineProvider).activeCombatantId;
              if (actorId != null) {
                _execute(
                  ref,
                  ActionDefinition.declareHaymaker,
                  targetId: actorId,
                );
              }
              return null;
            },
          ),
          ClearActionIntent: CallbackAction<ClearActionIntent>(
            onInvoke: (intent) {
              final actorId =
                  ref.read(turnEngineProvider).activeCombatantId;
              if (actorId != null) {
                ref.read(turnEngineProvider.notifier).clearAction(actorId);
              }
              return null;
            },
          ),
          AddCombatantIntent: CallbackAction<AddCombatantIntent>(
            onInvoke: (intent) {
              showAddCombatantDialog(context);
              return null;
            },
          ),
        },
        // The focus node must sit below Shortcuts/Actions so key events
        // bubble up through the shortcut handlers.
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}