import 'package:flutter_test/flutter_test.dart';
import 'package:herotrak/core/constants/speed_chart.dart';

void main() {
  /// The canonical Hero System 6e Speed Chart reference mapping.
  const expectedChart = <int, List<int>>{
    1: [7],
    2: [6, 12],
    3: [4, 8, 12],
    4: [3, 6, 9, 12],
    5: [3, 5, 8, 10, 12],
    6: [2, 4, 6, 8, 10, 12],
    7: [2, 4, 6, 7, 9, 11, 12],
    8: [2, 3, 5, 6, 8, 9, 11, 12],
    9: [2, 3, 4, 6, 7, 8, 10, 11, 12],
    10: [2, 3, 4, 5, 6, 8, 9, 10, 11, 12],
    11: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    12: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
  };

  group('kSpeedChart', () {
    test('matches the standard 6e chart exactly', () {
      expect(kSpeedChart, expectedChart);
    });

    test('contains exactly SPD 1 through 12', () {
      expect(kSpeedChart.keys.toList(), List<int>.generate(12, (i) => i + 1));
    });

    test('SPD 1 phases only on Segment 7, never Segment 12', () {
      expect(kSpeedChart[1], [7]);
      expect(getSegmentsForSpd(1), [7]);
      expect(getSegmentsForSpd(1), isNot(contains(12)));
    });
  });

  group('getSegmentsForSpd', () {
    for (final entry in expectedChart.entries) {
      test('SPD ${entry.key} acts on segments ${entry.value}', () {
        expect(getSegmentsForSpd(entry.key), entry.value);
      });
    }

    test('phase count equals SPD for every speed', () {
      for (var spd = 1; spd <= 12; spd++) {
        expect(getSegmentsForSpd(spd), hasLength(spd));
      }
    });

    test('segments are sorted ascending and within 1-12', () {
      for (var spd = 1; spd <= 12; spd++) {
        final segments = getSegmentsForSpd(spd);
        for (var i = 0; i < segments.length; i++) {
          expect(segments[i], inInclusiveRange(1, 12));
          if (i > 0) {
            expect(segments[i], greaterThan(segments[i - 1]));
          }
        }
      }
    });

    test('throws ArgumentError for speeds below 1', () {
      expect(() => getSegmentsForSpd(0), throwsArgumentError);
      expect(() => getSegmentsForSpd(-3), throwsArgumentError);
    });

    test('throws ArgumentError for speeds above 12', () {
      expect(() => getSegmentsForSpd(13), throwsArgumentError);
      expect(() => getSegmentsForSpd(100), throwsArgumentError);
    });

    test('returned list is unmodifiable', () {
      final segments = getSegmentsForSpd(4);
      expect(() => segments.add(12), throwsUnsupportedError);
      expect(() => segments.clear(), throwsUnsupportedError);
    });

    test('chart data is protected from mutation through the helper', () {
      getSegmentsForSpd(4);
      expect(kSpeedChart[4], [3, 6, 9, 12]);
    });
  });
}
