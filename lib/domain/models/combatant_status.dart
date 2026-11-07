/// Overall condition of a combatant (distinct from the temporary
/// [PhaseStatus] badges): drives the detail panel's status buttons, phase
/// rendering ([CLR STUN] / [REC] / [BLEED]) and the timeline traversal
/// bypass (unconscious combatants are skipped).
enum CombatantStatus {
  /// Fully operational.
  normal,

  /// Stunned: the next scheduled phase renders as `[CLR STUN]` and is
  /// consumed to clear the stun; 1/2 DCV.
  stunned,

  /// Dying: unconscious and bleeding (-1 BOD on Post-12); Post-12 REC is
  /// suppressed in favor of a `[BLEED]` indicator.
  dying,

  /// Knocked out — recovery pseudo-phases stop on the timeline; Post-12 REC
  /// remains active.
  knockedOut,

  /// Dead — phase slots are cleared from the row and the row is greyed.
  dead;

  /// Compact status label used by the Target column and status controls.
  String get label => switch (this) {
        CombatantStatus.normal => 'OK',
        CombatantStatus.stunned => 'STUN',
        CombatantStatus.dying => 'DYING',
        CombatantStatus.knockedOut => 'KO',
        CombatantStatus.dead => 'DEAD',
      };
}