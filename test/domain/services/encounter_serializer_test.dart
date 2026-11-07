import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/domain/services/encounter_serializer.dart';

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
  group('round trip', () {
    test('a full TurnState survives serialize/deserialize unchanged', () {
      final state = makeTurnState(
        turnNumber: 3,
        activeSegment: 9,
        activeCombatantId: 'c1',
        targetCombatantId: 'c2',
        combatants: [
          makeCombatant(
            id: 'c1',
            name: 'Hero One',
            dex: 18,
            ego: 12,
            spd: 5,
            stun: 40,
            end: 20,
            body: 10,
            isTargeted: false,
            isNpc: false,
            statusBadges: [PhaseStatus.held, PhaseStatus.aborted],
            phaseSlots: [
              makeSlot(segment: 3),
              makeSlot(
                segment: 8,
                originalSegment: 5,
                status: PhaseStatus.spent,
                isMental: true,
                actionId: 'declare_haymaker',
                actionLabel: 'Declare Haymaker',
              ),
              makeSlot(segment: 12, status: PhaseStatus.delayed),
            ],
          ),
          makeCombatant(
            id: 'c2',
            name: 'Goblin',
            dex: 11,
            ego: 8,
            spd: 4,
            stun: 20,
            end: 10,
            body: 6,
            isTargeted: true,
            isNpc: true,
            phaseSlots: [
              makeSlot(segment: 3, status: PhaseStatus.active),
              makeSlot(segment: 6, status: PhaseStatus.held),
              makeSlot(segment: 9, status: PhaseStatus.aborted),
              makeSlot(segment: 12),
            ],
          ),
        ],
      );

      final restored = deserializeEncounter(serializeEncounter(state));

      expect(restored, state);
      expect(restored.hashCode, state.hashCode);
    });

    test('a minimal TurnState with null selections round-trips', () {
      final state = makeTurnState(turnNumber: 1, activeSegment: 1);

      final restored = deserializeEncounter(serializeEncounter(state));

      expect(restored, state);
      expect(restored.activeCombatantId, isNull);
      expect(restored.targetCombatantId, isNull);
      expect(restored.combatants, isEmpty);
    });

    test('cleared action metadata and empty badges round-trip', () {
      final state = makeTurnState(
        activeSegment: 6,
        combatants: [
          makeCombatant(
            id: 'c1',
            phaseSlots: [makeSlot(segment: 6, actionId: null, actionLabel: null)],
          ),
        ],
      );

      final restored = deserializeEncounter(serializeEncounter(state));

      expect(restored, state);
      expect(restored.combatants.single.phaseSlots.single.actionId, isNull);
      expect(restored.combatants.single.statusBadges, isEmpty);
    });

    test('haymaker declarations round-trip', () {
      final state = makeTurnState(
        activeSegment: 6,
        combatants: [makeCombatant(id: 'c1')],
      ).copyWith(
        haymakerDeclarations: [
          HaymakerDeclaration.at(
            combatantId: 'c1',
            segment: 5,
            declaredTurn: 1,
          ),
          const HaymakerDeclaration(
            combatantId: 'c1',
            declaredSegment: 12,
            resolutionSegment: 1,
            declaredTurn: 1,
          ),
        ],
      );

      final restored = deserializeEncounter(serializeEncounter(state));

      expect(restored, state);
      expect(restored.haymakerDeclarations, hasLength(2));
      expect(restored.haymakerDeclarations.first.resolutionSegment, 6);
      expect(restored.haymakerDeclarations.last.resolutionSegment, 1);
    });

    test('combatant status and extended stats round-trip', () {
      final state = makeTurnState(
        activeSegment: 6,
        combatants: [
          makeCombatant(id: 'c1').copyWith(
            status: CombatantStatus.knockedOut,
            intelligence: 13,
            team: 'Red Team',
          ),
        ],
      );

      final restored = deserializeEncounter(serializeEncounter(state));

      expect(restored, state);
      final combatant = restored.combatants.single;
      expect(combatant.status, CombatantStatus.knockedOut);
      expect(combatant.intelligence, 13);
      expect(combatant.team, 'Red Team');
    });
  });

  group('serialized shape', () {
    test('emits the documented JSON keys with enum names', () {
      final state = makeTurnState(
        turnNumber: 2,
        activeSegment: 7,
        activeCombatantId: 'c1',
        combatants: [
          makeCombatant(
            id: 'c1',
            isNpc: true,
            statusBadges: [PhaseStatus.held],
            phaseSlots: [makeSlot(segment: 4, status: PhaseStatus.spent)],
          ),
        ],
      );

      final decoded =
          jsonDecode(serializeEncounter(state)) as Map<String, dynamic>;

      expect(decoded['turnNumber'], 2);
      expect(decoded['activeSegment'], 7);
      expect(decoded['activeCombatantId'], 'c1');
      expect(decoded['targetCombatantId'], isNull);

      final combatant = (decoded['combatants'] as List<Object?>).single
          as Map<String, dynamic>;
      expect(combatant['id'], 'c1');
      expect(combatant['dex'], 18);
      expect(combatant['isNpc'], isTrue);
      expect(combatant['statusBadges'], ['held']);

      final slot = (combatant['phaseSlots'] as List<Object?>).single
          as Map<String, dynamic>;
      expect(slot['segment'], 4);
      expect(slot['status'], 'spent');
      expect(slot['isMental'], isFalse);
    });
  });

  group('safe deserialization', () {
    test('throws FormatException on malformed JSON', () {
      expect(
        () => deserializeEncounter('not json at all'),
        throwsFormatException,
      );
    });

    test('throws FormatException when the root is not an object', () {
      expect(() => deserializeEncounter('[1, 2, 3]'), throwsFormatException);
    });

    test('throws FormatException when required fields are missing', () {
      expect(
        () => deserializeEncounter('{"turnNumber": 1}'),
        throwsFormatException,
      );
    });

    test('throws FormatException on wrong field types', () {
      expect(
        () => deserializeEncounter(
          '{"turnNumber": "two", "activeSegment": 1, "combatants": []}',
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException on an unknown phase status name', () {
      final json = jsonEncode(<String, Object?>{
        'turnNumber': 1,
        'activeSegment': 1,
        'activeCombatantId': null,
        'targetCombatantId': null,
        'combatants': [
          <String, Object?>{
            'id': 'c1',
            'name': 'Hero One',
            'dex': 10,
            'ego': 10,
            'spd': 3,
            'stun': 0,
            'end': 0,
            'body': 0,
            'isTargeted': false,
            'isNpc': false,
            'statusBadges': <Object?>[],
            'phaseSlots': [
              <String, Object?>{
                'segment': 4,
                'originalSegment': 4,
                'status': 'vanished',
                'isMental': false,
                'actionId': null,
                'actionLabel': null,
              },
            ],
          },
        ],
      });

      expect(() => deserializeEncounter(json), throwsFormatException);
    });

    test('throws FormatException on out-of-range segments instead of '
        'asserting', () {
      final json = jsonEncode(<String, Object?>{
        'turnNumber': 1,
        'activeSegment': 13,
        'activeCombatantId': null,
        'targetCombatantId': null,
        'combatants': <Object?>[],
      });

      expect(() => deserializeEncounter(json), throwsFormatException);
    });
  });
}