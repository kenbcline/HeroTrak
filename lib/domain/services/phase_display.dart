import '../models/models.dart';

/// Returns the index of [combatant]'s next `scheduled` phase slot at or
/// after [activeSegment] (no wrap — the "[CLR STUN]" phase must be an
/// upcoming phase of the current Turn), or -1 when none remains.
int nextScheduledSlotIndex(Combatant combatant, int activeSegment) {
  for (var segment = activeSegment; segment <= 12; segment++) {
    for (var i = 0; i < combatant.phaseSlots.length; i++) {
      final slot = combatant.phaseSlots[i];
      if (slot.segment == segment && slot.status == PhaseStatus.scheduled) {
        return i;
      }
    }
  }
  return -1;
}

/// Whether [slot] is the stunned [combatant]'s upcoming "[CLR STUN]" phase:
/// its next scheduled phase from [activeSegment], consumed to clear the stun.
bool isClearStunSlot(Combatant combatant, PhaseSlot slot, int activeSegment) {
  if (combatant.status != CombatantStatus.stunned) return false;
  if (slot.status != PhaseStatus.scheduled) return false;
  final index = nextScheduledSlotIndex(combatant, activeSegment);
  return index >= 0 && identical(combatant.phaseSlots[index], slot);
}

/// Status-driven display override for [slot] of [combatant], or `null` when
/// the regular phase-tile rendering applies:
///
/// - stunned: the next scheduled phase renders as `[CLR STUN]`;
/// - KO (stabilized/unconscious): every scheduled phase renders as `[REC]`
///   so the character can regain STUN and wake up;
/// - dying: standard active maneuver icons are stripped and every active
///   (scheduled) phase renders `[REC]`; the Post-12 `[BLEED]` indicator is
///   maintained separately (see [post12DisplayLabel]).
String? phaseSlotDisplayLabel(
  Combatant combatant,
  PhaseSlot slot,
  int activeSegment,
) {
  switch (combatant.status) {
    case CombatantStatus.stunned:
      return isClearStunSlot(combatant, slot, activeSegment)
          ? '[CLR STUN]'
          : null;
    case CombatantStatus.knockedOut:
    case CombatantStatus.dying:
      return slot.status == PhaseStatus.scheduled ? '[REC]' : null;
    case CombatantStatus.normal:
    case CombatantStatus.dead:
      return null;
  }
}

/// Whether [combatant]'s upcoming phase is a mandatory recovery/clear-stun
/// action — i.e. its next scheduled slot renders `[REC]` (KO/dying) or
/// `[CLR STUN]` (stunned) via [phaseSlotDisplayLabel].
///
/// While locked, the phase options are hard-locked: Haymaker, Abort and Hold
/// are suppressed and the mandatory recovery/clear-stun action is the only
/// legal choice (see `TurnEngineNotifier.executeAction`).
bool isPhaseActionLocked(Combatant combatant, int activeSegment) {
  final index = nextScheduledSlotIndex(combatant, activeSegment);
  if (index < 0) return false;
  final label = phaseSlotDisplayLabel(
    combatant,
    combatant.phaseSlots[index],
    activeSegment,
  );
  return label == '[REC]' || label == '[CLR STUN]';
}

/// Virtual `[HOLD]` marker label shown at [segment] for [combatant], or
/// `null` when no marker renders there.
///
/// While a combatant maintains an active hold (a [PhaseStatus.held] slot at
/// segment `N`), green `[HOLD]` markers span the intermediate segments from
/// the segment of declaration (`N`, where the `[H]` tile sits) up to but not
/// including the actor's next natural DEX phase (`M`, their next
/// `scheduled` slot after `N`; through Segment 12 when none remains).
///
/// The markers clear automatically:
/// - consumed — the held slot becomes [PhaseStatus.spent];
/// - aborted — the held slot becomes [PhaseStatus.aborted] (or is released);
/// - reached — the timeline cursor reaches the actor's next natural DEX
///   phase ([activeSegment] `>= M`), at which point the hold has lapsed.
///
/// Display-only: computed from immutable state, never mutates the timeline
/// model (same pattern as [phaseSlotDisplayLabel]).
String? virtualHoldLabel(Combatant combatant, int segment, int activeSegment) {
  final span = virtualHoldSpan(combatant, activeSegment);
  if (span == null) return null;
  return segment >= span.$1 && segment < span.$2 ? '[HOLD]' : null;
}

/// Whether [combatant] maintains an active held state: a [PhaseStatus.held]
/// phase slot whose virtual `[HOLD]` marker span is still open (see
/// [virtualHoldSpan]). Drives the contextual Actor button label
/// (`[H]old Action` → `Use [H]old`).
bool hasActiveHold(Combatant combatant, int activeSegment) {
  return virtualHoldSpan(combatant, activeSegment) != null;
}

/// The `[HOLD]` marker span for [combatant] as `(from, toExclusive)`, or
/// `null` when no hold is currently active. See [virtualHoldLabel].
///
/// [combatant] may hold at most one pending action at a time; the span runs
/// from the held phase's segment (the segment of declaration — where the
/// `[H]` tile sits) up to (but not including) the actor's next natural DEX
/// phase: their next phase slot on the timeline, or Segment 12 when none
/// remains this Turn.
(int, int)? virtualHoldSpan(Combatant combatant, int activeSegment) {
  var heldSegment = -1;
  var nextNatural = 13; // Exclusive end: through Segment 12 by default.
  for (final slot in combatant.phaseSlots) {
    if (slot.status == PhaseStatus.held &&
        (heldSegment < 0 || slot.segment < heldSegment)) {
      heldSegment = slot.segment;
    }
  }
  if (heldSegment < 0) return null;
  for (final slot in combatant.phaseSlots) {
    if (slot.segment > heldSegment && slot.segment < nextNatural) {
      nextNatural = slot.segment;
    }
  }
  // The hold lapses ("reached") once the timeline cursor arrives at the
  // actor's next natural DEX phase.
  if (activeSegment >= nextNatural) return null;
  return (heldSegment, nextNatural);
}

/// Post-12 end-of-Turn indicator for [combatant], or `null` when none is
/// shown (dead): `[REC]` while Post-12 Recovery is active (normal, stunned,
/// KO), `[BLEED]` when recovery is suppressed (dying, -1 BOD on Post-12).
String? post12DisplayLabel(Combatant combatant) {
  switch (combatant.status) {
    case CombatantStatus.normal:
    case CombatantStatus.stunned:
    case CombatantStatus.knockedOut:
      return '[REC]';
    case CombatantStatus.dying:
      return '[BLEED]';
    case CombatantStatus.dead:
      return null;
  }
}