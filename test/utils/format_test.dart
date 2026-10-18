import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/utils/format.dart';

void main() {
  test('rates and bytes keep the existing app formatting', () {
    expect(formatRate(0), '0 B/s');
    expect(formatRate(697), '697 B/s');
    expect(formatRate(2048), '2.00 KiB/s');
    expect(formatRate(15 * 1024 * 1024), '15.0 MiB/s');
    expect(formatBytes(-1), '0 B');
    expect(formatBytes(1536), '1.50 KiB');
    expect(formatBytes(300 * 1024 * 1024 * 1024), '300 GiB');
  });

  test('uptime and age', () {
    expect(formatUptime(0), '—');
    expect(formatUptime(42), '42s');
    expect(formatUptime(3 * 3600 + 5 * 60), '3h 5m');
    expect(formatUptime(2 * 86400 + 7200), '2d 2h');
    final now = DateTime(2026, 10, 17, 12);
    expect(formatAge(null), 'never');
    expect(
      formatAge(now.subtract(const Duration(seconds: 2)), now: now),
      'just now',
    );
    expect(
      formatAge(now.subtract(const Duration(seconds: 30)), now: now),
      '30s ago',
    );
    expect(
      formatAge(now.subtract(const Duration(minutes: 4)), now: now),
      '4 min ago',
    );
  });
}
