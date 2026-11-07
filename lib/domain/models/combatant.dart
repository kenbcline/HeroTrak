import 'package:equatable/equatable.dart';

import 'combatant_status.dart';
import 'phase_slot.dart';
import 'phase_status.dart';

/// Immutable representation of a combatant character in the tracker.
///
/// The [phaseSlots] list is defensively copied into an unmodifiable list at
/// construction time, so the instance is deeply immutable.
class Combatant extends Equatable {
  Combatant({
    required this.id,
    required this.name,
    required this.dex,
    required this.ego,
    required this.spd,
    required this.stun,
    required this.end,
    required this.body,
    this.intelligence = 0,
    this.strength = 0,
    this.constitution = 0,
    this.physicalDefense = 0,
    this.energyDefense = 0,
    this.recovery = 0,
    this.spdDelta = 0,
    this.team = '',
    this.status = CombatantStatus.normal,
    this.isTargeted = false,
    this.isNpc = false,
    List<PhaseSlot> phaseSlots = const <PhaseSlot>[],
    List<PhaseStatus> statusBadges = const <PhaseStatus>[],
  }) : phaseSlots = List<PhaseSlot>.unmodifiable(phaseSlots),
       statusBadges = List<PhaseStatus>.unmodifiable(statusBadges);

  /// Unique identifier.
  final String id;

  /// Display name.
  final String name;

  /// Dexterity (DEX) — determines acting order within a segment.
  final int dex;

  /// Ego (EGO).
  final int ego;

  /// Speed (SPD) — number of phases per Turn per the 6e Speed Chart.
  final int spd;

  /// Current STUN.
  final int stun;

  /// Current END.
  final int end;

  /// Current BODY.
  final int body;

  /// Intelligence (INT).
  final int intelligence;

  /// Strength (STR).
  final int strength;

  /// Constitution (CON).
  final int constitution;

  /// Physical Defense (PD).
  final int physicalDefense;

  /// Energy Defense (ED).
  final int energyDefense;

  /// Recovery (REC).
  final int recovery;

  /// Temporary SPD adjustment (Aid/Drain) layered on top of [spd].
  final int spdDelta;

  /// The SPD actually used for Speed Chart scheduling:
  /// `(spd + spdDelta)` clamped to the chart's 1–12 range.
  int get effectiveSpd => (spd + spdDelta).clamp(1, 12);

  /// SPD display value with its temporary delta when non-zero,
  /// e.g. `4 (+1)` or `5 (-1)`.
  String get spdDisplay =>
      spdDelta == 0 ? '$spd' : '$spd (${spdDelta > 0 ? '+' : ''}$spdDelta)';

  /// Team / faction affiliation shown in the detail panel.
  final String team;

  /// Overall condition (normal / stunned / KO / dead).
  final CombatantStatus status;

  /// Whether this combatant is currently targeted.
  final bool isTargeted;

  /// Whether this combatant is an NPC (as opposed to a player character).
  final bool isNpc;

  /// Scheduled phase slots for the current Turn.
  final List<PhaseSlot> phaseSlots;

  /// Temporary condition badges currently applied to this combatant.
  ///
  /// Badges (e.g. [PhaseStatus.aborted] for aborting to a defensive action,
  /// [PhaseStatus.held] while holding) are applied and removed via action
  /// mutations. The list is defensively copied and unmodifiable, and never
  /// contains duplicates.
  final List<PhaseStatus> statusBadges;

  /// Initiative ordering: SPD descending, then DEX descending, then EGO
  /// descending, then Name ascending. Ties fall back to the id so the order
  /// is always deterministic.
  ///
  /// Use with `list.sort(Combatant.compareByInitiative)`.
  static int compareByInitiative(Combatant a, Combatant b) {
    var compare = b.spd.compareTo(a.spd);
    if (compare != 0) return compare;
    compare = b.dex.compareTo(a.dex);
    if (compare != 0) return compare;
    compare = b.ego.compareTo(a.ego);
    if (compare != 0) return compare;
    compare = a.name.compareTo(b.name);
    if (compare != 0) return compare;
    return a.id.compareTo(b.id);
  }

  /// Returns a copy with the given fields replaced.
  Combatant copyWith({
    String? id,
    String? name,
    int? dex,
    int? ego,
    int? spd,
    int? stun,
    int? end,
    int? body,
    int? intelligence,
    int? strength,
    int? constitution,
    int? physicalDefense,
    int? energyDefense,
    int? recovery,
    int? spdDelta,
    String? team,
    CombatantStatus? status,
    bool? isTargeted,
    bool? isNpc,
    List<PhaseSlot>? phaseSlots,
    List<PhaseStatus>? statusBadges,
  }) {
    return Combatant(
      id: id ?? this.id,
      name: name ?? this.name,
      dex: dex ?? this.dex,
      ego: ego ?? this.ego,
      spd: spd ?? this.spd,
      stun: stun ?? this.stun,
      end: end ?? this.end,
      body: body ?? this.body,
      intelligence: intelligence ?? this.intelligence,
      strength: strength ?? this.strength,
      constitution: constitution ?? this.constitution,
      physicalDefense: physicalDefense ?? this.physicalDefense,
      energyDefense: energyDefense ?? this.energyDefense,
      recovery: recovery ?? this.recovery,
      spdDelta: spdDelta ?? this.spdDelta,
      team: team ?? this.team,
      status: status ?? this.status,
      isTargeted: isTargeted ?? this.isTargeted,
      isNpc: isNpc ?? this.isNpc,
      phaseSlots: phaseSlots ?? this.phaseSlots,
      statusBadges: statusBadges ?? this.statusBadges,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    dex,
    ego,
    spd,
    stun,
    end,
    body,
    intelligence,
    strength,
    constitution,
    physicalDefense,
    energyDefense,
    recovery,
    spdDelta,
    team,
    status,
    isTargeted,
    isNpc,
    phaseSlots,
    statusBadges,
  ];
}
