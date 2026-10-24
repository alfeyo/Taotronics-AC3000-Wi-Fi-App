import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/services/argon_status.dart';
import 'package:tt_router_flutter/widgets/speed_gauge.dart';

void main() {
  test(
    'weekly usage merges today, counts it once and keeps missing days empty',
    () {
      final c = ArgonClient.parse({
        'mac': '00:11:22:33:44:55',
        'usage': {
          'today': {
            'day': '2026-10-24',
            'totalBytes': 200,
            'observedSeconds': 21600,
            'coverage': 0.5,
          },
          'days': [
            {
              'day': '2026-10-24',
              'totalBytes': 100,
              'observedSeconds': 10800,
              'coverage': 0.25,
            },
            {
              'day': '2026-10-23',
              'totalBytes': 300,
              'observedSeconds': 86400,
              'coverage': 1,
            },
            {
              'day': '2026-10-17',
              'totalBytes': 999999,
              'observedSeconds': 86400,
              'coverage': 1,
            },
          ],
        },
      })!;
      expect(c.week.totalBytes, 500);
      expect(c.week.daysWithData, 2);
      expect(c.week.days, hasLength(7));
      expect(c.week.days.first, isNull);
      expect(c.week.coverage, closeTo(108000 / (6 * 86400 + 43200), 1e-9));
    },
  );
  test('today-only usage is included; absent coverage is unknown', () {
    final c = ArgonClient.parse({
      'mac': '00:11:22:33:44:55',
      'usage': {
        'today': {'day': '2026-10-24', 'totalBytes': 500},
        'days': [],
      },
    })!;
    expect(c.week.totalBytes, 500);
    expect(c.week.coverage, isNull);
    expect(c.usageDays, hasLength(1));
    expect(WeeklyUsage.of([]).totalBytes, isNull);
  });
  test(
    'gauge uses bit-rate scale, adapts to peak and never invents plan speed',
    () {
      expect(gaugeScaleBits(0), 1000000);
      expect(gaugeScaleBits(84200000), 100000000);
      expect(gaugeScaleBits(100000001), 200000000);
      expect(gaugeTickLabel(2000000), '2M');
      expect(gaugeTickLabel(500000), '500k');
    },
  );
}
