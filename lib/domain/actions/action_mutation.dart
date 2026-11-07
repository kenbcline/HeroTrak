import 'package:equatable/equatable.dart';

import '../models/phase_status.dart';

/// The primitive kinds of state change an action can perform.
enum ActionMutationType {
  /// Consumes the acting combatant's next scheduled phase.
  consumeNextPhase,

  /// Relocates a phase to a different segment.
  relocatePhase,

  /// Applies a status badge to a phase.
  applyStatusBadge,

  /// Inserts a one-off override into the phase/turn queue.
  insertQueueOverride,
}

/// A primitive, declarative state change applied by an action.
///
/// Each mutation maps onto exactly one [ActionMutationType]; the auxiliary
/// fields are only meaningful for their matching type:
///
/// | Type                 | Required field |
/// |----------------------|----------------|
/// | `consumeNextPhase`   | none           |
/// | `relocatePhase`      | `targetSegment` (1–12) |
/// | `applyStatusBadge`   | `status`       |
/// | `insertQueueOverride`| `queueOverride`|
class ActionMutation extends Equatable {
  const ActionMutation({
    required this.type,
    this.targetSegment,
    this.status,
    this.queueOverride,
  }) : assert(
         type != ActionMutationType.relocatePhase ||
             (targetSegment != null &&
                 targetSegment >= 1 &&
                 targetSegment <= 12),
         'relocatePhase requires a targetSegment between 1 and 12',
       ),
       assert(
         type != ActionMutationType.applyStatusBadge || status != null,
         'applyStatusBadge requires a status',
       ),
       assert(
         type != ActionMutationType.insertQueueOverride ||
             queueOverride != null,
         'insertQueueOverride requires a queueOverride descriptor',
       );

  /// Consumes the next scheduled phase of the acting combatant.
  const ActionMutation.consumeNextPhase()
    : this(type: ActionMutationType.consumeNextPhase);

  /// Relocates the phase to [targetSegment] (1–12).
  const ActionMutation.relocatePhase({required int targetSegment})
    : this(
        type: ActionMutationType.relocatePhase,
        targetSegment: targetSegment,
      );

  /// Applies [status] as a status badge to the phase.
  const ActionMutation.applyStatusBadge({required PhaseStatus status})
    : this(type: ActionMutationType.applyStatusBadge, status: status);

  /// Inserts [queueOverride] into the phase/turn queue.
  const ActionMutation.insertQueueOverride({required String queueOverride})
    : this(
        type: ActionMutationType.insertQueueOverride,
        queueOverride: queueOverride,
      );

  /// The primitive kind of this mutation.
  final ActionMutationType type;

  /// Target segment (1–12) for [ActionMutationType.relocatePhase].
  final int? targetSegment;

  /// Status badge for [ActionMutationType.applyStatusBadge].
  final PhaseStatus? status;

  /// Descriptor of the queue override for
  /// [ActionMutationType.insertQueueOverride].
  final String? queueOverride;

  @override
  List<Object?> get props => [type, targetSegment, status, queueOverride];
}
