/// Status of an individual phase slot during a Turn.
enum PhaseStatus {
  /// The phase is scheduled and has not been used yet.
  scheduled,

  /// The phase is currently being resolved.
  active,

  /// The action is being held for a later interrupt.
  held,

  /// The action was aborted (e.g. aborting to a defensive action).
  aborted,

  /// The phase has been fully consumed.
  spent,

  /// The action has been delayed to a later segment.
  delayed,
}
