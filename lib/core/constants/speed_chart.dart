/// Hero System 6th Edition (6e) Speed Chart constants and helpers.
///
/// The Speed Chart defines the Segments (1–12) of a Turn during which a
/// character acts, based on their Speed (SPD). This library contains only
/// standard, non-invented 6e chart data.
library;

/// Standard Hero System 6e Speed Chart.
///
/// Maps SPD (1–12) to the segments in which that character acts during a
/// single Turn. Segments are listed in ascending order.
///
/// SPD 1 phases only on Segment 7: per the HERO System 6e Speed Chart
/// (and its Post-12 Recovery), Speed 1 is an explicit chart entry distinct
/// from the formula distribution used by higher speeds.
const Map<int, List<int>> kSpeedChart = <int, List<int>>{
  1: <int>[7],
  2: <int>[6, 12],
  3: <int>[4, 8, 12],
  4: <int>[3, 6, 9, 12],
  5: <int>[3, 5, 8, 10, 12],
  6: <int>[2, 4, 6, 8, 10, 12],
  7: <int>[2, 4, 6, 7, 9, 11, 12],
  8: <int>[2, 3, 5, 6, 8, 9, 11, 12],
  9: <int>[2, 3, 4, 6, 7, 8, 10, 11, 12],
  10: <int>[2, 3, 4, 5, 6, 8, 9, 10, 11, 12],
  11: <int>[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
  12: <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
};

/// Returns the scheduled segments for the given [spd] per the 6e Speed Chart.
///
/// The returned list is unmodifiable and sorted in ascending order.
///
/// Throws [ArgumentError] if [spd] is outside the 1–12 chart range.
List<int> getSegmentsForSpd(int spd) {
  final segments = kSpeedChart[spd];
  if (segments == null) {
    throw ArgumentError.value(spd, 'spd', 'Speed must be between 1 and 12');
  }
  return List<int>.unmodifiable(segments);
}
