import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/presentation/state/matrix_ui_state.dart';
import 'package:herotrak/presentation/state/turn_engine_notifier.dart';
import 'package:herotrak/presentation/views/initiative_matrix_screen.dart';
import 'package:herotrak/presentation/widgets/active_combatant_panel.dart';
import 'package:herotrak/presentation/widgets/matrix_grid.dart';
import 'package:herotrak/presentation/widgets/target_combatant_panel.dart';

PhaseSlot makeSlot({
  int segment = 1,
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
  List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
}) {
  return Combatant(
    id: id,
    name: name,
    dex: dex,
    ego: ego,
    spd: 5,
    stun: 40,
    end: 20,
    body: 10,
    phaseSlots: phaseSlots,
  );
}

TurnState makeTurnState({
  int turnNumber = 1,
  int activeSegment = 1,
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

/// Pumps the full [InitiativeMatrixScreen] with the engine seeded from
/// [initial] and returns the backing [ProviderContainer].
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

Combatant subjectOf(ProviderContainer container, String id) {
  return container
      .read(turnEngineProvider)
      .combatants
      .firstWhere((combatant) => combatant.id == id);
}

void main() {
  group('screen assembly', () {
    testWidgets('renders control bar, matrix grid, and dual bottom panels',
        (tester) async {
      await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 5,
          activeCombatantId: 'c1',
          targetCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', name: 'Hero One'),
          ],
        ),
      );

      expect(find.byType(MatrixGrid), findsOneWidget);
      expect(find.byType(ActiveCombatantPanel), findsOneWidget);
      expect(find.byType(TargetCombatantPanel), findsOneWidget);

      // Top control bar: title, counters, compact two-line phase controls.
      expect(find.text('HeroTrak'), findsOneWidget);
      expect(find.text('Turn 1'), findsOneWidget);
      expect(find.text('Segment 5'), findsOneWidget);
      expect(find.text('Prev'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Phase'), findsNWidgets(2));
      expect(find.text('[N]ew Combatant'), findsOneWidget);

      // 15-column matrix is present (Post-12 marks the last column).
      expect(find.text('Post-12'), findsOneWidget);
      expect(find.byType(MatrixCell), findsNWidgets(kMatrixColumnCount));

      // Initiative actions on the Actor panel, reaction on the Target panel.
      expect(find.text('Declare Hay[M]aker'), findsOneWidget);
      expect(find.text('Interrupt with [H]old'), findsOneWidget);
      expect(find.text('[A]bort to Defensive Action'), findsOneWidget);
    });

    testWidgets('prev and next phase buttons walk the timeline phases',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 1, activeCombatantId: 'x', combatants: [
          makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 1)]),
          makeCombatant(
            id: 'y',
            dex: 20,
            phaseSlots: [makeSlot(segment: 5)],
          ),
        ]),
      );

      await tester.tap(find.byKey(const Key('next-step-button')));
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).activeSegment, 5);
      expect(container.read(turnEngineProvider).activeCombatantId, 'y');

      await tester.tap(find.byKey(const Key('previous-step-button')));
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).activeSegment, 1);
      expect(container.read(turnEngineProvider).activeCombatantId, 'x');
    });
  });

  group('hotkeys', () {
    testWidgets('space advances the segment', (tester) async {
      final container = await pumpScreen(tester, makeTurnState(activeSegment: 1));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(container.read(turnEngineProvider).activeSegment, 2);
    });

    testWidgets('down and up arrows move the target cursor without touching '
        'the timeline', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 1, combatants: [
          makeCombatant(id: 'c1', name: 'Hero One'),
          makeCombatant(id: 'c2', name: 'Villain Two'),
        ]),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c1');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c2');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // wrap
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c1');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // wrap back
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).targetCombatantId, 'c2');

      // Target navigation must NOT alter the turn clock or the actor.
      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 1);
      expect(state.turnNumber, 1);
      expect(state.activeCombatantId, isNull);
    });

    testWidgets('left and right arrows traverse the active segment queue',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(
            id: 'slow',
            dex: 10,
            phaseSlots: [makeSlot(segment: 6)],
          ),
          makeCombatant(
            id: 'fast',
            dex: 30,
            phaseSlots: [makeSlot(segment: 6)],
          ),
          makeCombatant(
            id: 'mental',
            dex: 5,
            ego: 20,
            phaseSlots: [makeSlot(segment: 6, isMental: true)],
          ),
        ]),
      );

      // Resolution order: mental (EGO 20), then physical by DEX (fast, slow).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).activeCombatantId, 'mental');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).activeCombatantId, 'fast');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).activeCombatantId, 'mental');

      // Queue traversal never touches the segment cursor either.
      expect(container.read(turnEngineProvider).activeSegment, 6);
    });

    testWidgets('right arrow jumps to the next phase, skipping empty '
        'segments and moving the highlight', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 1, activeCombatantId: 'x', combatants: [
          makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 1)]),
          makeCombatant(
            id: 'y',
            dex: 20,
            phaseSlots: [makeSlot(segment: 5)],
          ),
          makeCombatant(
            id: 'z',
            dex: 10,
            phaseSlots: [makeSlot(segment: 5)],
          ),
        ]),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Segments 2-4 are empty: the walk lands on Segment 5's first phase.
      final jumped = container.read(turnEngineProvider);
      expect(jumped.activeSegment, 5);
      expect(jumped.activeCombatantId, 'y');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final next = container.read(turnEngineProvider);
      expect(next.activeSegment, 5);
      expect(next.activeCombatantId, 'z');
    });

    testWidgets('left arrow jumps backward through active timeline phases',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 5, activeCombatantId: 'z', combatants: [
          makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 1)]),
          makeCombatant(
            id: 'y',
            dex: 20,
            phaseSlots: [makeSlot(segment: 5)],
          ),
          makeCombatant(
            id: 'z',
            dex: 10,
            phaseSlots: [makeSlot(segment: 5)],
          ),
        ]),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).activeCombatantId, 'y');

      // Jump back over empty Segments 2-4 to Segment 1's only phase.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      final jumped = container.read(turnEngineProvider);
      expect(jumped.activeSegment, 1);
      expect(jumped.activeCombatantId, 'x');
    });

    testWidgets('right arrow steps onto Post-12 before the turn-advance '
        'confirmation', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(turnNumber: 1, activeSegment: 12, activeCombatantId: 'x', combatants: [
          makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 12)]),
          makeCombatant(id: 'w', phaseSlots: [makeSlot(segment: 1)]),
        ]),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // The scan passed Segment 12: focus steps onto the Post-12 column
      // immediately, without any confirmation.
      expect(find.text('Start Next Turn?'), findsNothing);
      expect(container.read(selectedColumnProvider), 'post12');
      expect(container.read(turnEngineProvider).turnNumber, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // With Post-12 selected the confirmation appears; nothing moves
      // until confirmed.
      expect(find.text('Start Next Turn?'), findsOneWidget);
      expect(container.read(turnEngineProvider).turnNumber, 1);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).turnNumber, 1);
      expect(container.read(selectedColumnProvider), 'post12');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 2);
      expect(state.activeSegment, 1);
      expect(state.activeCombatantId, 'w');
      // The Post-12 selection clears with the turn rollover.
      expect(container.read(selectedColumnProvider), isNull);
    });
  });

  group('brand menu', () {
    testWidgets('contains New Encounter, Save and Load native options',
        (tester) async {
      await pumpScreen(tester, makeTurnState());

      await tester.tap(find.byKey(const Key('brand-menu')));
      await tester.pumpAndSettle();

      expect(find.text('New Encounter...'), findsOneWidget);
      expect(find.text('Save Encounter...'), findsOneWidget);
      expect(find.text('Load Encounter...'), findsOneWidget);
      // The redundant text-area options are pruned.
      expect(find.text('Export Encounter'), findsNothing);
      expect(find.text('Import Encounter'), findsNothing);
    });

    testWidgets('New Encounter... asks for confirmation and clears the '
        'encounter', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          turnNumber: 3,
          activeSegment: 7,
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 7)]),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('brand-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Encounter...'));
      await tester.pumpAndSettle();

      // The confirmation dialog pops; declining keeps the encounter.
      expect(
        find.text(
          'Clear current encounter? All unsaved combatants will be removed.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).turnNumber, 3);
      expect(container.read(turnEngineProvider).combatants, hasLength(1));

      // Confirming resets to Turn 1 / Segment 1 with no combatants.
      await tester.tap(find.byKey(const Key('brand-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Encounter...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 1);
      expect(state.activeSegment, 1);
      expect(state.combatants, isEmpty);
    });
  });

  group('action hotkeys', () {
    testWidgets('KeyA aborts the Target (Actee) first', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 1,
          activeCombatantId: 'actor',
          targetCombatantId: 'target',
          combatants: [
            makeCombatant(id: 'actor', phaseSlots: [makeSlot(segment: 3)]),
            makeCombatant(id: 'target', phaseSlots: [makeSlot(segment: 1)]),
          ],
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();

      // The reaction lands on the target...
      final target = subjectOf(container, 'target');
      expect(target.phaseSlots.single.status, PhaseStatus.spent);
      expect(target.statusBadges, contains(PhaseStatus.aborted));
      // ...never on the actor, whose timeline cursor is untouched.
      expect(
        subjectOf(container, 'actor').phaseSlots.single.status,
        PhaseStatus.scheduled,
      );
      expect(container.read(turnEngineProvider).activeCombatantId, 'actor');
    });

    testWidgets('KeyH executes Interrupt with [H]old', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 1, activeCombatantId: 'c1', combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 1)]),
        ]),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();

      final subject = subjectOf(container, 'c1');
      expect(subject.phaseSlots.single.status, PhaseStatus.held);
      expect(subject.statusBadges, contains(PhaseStatus.held));
    });

    testWidgets('KeyM declares the Haymaker on the Actor, not the Target',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 1,
          activeCombatantId: 'actor',
          targetCombatantId: 'target',
          combatants: [
            makeCombatant(id: 'actor', phaseSlots: [makeSlot(segment: 1)]),
            makeCombatant(id: 'target', phaseSlots: [makeSlot(segment: 1)]),
          ],
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();

      final slot = subjectOf(container, 'actor').phaseSlots.single;
      expect(slot.actionId, 'declare_haymaker');
      // The base slot is not relocated: it keeps its schedule at Segment 1
      // and retains the wind-up flag.
      expect(slot.segment, 1);
      expect(slot.originalSegment, 1);
      // The decoupled resolution marker schedules Segment + 1 for the actor.
      final state = container.read(turnEngineProvider);
      expect(state.haymakerDeclarations.single.combatantId, 'actor');
      expect(state.haymakerDeclarations.single.resolutionSegment, 2);
    });

    testWidgets('invalid hotkey actions are ignored without errors',
        (tester) async {
      final container = await pumpScreen(tester, makeTurnState(activeSegment: 1));

      // No subject combatant: abort must be a silent no-op, not a crash.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(container.read(turnEngineProvider), makeTurnState(activeSegment: 1));
    });
  });

  group('bottom panels', () {
    testWidgets('target panel abort clears the target\'s pending Haymaker '
        'without moving the timeline cursor', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          turnNumber: 1,
          activeSegment: 6,
          activeCombatantId: 'actor',
          targetCombatantId: 'target',
          combatants: [
            makeCombatant(id: 'actor', phaseSlots: [makeSlot(segment: 9)]),
            makeCombatant(id: 'target', phaseSlots: [makeSlot(segment: 8)]),
          ],
        ).copyWith(haymakerDeclarations: [
          HaymakerDeclaration.at(
            combatantId: 'target',
            segment: 2,
            declaredTurn: 1,
          ),
        ]),
      );

      await tester.tap(find.text('[A]bort to Defensive Action'));
      await tester.pumpAndSettle();

      final state = container.read(turnEngineProvider);
      // The target's pending Haymaker is cleared (both markers)...
      expect(state.haymakerDeclarations, isEmpty);
      final target = subjectOf(container, 'target');
      expect(target.phaseSlots.single.status, PhaseStatus.spent);
      expect(target.statusBadges, contains(PhaseStatus.aborted));
      // ...the actor is untouched and the timeline cursor stays put.
      expect(
        subjectOf(container, 'actor').phaseSlots.single.status,
        PhaseStatus.scheduled,
      );
      expect(state.activeCombatantId, 'actor');
      expect(state.activeSegment, 6);
    });

    testWidgets('actor panel hold button puts the actor\'s phase on hold',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 1,
          activeCombatantId: 'actor',
          targetCombatantId: 'target',
          combatants: [
            makeCombatant(id: 'actor', phaseSlots: [makeSlot(segment: 1)]),
            makeCombatant(id: 'target', phaseSlots: [makeSlot(segment: 1)]),
          ],
        ),
      );

      await tester.tap(find.text('Interrupt with [H]old'));
      await tester.pumpAndSettle();

      expect(
        subjectOf(container, 'actor').phaseSlots.single.status,
        PhaseStatus.held,
      );
      expect(
        subjectOf(container, 'target').phaseSlots.single.status,
        PhaseStatus.scheduled,
      );
    });

    testWidgets('actor panel haymaker button declares on the actor',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 1,
          activeCombatantId: 'actor',
          targetCombatantId: 'target',
          combatants: [
            makeCombatant(id: 'actor', phaseSlots: [makeSlot(segment: 1)]),
            makeCombatant(id: 'target', phaseSlots: [makeSlot(segment: 1)]),
          ],
        ),
      );

      await tester.tap(find.text('Declare Hay[M]aker'));
      await tester.pumpAndSettle();

      expect(
        container
            .read(turnEngineProvider)
            .haymakerDeclarations
            .single
            .combatantId,
        'actor',
      );
    });
  });

  group('turn transition', () {
    testWidgets('next phase steps onto Post-12, then asks to start the '
        'next turn', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 12,
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 12)]),
          ],
        ),
      );

      // First press: the turn's phases are exhausted → Post-12 focus,
      // no dialog.
      await tester.tap(find.byKey(const Key('next-step-button')));
      await tester.pumpAndSettle();
      expect(find.text('Start Next Turn?'), findsNothing);
      expect(container.read(selectedColumnProvider), 'post12');
      expect(container.read(turnEngineProvider).turnNumber, 1);
      expect(container.read(turnEngineProvider).activeSegment, 12);

      // Second press: the confirmation dialog appears.
      await tester.tap(find.byKey(const Key('next-step-button')));
      await tester.pumpAndSettle();
      expect(find.text('Start Next Turn?'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(container.read(turnEngineProvider).turnNumber, 1);

      // Declining keeps the tracker at Post-12.
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(container.read(turnEngineProvider).turnNumber, 1);
      expect(container.read(selectedColumnProvider), 'post12');

      // Confirming starts the next turn and clears the Post-12 selection.
      await tester.tap(find.byKey(const Key('next-step-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(container.read(turnEngineProvider).turnNumber, 2);
      expect(container.read(turnEngineProvider).activeSegment, 1);
      expect(container.read(selectedColumnProvider), isNull);
    });

    testWidgets('hotkey Space at segment 12 triggers the confirmation and '
        'clears transient state', (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          activeSegment: 12,
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [
              makeSlot(segment: 3, status: PhaseStatus.held),
              makeSlot(segment: 12),
            ]),
          ],
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Start Next Turn?'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      final state = container.read(turnEngineProvider);
      expect(state.turnNumber, 2);
      expect(state.activeSegment, 1);
      // The unspent expired held interruption does not bleed into the new
      // turn.
      expect(
        state.combatants.single.phaseSlots.first.status,
        PhaseStatus.scheduled,
      );
    });

    testWidgets('advancing within the turn needs no confirmation',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 6, activeCombatantId: 'y', combatants: [
          makeCombatant(id: 'y', dex: 20, phaseSlots: [makeSlot(segment: 8)]),
        ]),
      );

      await tester.tap(find.byKey(const Key('next-step-button')));
      await tester.pumpAndSettle();

      expect(find.text('Start Next Turn?'), findsNothing);
      expect(container.read(turnEngineProvider).activeSegment, 8);
    });

    testWidgets('prev phase backs off Post-12 and resumes the normal flow',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(
          turnNumber: 1,
          activeSegment: 12,
          activeCombatantId: 'x',
          combatants: [
            makeCombatant(id: 'x', phaseSlots: [makeSlot(segment: 12)]),
            makeCombatant(id: 'w', phaseSlots: [makeSlot(segment: 1)]),
          ],
        ),
      );

      // Stage onto Post-12 via the exhausted timeline walk.
      await tester.tap(find.byKey(const Key('next-step-button')));
      await tester.pumpAndSettle();
      expect(container.read(selectedColumnProvider), 'post12');

      // Prev Phase disengages Post-12 and lands on the Turn's last phase.
      await tester.tap(find.byKey(const Key('previous-step-button')));
      await tester.pumpAndSettle();
      expect(container.read(selectedColumnProvider), isNull);
      expect(container.read(turnEngineProvider).activeSegment, 12);
      expect(container.read(turnEngineProvider).activeCombatantId, 'x');

      // The next Next Phase press resumes the standard flow (silently
      // re-staging Post-12) instead of re-triggering the turn prompt.
      await tester.tap(find.byKey(const Key('next-step-button')));
      await tester.pumpAndSettle();
      expect(find.text('Start Next Turn?'), findsNothing);
      expect(container.read(selectedColumnProvider), 'post12');
    });
  });
}