import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/domain/services/segment_queue.dart';
import 'package:herotrak/domain/services/timeline_traversal.dart';

PhaseSlot makeSlot({
  int segment = 6,
  PhaseStatus status = PhaseStatus.scheduled,
  bool isMental = false,
}) {
  return PhaseSlot(segment: segment, status: status, isMental: isMental);
}

Combatant makeCombatant({
  String id = 'c1',
  String name = 'Hero One',
  int dex = 18,
  int ego = 10,
  int spd = 5,
  CombatantStatus status = CombatantStatus.normal,
  List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
}) {
  return Combatant(
    id: id,
    name: name,
    dex: dex,
    ego: ego,
    spd: spd,
    stun: 40,
    end: 20,
    body: 10,
    status: status,
    phaseSlots: phaseSlots,
  );
}

TurnState makeTurnState({
  int turnNumber = 1,
  int activeSegment = 6,
  String? activeCombatantId,
  List<Combatant> combatants = const <Combatant>[],
  List<HaymakerDeclaration> haymakerDeclarations = const <HaymakerDeclaration>[],
}) {
  return TurnState(
    turnNumber: turnNumber,
    activeSegment: activeSegment,
    activeCombatantId: activeCombatantId,
    combatants: combatants,
    haymakerDeclarations: haymakerDeclarations,
  );
}

/// Timeline layout: two phases at Segment 3 (physical by DEX: fast 30, then
/// slow 10), Segments 4–7 empty, two phases at Segment 8 (mental EGO 20
/// first, then physical DEX 50).
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

void main() {
  group('findNextPhasePosition', () {
    test('looks ahead in the active segment queue first', () {
      final next = findNextPhasePosition(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'fast',
          combatants: timelineCombatants(),
        ),
      );

      expect(next, const TimelinePosition(segment: 3, combatantId: 'slow'));
    });

    test('skips empty segments and lands on the first phase of the next '
        'one', () {
      final next = findNextPhasePosition(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'slow',
          combatants: timelineCombatants(),
        ),
      );

      expect(next, const TimelinePosition(segment: 8, combatantId: 'mental'));
    });

    test('returns null when the Turn timeline is exhausted', () {
      expect(
        findNextPhasePosition(
          makeTurnState(
            activeSegment: 8,
            activeCombatantId: 'eager',
            combatants: timelineCombatants(),
          ),
        ),
        isNull,
      );
    });

    test('resumes at the first queued phase when nothing is selected', () {
      final next = findNextPhasePosition(
        makeTurnState(activeSegment: 3, combatants: timelineCombatants()),
      );

      expect(next, const TimelinePosition(segment: 3, combatantId: 'fast'));
    });

    test('skips consumed phases', () {
      final next = findNextPhasePosition(
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
            makeCombatant(id: 'live', phaseSlots: [makeSlot(segment: 8)]),
          ],
        ),
      );

      expect(next, const TimelinePosition(segment: 8, combatantId: 'live'));
    });
  });

  group('findPreviousPhasePosition', () {
    test('walks backward within the active segment queue', () {
      final previous = findPreviousPhasePosition(
        makeTurnState(
          activeSegment: 8,
          activeCombatantId: 'eager',
          combatants: timelineCombatants(),
        ),
      );

      expect(
        previous,
        const TimelinePosition(segment: 8, combatantId: 'mental'),
      );
    });

    test('jumps back over empty segments to the last phase of an earlier '
        'one', () {
      final previous = findPreviousPhasePosition(
        makeTurnState(
          activeSegment: 8,
          activeCombatantId: 'mental',
          combatants: timelineCombatants(),
        ),
      );

      expect(previous, const TimelinePosition(segment: 3, combatantId: 'slow'));
    });

    test('returns null at the start of the Turn', () {
      expect(
        findPreviousPhasePosition(
          makeTurnState(
            activeSegment: 3,
            activeCombatantId: 'fast',
            combatants: timelineCombatants(),
          ),
        ),
        isNull,
      );
    });
  });

  group('segment queue', () {
    test('pending held interruptions come first in the queue but belong to '
        'their own segment chronologically', () {
      final state = makeTurnState(
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
      );

      // In the active segment's queue the pending held interruption is
      // resolved first...
      expect(segmentQueueIds(state, 6), ['holder', 'sluggish']);
      // ...but chronologically it belongs to Segment 3 only.
      expect(phaseIdsAtSegment(state, 6), ['sluggish']);
      expect(phaseIdsAtSegment(state, 3), ['holder']);
    });

    test('consumed phases never appear in queues or the timeline', () {
      final state = makeTurnState(
        activeSegment: 6,
        combatants: [
          makeCombatant(
            id: 'c1',
            phaseSlots: [
              makeSlot(segment: 6, status: PhaseStatus.spent),
              makeSlot(segment: 6, status: PhaseStatus.aborted),
            ],
          ),
        ],
      );

      expect(segmentQueueIds(state, 6), isEmpty);
      expect(phaseIdsAtSegment(state, 6), isEmpty);
    });

    test('segment 12 orders by DEX desc, then SPD desc, then name asc',
        () {
      // Every speed phases on Segment 12; the ids are deliberately arranged
      // so the old id-only tiebreak would misorder the equal-DEX entries.
      final state = makeTurnState(
        activeSegment: 12,
        combatants: [
          makeCombatant(
            id: 'a-slow',
            name: 'Bruiser',
            dex: 30,
            spd: 2,
            phaseSlots: [makeSlot(segment: 12)],
          ),
          makeCombatant(
            id: 'z-flash',
            name: 'Flash',
            dex: 30,
            spd: 8,
            phaseSlots: [makeSlot(segment: 12)],
          ),
          makeCombatant(
            id: 'z-zipped',
            name: 'Zipped',
            dex: 18,
            spd: 10,
            phaseSlots: [makeSlot(segment: 12)],
          ),
          makeCombatant(
            id: 'a-alpha',
            name: 'Alpha',
            dex: 18,
            spd: 10,
            phaseSlots: [makeSlot(segment: 12)],
          ),
          makeCombatant(
            id: 'a-aaron',
            name: 'Aaron',
            dex: 18,
            spd: 2,
            phaseSlots: [makeSlot(segment: 12)],
          ),
        ],
      );

      expect(segmentQueueIds(state, 12), [
        'z-flash', // DEX 30, SPD 8 — before the equal-DEX, lower-SPD peer
        'a-slow', // DEX 30, SPD 2
        'a-alpha', // DEX 18, SPD 10 — name ascending beats id order
        'z-zipped', // DEX 18, SPD 10
        'a-aaron', // DEX 18, SPD 2
      ]);
    });

    test('segment 12 keeps held and mental tiers ahead of physical', () {
      final state = makeTurnState(
        activeSegment: 12,
        combatants: [
          makeCombatant(
            id: 'phys',
            name: 'Phys',
            dex: 30,
            ego: 30,
            phaseSlots: [makeSlot(segment: 12)],
          ),
          makeCombatant(
            id: 'mental',
            name: 'Mental',
            dex: 5,
            ego: 20,
            phaseSlots: [makeSlot(segment: 12, isMental: true)],
          ),
          makeCombatant(
            id: 'holder',
            name: 'Holder',
            dex: 1,
            ego: 1,
            phaseSlots: [makeSlot(segment: 3, status: PhaseStatus.held)],
          ),
        ],
      );

      expect(segmentQueueIds(state, 12), ['holder', 'mental', 'phys']);
    });
  });

  group('resolution pseudo-phases and status bypass', () {
    test('pending Strikes resolutions are stops on the forward walk', () {
      final state = makeTurnState(
        activeSegment: 3,
        activeCombatantId: 'slow',
        haymakerDeclarations: [
          // Declared on Segment 4: the "Strikes" pseudo-phase sits on 5.
          HaymakerDeclaration.at(
            combatantId: 'slow',
            segment: 4,
            declaredTurn: 1,
          ),
        ],
        combatants: timelineCombatants(),
      );

      // Segments 4 is empty but Segment 5 holds the resolution marker:
      // the walk stops there instead of jumping to Segment 8.
      expect(
        findNextPhasePosition(state),
        const TimelinePosition(segment: 5, combatantId: 'slow'),
      );

      // From the pseudo-phase the walk continues to the next real phase.
      expect(
        findNextPhasePosition(
          state.copyWith(activeSegment: 5, activeCombatantId: 'slow'),
        ),
        const TimelinePosition(segment: 8, combatantId: 'mental'),
      );
    });

    test('the backward walk lands on Strikes pseudo-phases', () {
      final previous = findPreviousPhasePosition(
        makeTurnState(
          activeSegment: 8,
          activeCombatantId: 'mental',
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'slow',
              segment: 4,
              declaredTurn: 1,
            ),
          ],
          combatants: timelineCombatants(),
        ),
      );

      expect(previous, const TimelinePosition(segment: 5, combatantId: 'slow'));
    });

    test('pseudo-phases are ordered first within their segment', () {
      final previous = findPreviousPhasePosition(
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'fast',
          haymakerDeclarations: [
            // Resolution lands on Segment 3 alongside fast's and slow's
            // regular phases: it leads the segment's stops.
            HaymakerDeclaration.at(
              combatantId: 'eager',
              segment: 2,
              declaredTurn: 1,
            ),
          ],
          combatants: timelineCombatants(),
        ),
      );

      expect(previous, const TimelinePosition(segment: 3, combatantId: 'eager'));
    });

    test('resolutionIdsAtSegment lists only this Turn\'s pending strikes', () {
      final state = makeTurnState(
        turnNumber: 2,
        activeSegment: 3,
        haymakerDeclarations: [
          // Pending: strikes Segment 5 of Turn 2.
          HaymakerDeclaration.at(
            combatantId: 'slow',
            segment: 4,
            declaredTurn: 2,
          ),
          // Not pending here: its resolution Turn has not arrived.
          HaymakerDeclaration.at(
            combatantId: 'fast',
            segment: 12,
            declaredTurn: 2,
          ),
        ],
        combatants: timelineCombatants(),
      );

      expect(resolutionIdsAtSegment(state, 5), ['slow']);
      expect(resolutionIdsAtSegment(state, 1), isEmpty);
    });

    test('dead combatants are bypassed in the walk', () {
      final state = makeTurnState(
        activeSegment: 3,
        activeCombatantId: 'fast',
        combatants: [
          makeCombatant(id: 'fast', dex: 30, phaseSlots: [makeSlot(segment: 3)]),
          makeCombatant(
            id: 'slow',
            dex: 10,
            status: CombatantStatus.dead,
            phaseSlots: [makeSlot(segment: 3)],
          ),
          makeCombatant(
            id: 'mental',
            dex: 5,
            ego: 20,
            status: CombatantStatus.dead,
            phaseSlots: [makeSlot(segment: 8, isMental: true)],
          ),
          makeCombatant(id: 'eager', dex: 50, phaseSlots: [makeSlot(segment: 8)]),
        ],
      );

      // slow (dead) at Segment 3 and mental (dead) at Segment 8 are skipped.
      expect(
        findNextPhasePosition(state),
        const TimelinePosition(segment: 8, combatantId: 'eager'),
      );
    });

    test('a dead combatant\'s pending strike is bypassed too', () {
      final state = makeTurnState(
        activeSegment: 3,
        activeCombatantId: 'fast',
        haymakerDeclarations: [
          HaymakerDeclaration.at(
            combatantId: 'slow',
            segment: 4,
            declaredTurn: 1,
          ),
        ],
        combatants: [
          makeCombatant(id: 'fast', dex: 30, phaseSlots: [makeSlot(segment: 3)]),
          makeCombatant(
            id: 'slow',
            dex: 10,
            status: CombatantStatus.dead,
            phaseSlots: [makeSlot(segment: 3)],
          ),
          makeCombatant(id: 'mental', dex: 5, ego: 20, phaseSlots: [
            makeSlot(segment: 8, isMental: true),
          ]),
          makeCombatant(id: 'eager', dex: 50, phaseSlots: [makeSlot(segment: 8)]),
        ],
      );

      // The Segment 5 pseudo-stop belongs to a dead combatant: skipped.
      expect(
        findNextPhasePosition(state),
        const TimelinePosition(segment: 8, combatantId: 'mental'),
      );
    });

    test('KO and dying [REC] phases are valid timeline stops', () {
      final state = makeTurnState(
        activeSegment: 3,
        activeCombatantId: 'fast',
        combatants: [
          makeCombatant(id: 'fast', dex: 30, phaseSlots: [makeSlot(segment: 3)]),
          makeCombatant(
            id: 'ko',
            dex: 10,
            status: CombatantStatus.knockedOut,
            phaseSlots: [makeSlot(segment: 5)],
          ),
          makeCombatant(
            id: 'dy',
            dex: 20,
            status: CombatantStatus.dying,
            phaseSlots: [makeSlot(segment: 8)],
          ),
        ],
      );

      // The walk stops on each recovery pseudo-phase instead of skipping it.
      final first = findNextPhasePosition(state);
      expect(first, const TimelinePosition(segment: 5, combatantId: 'ko'));

      final second = findNextPhasePosition(
        state.copyWith(
          activeSegment: first!.segment,
          activeCombatantId: first.combatantId,
        ),
      );
      expect(second, const TimelinePosition(segment: 8, combatantId: 'dy'));

      // The backward walk stops on them too.
      expect(
        findPreviousPhasePosition(
          state.copyWith(
            activeSegment: first.segment,
            activeCombatantId: first.combatantId,
          ),
        ),
        const TimelinePosition(segment: 3, combatantId: 'fast'),
      );
    });

    test('findLastPhasePosition lands on the tail of the Segment 12 queue', () {
      final state = makeTurnState(
        activeSegment: 3,
        combatants: [
          makeCombatant(id: 'early', phaseSlots: [makeSlot(segment: 3)]),
          makeCombatant(id: 'late', phaseSlots: [makeSlot(segment: 12)]),
        ],
      );

      expect(
        findLastPhasePosition(state),
        const TimelinePosition(segment: 12, combatantId: 'late'),
      );
    });
  });
}