import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/domain/services/encounter_file_service.dart';
import 'package:herotrak/domain/services/encounter_serializer.dart';
import 'package:herotrak/presentation/state/turn_engine_notifier.dart';
import 'package:herotrak/presentation/views/initiative_matrix_screen.dart';
import 'package:herotrak/presentation/widgets/encounter_io_dialogs.dart';

PhaseSlot makeSlot({int segment = 6, PhaseStatus status = PhaseStatus.scheduled}) {
  return PhaseSlot(segment: segment, status: status);
}

Combatant makeCombatant({
  String id = 'c1',
  String name = 'Hero One',
  List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
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
    phaseSlots: phaseSlots,
  );
}

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

Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  TurnState initial, {
  EncounterFileService? fileService,
}) async {
  final container = ProviderContainer(
    overrides: [
      turnEngineProvider.overrideWith(
        () => TurnEngineNotifier(initial: initial),
      ),
      if (fileService != null)
        encounterFileServiceProvider.overrideWithValue(fileService),
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

Future<void> openBrandMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('brand-menu')));
  await tester.pumpAndSettle();
}

/// Pumps a minimal host with one button that opens a dialog via [onOpen],
/// for exercising the (menu-independent) clipboard dialogs directly.
Future<ProviderContainer> pumpDialogHost(
  WidgetTester tester,
  TurnState initial, {
  required void Function(BuildContext context) onOpen,
}) async {
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
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-dialog'),
                onPressed: () => onOpen(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Synchronous stand-in for [EncounterFileService] so widget tests avoid
/// real async file I/O (the real service flow is covered by its unit tests).
class FakeFileService extends EncounterFileService {
  FakeFileService({
    this.savePath,
    this.openPath,
    this.saveError,
    this.loadError,
  });

  final String? savePath;
  final String? openPath;

  /// When set, the corresponding method throws this error (e.g. a
  /// [PlatformException] from a failing native dialog).
  final Object? saveError;
  final Object? loadError;

  /// The JSON passed to [saveEncounterToFile], for assertions.
  String? savedJson;

  @override
  Future<String?> saveEncounterToFile(TurnState state) async {
    final error = saveError;
    if (error != null) throw error;
    if (savePath == null) return null;
    savedJson = serializeEncounter(state);
    File(savePath!).writeAsStringSync(savedJson!);
    return savePath;
  }

  @override
  Future<TurnState?> loadEncounterFromFile() async {
    final error = loadError;
    if (error != null) throw error;
    if (openPath == null) return null;
    return deserializeEncounter(File(openPath!).readAsStringSync());
  }
}

void main() {
  group('HeroTrak brand menu', () {
    testWidgets('offers only Save Encounter... and Load Encounter...',
        (tester) async {
      await pumpScreen(tester, makeTurnState());
      await openBrandMenu(tester);

      expect(find.text('Save Encounter...'), findsOneWidget);
      expect(find.text('Load Encounter...'), findsOneWidget);
      // The redundant text-area clipboard items were removed from the menu.
      expect(find.text('Export Encounter'), findsNothing);
      expect(find.text('Import Encounter'), findsNothing);
    });
  });

  group('export dialog', () {
    testWidgets('shows the serialized encounter JSON', (tester) async {
      final initial = makeTurnState(
        turnNumber: 2,
        activeSegment: 7,
        activeCombatantId: 'c1',
        combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 7)]),
        ],
      );
      await pumpDialogHost(
        tester,
        initial,
        onOpen: (context) =>
            showExportEncounterDialog(context, serializeEncounter(initial)),
      );
      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('Export Encounter'), findsOneWidget); // dialog title
      expect(find.text(serializeEncounter(initial)), findsOneWidget);
      expect(find.byKey(const Key('export-json')), findsOneWidget);
      // Copy mechanism + close control.
      expect(find.text('Copy to Clipboard'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-json')), findsNothing);
    });
  });

  group('import dialog', () {
    testWidgets('loads valid JSON into the engine', (tester) async {
      final incoming = makeTurnState(
        turnNumber: 4,
        activeSegment: 9,
        activeCombatantId: 'c9',
        combatants: [
          makeCombatant(id: 'c9', name: 'Imported Hero', phaseSlots: [
            makeSlot(segment: 4),
            makeSlot(segment: 8),
            makeSlot(segment: 12),
          ]),
        ],
      );
      final container = await pumpDialogHost(
        tester,
        makeTurnState(activeSegment: 3),
        onOpen: showImportEncounterDialog,
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import-json-field')),
        serializeEncounter(incoming),
      );
      await tester.tap(find.byKey(const Key('submit-import')));
      await tester.pumpAndSettle();

      expect(find.byType(ImportEncounterDialog), findsNothing);
      final state = container.read(turnEngineProvider);
      expect(state, incoming);
    });

    testWidgets('rejects invalid JSON inline and keeps the encounter',
        (tester) async {
      final initial = makeTurnState(activeSegment: 3);
      final container = await pumpDialogHost(
        tester,
        initial,
        onOpen: showImportEncounterDialog,
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import-json-field')),
        'not json at all',
      );
      await tester.tap(find.byKey(const Key('submit-import')));
      await tester.pumpAndSettle();

      expect(find.byType(ImportEncounterDialog), findsOneWidget);
      expect(find.textContaining('Invalid encounter JSON'), findsOneWidget);
      expect(container.read(turnEngineProvider), initial);
    });

    testWidgets('cancel leaves the encounter untouched', (tester) async {
      final initial = makeTurnState(activeSegment: 3);
      final container = await pumpDialogHost(
        tester,
        initial,
        onOpen: showImportEncounterDialog,
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import-json-field')),
        '{"turnNumber": 9, "activeSegment": 9, "activeCombatantId": null, '
            '"targetCombatantId": null, "combatants": []}',
      );
      await tester.tap(find.byKey(const Key('cancel-import')));
      await tester.pumpAndSettle();

      expect(find.byType(ImportEncounterDialog), findsNothing);
      expect(container.read(turnEngineProvider), initial);
    });
  });

  group('brand menu file actions', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('herotrak_file_menu');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('menu lists Save Encounter... and Load Encounter...',
        (tester) async {
      await pumpScreen(tester, makeTurnState());
      await openBrandMenu(tester);

      expect(find.text('Save Encounter...'), findsOneWidget);
      expect(find.text('Load Encounter...'), findsOneWidget);
    });

    testWidgets('Save Encounter... saves the encounter via the file service',
        (tester) async {
      final path = '${tempDir.path}/saved.json';
      final initial = makeTurnState(
        activeSegment: 7,
        activeCombatantId: 'c1',
        combatants: [
          makeCombatant(id: 'c1', phaseSlots: [makeSlot(segment: 7)]),
        ],
      );
      final service = FakeFileService(savePath: path);
      await pumpScreen(tester, initial, fileService: service);

      await openBrandMenu(tester);
      await tester.tap(find.text('Save Encounter...'));
      await tester.pumpAndSettle();

      expect(service.savedJson, serializeEncounter(initial));
      expect(File(path).readAsStringSync(), serializeEncounter(initial));
      // Success feedback confirms the file dialog flow completed.
      expect(find.textContaining('Encounter saved'), findsOneWidget);
      // Let the SnackBar auto-dismiss so no timers leak into teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('Load Encounter... loads the file into the engine',
        (tester) async {
      final incoming = makeTurnState(
        turnNumber: 4,
        activeSegment: 9,
        activeCombatantId: 'c9',
        combatants: [
          makeCombatant(id: 'c9', name: 'Imported Hero', phaseSlots: [
            makeSlot(segment: 4),
            makeSlot(segment: 8),
            makeSlot(segment: 12),
          ]),
        ],
      );
      final path = '${tempDir.path}/incoming.json';
      File(path).writeAsStringSync(serializeEncounter(incoming));
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 3),
        fileService: FakeFileService(openPath: path),
      );

      await openBrandMenu(tester);
      await tester.tap(find.text('Load Encounter...'));
      await tester.pumpAndSettle();

      // The details dialog shows the file summary and the reset option,
      // checked by default.
      expect(find.text('Turn 4 · Segment 9 · 1 combatants'), findsOneWidget);
      expect(find.text('Reset to Turn 1, Segment 1 on load'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('reset-on-load')))
            .value,
        isTrue,
      );

      // Unchecking preserves the saved timeline exactly.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();

      expect(container.read(turnEngineProvider), incoming);
      // Success feedback confirms the file dialog flow completed.
      expect(find.textContaining('Encounter loaded'), findsOneWidget);
      // Let the SnackBar auto-dismiss so no timers leak into teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the checked reset option loads at Turn 1 / Segment 1 with '
        'the roster preserved', (tester) async {
      final incoming = makeTurnState(
        turnNumber: 4,
        activeSegment: 9,
        activeCombatantId: 'c9',
        combatants: [
          makeCombatant(id: 'c9', name: 'Imported Hero', phaseSlots: [
            PhaseSlot(segment: 4, status: PhaseStatus.spent),
            PhaseSlot(segment: 8),
          ]),
        ],
      );
      final path = '${tempDir.path}/incoming-reset.json';
      File(path).writeAsStringSync(serializeEncounter(incoming));
      final container = await pumpScreen(
        tester,
        makeTurnState(activeSegment: 3),
        fileService: FakeFileService(openPath: path),
      );

      await openBrandMenu(tester);
      await tester.tap(find.text('Load Encounter...'));
      await tester.pumpAndSettle();

      // Keep the default checked state and load.
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();

      final state = container.read(turnEngineProvider);
      // The timeline resets to Turn 1 / Segment 1 with fresh cursors...
      expect(state.turnNumber, 1);
      expect(state.activeSegment, 1);
      expect(state.activeCombatantId, isNull);
      expect(state.targetCombatantId, isNull);
      // ...the loaded roster is preserved...
      expect(state.combatants.single.name, 'Imported Hero');
      // ...and transient phase states are cleared.
      expect(
        state.combatants.single.phaseSlots.map((slot) => slot.status),
        everyElement(PhaseStatus.scheduled),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('cancelling the load dialog keeps the current encounter',
        (tester) async {
      final incoming = makeTurnState(
        turnNumber: 4,
        activeSegment: 9,
        combatants: [
          makeCombatant(id: 'c9', name: 'Imported Hero'),
        ],
      );
      final path = '${tempDir.path}/incoming-cancel.json';
      File(path).writeAsStringSync(serializeEncounter(incoming));
      final initial = makeTurnState(activeSegment: 3);
      final container = await pumpScreen(
        tester,
        initial,
        fileService: FakeFileService(openPath: path),
      );

      await openBrandMenu(tester);
      await tester.tap(find.text('Load Encounter...'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(turnEngineProvider), initial);
    });

    testWidgets('cancelling Load Encounter... keeps the current encounter',
        (tester) async {
      final initial = makeTurnState(activeSegment: 3);
      final container = await pumpScreen(
        tester,
        initial,
        fileService: FakeFileService(),
      );

      await openBrandMenu(tester);
      await tester.tap(find.text('Load Encounter...'));
      await tester.pumpAndSettle();

      expect(container.read(turnEngineProvider), initial);
    });

    testWidgets('loading an invalid file shows an error and keeps the '
        'encounter', (tester) async {
      final path = '${tempDir.path}/broken.json';
      File(path).writeAsStringSync('not json at all');
      final initial = makeTurnState(activeSegment: 3);
      final container = await pumpScreen(
        tester,
        initial,
        fileService: FakeFileService(openPath: path),
      );

      await openBrandMenu(tester);
      await tester.tap(find.text('Load Encounter...'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid encounter JSON'), findsOneWidget);
      expect(container.read(turnEngineProvider), initial);

      // Let the SnackBar auto-dismiss so no timers leak into teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a PlatformException from the save dialog is reported, not '
        'unhandled', (tester) async {
      final service = FakeFileService(
        saveError:
            PlatformException(code: 'file_selector', message: 'dialog failed'),
      );
      await pumpScreen(tester, makeTurnState(), fileService: service);

      await openBrandMenu(tester);
      await tester.tap(find.text('Save Encounter...'));
      await tester.pumpAndSettle();

      expect(find.textContaining('File dialog failed'), findsOneWidget);
      // No unhandled exception escaped the handler.
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a PlatformException from the open dialog keeps the '
        'encounter', (tester) async {
      final initial = makeTurnState(activeSegment: 3);
      final container = await pumpScreen(
        tester,
        initial,
        fileService: FakeFileService(
          loadError: PlatformException(
            code: 'file_selector',
            message: 'dialog failed',
          ),
        ),
      );

      await openBrandMenu(tester);
      await tester.tap(find.text('Load Encounter...'));
      await tester.pumpAndSettle();

      expect(find.textContaining('File dialog failed'), findsOneWidget);
      expect(container.read(turnEngineProvider), initial);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}