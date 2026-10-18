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
    expect(
      formatAge(now.subtract(const Duration(hours: 47)), now: now),
      '47 h ago',
    );
    expect(
      formatAge(now.subtract(const Duration(hours: 244)), now: now),
      '10 d ago',
    );
  });

  test('live bit rates: Mbps from 1 Mbit/s, binary byte units below', () {
    expect(formatBitRate(0), '0 B/s');
    expect(formatBitRate(-5), '0 B/s');
    expect(formatBitRate(8), '1 B/s');
    expect(formatBitRate(8 * 1023), '1023 B/s');
    expect(formatBitRate(8 * 1024), '1.0 KiB/s');
    expect(formatBitRate(78800), '9.6 KiB/s');
    expect(formatBitRate(999999), '122.1 KiB/s', reason: 'just under 1 Mbit');
    expect(formatBitRate(1000000), '1.0 Mbps');
    expect(formatBitRate(84200000), '84.2 Mbps');
    expect(formatBitRate(940000000), '940.0 Mbps');
  });

  test('totals use binary units; shares and changes', () {
    expect(
      formatBytes(1024 * 1024 - 1),
      '1.00 MiB',
      reason: 'never "1024 KiB"',
    );
    expect(formatBytes(1024 * 1024), '1.00 MiB');
    expect(formatBytes(1024 * 1024 * 1024), '1.00 GiB');
    expect(formatShare(0), '0%');
    expect(formatShare(0.004), '<1%');
    expect(formatShare(0.42), '42%');
    expect(formatShare(1.5), '100%');
    expect(formatChange(24, 20), '+20%');
    expect(formatChange(15, 20), '−25%');
    expect(formatChange(20, 20), 'No change');
    expect(formatChange(5, 0), 'New');
  });
}
