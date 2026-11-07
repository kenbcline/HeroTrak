import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/actions/actions.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/presentation/state/matrix_ui_state.dart';
import 'package:herotrak/presentation/state/turn_engine_notifier.dart';

PhaseSlot makeSlot({
  int segment = 6,
  int? originalSegment,
  PhaseStatus status = PhaseStatus.scheduled,
  bool isMental = false,
  String? actionId,
  String? actionLabel,
}) {
  return PhaseSlot(
    segment: segment,
    originalSegment: originalSegment,
    status: status,
    isMental: isMental,
    actionId: actionId,
    actionLabel: actionLabel,
  );
}

Combatant makeCombatant({
  String id = 'c1',
  String name = 'Hero One',
  int dex = 18,
  int ego = 10,
  int spd = 5,
  int stun = 40,
  int end = 20,
  int body = 10,
  List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
}) {
  return Combatant(
    id: id,
    name: name,
    dex: dex,
    ego: ego,
    spd: spd,
    stun: stun,
    end: end,
    body: body,
    phaseSlots: phaseSlots,
  );
}

TurnState makeTurnState({
  int turnNumber = 1,
  int activeSegment = 6,
  String? activeCombatantId,
  String? targetCombatantId,
  List<Combatant> combatants = const <Combatant>[],
  List<HaymakerDeclaration> haymakerDeclarations = const <HaymakerDeclaration>[],
}) {
  return TurnState(
    turnNumber: turnNumber,
    activeSegment: activeSegment,
    activeCombatantId: activeCombatantId,
    targetCombatantId: targetCombatantId,
    combatants: combatants,
    haymakerDeclarations: haymakerDeclarations,
  );
}

ProviderContainer makeContainer([TurnState? initial]) {
  final container = ProviderContainer(
    overrides: [
      turnEngineProvider.overrideWith(
        () => TurnEngineNotifier(initial: initial),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Custom action exercising the [ActionMutationType.relocatePhase] mutation.
const relocateAction = ActionDefinition(
  id: 'test_relocate',
  label: 'Test Relocate',
  hotkey: 'r',
  targetType: ActionTargetType.self,
  mutations: [ActionMutation.relocatePhase(targetSegment: 9)],
);

/// Custom action exercising the [ActionMutationType.applyStatusBadge] mutation.
const delayBadgeAction = ActionDefinition(
  id: 'test_delay_badge',
  label: 'Test Delay Badge',
  hotkey: 'd',
  targetType: ActionTargetType.self,
  mutations: [ActionMutation.applyStatusBadge(status: PhaseStatus.delayed)],
);

/// Custom action with an unrecognized queue override descriptor.
const unknownOverrideAction = ActionDefinition(
  id: 'test_unknown_override',
  label: 'Test Unknown Override',
  hotkey: 'u',
  targetType: ActionTargetType.self,
  mutations: [ActionMutation.insertQueueOverride(queueOverride: 'nope')],
);

Combatant subjectOf(ProviderContainer container, String id) {
  return container
      .read(turnEngineProvider)
      .combatants
      .firstWhere((combatant) => combatant.id == id);
}

void main() {
  group('subject resolution', () {
    test('explicit targetId takes precedence over the state selections', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'active', targetCombatantId: 'target', combatants: [
          makeCombatant(id: 'explicit', phaseSlots: [makeSlot(segment: 6)]),
          makeCombatant(id: 'target', phaseSlots: [makeSlot(segment: 6)]),
          makeCombatant(id: 'active', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(
        ActionDefinition.abortToDefensiveAction,
        targetId: 'explicit',
      );

      expect(
        subjectOf(container, 'explicit').phaseSlots.single.status,
        PhaseStatus.spent,
      );
      expect(
        subjectOf(container, 'target').phaseSlots.single.status,
        PhaseStatus.scheduled,
      );
      expect(
        subjectOf(container, 'active').phaseSlots.single.status,
        PhaseStatus.scheduled,
      );
    });

    test('falls back to the state targetCombatantId', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'active', targetCombatantId: 'target', combatants: [
          makeCombatant(id: 'target', phaseSlots: [makeSlot(segment: 6)]),
          makeCombatant(id: 'active', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.abortToDefensiveAction);

      expect(
        subjectOf(container, 'target').phaseSlots.single.status,
        PhaseStatus.spent,
      );
      expect(
        subjectOf(container, 'active').phaseSlots.single.status,
        PhaseStatus.scheduled,
      );
    });

    test('falls back to the activeCombatantId when nothing is targeted', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'active', combatants: [
          makeCombatant(id: 'active', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.abortToDefensiveAction);

      expect(
        subjectOf(container, 'active').phaseSlots.single.status,
        PhaseStatus.spent,
      );
    });

    test('throws StateError when no subject can be resolved', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(
        () => notifier.executeAction(ActionDefinition.abortToDefensiveAction),
        throwsStateError,
      );
    });

    test('throws StateError when the resolved subject is unknown', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'ghost', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(
        () => notifier.executeAction(ActionDefinition.abortToDefensiveAction),
        throwsStateError,
      );
    });
  });

  group('[A]bort to Defensive Action', () {
    test('applies the defensive status badge and consumes the next upcoming '
        'phase', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 3), // earlier — must not be touched
            makeSlot(segment: 8), // next upcoming — consumed
            makeSlot(segment: 12), // later — untouched
          ]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.abortToDefensiveAction);

      final subject = subjectOf(container, 'c1');
      // Defensive status badge is applied to the subject combatant.
      expect(subject.statusBadges, contains(PhaseStatus.aborted));
      // The next upcoming phase is consumed (aborted/spent).
      expect(subject.phaseSlots[1].status, PhaseStatus.spent);
      expect(subject.phaseSlots[0].status, PhaseStatus.scheduled);
      expect(subject.phaseSlots[2].status, PhaseStatus.scheduled);
    });

    test('consumes the phase in the active segment when one is scheduled', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 6),
            makeSlot(segment: 8),
          ]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.abortToDefensiveAction);

      final subject = subjectOf(container, 'c1');
      expect(subject.phaseSlots[0].status, PhaseStatus.spent);
      expect(subject.phaseSlots[1].status, PhaseStatus.scheduled);
    });

    test('wraps to earlier phases when the rest of the turn is spent', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 3),
            makeSlot(segment: 8, status: PhaseStatus.spent),
          ]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.abortToDefensiveAction);

      expect(
        subjectOf(container, 'c1').phaseSlots[0].status,
        PhaseStatus.spent,
      );
    });

    test('throws StateError and leaves state untouched when no upcoming '
        'phase remains', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 3, status: PhaseStatus.spent),
            makeSlot(segment: 8, status: PhaseStatus.aborted),
          ]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);
      final before = container.read(turnEngineProvider);

      expect(
        () => notifier.executeAction(ActionDefinition.abortToDefensiveAction),
        throwsStateError,
      );
      // Failed execution is atomic: the turn state is unchanged.
      expect(container.read(turnEngineProvider), before);
    });
  });

  group('Interrupt with [H]old', () {
    test('sets the active phase to held and badges the subject', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 6),
            makeSlot(segment: 10),
          ]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.interruptWithHold);

      final subject = subjectOf(container, 'c1');
      expect(subject.phaseSlots[0].status, PhaseStatus.held);
      expect(subject.phaseSlots[1].status, PhaseStatus.scheduled);
      expect(subject.statusBadges, contains(PhaseStatus.held));
    });

    test('a held combatant can interrupt ahead of later segments', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 5, activeCombatantId: 'holder', combatants: [
          makeCombatant(
            id: 'holder',
            dex: 5,
            phaseSlots: [makeSlot(segment: 5)],
          ),
          makeCombatant(
            id: 'fast',
            dex: 30,
            phaseSlots: [makeSlot(segment: 7)],
          ),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.interruptWithHold);
      notifier
        ..nextStep()
        ..nextStep(); // Segment 7 — the held action may interrupt now.

      final queue = notifier.activeSegmentQueue;
      expect(queue.map((entry) => entry.combatant.id), ['holder', 'fast']);
      expect(queue.first.isHeldInterruption, isTrue);
    });

    test('throws StateError and rolls back when the subject has no phase '
        'to hold', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(
            id: 'c1',
            phaseSlots: [makeSlot(segment: 6, status: PhaseStatus.spent)],
          ),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);
      final before = container.read(turnEngineProvider);

      expect(
        () => notifier.executeAction(ActionDefinition.interruptWithHold),
        throwsStateError,
      );
      // The applyStatusBadge mutation ran first but must be rolled back too.
      expect(container.read(turnEngineProvider), before);
    });
  });

  group('Declare Hay[M]aker', () {
    test('flags the wind-up on the base slot and decouples the N+1 '
        'resolution marker', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 5, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 5)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.declareHaymaker);

      final slot = subjectOf(container, 'c1').phaseSlots.single;
      // The originating slot retains the wind-up flag and is NOT relocated.
      expect(slot.actionId, ActionDefinition.declareHaymaker.id);
      expect(slot.actionLabel, ActionDefinition.declareHaymaker.label);
      expect(slot.segment, 5);
      expect(slot.originalSegment, 5);
      // The decoupled declaration schedules the resolution marker at N+1.
      final declaration =
          container.read(turnEngineProvider).haymakerDeclarations.single;
      expect(declaration.combatantId, 'c1');
      expect(declaration.declaredSegment, 5);
      expect(declaration.resolutionSegment, 6);
    });

    test('wraps the resolution marker past segment 12 to segment 1', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 12, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 12)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.declareHaymaker);

      // The base slot is never relocated across the Turn boundary.
      final slot = subjectOf(container, 'c1').phaseSlots.single;
      expect(slot.segment, 12);
      expect(slot.originalSegment, 12);
      final declaration =
          container.read(turnEngineProvider).haymakerDeclarations.single;
      expect(declaration.declaredSegment, 12);
      expect(declaration.resolutionSegment, 1);
    });

    test('throws StateError when no phase can be scheduled', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1'),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(
        () => notifier.executeAction(ActionDefinition.declareHaymaker),
        throwsStateError,
      );
    });
  });

  group('relocatePhase mutation', () {
    test('relocates the next upcoming phase, preserving originalSegment', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 8)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(relocateAction);

      final slot = subjectOf(container, 'c1').phaseSlots.single;
      expect(slot.segment, 9);
      expect(slot.originalSegment, 8);
    });

    test('throws StateError when no upcoming phase exists', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1'),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(() => notifier.executeAction(relocateAction), throwsStateError);
    });
  });

  group('status badges', () {
    test('applying the same badge twice does not duplicate it', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier
        ..executeAction(delayBadgeAction)
        ..executeAction(delayBadgeAction);

      expect(
        subjectOf(container, 'c1').statusBadges,
        [PhaseStatus.delayed],
      );
    });

    test('removeStatusBadge removes an applied badge', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier
        ..executeAction(delayBadgeAction)
        ..removeStatusBadge(PhaseStatus.delayed);

      expect(subjectOf(container, 'c1').statusBadges, isEmpty);
    });

    test('removeStatusBadge is a no-op when the badge is absent', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);
      final before = container.read(turnEngineProvider);

      notifier.removeStatusBadge(PhaseStatus.delayed);

      expect(container.read(turnEngineProvider), before);
    });
  });

  group('preset action triggers', () {
    test('every standard action executes cleanly on a ready combatant', () {
      for (final action in ActionDefinition.standardActions) {
        final container = makeContainer(
          makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
            makeCombatant(id: 'c1', phaseSlots: [
              makeSlot(segment: 6),
              makeSlot(segment: 8),
              makeSlot(segment: 10),
            ]),
          ]),
        );
        final notifier = container.read(turnEngineProvider.notifier);

        expect(
          () => notifier.executeAction(action),
          returnsNormally,
          reason: 'standard action "${action.id}" must execute cleanly',
        );
      }
    });

    test('an unknown queue override descriptor is rejected', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(
        () => notifier.executeAction(unknownOverrideAction),
        throwsStateError,
      );
    });
  });

  group('abort vs. pending haymaker', () {
    test('abort cancels the subject\'s pending haymaker declarations', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 6,
          activeCombatantId: 'c1',
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 11,
              declaredTurn: 1,
            ),
          ],
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 9)]),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.abortToDefensiveAction);

      final state = container.read(turnEngineProvider);
      // Both the [M] wind-up and the "Strikes" resolution markers clear
      // with the declaration...
      expect(state.haymakerDeclarations, isEmpty);
      // ...while the regular abort flow still applies: the badge is set
      // and the next scheduled phase is consumed by the defensive action.
      final subject = state.combatants.single;
      expect(subject.statusBadges, contains(PhaseStatus.aborted));
      expect(subject.phaseSlots.single.status, PhaseStatus.spent);
    });

    test('abort at the pending resolution consumes the resolution phase, '
        'not a scheduled one', () {
      final container = makeContainer(
        makeTurnState(
          turnNumber: 2,
          activeSegment: 1,
          activeCombatantId: 'c1',
          haymakerDeclarations: [
            // Declared on Segment 12 of Turn 1: its "Strikes" pseudo-phase
            // is pending on Segment 1 of Turn 2.
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 12,
              declaredTurn: 1,
            ),
          ],
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 9)]),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.abortToDefensiveAction);

      final state = container.read(turnEngineProvider);
      // The pending "Strikes" pseudo-phase is consumed (marker cleared)...
      expect(state.haymakerDeclarations, isEmpty);
      final subject = state.combatants.single;
      expect(subject.statusBadges, contains(PhaseStatus.aborted));
      // ...and no downstream scheduled phase is double-aborted.
      expect(subject.phaseSlots.single.status, PhaseStatus.scheduled);
    });
  });

  group('status phase mechanics', () {
    test('stepping past the [CLR STUN] phase clears the stun and consumes '
        'the action', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [
              makeSlot(segment: 5),
              makeSlot(segment: 9),
            ]).copyWith(status: CombatantStatus.stunned),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      // Stepping up to Segment 5 does not clear: the phase is not passed.
      notifier.nextStep();
      notifier.nextStep();
      var subject = container.read(turnEngineProvider).combatants.single;
      expect(subject.status, CombatantStatus.stunned);

      // Stepping 5 → 6 walks past the [CLR STUN] phase: consumed + cleared.
      notifier.nextStep();
      subject = container.read(turnEngineProvider).combatants.single;
      expect(subject.status, CombatantStatus.normal);
      expect(subject.phaseSlots.first.status, PhaseStatus.spent);
      expect(subject.phaseSlots.last.status, PhaseStatus.scheduled);
    });

    test('selectNextPhaseSlot clears the stun when the walk passes the '
        'phase', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'x',
          combatants: [
            makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 3)]),
            makeCombatant(id: 'st', phaseSlots: [
              makeSlot(segment: 5),
              makeSlot(segment: 9),
            ]).copyWith(status: CombatantStatus.stunned),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      Combatant subjectOf() => container
          .read(turnEngineProvider)
          .combatants
          .firstWhere((combatant) => combatant.id == 'st');

      // Lands ON the [CLR STUN] phase: no clearing yet.
      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeSegment, 5);
      expect(subjectOf().status, CombatantStatus.stunned);

      // Moving on steps past it.
      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(subjectOf().status, CombatantStatus.normal);
      expect(subjectOf().phaseSlots.first.status, PhaseStatus.spent);
    });

    test('a turn wrap closes any remaining [CLR STUN] window', () {
      final container = makeContainer(
        makeTurnState(
          turnNumber: 2,
          activeSegment: 12,
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 12)])
                .copyWith(status: CombatantStatus.stunned),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.startNextTurn();

      expect(
        container.read(turnEngineProvider).combatants.single.status,
        CombatantStatus.normal,
      );
    });

    test('DEAD clears phase slots; restoring repopulates the Speed Chart', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 3, combatants: [
          makeCombatant(
            id: 'c1',
            spd: 3,
            phaseSlots: [makeSlot(segment: 4), makeSlot(segment: 8)],
          ),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.setCombatantStatus('c1', CombatantStatus.dead);
      expect(
        container.read(turnEngineProvider).combatants.single.phaseSlots,
        isEmpty,
      );

      notifier.setCombatantStatus('c1', CombatantStatus.knockedOut);
      final slots =
          container.read(turnEngineProvider).combatants.single.phaseSlots;
      expect(slots.map((slot) => slot.segment), [4, 8, 12]);
    });
  });

  group('post-12 backing off', () {
    test('selectPreviousPhaseSlot clears the Post-12 selection and lands '
        'on the Turn\'s last phase', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 12, activeCombatantId: 'x', combatants: [
          makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 12)]),
          makeCombatant(id: 'w', phaseSlots: [makeSlot(segment: 1)]),
        ]),
      );
      container.read(selectedColumnProvider.notifier).state = 'post12';
      final notifier = container.read(turnEngineProvider.notifier);

      expect(notifier.selectPreviousPhaseSlot(), isTrue);

      // The Post-12 state is fully disengaged and focus sits on the tail
      // of the Segment 12 queue.
      expect(container.read(selectedColumnProvider), isNull);
      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 12);
      expect(state.activeCombatantId, 'x');

      // Subsequent Next Phase presses walk the timeline again instead of
      // sitting on Post-12: here the exhausted walk reports false (the
      // caller stages Post-12 again) and never wraps the Turn by itself.
      expect(notifier.selectNextPhaseSlot(), isFalse);
      expect(container.read(turnEngineProvider).turnNumber, 1);
    });
  });
}