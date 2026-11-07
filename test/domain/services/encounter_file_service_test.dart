import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/domain/models/models.dart';
import 'package:herotrak/domain/services/encounter_file_service.dart';
import 'package:herotrak/domain/services/encounter_serializer.dart';

PhaseSlot makeSlot({
  int segment = 6,
  int? originalSegment,
  PhaseStatus status = PhaseStatus.scheduled,
}) {
  return PhaseSlot(
    segment: segment,
    originalSegment: originalSegment,
    status: status,
  );
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

TurnState sampleState() => makeTurnState(
      turnNumber: 2,
      activeSegment: 7,
      activeCombatantId: 'c1',
      combatants: [
        makeCombatant(
          id: 'c1',
          phaseSlots: [
            makeSlot(segment: 3),
            makeSlot(segment: 7, status: PhaseStatus.spent),
          ],
        ),
      ],
    );

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('herotrak_file_service');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('saveEncounterToFile', () {
    test('writes the encounter JSON to the chosen path', () async {
      final path = '${tempDir.path}/encounter.json';
      List<XTypeGroup>? seenGroups;
      final service = EncounterFileService(
        saveDialog: (groups) async {
          seenGroups = groups;
          return path;
        },
      );

      final savedPath = await service.saveEncounterToFile(sampleState());

      expect(savedPath, path);
      expect(File(path).readAsStringSync(), serializeEncounter(sampleState()));
      // The dialog filters for .json encounter files.
      expect(seenGroups, hasLength(1));
      expect(seenGroups!.single.extensions, ['json']);
    });

    test('returns null and writes nothing when cancelled', () async {
      final service = EncounterFileService(saveDialog: (groups) async => null);

      final savedPath = await service.saveEncounterToFile(sampleState());

      expect(savedPath, isNull);
      expect(tempDir.listSync(), isEmpty);
    });

    test('appends .json when the dialog returns an extension-less path',
        () async {
      final barePath = '${tempDir.path}/encounter';
      final service = EncounterFileService(
        saveDialog: (groups) async => barePath,
      );

      final savedPath = await service.saveEncounterToFile(sampleState());

      expect(savedPath, '$barePath.json');
      expect(
        File('$barePath.json').readAsStringSync(),
        serializeEncounter(sampleState()),
      );
    });

    test('keeps a chosen path that already has an extension', () async {
      for (final name in ['encounter.json', 'my.encounter.json', 'notes.txt']) {
        final path = '${tempDir.path}/$name';
        final service = EncounterFileService(
          saveDialog: (groups) async => path,
        );

        final savedPath = await service.saveEncounterToFile(sampleState());

        expect(savedPath, path);
        expect(File(path).existsSync(), isTrue);
      }
    });

    test('rejects a blank save path', () async {
      final service = EncounterFileService();

      await expectLater(
        service.saveEncounterToPath(sampleState(), '  '),
        throwsArgumentError,
      );
    });
  });

  group('loadEncounterFromFile', () {
    test('parses the chosen file into an equal TurnState', () async {
      final state = sampleState();
      final path = '${tempDir.path}/encounter.json';
      File(path).writeAsStringSync(serializeEncounter(state));
      List<XTypeGroup>? seenGroups;
      final service = EncounterFileService(
        openDialog: (groups) async {
          seenGroups = groups;
          return XFile(path);
        },
      );

      final loaded = await service.loadEncounterFromFile();

      expect(loaded, state);
      // The dialog filters for .json encounter files.
      expect(seenGroups, hasLength(1));
      expect(seenGroups!.single.extensions, ['json']);
    });

    test('returns null when cancelled', () async {
      final service = EncounterFileService(openDialog: (groups) async => null);

      expect(await service.loadEncounterFromFile(), isNull);
    });

    test('throws FormatException on invalid encounter JSON', () async {
      final path = '${tempDir.path}/broken.json';
      File(path).writeAsStringSync('not json at all');
      final service = EncounterFileService(
        openDialog: (groups) async => XFile(path),
      );

      expect(
        () => service.loadEncounterFromFile(),
        throwsFormatException,
      );
    });
  });

  group('path helpers', () {
    test('save and load round-trip through a real file', () async {
      final service = EncounterFileService();
      final state = sampleState();
      final path = '${tempDir.path}/roundtrip.json';

      await service.saveEncounterToPath(state, path);

      expect(await service.loadEncounterFromPath(path), state);
    });
  });

  group('encounterFileServiceProvider', () {
    test('provides a service using the native dialogs by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(encounterFileServiceProvider),
        isA<EncounterFileService>(),
      );
    });
  });
}