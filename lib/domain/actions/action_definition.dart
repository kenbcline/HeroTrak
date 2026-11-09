import 'package:equatable/equatable.dart';

import '../models/phase_status.dart';
import 'action_mutation.dart';

/// Who or what an [ActionDefinition] may target.
enum ActionTargetType {
  /// The acting combatant themselves.
  self,

  /// A friendly combatant.
  ally,

  /// A hostile combatant.
  enemy,

  /// Any combatant.
  any,
}

/// Declarative definition of a tracker action.
///
/// An action is a labeled, hotkey-accessible command composed of primitive
/// [ActionMutation]s. Business logic stays out of the UI: the presentation
/// layer dispatches an [ActionDefinition], and controllers apply its
/// mutations to the [TurnState] (see `lib/domain/models/turn_state.dart`).
///
/// [hotkey] must be a single character and is matched case-insensitively by
/// the presentation layer; the bracketed letter in the standard action
/// labels (e.g. "[A]bort") identifies the hotkey.
class ActionDefinition extends Equatable {
  const ActionDefinition({
    required this.id,
    required this.label,
    required this.hotkey,
    required this.targetType,
    this.mutations = const <ActionMutation>[],
  });

  /// Unique identifier of the action.
  final String id;

  /// Human-readable label (hotkey letter conventionally bracketed).
  final String label;

  /// Single-character hotkey for keyboard-first dispatch.
  final String hotkey;

  /// Who this action may target.
  final ActionTargetType targetType;

  /// Primitive state changes applied when this action is executed.
  final List<ActionMutation> mutations;

  /// **[A]bort to Defensive Action** (`A`).
  ///
  /// Aborts the combatant's current action and takes a defensive action
  /// instead: the declared action is badged [PhaseStatus.aborted] and the
  /// phase is consumed by the defensive action.
  static const ActionDefinition abortToDefensiveAction = ActionDefinition(
    id: 'abort_to_defensive_action',
    label: 'Abort to Defensive Action',
    hotkey: 'a',
    targetType: ActionTargetType.self,
    mutations: <ActionMutation>[
      ActionMutation.applyStatusBadge(status: PhaseStatus.aborted),
      ActionMutation.consumeNextPhase(),
    ],
  );

  /// Declare **Hay[M]aker** (`M`).
  ///
  /// Declares a haymaked attack (+4 DC in standard 6e) that resolves at the
  /// end of the segment: an initiative-queue override is inserted so the
  /// attack resolves after every other action in the segment.
  static const ActionDefinition declareHaymaker = ActionDefinition(
    id: 'declare_haymaker',
    label: 'Declare Haymaker',
    hotkey: 'm',
    targetType: ActionTargetType.self,
    mutations: <ActionMutation>[
      ActionMutation.insertQueueOverride(
        queueOverride: 'haymaker_end_of_segment',
      ),
    ],
  );

  /// Interrupt with **[H]old** (`H`).
  ///
  /// Puts the current phase on hold ([PhaseStatus.held]) and inserts a queue
  /// override so the held action may interrupt at any later point in the
  /// Turn.
  static const ActionDefinition interruptWithHold = ActionDefinition(
    id: 'interrupt_with_hold',
    label: 'Interrupt with Hold',
    hotkey: 'h',
    targetType: ActionTargetType.self,
    mutations: <ActionMutation>[
      ActionMutation.applyStatusBadge(status: PhaseStatus.held),
      ActionMutation.insertQueueOverride(queueOverride: 'hold_interrupt'),
    ],
  );

  /// All pre-configured standard 6e actions.
  static const List<ActionDefinition> standardActions = <ActionDefinition>[
    abortToDefensiveAction,
    declareHaymaker,
    interruptWithHold,
  ];

  /// Ids of the maneuver actions (`[A]bort`, Hay`[M]aker`, `[H]old`) that are
  /// hard-locked while the subject's upcoming phase renders `[REC]` or
  /// `[CLR STUN]` — the mandatory recovery / clear-stun action is the only
  /// legal choice on those phases (see `isPhaseActionLocked`).
  static List<String> get lockedDuringRecoveryIds => <String>[
        abortToDefensiveAction.id,
        declareHaymaker.id,
        interruptWithHold.id,
      ];

  @override
  List<Object?> get props => [id, label, hotkey, targetType, mutations];
}
