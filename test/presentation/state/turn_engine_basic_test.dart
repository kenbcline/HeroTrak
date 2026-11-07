import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/actions/actions.dart';
import 'package:herotrak/domain/models/models.dart';
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
  bool isTargeted = false,
  bool isNpc = false,
  List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
  List<PhaseStatus> statusBadges = const <PhaseStatus>[],
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
    isTargeted: isTargeted,
    isNpc: isNpc,
    phaseSlots: phaseSlots,
    statusBadges: statusBadges,
  );
}

TurnState makeTurnState({
  int turnNumber = 1,
  int activeSegment = 6,
  String? activeCombatantId,
  String? targetCombatantId,
  List<Combatant> combatants = const <Combatant>[],
  List<HaymakerDeclaration> haymakerDeclarations =
      const <HaymakerDeclaration>[],
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

/// Creates a [ProviderContainer] with the engine seeded from [initial],
/// torn down automatically at the end of the test.
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

void main() {
  group('initial state', () {
    test('starts at turn 1, segment 1 with no combatants or selections', () {
      final container = makeContainer();
      final state = container.read(turnEngineProvider);

      expect(state.turnNumber, 1);
      expect(state.activeSegment, 1);
      expect(state.combatants, isEmpty);
      expect(state.activeCombatantId, isNull);
      expect(state.targetCombatantId, isNull);
    });

    test('exposes an empty segment queue when nobody is scheduled', () {
      final container = makeContainer();
      final notifier = container.read(turnEngineProvider.notifier);

      expect(notifier.activeSegmentQueue, isEmpty);
    });
  });

  group('activeSegmentQueue sorting', () {
    test('queues only combatants with a phase in the active segment', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'here', phaseSlots: [makeSlot(segment: 6)]),
          makeCombatant(id: 'elsewhere', phaseSlots: [makeSlot(segment: 3)]),
        ]),
      );

      final queue =
          container.read(turnEngineProvider.notifier).activeSegmentQueue;

      expect(queue.map((entry) => entry.combatant.id), ['here']);
    });

    test('held interruptions come first regardless of DEX and EGO', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(
            id: 'fast-physical',
            dex: 30,
            ego: 30,
            phaseSlots: [makeSlot(segment: 6)],
          ),
          makeCombatant(
            id: 'held-slow',
            dex: 5,
            ego: 5,
            phaseSlots: [makeSlot(segment: 6, status: PhaseStatus.held)],
          ),
        ]),
      );

      final queue =
          container.read(turnEngineProvider.notifier).activeSegmentQueue;

      expect(
        queue.map((entry) => entry.combatant.id),
        ['held-slow', 'fast-physical'],
      );
      expect(queue.first.isHeldInterruption, isTrue);
    });

    test('mental actions precede physical actions and sort by EGO descending',
        () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(
            id: 'physical',
            dex: 30,
            ego: 30,
            phaseSlots: [makeSlot(segment: 6)],
          ),
          makeCombatant(
            id: 'mental-low',
            dex: 30,
            ego: 12,
            phaseSlots: [makeSlot(segment: 6, isMental: true)],
          ),
          makeCombatant(
            id: 'mental-high',
            dex: 5,
            ego: 23,
            phaseSlots: [makeSlot(segment: 6, isMental: true)],
          ),
        ]),
      );

      final queue =
          container.read(turnEngineProvider.notifier).activeSegmentQueue;

      expect(
        queue.map((entry) => entry.combatant.id),
        ['mental-high', 'mental-low', 'physical'],
      );
      expect(queue.first.isMentalAction, isTrue);
    });

    test('physical actions sort by DEX descending', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'slow', dex: 11, phaseSlots: [makeSlot(segment: 6)]),
          makeCombatant(id: 'fast', dex: 25, phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );

      final queue =
          container.read(turnEngineProvider.notifier).activeSegmentQueue;

      expect(queue.map((entry) => entry.combatant.id), ['fast', 'slow']);
    });

    test('applies the full ordering: held, mental, physical', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(
            id: 'physical-slow',
            dex: 11,
            phaseSlots: [makeSlot(segment: 6)],
          ),
          makeCombatant(
            id: 'mental-mid',
            dex: 20,
            ego: 15,
            phaseSlots: [makeSlot(segment: 6, isMental: true)],
          ),
          makeCombatant(
            id: 'held',
            dex: 8,
            ego: 8,
            phaseSlots: [makeSlot(segment: 6, status: PhaseStatus.held)],
          ),
          makeCombatant(
            id: 'physical-fast',
            dex: 23,
            phaseSlots: [makeSlot(segment: 6)],
          ),
          makeCombatant(
            id: 'mental-high',
            dex: 12,
            ego: 20,
            phaseSlots: [makeSlot(segment: 6, isMental: true)],
          ),
          makeCombatant(
            id: 'held-second',
            dex: 14,
            phaseSlots: [makeSlot(segment: 6, status: PhaseStatus.held)],
          ),
        ]),
      );

      final queue =
          container.read(turnEngineProvider.notifier).activeSegmentQueue;

      expect(queue.map((entry) => entry.combatant.id), [
        'held-second', // held, DEX 14
        'held', // held, DEX 8
        'mental-high', // mental, EGO 20
        'mental-mid', // mental, EGO 15
        'physical-fast', // physical, DEX 23
        'physical-slow', // physical, DEX 11
      ]);
    });

    test('exposes the queued combatant and phase slot on each entry', () {
      final combatant = makeCombatant(
        id: 'c1',
        phaseSlots: [makeSlot(segment: 6, isMental: true)],
      );
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [combatant]),
      );

      final entry =
          container.read(turnEngineProvider.notifier).activeSegmentQueue.single;

      expect(entry.combatant, combatant);
      expect(entry.phaseSlot, combatant.phaseSlots.single);
    });
  });

  group('nextStep', () {
    test('advances the active segment by one', () {
      final container = makeContainer(makeTurnState(activeSegment: 1));
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.nextStep();

      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 2);
      expect(state.turnNumber, 1);
    });

    test('wraps past segment 12 to segment 1 of the next turn', () {
      final container = makeContainer(
        makeTurnState(turnNumber: 3, activeSegment: 12),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.nextStep();

      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 1);
      expect(state.turnNumber, 4);
    });

    test('wrapping into a new turn clears transient per-turn state', () {
      final container = makeContainer(
        makeTurnState(
          turnNumber: 1,
          activeSegment: 12,
          activeCombatantId: 'c1',
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 5,
              declaredTurn: 1,
            ),
          ],
          combatants: [
          makeCombatant(
            id: 'c1',
            dex: 18,
            ego: 10,
            spd: 5,
            isNpc: true,
            statusBadges: [PhaseStatus.held, PhaseStatus.aborted],
            phaseSlots: [
              makeSlot(segment: 3, status: PhaseStatus.spent),
              makeSlot(segment: 5, status: PhaseStatus.held),
              makeSlot(
                segment: 8,
                originalSegment: 5,
                status: PhaseStatus.delayed,
                isMental: true,
                actionId: 'declare_haymaker',
                actionLabel: 'Declare Haymaker',
              ),
            ],
          ),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.nextStep();

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 2);
      expect(state.activeSegment, 1);
      final combatant = state.combatants.single;

      // Transient per-turn state is cleared: slot statuses (including the
      // unspent expired `held` interruption) return to scheduled, temporary
      // action flags are removed, and condition badges are dropped.
      expect(
        combatant.phaseSlots.map((slot) => slot.status),
        everyElement(PhaseStatus.scheduled),
      );
      expect(
        combatant.phaseSlots.map((slot) => slot.actionId),
        everyElement(isNull),
      );
      expect(
        combatant.phaseSlots.map((slot) => slot.actionLabel),
        everyElement(isNull),
      );
      expect(combatant.statusBadges, isEmpty);
      // Stale "Strikes/Resolves" markers expire with the turn.
      expect(state.haymakerDeclarations, isEmpty);

      // Persistent configuration stays intact: base stats, flags, custom
      // slot segments (incl. relocation) and mental flags.
      expect(combatant.dex, 18);
      expect(combatant.spd, 5);
      expect(combatant.isNpc, isTrue);
      expect(
        combatant.phaseSlots.map((slot) => slot.segment),
        [3, 5, 8],
      );
      expect(combatant.phaseSlots[2].originalSegment, 5);
      expect(combatant.phaseSlots[2].isMental, isTrue);
      expect(state.activeCombatantId, 'c1');
    });

    test('a deferred segment-12 haymaker survives into the next turn', () {
      final container = makeContainer(
        makeTurnState(
          turnNumber: 4,
          activeSegment: 12,
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 12,
              declaredTurn: 4,
            ),
          ],
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 12)]),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.nextStep();

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 5);
      final declaration = state.haymakerDeclarations.single;
      expect(declaration.declaredSegment, 12);
      expect(declaration.resolutionSegment, 1);
      // The "Strikes" marker is due in the new Turn...
      expect(declaration.resolutionTurn, 5);
      expect(declaration.resolutionTurn, state.turnNumber);
    });

    test('a stale deferred haymaker from an earlier turn is cleared', () {
      final container = makeContainer(
        makeTurnState(
          turnNumber: 5,
          activeSegment: 12,
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 12,
              declaredTurn: 3,
            ),
          ],
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 12)]),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.nextStep();

      expect(container.read(turnEngineProvider).haymakerDeclarations, isEmpty);
    });

    test('the smart reset only fires on the turn wrap', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 6, status: PhaseStatus.held, actionId: 'a1'),
          ]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.nextStep();

      final slot =
          container.read(turnEngineProvider).combatants.single.phaseSlots.single;
      // Stepping within the Turn must not touch per-turn state.
      expect(slot.status, PhaseStatus.held);
      expect(slot.actionId, 'a1');
    });
  });

  group('previousStep', () {
    test('steps the active segment back by one', () {
      final container = makeContainer(makeTurnState(activeSegment: 7));
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.previousStep();

      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 6);
      expect(state.turnNumber, 1);
    });

    test('wraps at segment 1 to segment 12 of the previous turn', () {
      final container = makeContainer(
        makeTurnState(turnNumber: 2, activeSegment: 1),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.previousStep();

      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 12);
      expect(state.turnNumber, 1);
    });

    test('is a no-op at turn 1, segment 1', () {
      final container = makeContainer(makeTurnState(activeSegment: 1));
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.previousStep();

      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 1);
      expect(state.turnNumber, 1);
    });
  });

  group('setActiveSegment', () {
    test('jumps to any segment without changing the turn', () {
      final container = makeContainer(
        makeTurnState(turnNumber: 3, activeSegment: 5),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.setActiveSegment(12);
      expect(container.read(turnEngineProvider).activeSegment, 12);
      expect(container.read(turnEngineProvider).turnNumber, 3);

      // Jumping backward never wraps into another turn.
      notifier.setActiveSegment(1);
      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 1);
      expect(state.turnNumber, 3);
    });

    test('rejects segments outside 1-12', () {
      final container = makeContainer(makeTurnState(activeSegment: 5));
      final notifier = container.read(turnEngineProvider.notifier);

      expect(() => notifier.setActiveSegment(0), throwsArgumentError);
      expect(() => notifier.setActiveSegment(13), throwsArgumentError);
    });
  });

  group('target selection cycling', () {
    test('selectNextTarget cycles the target cursor in order and wraps', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1'),
          makeCombatant(id: 'c2'),
          makeCombatant(id: 'c3'),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.selectNextTarget();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c1');
      notifier.selectNextTarget();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c2');
      notifier.selectNextTarget();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c3');
      notifier.selectNextTarget(); // wrap
      expect(container.read(turnEngineProvider).targetCombatantId, 'c1');
    });

    test('selectPreviousTarget cycles the target cursor backward and wraps',
        () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1'),
          makeCombatant(id: 'c2'),
          makeCombatant(id: 'c3'),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.selectPreviousTarget(); // no target -> last row
      expect(container.read(turnEngineProvider).targetCombatantId, 'c3');
      notifier.selectPreviousTarget();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c2');
      notifier.selectPreviousTarget();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c1');
      notifier.selectPreviousTarget(); // wrap
      expect(container.read(turnEngineProvider).targetCombatantId, 'c3');
    });

    test('target cycling never touches the turn clock, the actor, or phase '
        'state', () {
      final container = makeContainer(
        makeTurnState(
          turnNumber: 3,
          activeSegment: 6,
          activeCombatantId: 'c2',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [
              makeSlot(segment: 9, status: PhaseStatus.held),
            ]),
            makeCombatant(id: 'c2', phaseSlots: [makeSlot(segment: 8)])
                .copyWith(status: CombatantStatus.stunned),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.selectNextTarget();

      final state = container.read(turnEngineProvider);
      expect(state.targetCombatantId, 'c1');
      // Pure selection: the timeline clock, the actor, and all phase state
      // are untouched — no auto-recovery or phase-clear side effects.
      expect(state.activeCombatantId, 'c2');
      expect(state.activeSegment, 6);
      expect(state.turnNumber, 3);
      final stunned = state.combatants
          .firstWhere((combatant) => combatant.id == 'c2');
      expect(stunned.status, CombatantStatus.stunned);
      expect(stunned.phaseSlots.single.status, PhaseStatus.scheduled);
      expect(
        state.combatants
            .firstWhere((combatant) => combatant.id == 'c1')
            .phaseSlots
            .single
            .status,
        PhaseStatus.held,
      );
    });

    test('target cycling keeps the actor selection and no-ops without '
        'combatants', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 6,
          activeCombatantId: 'c2',
          combatants: [makeCombatant(id: 'c1'), makeCombatant(id: 'c2')],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.selectNextTarget();

      final state = container.read(turnEngineProvider);
      expect(state.targetCombatantId, 'c1');
      expect(state.activeCombatantId, 'c2');

      final empty = makeContainer(makeTurnState(activeSegment: 6));
      final emptyNotifier = empty.read(turnEngineProvider.notifier);
      emptyNotifier
        ..selectNextTarget()
        ..selectPreviousTarget();
      expect(empty.read(turnEngineProvider).targetCombatantId, isNull);
    });
  });

  group('transient tag expiry', () {
    test('reaching their next phase expires the combatant\'s condition '
        'badges', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [
              makeSlot(segment: 3),
              makeSlot(segment: 8),
            ]).copyWith(statusBadges: [
              PhaseStatus.held,
              PhaseStatus.aborted,
            ]),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      // Stale tags persist while the walk has not reached their next phase.
      expect(
        container.read(turnEngineProvider).combatants.single.statusBadges,
        hasLength(2),
      );

      expect(notifier.selectNextPhaseSlot(), isTrue); // lands on (8, c1)

      // The previous action's tags expire as the new phase begins.
      expect(
        container.read(turnEngineProvider).combatants.single.statusBadges,
        isEmpty,
      );
    });

    test('haymaker wind-ups expire once their resolution is behind the walk',
        () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'x',
          haymakerDeclarations: [
            // Strikes Segment 6 of this Turn.
            HaymakerDeclaration.at(
              combatantId: 'x',
              segment: 5,
              declaredTurn: 1,
            ),
          ],
          combatants: [
            makeCombatant(id: 'x', phaseSlots: [
              makeSlot(segment: 3),
              makeSlot(segment: 9),
            ]),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      // Landing ON the strike pseudo-phase keeps the marker pending.
      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeSegment, 6);
      expect(
        container.read(turnEngineProvider).haymakerDeclarations,
        hasLength(1),
      );

      // Stepping past the resolution expires the wind-up and its markers.
      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeSegment, 9);
      expect(
        container.read(turnEngineProvider).haymakerDeclarations,
        isEmpty,
      );
    });

    test('segment stepping expires wind-ups whose segment has concluded', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 5,
          activeCombatantId: 'x',
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'x',
              segment: 5,
              declaredTurn: 1,
            ),
          ],
          combatants: [
            makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 9)]),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.nextStep(); // 5 -> 6: the strike is due here, kept.
      expect(
        container.read(turnEngineProvider).haymakerDeclarations,
        hasLength(1),
      );

      notifier.nextStep(); // 6 -> 7: the segment concluded, expired.
      expect(
        container.read(turnEngineProvider).haymakerDeclarations,
        isEmpty,
      );
    });
  });

  group('spd delta scheduling', () {
    test('effectiveSpd clamps the base SPD with its temporary delta', () {
      final combatant = makeCombatant(id: 'c1', spd: 5);
      expect(combatant.effectiveSpd, 5);
      expect(combatant.copyWith(spdDelta: 2).effectiveSpd, 7);
      expect(combatant.copyWith(spdDelta: -99).effectiveSpd, 1);
      expect(combatant.copyWith(spdDelta: 99).effectiveSpd, 12);
    });

    test('spdDisplay shows the delta only when non-zero', () {
      final combatant = makeCombatant(id: 'c1', spd: 4);
      expect(combatant.spdDisplay, '4');
      expect(combatant.copyWith(spdDelta: 1).spdDisplay, '4 (+1)');
      expect(combatant.copyWith(spdDelta: -1).spdDisplay, '4 (-1)');
    });

    test('adjustSpdDelta re-schedules future segments without altering past '
        'ones', () {
      // spd 3 (chart 4, 8, 12) at Segment 5 with one consumed past slot.
      final container = makeContainer(
        makeTurnState(activeSegment: 5, combatants: [
          makeCombatant(id: 'c1', spd: 3, phaseSlots: [
            makeSlot(segment: 4, status: PhaseStatus.spent),
            makeSlot(segment: 8),
            makeSlot(segment: 12),
          ]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.adjustSpdDelta('c1', 1); // effective SPD 4 -> chart 3, 6, 9, 12

      final combatant = container.read(turnEngineProvider).combatants.single;
      expect(combatant.spdDelta, 1);
      expect(combatant.effectiveSpd, 4);
      // Past segments are untouched, consumed state included...
      expect(combatant.phaseSlots.first.segment, 4);
      expect(combatant.phaseSlots.first.status, PhaseStatus.spent);
      // ...and the upcoming phases follow the new Speed Chart.
      expect(
        combatant.phaseSlots
            .where((slot) => slot.segment > 5)
            .map((slot) => slot.segment),
        [6, 9, 12],
      );
      expect(
        combatant.phaseSlots
            .where((slot) => slot.segment > 5)
            .map((slot) => slot.status),
        everyElement(PhaseStatus.scheduled),
      );
    });

    test('clearReaction resets spdDelta and clears the Aborted badge', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 5, combatants: [
          makeCombatant(id: 'c1', spd: 3, phaseSlots: [
            makeSlot(segment: 8),
            makeSlot(segment: 12),
          ])
              .copyWith(spdDelta: 2)
              .copyWith(statusBadges: [PhaseStatus.aborted]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.clearReaction('c1');

      final combatant = container.read(turnEngineProvider).combatants.single;
      expect(combatant.spdDelta, 0);
      expect(combatant.effectiveSpd, 3);
      expect(combatant.statusBadges, isNot(contains(PhaseStatus.aborted)));
      // The upcoming schedule returns to the base SPD chart (8, 12).
      expect(
        combatant.phaseSlots
            .where((slot) => slot.segment > 5)
            .map((slot) => slot.segment),
        [8, 12],
      );
    });
  });

  group('timeline traversal', () {
    /// Timeline layout: two phases at Segment 3 (physical by DEX: fast 30,
    /// then slow 10), Segments 4–7 empty, two phases at Segment 8 (mental
    /// EGO 20 first, then physical DEX 50).
    List<Combatant> timelineCombatants() => [
          makeCombatant(
            id: 'fast',
            dex: 30,
            phaseSlots: [makeSlot(segment: 3)],
          ),
          makeCombatant(
            id: 'slow',
            dex: 10,
            phaseSlots: [makeSlot(segment: 3)],
          ),
          makeCombatant(
            id: 'mental',
            dex: 5,
            ego: 20,
            phaseSlots: [makeSlot(segment: 8, isMental: true)],
          ),
          makeCombatant(
            id: 'eager',
            dex: 50,
            phaseSlots: [makeSlot(segment: 8)],
          ),
        ];

    test('selectNextPhaseSlot walks the timeline forward, skipping empty '
        'segments', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'fast',
          combatants: timelineCombatants(),
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      // Look ahead in the active segment's queue first.
      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeCombatantId, 'slow');

      // Segments 4-7 are empty: jump to Segment 8's first phase (mental
      // sorts ahead of physical), moving the highlight and the row.
      expect(notifier.selectNextPhaseSlot(), isTrue);
      var state = container.read(turnEngineProvider);
      expect(state.activeSegment, 8);
      expect(state.activeCombatantId, 'mental');

      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeCombatantId, 'eager');

      // Nothing remains after Segment 8: the Turn's timeline is exhausted.
      final before = container.read(turnEngineProvider);
      expect(notifier.selectNextPhaseSlot(), isFalse);
      expect(container.read(turnEngineProvider), before);
    });

    test('selectNextPhaseSlot resumes at the first queued phase when '
        'nothing is selected', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 3, combatants: timelineCombatants()),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeCombatantId, 'fast');
    });

    test('selectPreviousPhaseSlot walks backward, landing on the last '
        'phase of earlier segments', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 8,
          activeCombatantId: 'eager',
          combatants: timelineCombatants(),
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(notifier.selectPreviousPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeCombatantId, 'mental');

      // Jump back over empty Segments 4-7 to Segment 3's last phase.
      expect(notifier.selectPreviousPhaseSlot(), isTrue);
      final jumped = container.read(turnEngineProvider);
      expect(jumped.activeSegment, 3);
      expect(jumped.activeCombatantId, 'slow');

      expect(notifier.selectPreviousPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeCombatantId, 'fast');

      // Start of the Turn: a no-op.
      final before = container.read(turnEngineProvider);
      expect(notifier.selectPreviousPhaseSlot(), isFalse);
      expect(container.read(turnEngineProvider), before);
    });

    test('consumed phases are skipped', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'done',
          combatants: [
            makeCombatant(
              id: 'done',
              phaseSlots: [makeSlot(segment: 3, status: PhaseStatus.spent)],
            ),
            makeCombatant(
              id: 'aborted',
              phaseSlots: [makeSlot(segment: 8, status: PhaseStatus.aborted)],
            ),
            makeCombatant(
              id: 'live',
              phaseSlots: [makeSlot(segment: 8)],
            ),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(notifier.selectNextPhaseSlot(), isTrue);
      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 8);
      expect(state.activeCombatantId, 'live');
    });

    test('pending held interruptions come first in the active segment', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 6,
          combatants: [
            makeCombatant(
              id: 'holder',
              dex: 5,
              phaseSlots: [makeSlot(segment: 3, status: PhaseStatus.held)],
            ),
            makeCombatant(
              id: 'sluggish',
              dex: 30,
              phaseSlots: [makeSlot(segment: 6)],
            ),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeCombatantId, 'holder');
      expect(notifier.selectNextPhaseSlot(), isTrue);
      expect(container.read(turnEngineProvider).activeCombatantId, 'sluggish');
    });

    test('startNextTurn wraps to the next Turn at Segment 1 and selects its '
        'first phase', () {
      final container = makeContainer(
        makeTurnState(turnNumber: 1, activeSegment: 8, combatants: [
          makeCombatant(
            id: 'late',
            phaseSlots: [makeSlot(segment: 8, status: PhaseStatus.held)],
          ),
          makeCombatant(
            id: 'early',
            phaseSlots: [makeSlot(segment: 1)],
          ),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.startNextTurn();

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 2);
      expect(state.activeSegment, 1);
      expect(state.activeCombatantId, 'early');
      // The smart turn reset still applies.
      expect(
        state.combatants.first.phaseSlots.single.status,
        PhaseStatus.scheduled,
      );
    });

    test('startNextTurn keeps the selection when Segment 1 has no phases',
        () {
      final container = makeContainer(
        makeTurnState(
          turnNumber: 1,
          activeSegment: 8,
          activeCombatantId: 'late',
          combatants: [
            makeCombatant(id: 'late', phaseSlots: [makeSlot(segment: 8)]),
          ],
        ),
      );

      container.read(turnEngineProvider.notifier).startNextTurn();

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 2);
      expect(state.activeSegment, 1);
      expect(state.activeCombatantId, 'late');
    });
  });

  group('setActiveCombatant / setTargetCombatant', () {
    test('sets the active combatant id', () {
      final container = makeContainer();
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.setActiveCombatant('c1');

      expect(container.read(turnEngineProvider).activeCombatantId, 'c1');
    });

    test('sets the target combatant id', () {
      final container = makeContainer();
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.setTargetCombatant('c2');

      expect(container.read(turnEngineProvider).targetCombatantId, 'c2');
    });

    test('passing null clears the selections', () {
      final container = makeContainer(
        makeTurnState(activeCombatantId: 'c1', targetCombatantId: 'c2'),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier
        ..setActiveCombatant(null)
        ..setTargetCombatant(null);

      final state = container.read(turnEngineProvider);
      expect(state.activeCombatantId, isNull);
      expect(state.targetCombatantId, isNull);
    });
  });

  group('addCombatant', () {
    test('appends a combatant with 6e Speed Chart phase slots', () {
      final container = makeContainer(makeTurnState(activeSegment: 6));
      final notifier = container.read(turnEngineProvider.notifier);

      final id = notifier.addCombatant(
        name: 'Hero One',
        dex: 18,
        ego: 12,
        spd: 3,
        stun: 40,
        end: 20,
        body: 10,
      );

      final state = container.read(turnEngineProvider);
      expect(state.combatants, hasLength(1));
      final added = state.combatants.single;
      expect(added.id, id);
      expect(added.name, 'Hero One');
      expect(added.dex, 18);
      expect(added.ego, 12);
      expect(added.spd, 3);
      expect(added.stun, 40);
      expect(added.end, 20);
      expect(added.body, 10);
      expect(added.isNpc, isFalse);
      expect(added.statusBadges, isEmpty);
      // SPD 3 acts on segments 4, 8, 12 per the standard 6e Speed Chart.
      expect(
        added.phaseSlots.map((slot) => slot.segment),
        [4, 8, 12],
      );
      expect(
        added.phaseSlots.map((slot) => slot.status),
        everyElement(PhaseStatus.scheduled),
      );
    });

    test('spd 12 generates a phase on every segment', () {
      final container = makeContainer(makeTurnState(activeSegment: 6));
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.addCombatant(
        name: 'Speedy',
        dex: 20,
        ego: 10,
        spd: 12,
        stun: 1,
        end: 1,
        body: 1,
      );

      final slots = container.read(turnEngineProvider).combatants.single.phaseSlots;
      expect(
        slots.map((slot) => slot.segment),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      );
    });

    test('spd 1 schedules its only phase on segment 7, never segment 12', () {
      final container = makeContainer(makeTurnState(activeSegment: 6));
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.addCombatant(
        name: 'Slowpoke',
        dex: 10,
        ego: 10,
        spd: 1,
        stun: 1,
        end: 1,
        body: 1,
      );

      final slots =
          container.read(turnEngineProvider).combatants.single.phaseSlots;
      expect(slots.map((slot) => slot.segment), [7]);
      expect(slots.map((slot) => slot.segment), isNot(contains(12)));
    });

    test('generates unique ids and trims the name', () {
      final container = makeContainer(makeTurnState(activeSegment: 6));
      final notifier = container.read(turnEngineProvider.notifier);

      final first = notifier.addCombatant(
        name: '  Hero One  ',
        dex: 10,
        ego: 10,
        spd: 1,
        stun: 0,
        end: 0,
        body: 0,
      );
      final second = notifier.addCombatant(
        name: 'Goblin',
        dex: 10,
        ego: 10,
        spd: 1,
        stun: 0,
        end: 0,
        body: 0,
        isNpc: true,
      );

      expect(first, isNot(second));
      final combatants = container.read(turnEngineProvider).combatants;
      // Equal initiative stats sort by name ascending.
      expect(combatants[0].name, 'Goblin');
      expect(combatants[0].isNpc, isTrue);
      expect(combatants[1].name, 'Hero One');
    });

    test('keeps existing combatants and selections untouched', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);
      final before = container.read(turnEngineProvider);

      notifier.addCombatant(
        name: 'Goblin',
        dex: 11,
        ego: 8,
        spd: 2,
        stun: 20,
        end: 10,
        body: 6,
      );

      final after = container.read(turnEngineProvider);
      expect(after.combatants, hasLength(2));
      expect(after.combatants.first, before.combatants.single);
      expect(after.activeCombatantId, 'c1');
      expect(after.activeSegment, 6);
    });

    test('rejects a blank name, out-of-range spd, and duplicate ids', () {
      final container = makeContainer(makeTurnState(activeSegment: 6));
      final notifier = container.read(turnEngineProvider.notifier);

      expect(
        () => notifier.addCombatant(
          name: '   ',
          dex: 10,
          ego: 10,
          spd: 3,
          stun: 0,
          end: 0,
          body: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => notifier.addCombatant(
          name: 'Too Fast',
          dex: 10,
          ego: 10,
          spd: 13,
          stun: 0,
          end: 0,
          body: 0,
        ),
        throwsArgumentError,
      );

      notifier.addCombatant(
        name: 'Hero One',
        dex: 10,
        ego: 10,
        spd: 3,
        stun: 0,
        end: 0,
        body: 0,
        id: 'custom-id',
      );
      expect(
        () => notifier.addCombatant(
          name: 'Impostor',
          dex: 10,
          ego: 10,
          spd: 3,
          stun: 0,
          end: 0,
          body: 0,
          id: 'custom-id',
        ),
        throwsArgumentError,
      );
      // Failed adds leave the state untouched.
      expect(container.read(turnEngineProvider).combatants, hasLength(1));
    });
  });

  group('initiative ordering', () {
    test('addCombatant inserts combatants in initiative order', () {
      final container = makeContainer(makeTurnState(activeSegment: 6));
      final notifier = container.read(turnEngineProvider.notifier);

      notifier
        ..addCombatant(
          name: 'Slow',
          dex: 10,
          ego: 10,
          spd: 2,
          stun: 1,
          end: 1,
          body: 1,
        )
        ..addCombatant(
          name: 'Quick',
          dex: 12,
          ego: 10,
          spd: 8,
          stun: 1,
          end: 1,
          body: 1,
        )
        ..addCombatant(
          name: 'Middle',
          dex: 20,
          ego: 10,
          spd: 4,
          stun: 1,
          end: 1,
          body: 1,
        );

      expect(
        container.read(turnEngineProvider).combatants.map((c) => c.name),
        ['Quick', 'Middle', 'Slow'],
      );
    });

    test('loadEncounter sorts the incoming combatants', () {
      final container = makeContainer(makeTurnState(activeSegment: 6));
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.loadEncounter(
        makeTurnState(combatants: [
          makeCombatant(id: 'slow', name: 'Slow', dex: 10, spd: 2),
          makeCombatant(id: 'quick', name: 'Quick', dex: 12, spd: 8),
        ]),
      );

      expect(
        container.read(turnEngineProvider).combatants.map((c) => c.id),
        ['quick', 'slow'],
      );
    });

    test('status changes keep the list in initiative order', () {
      final container = makeContainer(
        makeTurnState(
          activeSegment: 6,
          activeCombatantId: 'quick',
          combatants: [
            makeCombatant(id: 'slow', name: 'Slow', dex: 10, spd: 2),
            makeCombatant(
              id: 'quick',
              name: 'Quick',
              dex: 12,
              spd: 8,
              phaseSlots: [makeSlot(segment: 6)],
            ),
          ],
        ),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      notifier.executeAction(ActionDefinition.interruptWithHold);

      expect(
        container.read(turnEngineProvider).combatants.map((c) => c.id),
        ['quick', 'slow'],
      );
    });
  });

  group('loadEncounter', () {
    test('replaces the encounter state wholesale', () {
      final container = makeContainer(
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'old1'),
        ]),
      );
      final notifier = container.read(turnEngineProvider.notifier);

      final imported = makeTurnState(
        turnNumber: 4,
        activeSegment: 9,
        activeCombatantId: 'c9',
        combatants: [makeCombatant(id: 'c9', name: 'Imported Hero')],
      );
      notifier.loadEncounter(imported);

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 4);
      expect(state.activeSegment, 9);
      expect(state.activeCombatantId, 'c9');
      expect(state.combatants.single.id, 'c9');
    });
  });
}