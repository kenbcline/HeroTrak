import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/actions/actions.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/presentation/state/matrix_ui_state.dart';
import 'package:herotrak/presentation/state/turn_engine_notifier.dart';
import 'package:herotrak/presentation/widgets/matrix_grid.dart';

PhaseSlot makeSlot({
  int segment = 6,
  int? originalSegment,
  PhaseStatus status = PhaseStatus.scheduled,
  bool isMental = false,
}) {
  return PhaseSlot(
    segment: segment,
    originalSegment: originalSegment,
    status: status,
    isMental: isMental,
  );
}

Combatant makeCombatant({
  String id = 'c1',
  String name = 'Hero One',
  int dex = 18,
  int ego = 10,
  int spd = 5,
  bool isNpc = false,
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
    isNpc: isNpc,
    phaseSlots: phaseSlots,
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

/// Pumps [MatrixGrid] with the engine seeded from [initial] and returns the
/// backing [ProviderContainer] for state assertions.
Future<ProviderContainer> pumpMatrix(WidgetTester tester, TurnState initial) async {
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
      child: const MaterialApp(home: Scaffold(body: MatrixGrid())),
    ),
  );
  return container;
}

void main() {
  group('matrix structure', () {
    testWidgets(
        'renders the 14 columns: combatant header, segments 1-12, Post-12',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 1, combatants: [
          makeCombatant(id: 'c1', name: 'Hero One'),
        ]),
      );

      expect(find.text('Combatant'), findsOneWidget);
      for (var segment = 1; segment <= 12; segment++) {
        expect(
          find.text('$segment'),
          findsOneWidget,
          reason: 'segment $segment header',
        );
      }
      expect(find.text('Post-12'), findsOneWidget);
      // One cell per column on the combatant row: 14 total.
      expect(find.byType(MatrixCell), findsNWidgets(kMatrixColumnCount));
    });

    testWidgets('renders one row per combatant with its name', (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 1, combatants: [
          makeCombatant(id: 'c1', name: 'Hero One'),
          makeCombatant(id: 'c2', name: 'Villain Two'),
          makeCombatant(id: 'c3', name: 'Sidekick Three'),
        ]),
      );

      expect(find.text('Hero One'), findsOneWidget);
      expect(find.text('Villain Two'), findsOneWidget);
      expect(find.text('Sidekick Three'), findsOneWidget);
      expect(find.byKey(const Key('matrix-row-c1')), findsOneWidget);
      expect(find.byKey(const Key('matrix-row-c2')), findsOneWidget);
      expect(find.byKey(const Key('matrix-row-c3')), findsOneWidget);
      // 3 rows x 14 columns.
      expect(find.byType(MatrixCell), findsNWidgets(3 * kMatrixColumnCount));
    });

    testWidgets('shows the reserved Post-12 cell on every row', (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 12, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 12)]),
        ]),
      );

      expect(find.byKey(const Key('matrix-cell-c1-post12')), findsOneWidget);
      expect(find.byKey(const Key('matrix-cell-c1-12')), findsOneWidget);
      // The Segment-12 slot renders in segment 12, not in Post-12.
      expect(
        find.descendant(
          of: find.byKey(const Key('matrix-cell-c1-post12')),
          matching: find.byType(MatrixTile),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('matrix-cell-c1-12')),
          matching: find.byType(MatrixTile),
        ),
        findsOneWidget,
      );
    });
  });

  group('active segment highlight', () {
    testWidgets('styles the active segment column with a distinct background',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1'),
        ]),
      );

      Color? cellColor(String key) =>
          tester.widget<Container>(find.byKey(Key(key))).color;

      expect(cellColor('matrix-cell-c1-6'), kActiveSegmentColumnColor);
      expect(cellColor('matrix-cell-c1-5'), isNull);
      expect(cellColor('matrix-column-header-6'), kActiveSegmentColumnColor);
      // Non-highlighted headers carry the dark high-contrast background.
      expect(cellColor('matrix-column-header-5'), kMatrixHeaderColor);
    });
  });

  group('phase slot tiles', () {
    Future<ProviderContainer> pumpStatusMatrix(
        WidgetTester tester) async {
      return pumpMatrix(
        tester,
        makeTurnState(activeSegment: 1, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 1),
            makeSlot(segment: 2, status: PhaseStatus.active),
            makeSlot(segment: 3, status: PhaseStatus.held),
            makeSlot(segment: 4, status: PhaseStatus.aborted),
            makeSlot(segment: 5, status: PhaseStatus.spent),
            makeSlot(segment: 6, status: PhaseStatus.delayed),
          ]),
        ]),
      );
    }

    BoxDecoration tileDecoration(WidgetTester tester, Key tileKey) {
      final container = tester.widget<Container>(
        find
            .descendant(of: find.byKey(tileKey), matching: find.byType(Container))
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('scheduled renders a standard indicator tile', (tester) async {
      await pumpStatusMatrix(tester);

      expect(find.text('●'), findsOneWidget);
      expect(
        tileDecoration(tester, const Key('matrix-tile-c1-1-0')).color,
        kScheduledTileColor,
      );
    });

    testWidgets('active renders a glowing high-contrast tile', (tester) async {
      await pumpStatusMatrix(tester);

      expect(find.text('★'), findsOneWidget);
      final decoration = tileDecoration(tester, const Key('matrix-tile-c1-2-0'));
      expect(decoration.color, kActiveTileColor);
      expect(decoration.boxShadow, isNotEmpty);
    });

    testWidgets('held renders a distinct [H] badge', (tester) async {
      await pumpStatusMatrix(tester);

      expect(find.text('[H]'), findsOneWidget);
      expect(
        tileDecoration(tester, const Key('matrix-tile-c1-3-0')).color,
        kHeldTileColor,
      );
    });

    testWidgets('aborted and spent render greyed strikethrough tiles',
        (tester) async {
      await pumpStatusMatrix(tester);

      final aborted = tester.widget<Text>(find.text('⊘'));
      final spent = tester.widget<Text>(find.text('×'));
      expect(aborted.style!.decoration, TextDecoration.lineThrough);
      expect(spent.style!.decoration, TextDecoration.lineThrough);
      expect(
        tileDecoration(tester, const Key('matrix-tile-c1-4-0')).color,
        kSpentTileColor,
      );
      expect(
        tileDecoration(tester, const Key('matrix-tile-c1-5-0')).color,
        kSpentTileColor,
      );
    });

    testWidgets('delayed renders a shifted indicator tile', (tester) async {
      await pumpStatusMatrix(tester);

      expect(find.text('⇢'), findsOneWidget);

      // The delayed tile sits exactly 10px right of the cell's leading edge
      // compared to a standard (scheduled) tile in an identical cell.
      double tileDx(Key tileKey, String column) {
        final cell = tester.getTopLeft(
          find.byKey(Key('matrix-cell-c1-$column')),
        );
        final tile = tester.getTopLeft(
          find
              .descendant(
                of: find.byKey(tileKey),
                matching: find.byType(Container),
              )
              .first,
        );
        return tile.dx - cell.dx;
      }

      expect(
        tileDx(const Key('matrix-tile-c1-6-0'), '6') -
            tileDx(const Key('matrix-tile-c1-1-0'), '1'),
        10,
      );
    });
  });

  group('row selection', () {
    testWidgets('clicking a row targets the combatant (Actee)', (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', name: 'Hero One'),
          makeCombatant(id: 'c2', name: 'Villain Two'),
        ]),
      );

      await tester.tap(find.byKey(const Key('matrix-row-c2')));
      await tester.pump();

      // Row clicks drive the Target cursor — the Actor is driven
      // exclusively by timeline phase focus. The target highlight is
      // isolated to Column 1; the row background is left untouched.
      expect(container.read(turnEngineProvider).targetCombatantId, 'c2');
      expect(container.read(turnEngineProvider).activeCombatantId, isNull);
      final row = tester.widget<Container>(
        find.byKey(const Key('matrix-row-c2')),
      );
      expect((row.decoration! as BoxDecoration).color, isNull);
      expect(
        tester.widget<Container>(find.byKey(const Key('target-column-c2'))).color,
        kTargetRowColor,
      );
      // Other rows' Column 1 stays unhighlighted.
      expect(
        tester.widget<Container>(find.byKey(const Key('target-column-c1'))).color,
        isNull,
      );
    });

    testWidgets('the Target column renders status icons and targets on click',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1'),
          makeCombatant(id: 'c2').copyWith(status: CombatantStatus.knockedOut),
        ]),
      );

      // Column 1 renders each combatant's status icon...
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('KO'), findsOneWidget);

      await tester.tap(find.byKey(const Key('target-column-c1')));
      await tester.pump();

      expect(container.read(turnEngineProvider).targetCombatantId, 'c1');
    });

    testWidgets('right-clicking a row sets the targeted combatant',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', name: 'Hero One'),
          makeCombatant(id: 'c2', name: 'Villain Two'),
        ]),
      );

      await tester.tap(
        find.byKey(const Key('matrix-row-c2')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();

      expect(container.read(turnEngineProvider).targetCombatantId, 'c2');
      expect(container.read(turnEngineProvider).activeCombatantId, isNull);
      // The highlight lands on Column 1 only, never the row background.
      final row = tester.widget<Container>(
        find.byKey(const Key('matrix-row-c2')),
      );
      expect((row.decoration! as BoxDecoration).color, isNull);
      expect(
        tester.widget<Container>(find.byKey(const Key('target-column-c2'))).color,
        kTargetRowColor,
      );
    });
  });

  group('post-12 column selection', () {
    testWidgets('clicking the Post-12 header selects the column',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 6)]),
        ]),
      );

      await tester.tap(find.byKey(const Key('matrix-column-header-post12')));
      await tester.pump();

      expect(container.read(selectedColumnProvider), 'post12');
      Color? cellColor(String key) =>
          tester.widget<Container>(find.byKey(Key(key))).color;
      expect(cellColor('matrix-column-header-post12'), kSelectedColumnColor);
      expect(cellColor('matrix-cell-c1-post12'), kSelectedColumnColor);
      // Neither the active segment column nor others change.
      expect(cellColor('matrix-cell-c1-6'), kActiveSegmentColumnColor);
      expect(cellColor('matrix-cell-c1-5'), isNull);
    });

    testWidgets('clicking a Post-12 body cell selects the column without '
        'selecting the row', (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', name: 'Hero One'),
        ]),
      );

      await tester.tap(find.byKey(const Key('matrix-cell-c1-post12')));
      await tester.pump();

      expect(container.read(selectedColumnProvider), 'post12');
      // The Post-12 cell click selects the column, not the combatant row.
      expect(container.read(turnEngineProvider).activeCombatantId, isNull);
    });

    testWidgets('no column is selected initially', (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1'),
        ]),
      );

      expect(container.read(selectedColumnProvider), isNull);
      final cell = tester.widget<Container>(
        find.byKey(const Key('matrix-cell-c1-post12')),
      );
      expect(cell.color, isNull);
    });
  });

  group('segment header selection', () {
    testWidgets('clicking a segment header jumps the active segment',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(turnNumber: 2, activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 2)]),
        ]),
      );

      await tester.tap(find.byKey(const Key('matrix-column-header-2')));
      await tester.pump();

      final state = container.read(turnEngineProvider);
      expect(state.activeSegment, 2);
      // Jumping never wraps into a new turn.
      expect(state.turnNumber, 2);

      // The highlight follows the jump: clicked column on, old column off.
      Color? cellColor(String key) =>
          tester.widget<Container>(find.byKey(Key(key))).color;
      expect(cellColor('matrix-column-header-2'), kActiveSegmentColumnColor);
      expect(cellColor('matrix-cell-c1-2'), kActiveSegmentColumnColor);
      expect(cellColor('matrix-cell-c1-6'), isNull);
      expect(cellColor('matrix-column-header-6'), kMatrixHeaderColor);
    });

    testWidgets('every segment header is clickable', (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 1, combatants: [makeCombatant(id: 'c1')]),
      );

      for (var segment = 1; segment <= 12; segment++) {
        await tester.tap(find.byKey(Key('matrix-column-header-$segment')));
        await tester.pump();
        expect(container.read(turnEngineProvider).activeSegment, segment);
      }
    });

    testWidgets('clicking a segment header clears the Post-12 selection',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [makeCombatant(id: 'c1')]),
      );

      await tester.tap(find.byKey(const Key('matrix-column-header-post12')));
      await tester.pump();
      expect(container.read(selectedColumnProvider), 'post12');

      await tester.tap(find.byKey(const Key('matrix-column-header-4')));
      await tester.pump();

      expect(container.read(selectedColumnProvider), isNull);
      final post12 = tester.widget<Container>(
        find.byKey(const Key('matrix-cell-c1-post12')),
      );
      expect(post12.color, isNull);
    });
  });

  group('haymaker markers', () {
    testWidgets('renders the wind-up at N and the Strikes marker at N+1',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 5, haymakerDeclarations: [
          HaymakerDeclaration.at(
            combatantId: 'c1',
            segment: 5,
            declaredTurn: 1,
          ),
        ], combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 5)]),
        ]),
      );

      // Wind-up on the originating Segment...
      expect(find.text('[M]'), findsOneWidget);
      expect(find.byKey(const Key('haymaker-windup-c1-5')), findsOneWidget);
      // ...and the distinct "Strikes/Resolves" tile on N+1.
      expect(find.text('Strikes'), findsOneWidget);
      expect(find.byKey(const Key('haymaker-resolution-c1-6')), findsOneWidget);
      // The base phase tile is untouched alongside the wind-up.
      expect(find.byKey(const Key('matrix-tile-c1-5-0')), findsOneWidget);
    });

    testWidgets('markers are scoped to their own combatant row', (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 5, haymakerDeclarations: [
          HaymakerDeclaration.at(
            combatantId: 'c1',
            segment: 5,
            declaredTurn: 1,
          ),
        ], combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 5)]),
          makeCombatant(
            id: 'c2',
            name: 'Bystander',
            phaseSlots: [makeSlot(segment: 5)],
          ),
        ]),
      );

      expect(find.byKey(const Key('haymaker-windup-c1-5')), findsOneWidget);
      expect(find.byKey(const Key('haymaker-windup-c2-5')), findsNothing);
      expect(find.byKey(const Key('haymaker-resolution-c2-6')), findsNothing);
    });

    testWidgets('a segment-12 haymaker defers its Strikes marker to the '
        'next turn', (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(
          turnNumber: 1,
          activeSegment: 12,
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 12,
              declaredTurn: 1,
            ),
          ],
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 12)]),
          ],
        ),
      );

      // During the declaring turn the wind-up shows at 12 but the wrapped
      // resolution does NOT render on Segment 1 of the current turn.
      expect(find.byKey(const Key('haymaker-windup-c1-12')), findsOneWidget);
      expect(
        find.byKey(const Key('haymaker-resolution-c1-1')),
        findsNothing,
      );

      container.read(turnEngineProvider.notifier).startNextTurn();
      await tester.pump();

      // Turn 2: the wind-up is gone and the "Strikes" marker appears on
      // Segment 1 of the new Turn.
      expect(find.byKey(const Key('haymaker-windup-c1-12')), findsNothing);
      expect(find.text('Strikes'), findsOneWidget);
      expect(
        find.byKey(const Key('haymaker-resolution-c1-1')),
        findsOneWidget,
      );
      // The base phase slot is neither corrupted nor orphaned: still
      // scheduled at Segment 12 for the new Turn.
      final slot = container
          .read(turnEngineProvider)
          .combatants
          .single
          .phaseSlots
          .single;
      expect(slot.segment, 12);
      expect(slot.status, PhaseStatus.scheduled);
    });

    testWidgets('stale markers clear across the turn reset without '
        'corrupting phase slots', (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(
          turnNumber: 1,
          activeSegment: 12,
          haymakerDeclarations: [
            HaymakerDeclaration.at(
              combatantId: 'c1',
              segment: 5,
              declaredTurn: 1,
            ),
          ],
          combatants: [
            makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 5)]),
          ],
        ),
      );

      expect(find.byKey(const Key('haymaker-windup-c1-5')), findsOneWidget);
      expect(find.byKey(const Key('haymaker-resolution-c1-6')), findsOneWidget);

      container.read(turnEngineProvider.notifier).startNextTurn();
      await tester.pump();

      // Markers from the previous turn are gone...
      expect(find.text('[M]'), findsNothing);
      expect(find.text('Strikes'), findsNothing);
      // ...and the base phase slot is neither corrupted nor orphaned: it is
      // still scheduled at Segment 5 for the new Turn.
      final slot = container
          .read(turnEngineProvider)
          .combatants
          .single
          .phaseSlots
          .single;
      expect(slot.segment, 5);
      expect(slot.status, PhaseStatus.scheduled);
    });

    testWidgets('aborting clears the Strikes marker of a pending resolution',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(
          turnNumber: 2,
          activeSegment: 1,
          activeCombatantId: 'c1',
          haymakerDeclarations: [
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

      // The deferred "Strikes" marker is on Segment 1 of Turn 2...
      expect(find.text('Strikes'), findsOneWidget);
      expect(
        find.byKey(const Key('haymaker-resolution-c1-1')),
        findsOneWidget,
      );

      container.read(turnEngineProvider.notifier).executeAction(
            ActionDefinition.abortToDefensiveAction,
          );
      await tester.pump();

      // ...and the abort consumes it: both markers are gone.
      expect(find.text('Strikes'), findsNothing);
      expect(find.text('[M]'), findsNothing);
    });
  });

  group('visual polish', () {
    testWidgets('tints NPC rows pale red and leaves PC rows untouched',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'pc', name: 'Hero'),
          makeCombatant(id: 'npc', name: 'Goblin', isNpc: true),
        ]),
      );

      Color? rowColor(String id) => (tester
              .widget<Container>(find.byKey(Key('matrix-row-$id')))
              .decoration! as BoxDecoration)
          .color;

      expect(rowColor('npc'), kNpcRowColor);
      expect(rowColor('pc'), isNull);
    });

    testWidgets('target highlight is isolated to Column 1 over the NPC tint',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'npc', name: 'Goblin', isNpc: true),
        ]),
      );

      await tester.tap(find.byKey(const Key('matrix-row-npc')));
      await tester.pump();

      // The row keeps its NPC tint; only Column 1 shows the target
      // selection highlight.
      final row =
          tester.widget<Container>(find.byKey(const Key('matrix-row-npc')));
      expect((row.decoration! as BoxDecoration).color, kNpcRowColor);
      expect(
        tester.widget<Container>(find.byKey(const Key('target-column-npc'))).color,
        kTargetRowColor,
      );
    });

    testWidgets('segment columns are ~10% slimmer and the name column '
        'absorbs the freed width', (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1'),
        ]),
      );

      final rowWidth =
          tester.getSize(find.byKey(const Key('matrix-row-c1'))).width;
      final nameWidth =
          tester.getSize(find.byKey(const Key('matrix-cell-c1-combatant'))).width;
      final segmentWidth =
          tester.getSize(find.byKey(const Key('matrix-cell-c1-5'))).width;

      // Each segment column holds 9/150 of the row — 10% slimmer than the
      // previous 2/30 share.
      expect(segmentWidth / rowWidth, closeTo(0.06, 0.002));
      // The name column absorbed the freed width (27/150, 3x a segment).
      expect(nameWidth / rowWidth, closeTo(0.18, 0.005));
      expect(nameWidth / segmentWidth, closeTo(3.0, 0.02));
    });

    testWidgets('header cells carry the darker high-contrast background',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [makeCombatant(id: 'c1')]),
      );

      Color? cellColor(String key) =>
          tester.widget<Container>(find.byKey(Key(key))).color;
      expect(cellColor('matrix-column-header-combatant'), kMatrixHeaderColor);
      expect(cellColor('matrix-column-header-1'), kMatrixHeaderColor);
      expect(cellColor('matrix-column-header-post12'), kMatrixHeaderColor);
      // Header text is white for contrast against the dark background.
      final label = tester.widget<Text>(find.text('Combatant'));
      expect(label.style!.color, Colors.white);
    });
  });

  group('column centering', () {
    testWidgets('headers, data cells and tiles all align to center',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 5)]),
        ]),
      );

      AlignmentGeometry? cellAlignment(String key) =>
          tester.widget<Container>(find.byKey(Key(key))).alignment;

      // Column headers...
      expect(cellAlignment('matrix-column-header-combatant'), Alignment.center);
      expect(cellAlignment('matrix-column-header-1'), Alignment.center);
      expect(cellAlignment('matrix-column-header-post12'), Alignment.center);
      // ...data cells (name, segment, Post-12)...
      expect(cellAlignment('matrix-cell-c1-combatant'), Alignment.center);
      expect(cellAlignment('matrix-cell-c1-5'), Alignment.center);
      expect(cellAlignment('matrix-cell-c1-post12'), Alignment.center);
      // ...and the symbol tiles themselves.
      final tile = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('matrix-tile-c1-5-0')),
          matching: find.byType(Container),
        ),
      );
      expect(tile.alignment, Alignment.center);
    });
  });

  group('status phase rendering', () {
    testWidgets('a stunned combatant\'s next phase renders [CLR STUN]',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 3, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [
            makeSlot(segment: 5),
            makeSlot(segment: 9),
          ]).copyWith(status: CombatantStatus.stunned),
        ]),
      );

      // Only the NEXT scheduled phase shows [CLR STUN]; the later phase
      // keeps its regular indicator.
      expect(find.text('[CLR STUN]'), findsOneWidget);
      expect(find.text('●'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('matrix-cell-c1-5')),
          matching: find.text('[CLR STUN]'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('DYING suppresses natural/Post-12 REC while KO re-enables it',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 3, combatants: [
          makeCombatant(id: 'dy', phaseSlots: [makeSlot(segment: 5)])
              .copyWith(status: CombatantStatus.dying),
          makeCombatant(id: 'ko', phaseSlots: [makeSlot(segment: 5)])
              .copyWith(status: CombatantStatus.knockedOut),
        ]),
      );

      // Dying: all natural Phase Recoveries are suppressed (no [REC]) and
      // Post-12 Recovery is replaced by the [BLEED] indicator.
      expect(
        find.descendant(
          of: find.byKey(const Key('matrix-cell-dy-5')),
          matching: find.text('[REC]'),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('post12-bleed-dy')), findsOneWidget);
      expect(find.byKey(const Key('post12-rec-dy')), findsNothing);

      // KO (stabilized/unconscious): automatic phase [REC] and Post-12
      // [REC] are restored so the character can regain STUN and wake up.
      expect(
        find.descendant(
          of: find.byKey(const Key('matrix-cell-ko-5')),
          matching: find.text('[REC]'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('post12-rec-ko')), findsOneWidget);
    });

    testWidgets('Post-12 shows [REC] while recovery is active and [BLEED] '
        'while dying', (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 3, combatants: [
          makeCombatant(id: 'ok'),
          makeCombatant(id: 'st').copyWith(status: CombatantStatus.stunned),
          makeCombatant(id: 'dy').copyWith(status: CombatantStatus.dying),
          makeCombatant(id: 'dd').copyWith(status: CombatantStatus.dead),
        ]),
      );

      expect(find.byKey(const Key('post12-rec-ok')), findsOneWidget);
      expect(find.byKey(const Key('post12-rec-st')), findsOneWidget);
      expect(find.byKey(const Key('post12-bleed-dy')), findsOneWidget);
      expect(find.byKey(const Key('post12-rec-dd')), findsNothing);
      expect(find.byKey(const Key('post12-bleed-dd')), findsNothing);
    });

    testWidgets('dead combatants grey the row and render no phase tiles',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 3, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 5)]),
        ]),
      );

      // Marking the combatant DEAD clears its phases from the row...
      container
          .read(turnEngineProvider.notifier)
          .setCombatantStatus('c1', CombatantStatus.dead);
      await tester.pump();

      // ...greys the row and leaves no phase tiles behind.
      final row =
          tester.widget<Container>(find.byKey(const Key('matrix-row-c1')));
      expect((row.decoration! as BoxDecoration).color, kDeadRowColor);
      expect(find.text('●'), findsNothing);
      expect(find.byKey(const Key('matrix-tile-c1-5-0')), findsNothing);
    });

    testWidgets('a selected dead row gets the lighter selection tint',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(
          activeSegment: 3,
          activeCombatantId: 'c1',
          combatants: [
            makeCombatant(id: 'c1').copyWith(status: CombatantStatus.dead),
          ],
        ),
      );

      Color? rowColor() => (tester
              .widget<Container>(find.byKey(const Key('matrix-row-c1')))
              .decoration! as BoxDecoration)
          .color;

      // Selected dead row: distinct lighter grey selection tint...
      expect(rowColor(), kDeadSelectedRowColor);

      // ...unselected dead rows keep the standard muted grey.
      container.read(turnEngineProvider.notifier).setActiveCombatant(null);
      await tester.pump();
      expect(rowColor(), kDeadRowColor);
    });
  });

  group('scrollbar and auto-scroll', () {
    bool isFullyVisible(WidgetTester tester, String id) {
      final viewport = tester.getRect(find.byType(MatrixGrid));
      final row = tester.getRect(find.byKey(Key('matrix-row-$id')));
      return row.top >= viewport.top && row.bottom <= viewport.bottom;
    }

    List<Combatant> manyRows() => <Combatant>[
          for (var i = 1; i <= 30; i++)
            makeCombatant(id: 'row${i.toString().padLeft(2, '0')}'),
        ];

    testWidgets('renders a visible desktop scrollbar', (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [makeCombatant(id: 'c1')]),
      );

      final scrollbar = tester.widget<Scrollbar>(
        find.descendant(
          of: find.byType(MatrixGrid),
          matching: find.byType(Scrollbar),
        ),
      );
      expect(scrollbar.thumbVisibility, isTrue);
    });

    testWidgets('target navigation auto-scrolls the row into view',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: manyRows()),
      );

      // The last row starts below the fold.
      expect(isFullyVisible(tester, 'row30'), isFalse);

      for (var i = 0; i < 30; i++) {
        container.read(turnEngineProvider.notifier).selectNextTarget();
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(container.read(turnEngineProvider).targetCombatantId, 'row30');
      expect(isFullyVisible(tester, 'row30'), isTrue);
    });

    testWidgets('active actor changes auto-scroll the actor row into view',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: manyRows()),
      );

      expect(isFullyVisible(tester, 'row30'), isFalse);

      container.read(turnEngineProvider.notifier).setActiveCombatant('row30');
      await tester.pumpAndSettle();

      expect(isFullyVisible(tester, 'row30'), isTrue);
    });

    testWidgets('the header row stays pinned and visible while scrolling',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: manyRows()),
      );

      // Scroll the rows well down the list.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      // The rows moved (the first row is now out of view)...
      expect(isFullyVisible(tester, 'row01'), isFalse);
      // ...but the header is still rendered and pinned at the top.
      final matrix = tester.getRect(find.byType(MatrixGrid));
      final header = tester.getRect(
        find.byKey(const Key('matrix-column-header-combatant')),
      );
      expect(find.byKey(const Key('matrix-column-header-combatant')),
          findsOneWidget);
      expect(header.top, closeTo(matrix.top, 0.01));
      expect(header.bottom, lessThanOrEqualTo(matrix.bottom));
    });

    testWidgets('auto-scrolled rows land below the pinned header',
        (tester) async {
      final container = await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: manyRows()),
      );

      for (var i = 0; i < 30; i++) {
        container.read(turnEngineProvider.notifier).selectNextTarget();
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final header = tester.getRect(
        find.byKey(const Key('matrix-column-header-combatant')),
      );
      final row = tester.getRect(find.byKey(const Key('matrix-row-row30')));
      // The row lands cleanly below the pinned header bounds.
      expect(row.top, greaterThanOrEqualTo(header.bottom));
      expect(isFullyVisible(tester, 'row30'), isTrue);
    });

    testWidgets('pinned header columns stay aligned with the data columns',
        (tester) async {
      await pumpMatrix(
        tester,
        makeTurnState(activeSegment: 6, combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 5)]),
        ]),
      );

      final columns = <String, String>{
        'target': 'target-column-c1',
        'combatant': 'matrix-cell-c1-combatant',
        '1': 'matrix-cell-c1-1',
        '5': 'matrix-cell-c1-5',
        '12': 'matrix-cell-c1-12',
        'post12': 'matrix-cell-c1-post12',
      };
      columns.forEach((column, dataKey) {
        final header =
            tester.getRect(find.byKey(Key('matrix-column-header-$column')));
        final data = tester.getRect(find.byKey(Key(dataKey)));
        expect(data.left, closeTo(header.left, 0.01), reason: '$column left');
        expect(data.width, closeTo(header.width, 0.01), reason: '$column width');
      });
    });
  });
}