import 'package:equatable/equatable.dart';

/// A declared Haymaker: a wind-up on the originating Segment and a forced
/// strike ("Strikes/Resolves" marker) on the following Segment.
///
/// The declaration is deliberately decoupled from the base phase slot: the
/// slot keeps its own schedule (it is never relocated), so it cannot be
/// corrupted or orphaned across Turn boundaries (e.g. Segment 12 →
/// Turn 2 Segment 1). The wind-up marker lives only in the declaring Turn;
/// a deferred (Segment 12) declaration carries its "Strikes" marker into
/// Turn N+1 and is cleared once that resolution Turn has passed.
class HaymakerDeclaration extends Equatable {
  const HaymakerDeclaration({
    required this.combatantId,
    required this.declaredSegment,
    required this.resolutionSegment,
    required this.declaredTurn,
  });

  /// Declares a Haymaker on [segment] during [declaredTurn]: the wind-up
  /// marker sits on [segment] and the resolution marker on the next Segment
  /// (wrapping 12 → 1).
  HaymakerDeclaration.at({
    required this.combatantId,
    required int segment,
    required this.declaredTurn,
  }) : declaredSegment = segment,
       resolutionSegment = resolutionSegmentFor(segment);

  /// The combatant winding up the haymaker.
  final String combatantId;

  /// The originating Segment (1–12) carrying the wind-up `[M]` marker.
  final int declaredSegment;

  /// The Segment (1–12) carrying the "Strikes/Resolves" marker.
  final int resolutionSegment;

  /// The Turn in which the haymaker was declared (wind-up Turn).
  final int declaredTurn;

  /// Whether the resolution wraps past Segment 12 and therefore strikes on
  /// Segment 1 of the *next* Turn instead of the declaring one.
  bool get isDeferredToNextTurn => declaredSegment >= 12;

  /// The Turn in which the "Strikes/Resolves" marker renders: the declaring
  /// Turn normally, or Turn N+1 for a deferred (Segment 12) declaration.
  int get resolutionTurn =>
      isDeferredToNextTurn ? declaredTurn + 1 : declaredTurn;

  /// The forced resolution Segment for a haymaker declared on [segment]:
  /// Segment + 1, wrapping past Segment 12 back to Segment 1.
  static int resolutionSegmentFor(int segment) {
    return segment >= 12 ? 1 : segment + 1;
  }

  @override
  List<Object?> get props =>
      [combatantId, declaredSegment, resolutionSegment, declaredTurn];
}