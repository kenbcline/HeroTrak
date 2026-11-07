import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/speed_chart.dart';
import '../../domain/actions/actions.dart';
import '../../domain/models/models.dart';
import '../../domain/services/phase_display.dart';
import '../../domain/services/segment_queue.dart';
import '../../domain/services/timeline_traversal.dart';
import 'matrix_ui_state.dart';

/// Core turn engine for the tracker: segment navigation and action execution.
///
/// Holds the current [TurnState] and advances the turn cursor segment by
/// segment. [nextStep] advances the active segment; after Segment 12 the turn
/// wraps: [TurnState.turnNumber] is incremented and the cursor loops back to
/// Segment 1. [previousStep] mirrors that navigation and is a no-op at
/// Turn 1 / Segment 1.
///
/// [executeAction] applies an [ActionDefinition]'s primitive [ActionMutation]s
/// atomically to the resolved subject combatant: if any mutation cannot be
/// applied, a [StateError] is thrown and the turn state is left untouched.
class TurnEngineNotifier extends Notifier<TurnState> {
  TurnEngineNotifier({this.initial});

  /// Optional initial state (used by tests and encounter loading).
  final TurnState? initial;

  @override
  TurnState build() {
    return initial ?? TurnState(turnNumber: 1, activeSegment: 1);
  }

  /// The action queue for the active segment, in resolution order.
  ///
  /// Contains one [SegmentQueueEntry] per actionable phase slot: slots
  /// scheduled in [TurnState.activeSegment], plus pending held interruptions
  /// ([PhaseStatus.held] slots scheduled earlier in the Turn, which may
  /// interrupt at any later point). Consumed ([PhaseStatus.spent]) and
  /// aborted ([PhaseStatus.aborted]) phases are never queued.
  ///
  /// Entries are unmodifiable and sorted per [compareSegmentQueueEntries]:
  /// Held Interruptions first, then mental actions by EGO descending, then
  /// physical actions by DEX descending.
  List<SegmentQueueEntry> get activeSegmentQueue {
    return segmentQueueEntries(state, state.activeSegment);
  }

  /// Sets the active segment, jumping the board directly to it.
  ///
  /// Unlike [nextStep], this never wraps into a new Turn: `turnNumber` is
  /// unchanged and no turn reset or confirmation is triggered. The cursor
  /// stays in the current Turn.
  ///
  /// Throws [ArgumentError] when [segment] is outside 1–12.
  void setActiveSegment(int segment) {
    if (segment < 1 || segment > 12) {
      throw ArgumentError.value(
        segment,
        'segment',
        'segment must be between 1 and 12',
      );
    }
    state = state.copyWith(activeSegment: segment);
  }

  /// Selects the next combatant as the Target/Actee ([TurnState.targetCombatantId],
  /// Down Arrow).
  ///
  /// Pure target-cursor navigation in Column 1 order: cycles through
  /// [TurnState.combatants] in order, wrapping at the end. Never touches
  /// [TurnState.activeSegment], [TurnState.turnNumber],
  /// [TurnState.activeCombatantId], or any phase state — no auto-recovery
  /// or phase-clear side effects. With no target yet the first combatant is
  /// selected; with no combatants this is a no-op.
  void selectNextTarget() => _cycleTargetSelection(forward: true);

  /// Selects the previous combatant as the Target/Actee (Up Arrow).
  ///
  /// Reverse of [selectNextTarget]: same pure selection semantics, cycling
  /// backward and wrapping at the start.
  void selectPreviousTarget() => _cycleTargetSelection(forward: false);

  void _cycleTargetSelection({required bool forward}) {
    final combatants = state.combatants;
    if (combatants.isEmpty) return;

    final index = combatants.indexWhere(
      (combatant) => combatant.id == state.targetCombatantId,
    );
    final next = index < 0
        ? (forward ? 0 : combatants.length - 1)
        : forward
            ? (index + 1) % combatants.length
            : (index - 1 + combatants.length) % combatants.length;
    state = state.copyWith(targetCombatantId: combatants[next].id);
  }

  /// Selects the very next phase on the Turn's timeline (Right Arrow).
  ///
  /// The walk looks ahead in [activeSegmentQueue] (Held → Mental by EGO →
  /// Physical by DEX), then steps forward through Segments +1, +2, ...
  /// skipping empty ones, jumping both [TurnState.activeSegment] (the
  /// highlight) and [TurnState.activeCombatantId] (the row) to the first
  /// phase of the next segment that contains one.
  ///
  /// Returns `false` without changing state when the Turn's timeline is
  /// exhausted — the caller decides whether to confirm "Start Next Turn?"
  /// and then call [startNextTurn].
  bool selectNextPhaseSlot() {
    final position = findNextPhasePosition(state);
    if (position == null) {
      // The Turn's timeline is exhausted (the walk steps onto Post-12):
      // every remaining "[CLR STUN]" window closes with the Turn.
      _clearPassedStunPhases(destinationSegment: null);
      return false;
    }
    _clearPassedStunPhases(destinationSegment: position.segment);
    state = state.copyWith(
      activeSegment: position.segment,
      activeCombatantId: position.combatantId,
    );
    _expireTransientTags(
      cursorSegment: position.segment,
      arrivingCombatantId: position.combatantId,
    );
    return true;
  }

  /// 6e stun recovery: a stunned combatant's next scheduled phase renders as
  /// "[CLR STUN]" and its action is consumed to clear the stun. Advancing
  /// the timeline past that phase ([destinationSegment] beyond it) auto-
  /// clears the status to [CombatantStatus.normal]; `destinationSegment:
  /// null` closes every remaining stun (the Turn's timeline is done).
  void _clearPassedStunPhases({required int? destinationSegment}) {
    var changed = false;
    final combatants = List<Combatant>.of(state.combatants);
    for (var i = 0; i < combatants.length; i++) {
      final combatant = combatants[i];
      if (combatant.status != CombatantStatus.stunned) continue;
      final slotIndex = nextScheduledSlotIndex(combatant, state.activeSegment);
      if (destinationSegment != null) {
        if (slotIndex < 0) continue;
        if (combatant.phaseSlots[slotIndex].segment >= destinationSegment) {
          continue;
        }
      }
      final slots = List<PhaseSlot>.of(combatant.phaseSlots);
      if (slotIndex >= 0) {
        slots[slotIndex] = slots[slotIndex].copyWith(status: PhaseStatus.spent);
      }
      combatants[i] = combatant.copyWith(
        status: CombatantStatus.normal,
        phaseSlots: slots,
      );
      changed = true;
    }
    if (!changed) return;
    state = state.copyWith(combatants: _sortedCombatants(combatants));
  }

  /// Selects the previous phase on the Turn's timeline (Left Arrow).
  ///
  /// Mirror of [selectNextPhaseSlot]: walks backward through the active
  /// segment's queue, then steps back through Segments -1, -2, ... landing
  /// on the *last* phase of the nearest earlier segment that contains one.
  /// At the very start of the Turn this is a no-op returning `false`.
  ///
  /// Reversing out of the Post-12 column disengages it first: the column
  /// selection clears and focus lands on the Turn's final timeline stop
  /// (the tail of the Segment 12 queue), so subsequent Next Phase presses
  /// resume standard segment walking instead of re-triggering the
  /// "Start Next Turn?" prompt.
  bool selectPreviousPhaseSlot() {
    if (ref.read(selectedColumnProvider) == 'post12') {
      ref.read(selectedColumnProvider.notifier).state = null;
      final last = findLastPhasePosition(state);
      if (last == null) return false;
      state = state.copyWith(
        activeSegment: last.segment,
        activeCombatantId: last.combatantId,
      );
      return true;
    }

    final position = findPreviousPhasePosition(state);
    if (position == null) return false;
    state = state.copyWith(
      activeSegment: position.segment,
      activeCombatantId: position.combatantId,
    );
    return true;
  }

  /// Starts the next Turn (Turn N+1, Segment 1) with the smart reset, and
  /// selects the first combatant of Segment 1's queue when it has phases.
  ///
  /// This is the confirmed outcome of a timeline walk that ran past
  /// Segment 12 (see [selectNextPhaseSlot]); it is also the standard turn
  /// advance used by the "Start Next Turn?" flow.
  void startNextTurn() {
    state = _enterNextTurn();
    final ids = phaseIdsAtSegment(state, 1);
    if (ids.isNotEmpty) {
      state = state.copyWith(activeCombatantId: ids.first);
    }
  }

  /// Advances to the next segment.
  ///
  /// After Segment 12 the turn wraps: the turn number increments, the cursor
  /// loops to Segment 1, and the smart turn reset clears transient per-turn
  /// state (see [_enterNextTurn]).
  void nextStep() {
    if (state.activeSegment < 12) {
      _clearPassedStunPhases(destinationSegment: state.activeSegment + 1);
      state = state.copyWith(activeSegment: state.activeSegment + 1);
      _expireTransientTags(cursorSegment: state.activeSegment);
    } else {
      state = _enterNextTurn();
    }
  }

  /// Expires transient per-action tags so they never linger on the panels:
  /// a combatant's condition badges (`held`/`aborted`/…) clear when they
  /// reach their next scheduled phase ([arrivingCombatantId]), and haymaker
  /// wind-ups (with their markers) expire once their resolution is behind
  /// the timeline cursor ([cursorSegment]) or their Turn concludes.
  void _expireTransientTags({
    required int cursorSegment,
    String? arrivingCombatantId,
  }) {
    var changed = false;
    final declarations = <HaymakerDeclaration>[
      for (final declaration in state.haymakerDeclarations)
        if (declaration.resolutionTurn > state.turnNumber ||
            (declaration.resolutionTurn == state.turnNumber &&
                declaration.resolutionSegment >= cursorSegment))
          declaration,
    ];
    if (declarations.length != state.haymakerDeclarations.length) {
      changed = true;
    }

    final combatants = List<Combatant>.of(state.combatants);
    if (arrivingCombatantId != null) {
      final index = combatants.indexWhere(
        (combatant) => combatant.id == arrivingCombatantId,
      );
      if (index >= 0 && combatants[index].statusBadges.isNotEmpty) {
        combatants[index] = combatants[index].copyWith(
          statusBadges: const <PhaseStatus>[],
        );
        changed = true;
      }
    }
    if (!changed) return;
    state = state.copyWith(
      combatants: _sortedCombatants(combatants),
      haymakerDeclarations: declarations,
    );
  }

  /// Wraps into the next Turn with a smart reset of transient per-turn state.
  ///
  /// Cleared (must not bleed into the new Turn):
  /// - phase slot statuses — including unspent expired `held` interruptions —
  ///   return to [PhaseStatus.scheduled] (the 6e Speed Chart schedule repeats
  ///   every Turn, so no phase is lost);
  /// - leftover temporary action flags on slots (`actionId`/`actionLabel`,
  ///   e.g. declared haymaker execution flags);
  /// - temporary condition badges ([Combatant.statusBadges]);
  /// - expired haymaker declarations (including stale Segment-12 wind-ups
  ///   whose deferred strike Turn has already passed).
  ///
  /// Kept intact: combatant base stats and flags, custom phase slot
  /// configuration (segments incl. relocations, [PhaseSlot.originalSegment],
  /// [PhaseSlot.isMental]), ongoing selections, and haymakers declared on
  /// Segment 12 whose "Strikes" marker resolves on Segment 1 of the new Turn.
  TurnState _enterNextTurn() {
    final nextTurnNumber = state.turnNumber + 1;
    return state.copyWith(
      turnNumber: nextTurnNumber,
      activeSegment: 1,
      // Segment-12 declarations carry their "Strikes/Resolves" marker into
      // the next Turn; everything else expires with the current one.
      haymakerDeclarations: <HaymakerDeclaration>[
        for (final declaration in state.haymakerDeclarations)
          if (declaration.resolutionTurn >= nextTurnNumber) declaration,
      ],
      combatants: _sortedCombatants([
        for (final combatant in state.combatants)
          combatant.copyWith(
            // A stun whose "[CLR STUN]" action window closed with the Turn
            // ends here; other conditions (dying/KO/dead) persist.
            status: combatant.status == CombatantStatus.stunned
                ? CombatantStatus.normal
                : combatant.status,
            statusBadges: const <PhaseStatus>[],
            phaseSlots: <PhaseSlot>[
              for (final slot in combatant.phaseSlots)
                slot.copyWith(
                  status: PhaseStatus.scheduled,
                  actionId: null,
                  actionLabel: null,
                ),
            ],
          ),
      ]),
    );
  }

  /// Replaces the whole encounter state with [encounter] (JSON import),
  /// maintaining initiative order.
  void loadEncounter(TurnState encounter) {
    state = encounter.copyWith(
      combatants: _sortedCombatants(encounter.combatants),
    );
  }

  /// Maintains [TurnState.combatants] in initiative order (SPD descending,
  /// DEX descending, EGO descending, Name ascending) so table rows stack
  /// naturally and timeline navigation moves smoothly down the page.
  List<Combatant> _sortedCombatants(Iterable<Combatant> combatants) {
    return combatants.toList()..sort(Combatant.compareByInitiative);
  }

  /// Steps back to the previous segment.
  ///
  /// At Segment 1 of a later turn the cursor wraps back to Segment 12 of
  /// the previous turn. At Turn 1 / Segment 1 there is nowhere to step back
  /// to, so the call is a no-op.
  void previousStep() {
    if (state.activeSegment > 1) {
      state = state.copyWith(activeSegment: state.activeSegment - 1);
    } else if (state.turnNumber > 1) {
      state = state.copyWith(turnNumber: state.turnNumber - 1, activeSegment: 12);
    }
  }

  /// Sets the active (acting) combatant.
  ///
  /// Passing `null` clears the selection.
  void setActiveCombatant(String? id) {
    state = state.copyWith(activeCombatantId: id);
  }

  /// Sets the targeted combatant.
  ///
  /// Passing `null` clears the selection.
  void setTargetCombatant(String? id) {
    state = state.copyWith(targetCombatantId: id);
  }

  /// Adds a new combatant to the encounter.
  ///
  /// The combatant's [PhaseSlot] list is auto-generated from the standard 6e
  /// Speed Chart for [spd] (see [getSegmentsForSpd]); every slot starts as
  /// [PhaseStatus.scheduled]. An [id] may be supplied (e.g. for imports);
  /// otherwise a unique `combatant-N` id is generated. Returns the id of the
  /// added combatant.
  ///
  /// Throws [ArgumentError] when [name] is blank, [spd] is outside the
  /// 1–12 Speed Chart range, or [id] collides with an existing combatant.
  String addCombatant({
    required String name,
    required int dex,
    required int ego,
    required int spd,
    required int stun,
    required int end,
    required int body,
    int intelligence = 0,
    int strength = 0,
    int constitution = 0,
    int physicalDefense = 0,
    int energyDefense = 0,
    int recovery = 0,
    String team = '',
    bool isNpc = false,
    String? id,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'name must not be blank');
    }

    final combatantId = id ?? _uniqueCombatantId();
    if (state.combatants.any((combatant) => combatant.id == combatantId)) {
      throw ArgumentError.value(
        combatantId,
        'id',
        'a combatant with this id already exists',
      );
    }

    final slots = <PhaseSlot>[
      for (final segment in getSegmentsForSpd(spd)) PhaseSlot(segment: segment),
    ];
    final combatant = Combatant(
      id: combatantId,
      name: name.trim(),
      dex: dex,
      ego: ego,
      spd: spd,
      stun: stun,
      end: end,
      body: body,
      intelligence: intelligence,
      strength: strength,
      constitution: constitution,
      physicalDefense: physicalDefense,
      energyDefense: energyDefense,
      recovery: recovery,
      team: team,
      isNpc: isNpc,
      phaseSlots: slots,
    );
    state = state.copyWith(
      combatants: _sortedCombatants([...state.combatants, combatant]),
    );
    return combatantId;
  }

  /// Returns a combatant id of the form `combatant-N` not yet in use.
  String _uniqueCombatantId() {
    final taken = <String>{
      for (final combatant in state.combatants) combatant.id,
    };
    var n = state.combatants.length + 1;
    while (taken.contains('combatant-$n')) {
      n++;
    }
    return 'combatant-$n';
  }

  /// Executes [action]'s primitive mutations against the resolved subject
  /// combatant.
  ///
  /// Subject resolution order: an explicit [targetId], otherwise the state's
  /// [TurnState.targetCombatantId], otherwise [TurnState.activeCombatantId].
  ///
  /// Mutations are applied atomically: if any mutation cannot be applied a
  /// [StateError] is thrown and the turn state is left untouched.
  void executeAction(ActionDefinition action, {String? targetId}) {
    final subjectId =
        targetId ?? state.targetCombatantId ?? state.activeCombatantId;
    if (subjectId == null) {
      throw StateError(
        'executeAction(${action.id}): no subject combatant could be resolved',
      );
    }

    var combatants = List<Combatant>.of(state.combatants);
    final declarations =
        List<HaymakerDeclaration>.of(state.haymakerDeclarations);
    var mutations = action.mutations;
    if (action.id == ActionDefinition.abortToDefensiveAction.id) {
      // [A]bort cancels the subject's pending haymaker outright: both the
      // `[M]` wind-up and the "Strikes" resolution markers clear with the
      // declaration.
      final abortsPendingResolution = declarations.any(
        (declaration) =>
            declaration.combatantId == subjectId &&
            declaration.resolutionSegment == state.activeSegment &&
            declaration.resolutionTurn == state.turnNumber,
      );
      declarations.removeWhere(
        (declaration) => declaration.combatantId == subjectId,
      );
      if (abortsPendingResolution) {
        // The abort lands on the pending "Strikes" resolution phase: that
        // pseudo-phase is what gets consumed, so the mutation stream is
        // trimmed and no downstream scheduled phase is double-aborted.
        mutations = <ActionMutation>[
          for (final mutation in mutations)
            if (mutation.type != ActionMutationType.consumeNextPhase) mutation,
        ];
      }
    }
    for (final mutation in mutations) {
      combatants = _applyMutation(mutation, combatants, subjectId, declarations);
    }
    state = state.copyWith(
      combatants: _sortedCombatants(combatants),
      haymakerDeclarations: declarations,
    );
  }

  /// Sets the overall condition ([CombatantStatus]) of [combatantId].
  ///
  /// Status-driven phase markers ([CLR STUN] / [REC]) clear back to standard
  /// phase slots the moment the combatant recovers to
  /// [CombatantStatus.normal] — the recovered phase is available (scheduled)
  /// immediately, nothing is consumed. Entering [CombatantStatus.dead]
  /// clears every phase slot from the row; restoring away from DEAD
  /// re-populates the combatant's natural Speed Chart phases.
  void setCombatantStatus(String combatantId, CombatantStatus status) {
    final combatants = List<Combatant>.of(state.combatants);
    final index = _indexOfCombatant(
      combatants,
      combatantId,
      'setCombatantStatus',
    );
    final combatant = combatants[index];
    var phaseSlots = combatant.phaseSlots;
    if (status == CombatantStatus.dead &&
        combatant.status != CombatantStatus.dead) {
      // DEAD clears all phase slots from the matrix grid row.
      phaseSlots = const <PhaseSlot>[];
    } else if (combatant.status == CombatantStatus.dead &&
        status != CombatantStatus.dead) {
      // Restoring away from DEAD re-populates the natural Speed Chart.
      phaseSlots = <PhaseSlot>[
        for (final segment in getSegmentsForSpd(combatant.effectiveSpd))
          PhaseSlot(segment: segment),
      ];
    }
    combatants[index] = combatant.copyWith(
      status: status,
      phaseSlots: phaseSlots,
    );
    state = state.copyWith(combatants: _sortedCombatants(combatants));
  }

  /// Quick-toggle used by the detail panel's status buttons: selecting an
  /// already-active status returns the combatant to
  /// [CombatantStatus.normal] instead of keeping it stuck.
  void toggleCombatantStatus(String combatantId, CombatantStatus status) {
    final index = state.combatants.indexWhere(
      (combatant) => combatant.id == combatantId,
    );
    final current = index < 0 ? null : state.combatants[index].status;
    setCombatantStatus(
      combatantId,
      current == status ? CombatantStatus.normal : status,
    );
  }

  /// Adjusts the temporary SPD modifier ([Combatant.spdDelta], the Aid/Drain
  /// adjustment) of [combatantId] by [change] and immediately re-schedules
  /// their upcoming phases: every slot after [TurnState.activeSegment] is
  /// rebuilt from the new [Combatant.effectiveSpd] Speed Chart, while past
  /// segments are left untouched.
  void adjustSpdDelta(String combatantId, int change) {
    final combatants = List<Combatant>.of(state.combatants);
    final index = _indexOfCombatant(combatants, combatantId, 'adjustSpdDelta');
    final combatant = combatants[index];
    final updated = combatant.copyWith(spdDelta: combatant.spdDelta + change);
    combatants[index] = updated.copyWith(
      phaseSlots: _rescheduledPhaseSlots(updated),
    );
    state = state.copyWith(combatants: _sortedCombatants(combatants));
  }

  /// Clears the Target's reaction state: the `Aborted` badge is removed and
  /// the temporary SPD modifier resets to `0` (with the upcoming phase
  /// schedule re-calculated for the base SPD).
  void clearReaction(String combatantId) {
    final combatants = List<Combatant>.of(state.combatants);
    final index = _indexOfCombatant(combatants, combatantId, 'clearReaction');
    final combatant = combatants[index];
    final cleared = combatant.copyWith(
      spdDelta: 0,
      statusBadges: <PhaseStatus>[
        for (final badge in combatant.statusBadges)
          if (badge != PhaseStatus.aborted) badge,
      ],
    );
    combatants[index] = cleared.copyWith(
      phaseSlots: _rescheduledPhaseSlots(cleared),
    );
    state = state.copyWith(combatants: _sortedCombatants(combatants));
  }

  /// Clears the Actor's active action state — `[C]lear Action`: `Hold`
  /// interruptions are released (held slots return to `scheduled`) and
  /// declared Haymakers are cancelled (declarations and wind-up flags
  /// removed), restoring normal phase markers.
  void clearAction(String combatantId) {
    var changed = false;
    final declarations = <HaymakerDeclaration>[
      for (final declaration in state.haymakerDeclarations)
        if (declaration.combatantId != combatantId) declaration,
    ];
    if (declarations.length != state.haymakerDeclarations.length) {
      changed = true;
    }

    final combatants = List<Combatant>.of(state.combatants);
    final index = _indexOfCombatant(combatants, combatantId, 'clearAction');
    final combatant = combatants[index];
    var slotsChanged = false;
    final slots = <PhaseSlot>[];
    for (final slot in combatant.phaseSlots) {
      if (slot.status == PhaseStatus.held) {
        slots.add(
          slot.copyWith(
            status: PhaseStatus.scheduled,
            actionId: null,
            actionLabel: null,
          ),
        );
        slotsChanged = true;
      } else if (slot.actionId == ActionDefinition.declareHaymaker.id) {
        slots.add(slot.copyWith(actionId: null, actionLabel: null));
        slotsChanged = true;
      } else {
        slots.add(slot);
      }
    }
    final badges = <PhaseStatus>[
      for (final badge in combatant.statusBadges)
        if (badge != PhaseStatus.held) badge,
    ];
    if (badges.length != combatant.statusBadges.length) changed = true;

    if (!changed && !slotsChanged) return;
    combatants[index] = combatant.copyWith(
      phaseSlots: slots,
      statusBadges: badges,
    );
    state = state.copyWith(
      combatants: _sortedCombatants(combatants),
      haymakerDeclarations: declarations,
    );
  }

  /// Rebuilds [combatant]'s phase schedule for their effective SPD: slots up
  /// to and including [TurnState.activeSegment] are kept verbatim (past
  /// segments are never altered), while every later segment is
  /// re-calculated from the Speed Chart.
  List<PhaseSlot> _rescheduledPhaseSlots(Combatant combatant) {
    final futureSegments = <int>{
      for (final segment in getSegmentsForSpd(combatant.effectiveSpd))
        if (segment > state.activeSegment) segment,
    }.toList()..sort();
    return <PhaseSlot>[
      for (final slot in combatant.phaseSlots)
        if (slot.segment <= state.activeSegment) slot,
      for (final segment in futureSegments) PhaseSlot(segment: segment),
    ];
  }

  /// Resets the encounter to a clean slate: Turn 1, Segment 1, no combatants,
  /// no selections and no pending haymakers. The confirmed outcome of the
  /// "New Encounter..." menu command.
  void resetEncounter() {
    state = TurnState(turnNumber: 1, activeSegment: 1);
  }

  /// Resets the timeline to Turn 1 / Segment 1 while preserving the combatant
  /// roster (used by the "Reset to Turn 1, Segment 1 on load" option):
  /// transient per-turn state clears — phase statuses and action flags,
  /// condition badges, haymaker declarations — and the timeline cursors
  /// reset.
  void resetTimeline() {
    state = state.copyWith(
      turnNumber: 1,
      activeSegment: 1,
      activeCombatantId: null,
      targetCombatantId: null,
      haymakerDeclarations: const <HaymakerDeclaration>[],
      combatants: _sortedCombatants([
        for (final combatant in state.combatants)
          combatant.copyWith(
            statusBadges: const <PhaseStatus>[],
            phaseSlots: <PhaseSlot>[
              for (final slot in combatant.phaseSlots)
                slot.copyWith(
                  status: PhaseStatus.scheduled,
                  actionId: null,
                  actionLabel: null,
                ),
            ],
          ),
      ]),
    );
  }

  /// Removes a temporary condition [badge] from the resolved subject combatant.
  ///
  /// Subject resolution matches [executeAction]. No-op when the badge is not
  /// applied; throws [StateError] when no subject can be resolved.
  void removeStatusBadge(PhaseStatus badge, {String? targetId}) {
    final subjectId =
        targetId ?? state.targetCombatantId ?? state.activeCombatantId;
    if (subjectId == null) {
      throw StateError(
        'removeStatusBadge: no subject combatant could be resolved',
      );
    }

    final combatants = List<Combatant>.of(state.combatants);
    final index = _indexOfCombatant(combatants, subjectId, 'removeStatusBadge');
    final subject = combatants[index];
    if (!subject.statusBadges.contains(badge)) return;

    combatants[index] = subject.copyWith(
      statusBadges: [
        for (final existing in subject.statusBadges)
          if (existing != badge) existing,
      ],
    );
    state = state.copyWith(combatants: _sortedCombatants(combatants));
  }

  List<Combatant> _applyMutation(
    ActionMutation mutation,
    List<Combatant> combatants,
    String subjectId,
    List<HaymakerDeclaration> declarations,
  ) {
    return switch (mutation.type) {
      ActionMutationType.consumeNextPhase =>
        _consumeNextPhase(combatants, subjectId),
      ActionMutationType.relocatePhase =>
        _relocatePhase(combatants, subjectId, mutation.targetSegment!),
      ActionMutationType.applyStatusBadge =>
        _applyStatusBadge(combatants, subjectId, mutation.status!),
      ActionMutationType.insertQueueOverride => _insertQueueOverride(
        combatants,
        declarations,
        subjectId,
        mutation.queueOverride!,
      ),
    };
  }

  /// Consumes the subject's next `scheduled` phase slot
  /// (see [_nextScheduledSlotIndex]) by marking it [PhaseStatus.spent].
  List<Combatant> _consumeNextPhase(
    List<Combatant> combatants,
    String subjectId,
  ) {
    return _replaceNextScheduledSlot(
      combatants,
      subjectId,
      'consumeNextPhase',
      (slot) => slot.copyWith(status: PhaseStatus.spent),
    );
  }

  /// Relocates the subject's next scheduled phase slot to [targetSegment],
  /// preserving [PhaseSlot.originalSegment].
  List<Combatant> _relocatePhase(
    List<Combatant> combatants,
    String subjectId,
    int targetSegment,
  ) {
    return _replaceNextScheduledSlot(
      combatants,
      subjectId,
      'relocatePhase',
      (slot) => slot.copyWith(segment: targetSegment),
    );
  }

  /// Applies [badge] as a temporary condition badge to the subject combatant.
  /// Applying a badge that is already present is a no-op.
  List<Combatant> _applyStatusBadge(
    List<Combatant> combatants,
    String subjectId,
    PhaseStatus badge,
  ) {
    final index = _indexOfCombatant(combatants, subjectId, 'applyStatusBadge');
    final subject = combatants[index];
    if (subject.statusBadges.contains(badge)) return combatants;

    combatants[index] = subject.copyWith(
      statusBadges: [...subject.statusBadges, badge],
    );
    return combatants;
  }

  /// Handles a queue override insertion by descriptor.
  ///
  /// - `hold_interrupt` (**[H]old**): the phase being acted on is put on
  ///   hold ([PhaseStatus.held]) and jumps the queue — see
  ///   [activeSegmentQueue].
  /// - `haymaker_end_of_segment` (**Hay[M]aker**): the originating phase slot
  ///   keeps its own schedule (it is never relocated, so nothing is orphaned
  ///   across Turn boundaries) and retains the wind-up flag at Segment N;
  ///   a decoupled [HaymakerDeclaration] schedules the "Strikes/Resolves"
  ///   marker at N+1 (wrapping past Segment 12 to Segment 1).
  List<Combatant> _insertQueueOverride(
    List<Combatant> combatants,
    List<HaymakerDeclaration> declarations,
    String subjectId,
    String queueOverride,
  ) {
    switch (queueOverride) {
      case 'hold_interrupt':
        return _replaceNextScheduledSlot(
          combatants,
          subjectId,
          'insertQueueOverride(hold_interrupt)',
          (slot) => slot.copyWith(status: PhaseStatus.held),
        );
      case 'haymaker_end_of_segment':
        const operation = 'insertQueueOverride(haymaker_end_of_segment)';
        final index = _indexOfCombatant(combatants, subjectId, operation);
        final subject = combatants[index];
        final slotIndex = _nextScheduledSlotIndex(subject);
        if (slotIndex < 0) {
          throw StateError(
            '$operation: combatant "$subjectId" has no upcoming scheduled '
            'phase',
          );
        }

        final slot = subject.phaseSlots[slotIndex];
        final slots = List<PhaseSlot>.of(subject.phaseSlots);
        // The base phase slot is NOT relocated: it stays on its own Segment
        // and retains the wind-up/charging indicator there.
        slots[slotIndex] = slot.copyWith(
          actionId: ActionDefinition.declareHaymaker.id,
          actionLabel: ActionDefinition.declareHaymaker.label,
        );
        combatants[index] = subject.copyWith(phaseSlots: slots);
        // The decoupled declaration drives the "Strikes/Resolves" marker at
        // N+1; one pending haymaker per combatant (re-declaring replaces).
        declarations
          ..removeWhere((declaration) => declaration.combatantId == subjectId)
          ..add(
            HaymakerDeclaration.at(
              combatantId: subjectId,
              segment: slot.segment,
              declaredTurn: state.turnNumber,
            ),
          );
        return combatants;
      default:
        throw StateError(
          'insertQueueOverride: unknown queue override "$queueOverride"',
        );
    }
  }

  /// Applies [replace] to the subject's next scheduled phase slot and returns
  /// the updated combatants list. Throws [StateError] when the subject has no
  /// upcoming scheduled phase.
  List<Combatant> _replaceNextScheduledSlot(
    List<Combatant> combatants,
    String subjectId,
    String operation,
    PhaseSlot Function(PhaseSlot slot) replace,
  ) {
    final index = _indexOfCombatant(combatants, subjectId, operation);
    final subject = combatants[index];
    final slotIndex = _nextScheduledSlotIndex(subject);
    if (slotIndex < 0) {
      throw StateError(
        '$operation: combatant "$subjectId" has no upcoming scheduled phase',
      );
    }

    final slots = List<PhaseSlot>.of(subject.phaseSlots);
    slots[slotIndex] = replace(slots[slotIndex]);
    combatants[index] = subject.copyWith(phaseSlots: slots);
    return combatants;
  }

  /// Index of the subject's next `scheduled` phase slot in time order starting
  /// at [TurnState.activeSegment]: segments `activeSegment..12` first, then
  /// wrapping to `1..activeSegment-1` (future Turns reuse the same schedule).
  ///
  /// Returns -1 when the subject has no scheduled phase left.
  int _nextScheduledSlotIndex(Combatant subject) {
    final active = state.activeSegment;
    for (var segment = active; segment <= 12; segment++) {
      for (var i = 0; i < subject.phaseSlots.length; i++) {
        final slot = subject.phaseSlots[i];
        if (slot.segment == segment && slot.status == PhaseStatus.scheduled) {
          return i;
        }
      }
    }
    for (var segment = 1; segment < active; segment++) {
      for (var i = 0; i < subject.phaseSlots.length; i++) {
        final slot = subject.phaseSlots[i];
        if (slot.segment == segment && slot.status == PhaseStatus.scheduled) {
          return i;
        }
      }
    }
    return -1;
  }

  int _indexOfCombatant(
    List<Combatant> combatants,
    String subjectId,
    String operation,
  ) {
    final index = combatants.indexWhere(
      (combatant) => combatant.id == subjectId,
    );
    if (index < 0) {
      throw StateError('$operation: no combatant with id "$subjectId"');
    }
    return index;
  }
}

/// Provider for the core turn navigation engine.
final turnEngineProvider =
    NotifierProvider<TurnEngineNotifier, TurnState>(TurnEngineNotifier.new);