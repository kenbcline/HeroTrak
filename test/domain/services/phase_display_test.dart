import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/domain/services/phase_display.dart';

PhaseSlot makeSlot({
  int segment = 6,
  PhaseStatus status = PhaseStatus.scheduled,
}) {
  return PhaseSlot(segment: segment, status: status);
}

Combatant makeCombatant({
  String id = 'c1',
  CombatantStatus status = CombatantStatus.normal,
  List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
  List<PhaseStatus> statusBadges = const <PhaseStatus>[],
}) {
  return Combatant(
    id: id,
    name: 'Hero One',
    dex: 18,
    ego: 10,
    spd: 5,
    stun: 40,
    end: 20,
    body: 10,
    status: status,
    phaseSlots: phaseSlots,
    statusBadges: statusBadges,
  );
}

void main() {
  group('phaseSlotDisplayLabel (DYING [REC] override)', () {
    test('dying renders [REC] across active (scheduled) phases', () {
      final dying = makeCombatant(
        status: CombatantStatus.dying,
        phaseSlots: [makeSlot(segment: 5), makeSlot(segment: 9)],
      );

      expect(phaseSlotDisplayLabel(dying, dying.phaseSlots[0], 3), '[REC]');
      expect(phaseSlotDisplayLabel(dying, dying.phaseSlots[1], 3), '[REC]');
    });

    test('dying keeps standard rendering for non-active slots', () {
      final dying = makeCombatant(
        status: CombatantStatus.dying,
        phaseSlots: [makeSlot(segment: 5, status: PhaseStatus.spent)],
      );

      expect(phaseSlotDisplayLabel(dying, dying.phaseSlots[0], 3), isNull);
    });

    test('dying Post-12 still renders [BLEED] (not [REC])', () {
      final dying = makeCombatant(status: CombatantStatus.dying);

      expect(post12DisplayLabel(dying), '[BLEED]');
    });

    test('dying replaces the standard glyph with [REC] (maneuver icons '
        'stripped)', () {
      final dying = makeCombatant(
        status: CombatantStatus.dying,
        phaseSlots: [makeSlot(segment: 5)],
      );
      final normal = makeCombatant(phaseSlots: [makeSlot(segment: 5)]);

      expect(phaseSlotDisplayLabel(dying, dying.phaseSlots[0], 3), '[REC]');
      expect(phaseSlotDisplayLabel(normal, normal.phaseSlots[0], 3), isNull);
    });
  });

  group('isPhaseActionLocked', () {
    test('stunned is locked while the [CLR STUN] phase is upcoming', () {
      final stunned = makeCombatant(
        status: CombatantStatus.stunned,
        phaseSlots: [makeSlot(segment: 5), makeSlot(segment: 9)],
      );

      expect(isPhaseActionLocked(stunned, 3), isTrue);
    });

    test('KO and dying are locked while a [REC] phase is upcoming', () {
      final ko = makeCombatant(
        status: CombatantStatus.knockedOut,
        phaseSlots: [makeSlot(segment: 5)],
      );
      final dying = makeCombatant(
        status: CombatantStatus.dying,
        phaseSlots: [makeSlot(segment: 5)],
      );

      expect(isPhaseActionLocked(ko, 3), isTrue);
      expect(isPhaseActionLocked(dying, 3), isTrue);
    });

    test('normal and dead combatants are never locked', () {
      final normal = makeCombatant(phaseSlots: [makeSlot(segment: 5)]);
      final dead = makeCombatant(
        status: CombatantStatus.dead,
        phaseSlots: [makeSlot(segment: 5)],
      );

      expect(isPhaseActionLocked(normal, 3), isFalse);
      expect(isPhaseActionLocked(dead, 3), isFalse);
    });

    test('no upcoming phase means no lock', () {
      final ko = makeCombatant(
        status: CombatantStatus.knockedOut,
        phaseSlots: [makeSlot(segment: 5, status: PhaseStatus.spent)],
      );

      expect(isPhaseActionLocked(ko, 6), isFalse);
    });
  });

  group('virtualHoldLabel / virtualHoldSpan', () {
    // Hold declared on the actor's Segment-6 phase; next natural DEX phase
    // at Segment 10. Marker window: [6, 10).
    Combatant holder({PhaseStatus heldStatus = PhaseStatus.held}) {
      return makeCombatant(
        phaseSlots: [
          makeSlot(segment: 6, status: heldStatus),
          makeSlot(segment: 10),
        ],
        statusBadges: const [PhaseStatus.held],
      );
    }

    test('markers span from the declaration segment up to the next natural '
        'DEX phase (exclusive)', () {
      final combatant = holder();

      expect(virtualHoldLabel(combatant, 6, 5), '[HOLD]');
      expect(virtualHoldLabel(combatant, 7, 5), '[HOLD]');
      expect(virtualHoldLabel(combatant, 8, 5), '[HOLD]');
      expect(virtualHoldLabel(combatant, 9, 5), '[HOLD]');
      // Not before the declaration segment, not at/after the next phase.
      expect(virtualHoldLabel(combatant, 5, 5), isNull);
      expect(virtualHoldLabel(combatant, 10, 5), isNull);
      expect(virtualHoldLabel(combatant, 11, 5), isNull);
    });

    test('markers clear when the held action is consumed', () {
      final consumed = holder(heldStatus: PhaseStatus.spent);

      for (var segment = 6; segment <= 11; segment++) {
        expect(virtualHoldLabel(consumed, segment, 7), isNull);
      }
    });

    test('markers clear when the held action is aborted', () {
      final aborted = holder(heldStatus: PhaseStatus.aborted);

      expect(virtualHoldLabel(aborted, 7, 7), isNull);
    });

    test('markers clear once the next natural DEX phase is reached', () {
      final combatant = holder();

      // Cursor at Segment 9: window still open.
      expect(virtualHoldLabel(combatant, 7, 9), '[HOLD]');
      // Cursor reaches Segment 10: the hold has lapsed — all markers clear.
      expect(virtualHoldLabel(combatant, 7, 10), isNull);
      expect(virtualHoldLabel(combatant, 9, 10), isNull);
    });

    test('no held slot means no markers', () {
      final idle = makeCombatant(phaseSlots: [makeSlot(segment: 6)]);

      expect(virtualHoldLabel(idle, 6, 3), isNull);
      expect(virtualHoldSpan(idle, 3), isNull);
    });

    test('span runs to Segment 12 when no later phase remains', () {
      final last = makeCombatant(
        phaseSlots: [makeSlot(segment: 12, status: PhaseStatus.held)],
      );

      expect(virtualHoldSpan(last, 6), const (12, 13));
      expect(virtualHoldLabel(last, 12, 6), '[HOLD]');
    });
  });

  group('hasActiveHold', () {
    test('true while the hold window is open, false once reached', () {
      final combatant = makeCombatant(
        phaseSlots: [
          makeSlot(segment: 6, status: PhaseStatus.held),
          makeSlot(segment: 10),
        ],
        statusBadges: const [PhaseStatus.held],
      );

      expect(hasActiveHold(combatant, 7), isTrue);
      expect(hasActiveHold(combatant, 10), isFalse);
    });

    test('false when the hold was consumed', () {
      final combatant = makeCombatant(
        phaseSlots: [makeSlot(segment: 6, status: PhaseStatus.spent)],
      );

      expect(hasActiveHold(combatant, 3), isFalse);
    });
  });
}