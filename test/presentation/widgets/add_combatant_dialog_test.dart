import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/presentation/state/turn_engine_notifier.dart';
import 'package:herotrak/presentation/views/initiative_matrix_screen.dart';
import 'package:herotrak/presentation/widgets/add_combatant_dialog.dart';

TurnState makeTurnState({
  int turnNumber = 1,
  int activeSegment = 6,
  String? activeCombatantId,
  List<Combatant> combatants = const <Combatant>[],
}) {
  return TurnState(
    turnNumber: turnNumber,
    activeSegment: activeSegment,
    activeCombatantId: activeCombatantId,
    combatants: combatants,
  );
}

/// Pumps the full screen with the engine seeded from [initial] and returns
/// the backing [ProviderContainer].
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

Future<void> openDialog(WidgetTester tester) async {
  // The control bar scrolls horizontally on narrow surfaces; bring the
  // button into view before tapping.
  await tester.ensureVisible(find.byKey(const Key('add-combatant-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('add-combatant-button')));
  await tester.pumpAndSettle();
  expect(find.byType(AddCombatantDialog), findsOneWidget);
}

void main() {
  group('form validation', () {
    testWidgets('blank name shows an error and adds nothing', (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), '   ');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      expect(find.byType(AddCombatantDialog), findsOneWidget);
      expect(container.read(turnEngineProvider).combatants, isEmpty);
    });

    testWidgets('spd outside 1-12 is rejected', (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), 'Speedy');
      await tester.enterText(find.byKey(const Key('field-spd')), '13');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      expect(find.text('SPD must be between 1 and 12'), findsOneWidget);
      expect(container.read(turnEngineProvider).combatants, isEmpty);

      await tester.enterText(find.byKey(const Key('field-spd')), '0');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      expect(find.text('SPD must be between 1 and 12'), findsOneWidget);
      expect(container.read(turnEngineProvider).combatants, isEmpty);
    });

    testWidgets('non-numeric stat fields are rejected', (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), 'Hero One');
      await tester.enterText(find.byKey(const Key('field-dex')), 'abc');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a whole number'), findsOneWidget);
      expect(container.read(turnEngineProvider).combatants, isEmpty);
    });

    testWidgets('cancel closes the dialog without adding', (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), 'Hero One');
      await tester.tap(find.byKey(const Key('cancel-add-combatant')));
      await tester.pumpAndSettle();

      expect(find.byType(AddCombatantDialog), findsNothing);
      expect(container.read(turnEngineProvider).combatants, isEmpty);
    });
  });

  group('submitting', () {
    testWidgets('adds a combatant with correct 6e phase slots', (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), 'Goblin');
      await tester.enterText(find.byKey(const Key('field-dex')), '11');
      await tester.enterText(find.byKey(const Key('field-ego')), '8');
      await tester.enterText(find.byKey(const Key('field-spd')), '3');
      await tester.tap(find.byKey(const Key('toggle-npc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      expect(find.byType(AddCombatantDialog), findsNothing);
      final added = container.read(turnEngineProvider).combatants.single;
      expect(added.name, 'Goblin');
      expect(added.dex, 11);
      expect(added.ego, 8);
      expect(added.spd, 3);
      // The removed HP fields default to zero.
      expect(added.stun, 0);
      expect(added.end, 0);
      expect(added.body, 0);
      expect(added.isNpc, isTrue);
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

    testWidgets('unmodified fields fall back to their defaults',
        (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), 'Hero One');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      final added = container.read(turnEngineProvider).combatants.single;
      expect(added.dex, 10); // default
      expect(added.ego, 10); // default
      expect(added.spd, 3); // default
      expect(added.stun, 0);
      expect(added.end, 0);
      expect(added.body, 0);
      expect(added.isNpc, isFalse);
      // SPD 3 default still yields the chart's segments 4, 8, 12.
      expect(
        added.phaseSlots.map((slot) => slot.segment),
        [4, 8, 12],
      );
    });

    testWidgets('spd 12 generates a phase on every segment', (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), 'Speedy');
      await tester.enterText(find.byKey(const Key('field-spd')), '12');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      final added = container.read(turnEngineProvider).combatants.single;
      expect(
        added.phaseSlots.map((slot) => slot.segment),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      );
    });
  });

  group('integration', () {
    testWidgets('the toolbar button opens the dialog', (tester) async {
      await pumpScreen(tester, makeTurnState());

      expect(find.text('[N]ew Combatant'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('add-combatant-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-combatant-button')));
      await tester.pumpAndSettle();

      expect(find.byType(AddCombatantDialog), findsOneWidget);
    });

    testWidgets('hotkey N opens the dialog', (tester) async {
      await pumpScreen(tester, makeTurnState());

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();

      expect(find.byType(AddCombatantDialog), findsOneWidget);
    });
  });

  group('archetypes and faction', () {
    testWidgets('archetype pre-fills DEX/EGO/SPD and sets Is NPC',
        (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.tap(find.byKey(const Key('field-archetype')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fast Tough Goon'));
      await tester.pumpAndSettle();

      String fieldText(String key) =>
          tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
      expect(fieldText('field-dex'), '18');
      expect(fieldText('field-ego'), '10');
      expect(fieldText('field-spd'), '5');
      expect(
        tester.widget<SwitchListTile>(find.byKey(const Key('toggle-npc'))).value,
        isTrue,
      );

      await tester.enterText(find.byKey(const Key('field-name')), 'Mook');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      final added = container.read(turnEngineProvider).combatants.single;
      expect(added.name, 'Mook');
      expect(added.dex, 18);
      expect(added.ego, 10);
      expect(added.spd, 5);
      expect(added.isNpc, isTrue);
    });

    testWidgets('faction input autocompletes from existing factions',
        (tester) async {
      final container = await pumpScreen(
        tester,
        makeTurnState(combatants: [
          Combatant(
            id: 'c1',
            name: 'Hero',
            dex: 10,
            ego: 10,
            spd: 3,
            stun: 1,
            end: 1,
            body: 1,
            team: 'Red Team',
          ),
        ]),
      );
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-faction')), 'R');
      await tester.pumpAndSettle();

      // The existing faction appears in the autocomplete drop-down...
      expect(find.text('Red Team'), findsOneWidget);
      await tester.tap(find.text('Red Team'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-name')), 'Mook');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      final added = container
          .read(turnEngineProvider)
          .combatants
          .firstWhere((combatant) => combatant.name == 'Mook');
      expect(added.team, 'Red Team');
    });

    testWidgets('the SPD helper label is removed', (tester) async {
      await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      expect(find.text('Speed Chart range: 1–12'), findsNothing);
    });

    testWidgets('STUN, END, BODY fields are absent from the dialog',
        (tester) async {
      await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      expect(find.byKey(const Key('field-stun')), findsNothing);
      expect(find.byKey(const Key('field-end')), findsNothing);
      expect(find.byKey(const Key('field-body')), findsNothing);
      // The remaining fields are exactly the documented set.
      expect(find.byKey(const Key('field-name')), findsOneWidget);
      expect(find.byKey(const Key('field-faction')), findsOneWidget);
      expect(find.byKey(const Key('field-archetype')), findsOneWidget);
      expect(find.byKey(const Key('field-dex')), findsOneWidget);
      expect(find.byKey(const Key('field-ego')), findsOneWidget);
      expect(find.byKey(const Key('field-spd')), findsOneWidget);
      expect(find.byKey(const Key('toggle-npc')), findsOneWidget);
    });

    testWidgets('goon templates auto-number the name field against the '
        'encounter', (tester) async {
      await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      // Empty name: the template name is auto-numbered from 1.
      await tester.tap(find.byKey(const Key('field-archetype')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Slow Weak Goon').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('field-name')))
            .controller!
            .text,
        'Slow Weak Goon 1',
      );

      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      // The next goon of the same template gets the next number.
      await openDialog(tester);
      await tester.tap(find.byKey(const Key('field-archetype')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Slow Weak Goon').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('field-name')))
            .controller!
            .text,
        'Slow Weak Goon 2',
      );
      await tester.tap(find.byKey(const Key('cancel-add-combatant')));
      await tester.pumpAndSettle();
    });

    testWidgets('custom names are preserved when a template is selected',
        (tester) async {
      await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-name')), 'Boss Man');
      await tester.tap(find.byKey(const Key('field-archetype')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mastermind / Elite Boss').last);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('field-name')))
            .controller!
            .text,
        'Boss Man',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('field-dex')))
            .controller!
            .text,
        '23',
      );
    });

    testWidgets('faction defaults appear in the drop-down and submit',
        (tester) async {
      final container = await pumpScreen(tester, makeTurnState());
      await openDialog(tester);

      await tester.enterText(find.byKey(const Key('field-faction')), 'a');
      await tester.pumpAndSettle();

      expect(find.text('Players'), findsOneWidget);
      expect(find.text('Villain'), findsOneWidget);
      expect(find.text('Civilian'), findsOneWidget);
      expect(find.text('Law Enforcement'), findsOneWidget);

      await tester.tap(find.text('Villain'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-name')), 'Goon');
      await tester.tap(find.byKey(const Key('submit-add-combatant')));
      await tester.pumpAndSettle();

      expect(
        container.read(turnEngineProvider).combatants.single.team,
        'Villain',
      );
    });
  });
}