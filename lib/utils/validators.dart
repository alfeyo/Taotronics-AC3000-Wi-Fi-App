import 'dart:convert';

/// Form validators. Each returns an error message, or null when valid.
abstract final class Validators {
  /// SSIDs are 1–32 bytes (UTF-8).
  static String? ssid(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter a network name';
    if (utf8.encode(text).length > 32) {
      return 'Network names can be at most 32 bytes';
    }
    return null;
  }

  /// WPA/WPA2/WPA3 personal: 8–63 printable ASCII characters, or 64 hex
  /// digits. Open networks ([secured] false) need no password.
  static String? wifiPassword(String? value, {bool secured = true}) {
    if (!secured) return null;
    final text = value ?? '';
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text)) return null;
    if (text.length < 8) return 'Use at least 8 characters';
    if (text.length > 63) return 'Use at most 63 characters';
    if (!RegExp(r'^[\x20-\x7e]+$').hasMatch(text)) {
      return 'Use letters, numbers and standard symbols only';
    }
    return null;
  }

  static bool isIpv4(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (!RegExp(r'^\d{1,3}$').hasMatch(part)) return false;
      final n = int.parse(part);
      if (n > 255) return false;
      if (part.length > 1 && part.startsWith('0')) return false;
    }
    return true;
  }

  static String? ipv4(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Enter an IP address' : null;
    return isIpv4(text) ? null : 'Enter an address like 192.168.10.1';
  }

  /// Contiguous netmask such as 255.255.255.0.
  static String? netmask(String? value) {
    final text = value?.trim() ?? '';
    if (!isIpv4(text)) return 'Enter a mask like 255.255.255.0';
    final bits = text
        .split('.')
        .map((p) => int.parse(p).toRadixString(2).padLeft(8, '0'))
        .join();
    if (bits.contains('01') || !bits.contains('1')) {
      return 'Not a valid subnet mask';
    }
    return null;
  }

  static String? port(String? value) {
    final n = int.tryParse(value?.trim() ?? '');
    if (n == null || n < 1 || n > 65535) return 'Use a port from 1 to 65535';
    return null;
  }

  static String? vlanId(String? value) {
    final n = int.tryParse(value?.trim() ?? '');
    if (n == null || n < 1 || n > 4094) return 'Use a VLAN ID from 1 to 4094';
    return null;
  }

  static String? required(String? value, String label) =>
      (value?.trim().isEmpty ?? true) ? 'Enter $label' : null;

  /// Whether [a] and [b] are in the same subnet defined by [mask].
  static bool sameSubnet(String a, String b, String mask) {
    if (!isIpv4(a) || !isIpv4(b) || !isIpv4(mask)) return false;
    int value(String ip) =>
        ip.split('.').fold(0, (sum, p) => sum * 256 + int.parse(p));
    final m = value(mask);
    return value(a) & m == value(b) & m;
  }

  static int ipValue(String ip) =>
      ip.split('.').fold(0, (sum, p) => sum * 256 + int.parse(p));
}
