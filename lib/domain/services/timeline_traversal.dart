import 'package:equatable/equatable.dart';

import '../models/models.dart';
import 'phase_display.dart';
import 'segment_queue.dart';

/// A position on the Turn's combat timeline: the segment being resolved and
/// the combatant whose phase is selected there.
class TimelinePosition extends Equatable {
  const TimelinePosition({required this.segment, required this.combatantId});

  /// The segment (1–12) the phase is resolved in.
  final int segment;

  /// The combatant whose phase is selected.
  final String combatantId;

  @override
  List<Object?> get props => [segment, combatantId];
}

/// Returns the ids of combatants with a pending haymaker "Strikes"
/// resolution at [segment] this Turn — timeline pseudo-phases that
/// [findNextPhasePosition]/[findPreviousPhasePosition] stop on. In
/// declaration order, deduplicated.
List<String> resolutionIdsAtSegment(TurnState state, int segment) {
  final ids = <String>[];
  for (final declaration in state.haymakerDeclarations) {
    if (declaration.resolutionSegment != segment) continue;
    if (declaration.resolutionTurn != state.turnNumber) continue;
    if (ids.contains(declaration.combatantId)) continue;
    ids.add(declaration.combatantId);
  }
  return ids;
}

/// Whether [combatant] is bypassed in phase traversal. Only the dead are
/// skipped: their row is cleared entirely. Recovery pseudo-phases ([REC] for
/// KO/dying, `[CLR STUN]` for stunned) and virtual `[HOLD]` stops are valid
/// stop points so the GM is alerted to resolve recovery / use the hold before
/// advancing.
bool _isBypassedInTraversal(Combatant combatant) {
  return combatant.status == CombatantStatus.dead;
}

/// Navigation stops of [segment] in queue order: pending "Strikes"
/// pseudo-phases first (the strike continues the previous segment's
/// end-of-segment timing), then [segmentQueueIds]. Deduplicated — a combatant
/// with both a resolution and regular phases there occupies one stop — and
/// KO/Dead combatants are bypassed.
List<String> _queueStopIds(TurnState state, int segment) {
  return _navigationStops(state, [
    ...resolutionIdsAtSegment(state, segment),
    ...segmentQueueIds(state, segment),
  ]);
}

/// Navigation stops of [segment] in timeline order: pseudo-phases first,
/// then virtual `[HOLD]` stops, then [phaseIdsAtSegment]. Same dedupe/bypass
/// rules as [_queueStopIds].
List<String> _timelineStopIds(TurnState state, int segment) {
  return _navigationStops(state, [
    ...resolutionIdsAtSegment(state, segment),
    ...virtualHoldIdsAtSegment(state, segment),
    ...phaseIdsAtSegment(state, segment),
  ]);
}

/// Whether [combatant] is on an active virtual `[HOLD]` stop at [segment]:
/// their held slot's span covers [segment] as a strictly intermediate segment
/// (`declSeg < segment < nextNatural`).
///
/// The span is evaluated with [segment] itself as the cursor (see
/// [virtualHoldSpan]), so eligibility depends only on whether [segment] lies
/// inside the span — `prev phase` and `next phase` behave symmetrically,
/// independent of [TurnState.activeSegment].
bool isVirtualHoldStop(Combatant combatant, int segment) {
  final span = virtualHoldSpan(combatant, segment);
  return span != null && segment > span.$1 && segment < span.$2;
}

/// The ids of combatants on an active virtual `[HOLD]` stop at [segment] (see
/// [isVirtualHoldStop]), in roster order, deduplicated — a combatant with a
/// natural scheduled phase or haymaker resolution at [segment] is listed only
/// once by [_navigationStops].
List<String> virtualHoldIdsAtSegment(TurnState state, int segment) {
  final ids = <String>[];
  for (final combatant in state.combatants) {
    if (isVirtualHoldStop(combatant, segment) && !ids.contains(combatant.id)) {
      ids.add(combatant.id);
    }
  }
  return ids;
}

List<String> _navigationStops(TurnState state, List<String> ids) {
  final stops = <String>[];
  for (final id in ids) {
    if (stops.contains(id)) continue;
    final index = state.combatants.indexWhere((combatant) => combatant.id == id);
    if (index < 0) continue;
    if (_isBypassedInTraversal(state.combatants[index])) continue;
    stops.add(id);
  }
  return stops;
}

/// Returns the position of the very next phase on the Turn's timeline after
/// the current cursor ([TurnState.activeSegment] /
/// [TurnState.activeCombatantId]), or `null` when the Turn's timeline is
/// exhausted (the next phase belongs to the next Turn).
///
/// Within the active segment the walk looks ahead in the sorted action
/// queue (Held → Mental by EGO descending → Physical by DEX descending),
/// with pending haymaker "Strikes" pseudo-phases ordered first. When no
/// stop remains there, the search steps forward through Segments +1, +2, ...
/// skipping empty ones, and lands on the first stop of the next segment
/// that contains one. KO/Dead combatants are bypassed.
TimelinePosition? findNextPhasePosition(TurnState state) {
  final queue = _queueStopIds(state, state.activeSegment);
  final index = state.activeCombatantId == null
      ? -1
      : queue.indexOf(state.activeCombatantId!);

  if (index >= 0 && index + 1 < queue.length) {
    return TimelinePosition(
      segment: state.activeSegment,
      combatantId: queue[index + 1],
    );
  }
  if (index < 0 && queue.isNotEmpty) {
    // Nothing selected (or the selection has no phase here): the walk
    // resumes at the first queued phase of the current segment.
    return TimelinePosition(
      segment: state.activeSegment,
      combatantId: queue.first,
    );
  }

  for (var segment = state.activeSegment + 1; segment <= 12; segment++) {
    final ids = _timelineStopIds(state, segment);
    if (ids.isNotEmpty) {
      return TimelinePosition(segment: segment, combatantId: ids.first);
    }
  }
  return null;
}

/// Returns the position of the previous phase on the Turn's timeline before
/// the current cursor, or `null` at the very start of the Turn.
///
/// Reverse of [findNextPhasePosition]: the walk goes backward through the
/// active segment's sorted stops (pseudo-phases first, then virtual `[HOLD]`
/// stops), then steps back through Segments -1, -2, ... skipping empty ones,
/// landing on the *last* stop of the nearest earlier segment that contains
/// one. KO/Dead combatants are bypassed.
///
/// Intermediate virtual `[HOLD]` stops ([virtualHoldIdsAtSegment]) are valid
/// backward stops: a held combatant is focused once per span segment
/// (`declSeg < seg < nextNatural`) so `prev phase` steps cleanly onto each
/// virtual hold segment without re-highlighting the combatant at both a
/// queue carry-in position and their baseline slot.
TimelinePosition? findPreviousPhasePosition(TurnState state) {
  final segment = state.activeSegment;
  final queue = _timelineStopIds(state, segment);
  final index =
      state.activeCombatantId == null ? -1 : queue.indexOf(state.activeCombatantId!);

  if (index > 0) {
    return TimelinePosition(
      segment: segment,
      combatantId: queue[index - 1],
    );
  }
  if (index < 0 && queue.isNotEmpty) {
    // Nothing selected (or the selection has no baseline phase here): the
    // walk resumes at the last stop of the resolved segment.
    return TimelinePosition(
      segment: segment,
      combatantId: queue.last,
    );
  }

  for (var earlier = segment - 1; earlier >= 1; earlier--) {
    final ids = _timelineStopIds(state, earlier);
    if (ids.isNotEmpty) {
      return TimelinePosition(segment: earlier, combatantId: ids.last);
    }
  }
  return null;
}

/// Returns the position of the Turn's final timeline stop: the last entry
/// of the Segment 12 queue (or of the nearest earlier segment with stops),
/// or `null` on an empty Turn. Used when reversing out of the Post-12
/// column so focus lands on the Turn's last active phase.
TimelinePosition? findLastPhasePosition(TurnState state) {
  for (var segment = 12; segment >= 1; segment--) {
    final ids = _timelineStopIds(state, segment);
    if (ids.isNotEmpty) {
      return TimelinePosition(segment: segment, combatantId: ids.last);
    }
  }
  return null;
}