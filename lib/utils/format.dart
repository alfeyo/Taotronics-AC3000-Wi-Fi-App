/// Shared display formatting for router values.
library;

String _scaled(double value) => value >= 100
    ? value.toStringAsFixed(0)
    : value >= 10
    ? value.toStringAsFixed(1)
    : value.toStringAsFixed(2);

/// Bytes per second as B/s, KiB/s, MiB/s or GiB/s (1024 based, labelled as such).
String formatRate(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  const units = ['B/s', 'KiB/s', 'MiB/s', 'GiB/s'];
  var value = bytesPerSecond.toDouble();
  var unit = 0;
  while (value >= 1023.5 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${_scaled(value)} ${units[unit]}';
}

/// Byte counts as B, KiB, MiB, GiB or TiB (1024 based, labelled as such,
/// matching Argon's dashboard).
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1023.5 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${_scaled(value)} ${units[unit]}';
}

/// A duration in seconds as "3d 4h", "5h 12m", "7m" or "40s".
String formatUptime(int seconds) {
  if (seconds <= 0) return '—';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '${seconds}s';
}

/// "just now", "12s ago", "3 min ago", "2 h ago", "10 d ago".
String formatAge(DateTime? time, {DateTime? now}) {
  if (time == null) return 'never';
  final age = (now ?? DateTime.now()).difference(time);
  if (age.inSeconds < 5) return 'just now';
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 48) return '${age.inHours} h ago';
  return '${age.inDays} d ago';
}

/// A live link speed that Argon reports in BITS per second.
///
/// At or above 1 Mbit/s it reads as "x.x Mbps" (decimal, as ISPs quote
/// speeds); below that the rate is shown in bytes with binary units so small
/// flows stay accurate: 78 800 bit/s → "9.6 KiB/s".
String formatBitRate(num bitsPerSecond) {
  if (bitsPerSecond.isNaN || bitsPerSecond <= 0) return '0 B/s';
  if (bitsPerSecond >= 1000000) {
    return '${(bitsPerSecond / 1000000).toStringAsFixed(1)} Mbps';
  }
  final bytes = bitsPerSecond / 8;
  if (bytes < 1024) return '${bytes.round()} B/s';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB/s';
  return '${(kib / 1024).toStringAsFixed(1)} MiB/s';
}

/// A 0..1 share as a percentage; tiny non-zero shares read "<1%".
String formatShare(double share) {
  final pct = share.clamp(0.0, 1.0) * 100;
  if (pct > 0 && pct < 1) return '<1%';
  return '${pct.round()}%';
}

/// Signed change between two periods, e.g. "+12% vs previous 7 days".
String formatChange(int current, int previous) {
  if (previous <= 0) return current > 0 ? 'New' : 'No change';
  final pct = ((current - previous) / previous * 100).round();
  if (pct == 0) return 'No change';
  return '${pct > 0 ? '+' : '−'}${pct.abs()}%';
}
