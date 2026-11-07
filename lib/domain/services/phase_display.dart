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
/// - dying: all natural Phase Recoveries are suppressed (no `[REC]` — the
///   character only bleeds, see [post12DisplayLabel]).
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
      return slot.status == PhaseStatus.scheduled ? '[REC]' : null;
    case CombatantStatus.dying:
    case CombatantStatus.normal:
    case CombatantStatus.dead:
      return null;
  }
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