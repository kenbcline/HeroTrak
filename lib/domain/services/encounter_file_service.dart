import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'encounter_serializer.dart';

/// Opens the native save dialog and returns the chosen file path, or `null`
/// when the user cancels.
typedef SaveLocationOpener = Future<String?> Function(
  List<XTypeGroup> acceptedTypeGroups,
);

/// Opens the native open dialog and returns the chosen file, or `null` when
/// the user cancels.
typedef FileOpener = Future<XFile?> Function(
  List<XTypeGroup> acceptedTypeGroups,
);

/// File type filter for encounter JSON files.
const XTypeGroup kEncounterTypeGroup = XTypeGroup(
  label: 'Encounter',
  extensions: <String>['json'],
);

/// Native file save/load for encounter JSON.
///
/// Wraps the `file_selector` native dialogs: [saveEncounterToFile] writes an
/// encounter via [serializeEncounter] to a user-chosen `.json` file, and
/// [loadEncounterFromFile] reads and parses a chosen `.json` file via
/// [deserializeEncounter].
///
/// The dialog openers are injectable so the file-selection flow can be
/// exercised in tests without native dialogs; the defaults delegate to
/// `file_selector`'s [getSaveLocation] and [openFile] and are properly
/// awaited, so dialogs complete (or cancel) before any file I/O happens.
/// Native dialog failures surface as [PlatformException]s for the caller to
/// report.
class EncounterFileService {
  EncounterFileService({
    SaveLocationOpener? saveDialog,
    FileOpener? openDialog,
  })  : _saveDialog = saveDialog ?? _nativeSaveDialog,
        _openDialog = openDialog ?? _nativeOpenDialog;

  final SaveLocationOpener _saveDialog;
  final FileOpener _openDialog;

  static Future<String?> _nativeSaveDialog(
    List<XTypeGroup> acceptedTypeGroups,
  ) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: acceptedTypeGroups,
      suggestedName: 'encounter.json',
    );
    return location?.path;
  }

  static Future<XFile?> _nativeOpenDialog(
    List<XTypeGroup> acceptedTypeGroups,
  ) async {
    final file = await openFile(acceptedTypeGroups: acceptedTypeGroups);
    return file;
  }

  /// Opens a native save dialog and writes [state] as encounter JSON to the
  /// chosen file.
  ///
  /// Returns the saved file path, or `null` when the user cancels. A chosen
  /// path without any extension is normalized to `.json` (native save dialogs
  /// may omit it) so the file round-trips through the `.json`-filtered open
  /// dialog.
  ///
  /// Throws [FileSystemException] when the file cannot be written and lets
  /// [PlatformException]s from the native dialog propagate.
  Future<String?> saveEncounterToFile(TurnState state) async {
    final path = await _saveDialog(const <XTypeGroup>[kEncounterTypeGroup]);
    if (path == null) return null;
    final targetPath = _withJsonExtension(path);
    await saveEncounterToPath(state, targetPath);
    return targetPath;
  }

  /// Opens a native open dialog (`.json` filter), awaits the user's choice,
  /// reads the chosen file, and parses it with [deserializeEncounter].
  ///
  /// Returns `null` when the user cancels. Throws [FormatException] when the
  /// file is not a valid encounter, [FileSystemException] when the file
  /// cannot be read, and lets [PlatformException]s from the native dialog
  /// propagate.
  Future<TurnState?> loadEncounterFromFile() async {
    final file = await _openDialog(const <XTypeGroup>[kEncounterTypeGroup]);
    if (file == null) return null;
    final contents = await file.readAsString();
    return deserializeEncounter(contents);
  }

  /// Writes [state] as encounter JSON to [path] using standard `dart:io`
  /// operations (flushed on completion).
  ///
  /// Throws [ArgumentError] when [path] is blank and [FileSystemException]
  /// when the file cannot be written.
  Future<void> saveEncounterToPath(TurnState state, String path) async {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'path must not be blank');
    }
    await File(path).writeAsString(serializeEncounter(state), flush: true);
  }

  /// Reads and parses the encounter JSON at [path].
  ///
  /// Throws [FormatException] on invalid encounter JSON and
  /// [FileSystemException] when the file cannot be read.
  Future<TurnState> loadEncounterFromPath(String path) async {
    return deserializeEncounter(await File(path).readAsString());
  }

  /// Appends `.json` to extension-less paths chosen in native save dialogs.
  static String _withJsonExtension(String path) {
    if (path.toLowerCase().endsWith('.json')) return path;
    final fileName = path.split(RegExp(r'[\\/]')).last;
    if (fileName.contains('.')) return path;
    return '$path.json';
  }
}

/// The [EncounterFileService] used by the brand menu Save/Load actions.
final encounterFileServiceProvider = Provider<EncounterFileService>(
  (ref) => EncounterFileService(),
);