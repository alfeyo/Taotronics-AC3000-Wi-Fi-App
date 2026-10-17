/// Shared display formatting for router values.
library;

String _scaled(double value) => value >= 100
    ? value.toStringAsFixed(0)
    : value >= 10
    ? value.toStringAsFixed(1)
    : value.toStringAsFixed(2);

/// Bytes per second as B/s, KB/s, MB/s or GB/s (1024 based, as the router).
String formatRate(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var value = bytesPerSecond.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${_scaled(value)} ${units[unit]}';
}

/// Byte counts as B, KB, MB, GB or TB (1024 based).
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
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

/// "just now", "12s ago", "3 min ago", "2 h ago".
String formatAge(DateTime? time, {DateTime? now}) {
  if (time == null) return 'never';
  final age = (now ?? DateTime.now()).difference(time);
  if (age.inSeconds < 5) return 'just now';
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  return '${age.inHours} h ago';
}
