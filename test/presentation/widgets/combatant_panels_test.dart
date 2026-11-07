import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/presentation/state/turn_engine_notifier.dart';
import 'package:herotrak/presentation/views/initiative_matrix_screen.dart';

PhaseSlot makeSlot({int segment = 1}) {
  return PhaseSlot(segment: segment);
}

Combatant makeCombatant({
  String id = 'c1',
  String name = 'Hero One',
  bool isNpc = false,
  String team = '',
  List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
  List<PhaseStatus> statusBadges = const <PhaseStatus>[],
}) {
  return Combatant(
    id: id,
    name: name,
    dex: 18,
    ego: 10,
    spd: 5,
    stun: 40,
    end: 20,
    body: 10,
    team: team,
    isNpc: isNpc,
    phaseSlots: phaseSlots,
    statusBadges: statusBadges,
  );
}

TurnState makeTurnState({
  int turnNumber = 1,
  int activeSegment = 1,
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

Future<ProviderContainer> pumpScreen(
    WidgetTester tester, TurnState initial) async {
  final container = ProviderContainer(
    overrides: [
      turnEngineProvider.overrideWith(
        () => TurnEngineNotifier(initial: initial),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InitiativeMatrixScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder inPanel(String panelKey, Finder finder) {
  return find.descendant(
    of: find.byKey(Key(panelKey)),
    matching: finder,
  );
}

void main() {
  group('dual bottom panels', () {
    testWidgets('renders Active and Target panels side by side with fallbacks',
        (tester) async {
      await pumpScreen(tester, makeTurnState(activeSegment: 3));

      expect(find.byKey(const Key('active-combatant-panel')), findsOneWidget);
      expect(find.byKey(const Key('target-combatant-panel')), findsOneWidget);
      expect(find.text('No Combatant Selected'), findsOneWidget);
      expect(find.text('No Target Selected'), findsOneWidget);
    });

    testWidgets('actor and target headers show name and faction badge',
        (tester) async {
      await pumpScreen(
        tester,
        makeTurnState(
          activeCombatantId: 'actor',
          targetCombatantId: 'target',
          combatants: [
            makeCombatant(id: 'actor', name: 'Hero One', team: 'Players'),
            makeCombatant(id: 'target', name: 'Goon', team: 'Villain'),
          ],
        ),
      );

      expect(inPanel('active-combatant-panel', find.text('Hero One')),
          findsOneWidget);
      expect(inPanel('active-combatant-panel', find.text('Players')),
          findsOneWidget);
      expect(
          inPanel('target-combatant-panel', find.text('Goon')), findsOneWidget);
      expect(inPanel('target-combatant-panel', find.text('Villain')),
          findsOneWidget);
    });

    testWidgets('actor panel shows the primary stats and omits the HP pools',
        (tester) async {
      await pumpScreen(
        tester,
        makeTurnState(
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 1)]),
          ],
        ),
      );

      for (final label in ['SPD', 'DEX', 'EGO']) {
        expect(inPanel('active-combatant-panel', find.text(label)),
            findsOneWidget);
      }
      for (final label in ['STUN', 'END', 'BOD', 'BODY']) {
        expect(inPanel('active-combatant-panel', find.text(label)), findsNothing);
      }
    });

    testWidgets('actor panel shows status badges and haymaker charging',
        (tester) async {
      await pumpScreen(
        tester,
        makeTurnState(
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(
              id: 'c1',
              phaseSlots: [makeSlot(segment: 5)],
              statusBadges: [PhaseStatus.held, PhaseStatus.aborted],
            ),
          ],
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 5,
              declaredTurn: 1,
            ),
          ],
        ),
      );

      expect(find.text('Held'), findsOneWidget);
      expect(find.text('Aborted'), findsOneWidget);
      expect(find.text('Haymaker Charging'), findsOneWidget);
    });

    testWidgets('status toggles update the target combatant only',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeCombatantId: 'actor',
          targetCombatantId: 'target',
          combatants: [
            makeCombatant(id: 'actor'),
            makeCombatant(id: 'target'),
          ],
        ),
      );

      CombatantStatus statusOf(String id) => container
          .read(turnEngineProvider)
          .combatants
          .firstWhere((combatant) => combatant.id == id)
          .status;

      Future<void> tapStatus(String label) async {
        await tester.tap(find.byKey(Key('detail-status-$label')));
        await tester.pumpAndSettle();
      }

      await tapStatus('STUN');
      expect(statusOf('target'), CombatantStatus.stunned);
      expect(statusOf('actor'), CombatantStatus.normal);

      await tapStatus('DYING');
      expect(statusOf('target'), CombatantStatus.dying);

      await tapStatus('KO');
      expect(statusOf('target'), CombatantStatus.knockedOut);

      await tapStatus('DEAD');
      expect(statusOf('target'), CombatantStatus.dead);

      await tapStatus('OK');
      expect(statusOf('target'), CombatantStatus.normal);
    });

    testWidgets('tactical status box reflects each target condition',
        (tester) async {
      await pumpScreen(
        tester,
        makeTurnState(
          targetCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 1)]),
          ],
        ),
      );

      String rule() => tester
          .widget<Text>(find.byKey(const Key('tactical-status-rule')))
          .data!;

      Future<void> tapStatus(String label) async {
        await tester.tap(find.byKey(Key('detail-status-$label')));
        await tester.pumpAndSettle();
      }

      expect(rule(), 'Full OCV / Full DCV');

      await tapStatus('STUN');
      expect(rule(), '1/2 DCV | Action consumed to clear Stun on next phase');

      await tapStatus('DYING');
      expect(
        rule(),
        '0 OCV / 0 DCV | Unconscious / Bleeding (-1 BOD on Post-12)',
      );

      await tapStatus('KO');
      expect(
        rule(),
        '0 OCV / 0 DCV | Unconscious / Bleeding (-1 BOD on Post-12)',
      );

      await tapStatus('DEAD');
      expect(rule(), '0 OCV / 0 DCV | Dead');

      await tapStatus('OK');
      expect(rule(), 'Full OCV / Full DCV');
    });

    testWidgets('target panel follows the target cursor', (tester) async {
      await pumpScreen(
        tester,
        makeTurnState(activeSegment: 1, combatants: [
          makeCombatant(id: 'c1', name: 'Hero One'),
          makeCombatant(id: 'c2', name: 'Villain Two'),
        ]),
      );

      // Nothing targeted yet.
      expect(find.text('No Target Selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('matrix-row-c1')));
      await tester.pumpAndSettle();
      expect(find.text('No Target Selected'), findsNothing);
      expect(inPanel('target-combatant-panel', find.text('Hero One')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('matrix-row-c2')));
      await tester.pumpAndSettle();
      expect(inPanel('target-combatant-panel', find.text('Hero One')),
          findsNothing);
      expect(inPanel('target-combatant-panel', find.text('Villain Two')),
          findsOneWidget);
    });

    testWidgets('OK from STUN/KO/DYING resets the phase markers to standard '
        'slots', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 3, targetCombatantId: 'st', combatants: [
          makeCombatant(id: 'st', phaseSlots: [makeSlot(segment: 5)])
              .copyWith(status: CombatantStatus.stunned),
          makeCombatant(id: 'ko', phaseSlots: [makeSlot(segment: 5)])
              .copyWith(status: CombatantStatus.knockedOut),
          makeCombatant(id: 'dy', phaseSlots: [makeSlot(segment: 5)])
              .copyWith(status: CombatantStatus.dying),
        ]),
      );

      Finder cellText(String id, String text) => find.descendant(
            of: find.byKey(Key('matrix-cell-$id-5')),
            matching: find.text(text),
          );

      Combatant subjectOf(String id) => container
          .read(turnEngineProvider)
          .combatants
          .firstWhere((combatant) => combatant.id == id);

      // Stunned shows [CLR STUN]; KO shows [REC]; dying renders a standard
      // slot (natural Phase Recoveries are suppressed while dying).
      expect(cellText('st', '[CLR STUN]'), findsOneWidget);
      expect(cellText('ko', '[REC]'), findsOneWidget);
      expect(cellText('dy', '●'), findsOneWidget);

      // OK on the targeted stunned combatant: the marker clears back to a
      // standard phase slot — available (scheduled) immediately.
      await tester.tap(find.byKey(const Key('detail-status-OK')));
      await tester.pumpAndSettle();
      expect(cellText('st', '[CLR STUN]'), findsNothing);
      expect(cellText('st', '●'), findsOneWidget);
      expect(subjectOf('st').phaseSlots.single.status, PhaseStatus.scheduled);

      // Same for the KO'd combatant.
      await tester.tap(find.byKey(const Key('matrix-row-ko')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-status-OK')));
      await tester.pumpAndSettle();
      expect(cellText('ko', '[REC]'), findsNothing);
      expect(cellText('ko', '●'), findsOneWidget);
      expect(subjectOf('ko').phaseSlots.single.status, PhaseStatus.scheduled);

      // ...and the dying combatant (already on a standard slot) is
      // unchanged by OK.
      await tester.tap(find.byKey(const Key('matrix-row-dy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-status-OK')));
      await tester.pumpAndSettle();
      expect(cellText('dy', '[REC]'), findsNothing);
      expect(cellText('dy', '●'), findsOneWidget);
      expect(subjectOf('dy').phaseSlots.single.status, PhaseStatus.scheduled);
    });

    testWidgets('SPD +1 / SPD -1 adjust the target and re-plan their phases',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 5,
          targetCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [
              makeSlot(segment: 4),
              makeSlot(segment: 8),
              makeSlot(segment: 12),
            ]),
          ],
        ),
      );

      Combatant subject() =>
          container.read(turnEngineProvider).combatants.single;

      // Base SPD shows without a delta.
      expect(find.text('5'), findsWidgets);

      await tester.tap(find.byKey(const Key('target-spd-plus')));
      await tester.pumpAndSettle();

      expect(subject().spdDelta, 1);
      expect(subject().effectiveSpd, 6);
      expect(find.text('5 (+1)'), findsOneWidget);
      // Upcoming phases re-planned for SPD 6 (chart 2, 4, 6, 8, 10, 12):
      // segments after 5 become 6, 8, 10, 12; the past slot at 4 is kept.
      expect(
        subject().phaseSlots.map((slot) => slot.segment),
        [4, 6, 8, 10, 12],
      );

      await tester.tap(find.byKey(const Key('target-spd-minus')));
      await tester.tap(find.byKey(const Key('target-spd-minus')));
      await tester.pumpAndSettle();

      expect(subject().spdDelta, -1);
      expect(subject().effectiveSpd, 4);
      expect(find.text('5 (-1)'), findsOneWidget);
    });

    testWidgets('[C]lear Action releases Hold and cancels Haymakers on the '
        'actor', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 1,
          activeCombatantId: 'actor',
          combatants: [
            makeCombatant(
              id: 'actor',
              phaseSlots: [
                PhaseSlot(segment: 3, status: PhaseStatus.held),
                PhaseSlot(
                  segment: 6,
                  actionId: 'declare_haymaker',
                  actionLabel: 'Declare Haymaker',
                ),
              ],
              statusBadges: [PhaseStatus.held],
            ),
          ],
        ).copyWith(haymakerDeclarations: [
          HaymakerDeclaration.at(
            combatantId: 'actor',
            segment: 5,
            declaredTurn: 1,
          ),
        ]),
      );

      await tester.tap(find.text('[C]lear Action'));
      await tester.pumpAndSettle();

      final state = container.read(turnEngineProvider);
      // The Haymaker declaration and its markers are cancelled...
      expect(state.haymakerDeclarations, isEmpty);
      final actor = state.combatants.single;
      // ...the Hold is released back to a normal scheduled phase...
      expect(actor.phaseSlots.first.status, PhaseStatus.scheduled);
      expect(actor.statusBadges, isEmpty);
      // ...and the wind-up flags are gone, restoring normal phase markers.
      expect(
        actor.phaseSlots.map((slot) => slot.actionId),
        everyElement(isNull),
      );
    });

    testWidgets('hotkey C clears the actor\'s action state', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 1,
          activeCombatantId: 'actor',
          combatants: [
            makeCombatant(
              id: 'actor',
              phaseSlots: [PhaseSlot(segment: 3, status: PhaseStatus.held)],
              statusBadges: [PhaseStatus.held],
            ),
          ],
        ).copyWith(haymakerDeclarations: [
          HaymakerDeclaration.at(
            combatantId: 'actor',
            segment: 5,
            declaredTurn: 1,
          ),
        ]),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();

      final actor = container.read(turnEngineProvider).combatants.single;
      expect(container.read(turnEngineProvider).haymakerDeclarations, isEmpty);
      expect(actor.phaseSlots.single.status, PhaseStatus.scheduled);
      expect(actor.statusBadges, isEmpty);
    });

    testWidgets('Clear Reaction clears the target Aborted state and SPD delta',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 5,
          targetCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [
              makeSlot(segment: 8),
              makeSlot(segment: 12),
            ])
                .copyWith(spdDelta: 1)
                .copyWith(statusBadges: [PhaseStatus.aborted]),
          ],
        ),
      );

      await tester.tap(find.text('Clear Reaction'));
      await tester.pumpAndSettle();

      final target = container.read(turnEngineProvider).combatants.single;
      expect(target.spdDelta, 0);
      expect(target.statusBadges, isNot(contains(PhaseStatus.aborted)));
      // The upcoming schedule returns to the base SPD 5 chart (8, 10, 12).
      expect(
        target.phaseSlots.map((slot) => slot.segment),
        [8, 10, 12],
      );
      expect(find.text('5'), findsWidgets);
    });
  });
}
