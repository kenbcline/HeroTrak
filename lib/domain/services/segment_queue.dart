import 'package:equatable/equatable.dart';

import '../models/models.dart';

/// A single entry in a segment's action queue.
///
/// Pairs the acting [combatant] with the [phaseSlot] being resolved in the
/// segment. Immutable value object.
class SegmentQueueEntry extends Equatable {
  const SegmentQueueEntry({required this.combatant, required this.phaseSlot});

  /// The combatant scheduled to act.
  final Combatant combatant;

  /// The phase slot scheduled in the segment being resolved.
  final PhaseSlot phaseSlot;

  /// Whether this entry is a held interruption ([PhaseStatus.held]). Held
  /// interruptions resolve ahead of all regular actions in a segment's queue.
  bool get isHeldInterruption => phaseSlot.status == PhaseStatus.held;

  /// Whether this entry's action is a mental action ([PhaseSlot.isMental]).
  bool get isMentalAction => phaseSlot.isMental;

  @override
  List<Object?> get props => [combatant, phaseSlot];
}

/// Ordering tiers within a segment's action queue.
///
/// 0: Held Interruptions, 1: Mental actions, 2: Physical actions.
int _queueTier(SegmentQueueEntry entry) {
  if (entry.isHeldInterruption) return 0;
  if (entry.isMentalAction) return 1;
  return 2;
}

/// Sorts segment queue entries per the 6e action ordering:
///
/// 1. Held Interruptions first,
/// 2. Mental actions (by EGO descending),
/// 3. Physical actions (by DEX descending),
/// 4. then SPD descending,
/// 5. then Name ascending.
///
/// Ties fall back to the combatant id to keep the queue deterministic. The
/// SPD/Name steps keep high-SPD combatants ahead of equal-DEX peers (most
/// visible on Segment 12, where every speed phases) instead of letting the
/// id fallback misorder them.
int compareSegmentQueueEntries(SegmentQueueEntry a, SegmentQueueEntry b) {
  final tierCompare = _queueTier(a).compareTo(_queueTier(b));
  if (tierCompare != 0) return tierCompare;

  if (_queueTier(a) == 1) {
    final egoCompare = b.combatant.ego.compareTo(a.combatant.ego);
    if (egoCompare != 0) return egoCompare;
  }

  final dexCompare = b.combatant.dex.compareTo(a.combatant.dex);
  if (dexCompare != 0) return dexCompare;

  final spdCompare = b.combatant.spd.compareTo(a.combatant.spd);
  if (spdCompare != 0) return spdCompare;

  final nameCompare = a.combatant.name.compareTo(b.combatant.name);
  if (nameCompare != 0) return nameCompare;

  return a.combatant.id.compareTo(b.combatant.id);
}

/// Whether [slot] is still actionable (not consumed or aborted).
bool isActionablePhase(PhaseSlot slot) {
  return slot.status != PhaseStatus.spent &&
      slot.status != PhaseStatus.aborted;
}

/// The action queue for [segment]: one entry per actionable phase slot
/// scheduled in [segment], plus pending held interruptions (held slots
/// scheduled earlier in the Turn, which may interrupt at any later point),
/// in 6e resolution order (see [compareSegmentQueueEntries]).
List<SegmentQueueEntry> segmentQueueEntries(TurnState state, int segment) {
  final entries = <SegmentQueueEntry>[];
  for (final combatant in state.combatants) {
    for (final slot in combatant.phaseSlots) {
      if (!isActionablePhase(slot)) continue;
      if (slot.segment == segment ||
          (slot.status == PhaseStatus.held && slot.segment < segment)) {
        entries.add(SegmentQueueEntry(combatant: combatant, phaseSlot: slot));
      }
    }
  }
  entries.sort(compareSegmentQueueEntries);
  return List<SegmentQueueEntry>.unmodifiable(entries);
}

/// The combatant ids of [segment]'s action queue in resolution order,
/// deduplicated (a combatant with several phases in one segment occupies
/// one queue position).
List<String> segmentQueueIds(TurnState state, int segment) {
  return _dedupeIds([
    for (final entry in segmentQueueEntries(state, segment)) entry,
  ]);
}

/// The combatant ids of the phase slots scheduled *at* [segment] (their
/// chronological position in the Turn timeline), in resolution order and
/// deduplicated. Pending held interruptions from earlier segments are
/// excluded — chronologically they belong to the segment they were
/// scheduled on.
List<String> phaseIdsAtSegment(TurnState state, int segment) {
  return _dedupeIds([
    for (final entry in segmentQueueEntries(state, segment))
      if (entry.phaseSlot.segment == segment) entry,
  ]);
}

List<String> _dedupeIds(List<SegmentQueueEntry> entries) {
  final ids = <String>[];
  for (final entry in entries) {
    if (!ids.contains(entry.combatant.id)) ids.add(entry.combatant.id);
  }
  return ids;
}