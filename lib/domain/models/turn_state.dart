import 'package:equatable/equatable.dart';

import '../../core/utils/copy_with_sentinel.dart';
import 'combatant.dart';
import 'haymaker_declaration.dart';

/// Immutable snapshot of the tracker state for the current Turn.
///
/// The [combatants] and [haymakerDeclarations] lists are defensively copied
/// into unmodifiable lists at construction time, so the instance is deeply
/// immutable.
class TurnState extends Equatable {
  TurnState({
    this.turnNumber = 1,
    required this.activeSegment,
    this.activeCombatantId,
    this.targetCombatantId,
    List<Combatant> combatants = const <Combatant>[],
    List<HaymakerDeclaration> haymakerDeclarations = const <HaymakerDeclaration>[],
  }) : assert(turnNumber >= 1, 'turnNumber must be at least 1'),
       assert(
         activeSegment >= 1 && activeSegment <= 12,
         'activeSegment must be between 1 and 12',
       ),
       combatants = List<Combatant>.unmodifiable(combatants),
       haymakerDeclarations = List<HaymakerDeclaration>.unmodifiable(
         haymakerDeclarations,
       );

  /// Current Turn number (1-based).
  final int turnNumber;

  /// The segment (1–12) currently being resolved.
  final int activeSegment;

  /// Id of the combatant currently acting, if any.
  final String? activeCombatantId;

  /// Id of the combatant currently targeted, if any.
  final String? targetCombatantId;

  /// All combatants in the encounter.
  final List<Combatant> combatants;

  /// Pending Haymaker declarations for the current Turn (see
  /// [HaymakerDeclaration]); cleared by the smart turn reset.
  final List<HaymakerDeclaration> haymakerDeclarations;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields ([activeCombatantId], [targetCombatantId]) may be
  /// explicitly cleared by passing `null`; omitting them keeps their current
  /// value.
  TurnState copyWith({
    int? turnNumber,
    int? activeSegment,
    Object? activeCombatantId = kCopyWithUnset,
    Object? targetCombatantId = kCopyWithUnset,
    List<Combatant>? combatants,
    List<HaymakerDeclaration>? haymakerDeclarations,
  }) {
    return TurnState(
      turnNumber: turnNumber ?? this.turnNumber,
      activeSegment: activeSegment ?? this.activeSegment,
      activeCombatantId: identical(activeCombatantId, kCopyWithUnset)
          ? this.activeCombatantId
          : activeCombatantId as String?,
      targetCombatantId: identical(targetCombatantId, kCopyWithUnset)
          ? this.targetCombatantId
          : targetCombatantId as String?,
      combatants: combatants ?? this.combatants,
      haymakerDeclarations:
          haymakerDeclarations ?? this.haymakerDeclarations,
    );
  }

  @override
  List<Object?> get props => [
    turnNumber,
    activeSegment,
    activeCombatantId,
    targetCombatantId,
    combatants,
    haymakerDeclarations,
  ];
}
