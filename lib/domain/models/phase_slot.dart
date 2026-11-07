import 'package:equatable/equatable.dart';

import '../../core/utils/copy_with_sentinel.dart';
import 'phase_status.dart';

/// A single scheduled action slot within a Turn for a combatant.
///
/// Immutable value object. A slot's [segment] can change (e.g. when the
/// phase is relocated), while [originalSegment] preserves the segment the
/// phase was originally scheduled on per the Speed Chart.
class PhaseSlot extends Equatable {
  const PhaseSlot({
    required this.segment,
    int? originalSegment,
    this.status = PhaseStatus.scheduled,
    this.isMental = false,
    this.actionId,
    this.actionLabel,
  }) : assert(
         segment >= 1 && segment <= 12,
         'segment must be between 1 and 12',
       ),
       assert(
         originalSegment == null ||
             (originalSegment >= 1 && originalSegment <= 12),
         'originalSegment must be between 1 and 12',
       ),
       originalSegment = originalSegment ?? segment;

  /// The segment (1–12) this phase is currently scheduled on.
  final int segment;

  /// The segment (1–12) this phase was originally scheduled on.
  final int originalSegment;

  /// Current status of the phase.
  final PhaseStatus status;

  /// Whether the action declared for this phase is a mental action.
  ///
  /// Mental actions are ordered by EGO (descending) ahead of physical
  /// actions, which are ordered by DEX (descending), when resolving a
  /// segment's action queue.
  final bool isMental;

  /// Optional identifier of the action declared for this phase.
  final String? actionId;

  /// Optional human-readable label of the action declared for this phase.
  final String? actionLabel;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields ([actionId], [actionLabel]) may be explicitly cleared by
  /// passing `null`; omitting them keeps their current value.
  PhaseSlot copyWith({
    int? segment,
    int? originalSegment,
    PhaseStatus? status,
    bool? isMental,
    Object? actionId = kCopyWithUnset,
    Object? actionLabel = kCopyWithUnset,
  }) {
    return PhaseSlot(
      segment: segment ?? this.segment,
      originalSegment: originalSegment ?? this.originalSegment,
      status: status ?? this.status,
      isMental: isMental ?? this.isMental,
      actionId: identical(actionId, kCopyWithUnset)
          ? this.actionId
          : actionId as String?,
      actionLabel: identical(actionLabel, kCopyWithUnset)
          ? this.actionLabel
          : actionLabel as String?,
    );
  }

  @override
  List<Object?> get props => [
    segment,
    originalSegment,
    status,
    isMental,
    actionId,
    actionLabel,
  ];
}
