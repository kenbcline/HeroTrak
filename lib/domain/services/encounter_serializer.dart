import 'dart:convert';

import '../models/models.dart';

/// Serializes [state] into a JSON string suitable for encounter save files.
///
/// The format maps 1:1 onto the immutable domain models:
///
/// ```json
/// {
///   "turnNumber": 1,
///   "activeSegment": 6,
///   "activeCombatantId": "c1",
///   "targetCombatantId": null,
///   "combatants": [
///     {
///       "id": "c1", "name": "Hero One",
///       "dex": 18, "ego": 10, "spd": 5, "stun": 40, "end": 20, "body": 10,
///       "isTargeted": false, "isNpc": false,
///       "statusBadges": ["held"],
///       "phaseSlots": [
///         {
///           "segment": 3, "originalSegment": 3,
///           "status": "scheduled", "isMental": false,
///           "actionId": null, "actionLabel": null
///         }
///       ]
///     }
///   ]
/// }
/// ```
///
/// Enum values are stored by name. The inverse operation is
/// [deserializeEncounter].
String serializeEncounter(TurnState state) {
  return jsonEncode(<String, Object?>{
    'turnNumber': state.turnNumber,
    'activeSegment': state.activeSegment,
    'activeCombatantId': state.activeCombatantId,
    'targetCombatantId': state.targetCombatantId,
    'haymakerDeclarations': <Object?>[
      for (final declaration in state.haymakerDeclarations)
        _declarationToMap(declaration),
    ],
    'combatants': <Object?>[
      for (final combatant in state.combatants) _combatantToMap(combatant),
    ],
  });
}

Map<String, Object?> _declarationToMap(HaymakerDeclaration declaration) {
  return <String, Object?>{
    'combatantId': declaration.combatantId,
    'declaredSegment': declaration.declaredSegment,
    'resolutionSegment': declaration.resolutionSegment,
    'declaredTurn': declaration.declaredTurn,
  };
}

Map<String, Object?> _combatantToMap(Combatant combatant) {
  return <String, Object?>{
    'id': combatant.id,
    'name': combatant.name,
    'dex': combatant.dex,
    'ego': combatant.ego,
    'spd': combatant.spd,
    'stun': combatant.stun,
    'end': combatant.end,
    'body': combatant.body,
    'intelligence': combatant.intelligence,
    'strength': combatant.strength,
    'constitution': combatant.constitution,
    'physicalDefense': combatant.physicalDefense,
    'energyDefense': combatant.energyDefense,
    'recovery': combatant.recovery,
    'spdDelta': combatant.spdDelta,
    'team': combatant.team,
    'status': combatant.status.name,
    'isTargeted': combatant.isTargeted,
    'isNpc': combatant.isNpc,
    'statusBadges': <Object?>[
      for (final badge in combatant.statusBadges) badge.name,
    ],
    'phaseSlots': <Object?>[
      for (final slot in combatant.phaseSlots) _slotToMap(slot),
    ],
  };
}

Map<String, Object?> _slotToMap(PhaseSlot slot) {
  return <String, Object?>{
    'segment': slot.segment,
    'originalSegment': slot.originalSegment,
    'status': slot.status.name,
    'isMental': slot.isMental,
    'actionId': slot.actionId,
    'actionLabel': slot.actionLabel,
  };
}

/// Parses a JSON encounter produced by [serializeEncounter] back into an
/// immutable [TurnState].
///
/// Throws [FormatException] when the JSON is malformed, structurally
/// incomplete, or contains out-of-range values (e.g. a segment outside
/// 1–12); the result is always a valid, deeply immutable state object.
TurnState deserializeEncounter(String jsonString) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonString);
  } on FormatException {
    rethrow;
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Encounter JSON must be an object');
  }

  final turnNumber = _requireInt(decoded, 'turnNumber');
  final activeSegment = _requireInt(decoded, 'activeSegment');
  if (turnNumber < 1) {
    throw FormatException('turnNumber must be at least 1, got $turnNumber');
  }
  _checkSegment(activeSegment, 'activeSegment');

  final rawCombatants = _requireList(decoded, 'combatants');
  final rawDeclarations = _optionalList(decoded, 'haymakerDeclarations');
  return TurnState(
    turnNumber: turnNumber,
    activeSegment: activeSegment,
    activeCombatantId: _optionalString(decoded, 'activeCombatantId'),
    targetCombatantId: _optionalString(decoded, 'targetCombatantId'),
    haymakerDeclarations: <HaymakerDeclaration>[
      for (var i = 0; i < rawDeclarations.length; i++)
        _declarationFromMap(
          rawDeclarations[i],
          'haymakerDeclarations[$i]',
          turnNumber,
        ),
    ],
    combatants: <Combatant>[
      for (var i = 0; i < rawCombatants.length; i++)
        _combatantFromMap(rawCombatants[i], 'combatants[$i]'),
    ],
  );
}

HaymakerDeclaration _declarationFromMap(
  Object? value,
  String path,
  int turnNumber,
) {
  final map = _requireMap(value, path);
  final declaredSegment = _requireInt(map, 'declaredSegment');
  final resolutionSegment = _requireInt(map, 'resolutionSegment');
  _checkSegment(declaredSegment, '$path.declaredSegment');
  _checkSegment(resolutionSegment, '$path.resolutionSegment');

  return HaymakerDeclaration(
    combatantId: _requireString(map, 'combatantId'),
    declaredSegment: declaredSegment,
    resolutionSegment: resolutionSegment,
    // Older encounter files predate `declaredTurn`; any declaration they
    // carry was made during the file's own Turn.
    declaredTurn: _optionalInt(map, 'declaredTurn') ?? turnNumber,
  );
}

Combatant _combatantFromMap(Object? value, String path) {
  final map = _requireMap(value, path);
  final rawSlots = _requireList(map, 'phaseSlots');
  return Combatant(
    id: _requireString(map, 'id'),
    name: _requireString(map, 'name'),
    dex: _requireInt(map, 'dex'),
    ego: _requireInt(map, 'ego'),
    spd: _requireInt(map, 'spd'),
    stun: _requireInt(map, 'stun'),
    end: _requireInt(map, 'end'),
    body: _requireInt(map, 'body'),
    intelligence: _optionalInt(map, 'intelligence') ?? 0,
    strength: _optionalInt(map, 'strength') ?? 0,
    constitution: _optionalInt(map, 'constitution') ?? 0,
    physicalDefense: _optionalInt(map, 'physicalDefense') ?? 0,
    energyDefense: _optionalInt(map, 'energyDefense') ?? 0,
    recovery: _optionalInt(map, 'recovery') ?? 0,
    spdDelta: _optionalInt(map, 'spdDelta') ?? 0,
    team: _optionalString(map, 'team') ?? '',
    status: _combatantStatusFromName(_optionalString(map, 'status') ?? 'normal'),
    isTargeted: _requireBool(map, 'isTargeted'),
    isNpc: _requireBool(map, 'isNpc'),
    statusBadges: <PhaseStatus>[
      for (final raw in _requireList(map, 'statusBadges'))
        _statusFromName(_stringFromValue(raw, '$path.statusBadges[]')),
    ],
    phaseSlots: <PhaseSlot>[
      for (var i = 0; i < rawSlots.length; i++)
        _slotFromMap(rawSlots[i], '$path.phaseSlots[$i]'),
    ],
  );
}

PhaseSlot _slotFromMap(Object? value, String path) {
  final map = _requireMap(value, path);
  final segment = _requireInt(map, 'segment');
  final originalSegment = _requireInt(map, 'originalSegment');
  _checkSegment(segment, '$path.segment');
  _checkSegment(originalSegment, '$path.originalSegment');

  return PhaseSlot(
    segment: segment,
    originalSegment: originalSegment,
    status: _statusFromName(_requireString(map, 'status')),
    isMental: _requireBool(map, 'isMental'),
    actionId: _optionalString(map, 'actionId'),
    actionLabel: _optionalString(map, 'actionLabel'),
  );
}

PhaseStatus _statusFromName(String name) {
  for (final status in PhaseStatus.values) {
    if (status.name == name) return status;
  }
  throw FormatException('Unknown PhaseStatus "$name"');
}

CombatantStatus _combatantStatusFromName(String name) {
  for (final status in CombatantStatus.values) {
    if (status.name == name) return status;
  }
  throw FormatException('Unknown CombatantStatus "$name"');
}

void _checkSegment(int value, String path) {
  if (value < 1 || value > 12) {
    throw FormatException('$path must be between 1 and 12, got $value');
  }
}

Map<String, dynamic> _requireMap(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _requireList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List<Object?>) {
    throw FormatException('"$key" must be a list');
  }
  return value;
}

/// Like [_requireList], but tolerates a missing key (older encounter files).
List<Object?> _optionalList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return const <Object?>[];
  return _requireList(map, key);
}

int _requireInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('"$key" must be an int');
  }
  return value;
}

/// Like [_requireInt], but tolerates a missing key (older encounter files).
int? _optionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return null;
  return _requireInt(map, key);
}

bool _requireBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException('"$key" must be a bool');
  }
  return value;
}

String _requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw FormatException('"$key" must be a string');
  }
  return value;
}

String _stringFromValue(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('"$key" must be a string or null');
  }
  return value;
}