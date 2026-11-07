import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';

/// Builds a [PhaseSlot] through runtime parameters so constructor asserts are
/// exercised at runtime (a failing assert in a `const` invocation would be a
/// compile-time error instead).
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
}) {
  return TurnState(
    turnNumber: turnNumber,
    activeSegment: activeSegment,
    activeCombatantId: activeCombatantId,
    targetCombatantId: targetCombatantId,
    combatants: combatants,
  );
}

void main() {
  group('PhaseStatus', () {
    test('exposes exactly the six 6e phase statuses', () {
      expect(PhaseStatus.values, [
        PhaseStatus.scheduled,
        PhaseStatus.active,
        PhaseStatus.held,
        PhaseStatus.aborted,
        PhaseStatus.spent,
        PhaseStatus.delayed,
      ]);
    });
  });

  group('PhaseSlot', () {
    group('initialization', () {
      test('defaults status to scheduled and action metadata to null', () {
        final slot = makeSlot(segment: 6);
        expect(slot.segment, 6);
        expect(slot.status, PhaseStatus.scheduled);
        expect(slot.actionId, isNull);
        expect(slot.actionLabel, isNull);
      });

      test('defaults originalSegment to segment', () {
        expect(makeSlot(segment: 3).originalSegment, 3);
      });

      test('preserves an explicit originalSegment', () {
        final slot = makeSlot(segment: 8, originalSegment: 3);
        expect(slot.segment, 8);
        expect(slot.originalSegment, 3);
      });

      test('carries action metadata', () {
        final slot = makeSlot(
          segment: 12,
          actionId: 'declare_haymaker',
          actionLabel: 'Declare Haymaker',
        );
        expect(slot.actionId, 'declare_haymaker');
        expect(slot.actionLabel, 'Declare Haymaker');
      });

      test('defaults isMental to false', () {
        expect(makeSlot(segment: 6).isMental, isFalse);
      });

      test('carries an explicit isMental flag', () {
        expect(makeSlot(segment: 6, isMental: true).isMental, isTrue);
      });

      test('asserts on segment outside 1-12', () {
        expect(() => makeSlot(segment: 0), throwsA(isA<AssertionError>()));
        expect(() => makeSlot(segment: 13), throwsA(isA<AssertionError>()));
      });

      test('asserts on originalSegment outside 1-12', () {
        expect(
          () => makeSlot(segment: 6, originalSegment: 0),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => makeSlot(segment: 6, originalSegment: 13),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('copyWith', () {
      test('changes only the provided fields', () {
        final slot = makeSlot(
          segment: 6,
          originalSegment: 4,
          actionId: 'a1',
          actionLabel: 'Label',
        );
        final updated = slot.copyWith(status: PhaseStatus.spent);

        expect(updated.status, PhaseStatus.spent);
        expect(updated.segment, 6);
        expect(updated.originalSegment, 4);
        expect(updated.actionId, 'a1');
        expect(updated.actionLabel, 'Label');
      });

      test('relocating the segment keeps the originalSegment', () {
        final updated = makeSlot(segment: 4).copyWith(segment: 10);
        expect(updated.segment, 10);
        expect(updated.originalSegment, 4);
      });

      test('sets action metadata', () {
        final updated = makeSlot().copyWith(
          actionId: 'interrupt_with_hold',
          actionLabel: 'Interrupt with Hold',
        );
        expect(updated.actionId, 'interrupt_with_hold');
        expect(updated.actionLabel, 'Interrupt with Hold');
      });

      test('sets isMental without touching other fields', () {
        final slot = makeSlot(segment: 6, actionId: 'a1');
        final updated = slot.copyWith(isMental: true);
        expect(updated.isMental, isTrue);
        expect(updated.segment, 6);
        expect(updated.actionId, 'a1');
      });

      test('clears action metadata when null is passed explicitly', () {
        final slot = makeSlot(actionId: 'a1', actionLabel: 'Label');
        final cleared = slot.copyWith(actionId: null, actionLabel: null);
        expect(cleared.actionId, isNull);
        expect(cleared.actionLabel, isNull);
      });

      test('omitted nullable fields keep their current value', () {
        final slot = makeSlot(actionId: 'a1', actionLabel: 'Label');
        final updated = slot.copyWith(status: PhaseStatus.held);
        expect(updated.actionId, 'a1');
        expect(updated.actionLabel, 'Label');
      });

      test('returns an equal value when nothing changes', () {
        final slot = makeSlot(actionId: 'a1');
        expect(slot.copyWith(), slot);
      });
    });

    group('equality', () {
      test('equal values are equal', () {
        expect(
          makeSlot(segment: 6, actionId: 'a1'),
          makeSlot(segment: 6, actionId: 'a1'),
        );
      });

      test('different segment is not equal', () {
        expect(makeSlot(segment: 6), isNot(makeSlot(segment: 7)));
      });

      test('different status is not equal', () {
        expect(
          makeSlot(status: PhaseStatus.held),
          isNot(makeSlot(status: PhaseStatus.spent)),
        );
      });

      test('different action metadata is not equal', () {
        expect(makeSlot(actionId: 'a1'), isNot(makeSlot(actionId: 'a2')));
      });

      test('different isMental is not equal', () {
        expect(makeSlot(isMental: true), isNot(makeSlot(isMental: false)));
      });
    });
  });

  group('Combatant', () {
    group('initialization', () {
      test('defaults targeting, npc flags, and phases', () {
        final combatant = makeCombatant();
        expect(combatant.isTargeted, isFalse);
        expect(combatant.isNpc, isFalse);
        expect(combatant.phaseSlots, isEmpty);
        expect(combatant.statusBadges, isEmpty);
      });

      test('statusBadges are defensively copied and unmodifiable', () {
        final input = <PhaseStatus>[PhaseStatus.held];
        final combatant = makeCombatant(statusBadges: input);

        input.add(PhaseStatus.aborted);
        expect(combatant.statusBadges, [PhaseStatus.held]);

        expect(
          () => combatant.statusBadges.add(PhaseStatus.aborted),
          throwsUnsupportedError,
        );
      });

      test('carries all character fields', () {
        final combatant = makeCombatant(
          id: 'g1',
          name: 'Goblin',
          dex: 11,
          ego: 8,
          spd: 4,
          stun: 20,
          end: 10,
          body: 6,
          isTargeted: true,
          isNpc: true,
          phaseSlots: const [PhaseSlot(segment: 3)],
        );
        expect(combatant.id, 'g1');
        expect(combatant.name, 'Goblin');
        expect(combatant.dex, 11);
        expect(combatant.ego, 8);
        expect(combatant.spd, 4);
        expect(combatant.stun, 20);
        expect(combatant.end, 10);
        expect(combatant.body, 6);
        expect(combatant.isTargeted, isTrue);
        expect(combatant.isNpc, isTrue);
        expect(combatant.phaseSlots, hasLength(1));
      });

      test('phaseSlots are defensively copied and unmodifiable', () {
        final input = <PhaseSlot>[const PhaseSlot(segment: 3)];
        final combatant = makeCombatant(phaseSlots: input);

        input.add(const PhaseSlot(segment: 6));
        expect(combatant.phaseSlots, hasLength(1));

        expect(
          () => combatant.phaseSlots.add(const PhaseSlot(segment: 9)),
          throwsUnsupportedError,
        );
      });
    });

    group('copyWith', () {
      test('changes only the provided fields', () {
        final combatant = makeCombatant(
          id: 'c1',
          stun: 40,
          isNpc: true,
          phaseSlots: const [PhaseSlot(segment: 3)],
        );
        final damaged = combatant.copyWith(stun: 25);

        expect(damaged.stun, 25);
        expect(damaged.id, 'c1');
        expect(damaged.isNpc, isTrue);
        expect(damaged.phaseSlots, [const PhaseSlot(segment: 3)]);
      });

      test('toggles targeting without touching other fields', () {
        final targeted = makeCombatant().copyWith(isTargeted: true);
        expect(targeted.isTargeted, isTrue);
        expect(targeted.name, 'Hero One');
      });

      test('replaces phase slots', () {
        final updated = makeCombatant().copyWith(
          phaseSlots: const [PhaseSlot(segment: 2), PhaseSlot(segment: 4)],
        );
        expect(updated.phaseSlots, hasLength(2));
      });

      test('replaces status badges', () {
        final combatant = makeCombatant(
          statusBadges: const [PhaseStatus.held],
        );
        final updated = combatant.copyWith(
          statusBadges: const [PhaseStatus.aborted],
        );
        expect(updated.statusBadges, [PhaseStatus.aborted]);
        expect(combatant.statusBadges, [PhaseStatus.held]);
      });

      test('returns an equal value when nothing changes', () {
        final combatant = makeCombatant();
        expect(combatant.copyWith(), combatant);
      });
    });

    group('equality', () {
      test('equal values are equal with distinct phase list instances', () {
        final a = makeCombatant(
          phaseSlots: [makeSlot(segment: 3), makeSlot(segment: 6)],
        );
        final b = makeCombatant(
          phaseSlots: [makeSlot(segment: 3), makeSlot(segment: 6)],
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('different phase slot status is not equal', () {
        final a = makeCombatant(
          phaseSlots: [makeSlot(status: PhaseStatus.held)],
        );
        final b = makeCombatant(phaseSlots: [makeSlot()]);
        expect(a, isNot(b));
      });

      test('different stats are not equal', () {
        expect(makeCombatant(stun: 40), isNot(makeCombatant(stun: 39)));
      });

      test('different flags are not equal', () {
        expect(makeCombatant(isNpc: true), isNot(makeCombatant(isNpc: false)));
      });

      test('different status badges are not equal', () {
        expect(
          makeCombatant(statusBadges: const [PhaseStatus.held]),
          isNot(makeCombatant()),
        );
      });
    });

    group('initiative sorting', () {
      test('sorts by SPD desc, then DEX desc, then EGO desc, then name asc',
          () {
        final combatants = <Combatant>[
          makeCombatant(id: 'c', name: 'Bravo', dex: 10, ego: 10, spd: 3),
          makeCombatant(id: 'a', name: 'Alpha', dex: 10, ego: 10, spd: 3),
          makeCombatant(id: 'd', name: 'Delta', dex: 12, ego: 10, spd: 5),
          makeCombatant(id: 'e', name: 'Echo', dex: 20, ego: 1, spd: 3),
          makeCombatant(id: 'f', name: 'Foxtrot', dex: 10, ego: 20, spd: 3),
        ];
        combatants.sort(Combatant.compareByInitiative);

        expect(combatants.map((c) => c.id), ['d', 'e', 'f', 'a', 'c']);
      });

      test('fully equal stats fall back to the id for determinism', () {
        final combatants = <Combatant>[
          makeCombatant(id: 'z', name: 'Twin', dex: 10, ego: 10, spd: 3),
          makeCombatant(id: 'b', name: 'Twin', dex: 10, ego: 10, spd: 3),
        ];
        combatants.sort(Combatant.compareByInitiative);

        expect(combatants.map((c) => c.id), ['b', 'z']);
      });
    });
  });

  group('TurnState', () {
    group('initialization', () {
      test('defaults to turn 1 with no active or targeted combatant', () {
        final state = makeTurnState();
        expect(state.turnNumber, 1);
        expect(state.activeCombatantId, isNull);
        expect(state.targetCombatantId, isNull);
        expect(state.combatants, isEmpty);
      });

      test('carries full state', () {
        final state = makeTurnState(
          turnNumber: 3,
          activeSegment: 12,
          activeCombatantId: 'c2',
          targetCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1'),
            makeCombatant(id: 'c2'),
          ],
        );
        expect(state.turnNumber, 3);
        expect(state.activeSegment, 12);
        expect(state.activeCombatantId, 'c2');
        expect(state.targetCombatantId, 'c1');
        expect(state.combatants, hasLength(2));
      });

      test('asserts on activeSegment outside 1-12', () {
        expect(
          () => makeTurnState(activeSegment: 0),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => makeTurnState(activeSegment: 13),
          throwsA(isA<AssertionError>()),
        );
      });

      test('asserts on turnNumber below 1', () {
        expect(
          () => makeTurnState(turnNumber: 0),
          throwsA(isA<AssertionError>()),
        );
      });

      test('combatants are defensively copied and unmodifiable', () {
        final input = <Combatant>[makeCombatant(id: 'c1')];
        final state = makeTurnState(combatants: input);

        input.add(makeCombatant(id: 'c2'));
        expect(state.combatants, hasLength(1));

        expect(
          () => state.combatants.add(makeCombatant(id: 'c3')),
          throwsUnsupportedError,
        );
      });
    });

    group('copyWith', () {
      test('advances turn and segment independently', () {
        final state = makeTurnState(turnNumber: 1, activeSegment: 11);

        expect(state.copyWith(activeSegment: 12).activeSegment, 12);
        expect(state.copyWith(turnNumber: 2).turnNumber, 2);
        expect(state.copyWith(turnNumber: 2).activeSegment, 11);
      });

      test('sets active and target combatant ids', () {
        final state = makeTurnState().copyWith(
          activeCombatantId: 'c2',
          targetCombatantId: 'c1',
        );
        expect(state.activeCombatantId, 'c2');
        expect(state.targetCombatantId, 'c1');
      });

      test('clears nullable ids when null is passed explicitly', () {
        final state = makeTurnState(
          activeCombatantId: 'c2',
          targetCombatantId: 'c1',
        );
        final cleared = state.copyWith(
          activeCombatantId: null,
          targetCombatantId: null,
        );
        expect(cleared.activeCombatantId, isNull);
        expect(cleared.targetCombatantId, isNull);
      });

      test('omitted nullable ids keep their current value', () {
        final state = makeTurnState(targetCombatantId: 'c1');
        final updated = state.copyWith(activeSegment: 7);
        expect(updated.targetCombatantId, 'c1');
      });

      test('replaces the combatant list', () {
        final state = makeTurnState(combatants: [makeCombatant(id: 'c1')]);
        final updated = state.copyWith(
          combatants: [
            makeCombatant(id: 'c1'),
            makeCombatant(id: 'c2'),
          ],
        );
        expect(updated.combatants, hasLength(2));
      });

      test('returns an equal value when nothing changes', () {
        final state = makeTurnState(activeCombatantId: 'c2');
        expect(state.copyWith(), state);
      });
    });

    group('equality', () {
      test('equal values are equal with distinct combatant lists', () {
        final a = makeTurnState(combatants: [makeCombatant(id: 'c1')]);
        final b = makeTurnState(combatants: [makeCombatant(id: 'c1')]);
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('different turn number is not equal', () {
        expect(
          makeTurnState(turnNumber: 1),
          isNot(makeTurnState(turnNumber: 2)),
        );
      });

      test('nested combatant differences break equality', () {
        final a = makeTurnState(combatants: [makeCombatant(stun: 40)]);
        final b = makeTurnState(combatants: [makeCombatant(stun: 25)]);
        expect(a, isNot(b));
      });

      test('different target id is not equal', () {
        expect(
          makeTurnState(targetCombatantId: 'c1'),
          isNot(makeTurnState(targetCombatantId: 'c2')),
        );
      });
    });
  });

  group('HaymakerDeclaration', () {
    test('resolves at Segment N+1 within the declaring turn', () {
      final declaration = HaymakerDeclaration.at(
        combatantId: 'c1',
        segment: 5,
        declaredTurn: 1,
      );

      expect(declaration.combatantId, 'c1');
      expect(declaration.declaredSegment, 5);
      expect(declaration.resolutionSegment, 6);
      expect(declaration.declaredTurn, 1);
      expect(declaration.isDeferredToNextTurn, isFalse);
      expect(declaration.resolutionTurn, 1);
    });

    test('wraps the resolution past Segment 12 into the next turn', () {
      final declaration = HaymakerDeclaration.at(
        combatantId: 'c1',
        segment: 12,
        declaredTurn: 3,
      );

      expect(declaration.declaredSegment, 12);
      expect(declaration.resolutionSegment, 1);
      expect(declaration.isDeferredToNextTurn, isTrue);
      expect(declaration.resolutionTurn, 4);
    });

    test('equal declarations are equal', () {
      expect(
        HaymakerDeclaration.at(combatantId: 'c1', segment: 5, declaredTurn: 1),
        const HaymakerDeclaration(
          combatantId: 'c1',
          declaredSegment: 5,
          resolutionSegment: 6,
          declaredTurn: 1,
        ),
      );
    });

    test('different declared turns are not equal', () {
      expect(
        HaymakerDeclaration.at(combatantId: 'c1', segment: 12, declaredTurn: 1),
        isNot(
          HaymakerDeclaration.at(
            combatantId: 'c1',
            segment: 12,
            declaredTurn: 2,
          ),
        ),
      );
    });
  });
}
