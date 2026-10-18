import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of reading the phone's own Wi-Fi scan results.
enum WifiScanStatus {
  ok,

  /// Android shares scan results only with location permission.
  permissionDenied,

  /// Denied with "don't ask again"; only system settings can grant it.
  permissionBlocked,
  wifiOff,

  /// Not Android, or the native channel is missing.
  unsupported,
  failed,
}

/// One access point the phone heard (Android `ScanResult`).
class WifiScanResult {
  const WifiScanResult({
    required this.ssid,
    required this.bssid,
    required this.frequency,
    required this.level,
    required this.capabilities,
  });

  /// Empty for hidden networks.
  final String ssid;
  final String bssid;

  /// MHz.
  final int frequency;

  /// dBm.
  final int level;
  final String capabilities;

  bool get hidden => ssid.trim().isEmpty;

  String get band => frequency <= 0
      ? 'Unknown band'
      : frequency < 3000
      ? '2.4 GHz'
      : frequency < 5925
      ? '5 GHz'
      : '6 GHz';

  /// No WEP/WPA/RSN element advertised.
  bool get open => !RegExp(
    r'WPA|RSN|WEP|SAE|PSK|EAP|OWE',
  ).hasMatch(capabilities.toUpperCase());

  static WifiScanResult? parse(Object? raw) {
    if (raw is! Map) return null;
    final bssid = raw['bssid'];
    if (bssid is! String || bssid.isEmpty) return null;
    int n(Object? v) => v is num ? v.toInt() : 0;
    return WifiScanResult(
      ssid: raw['ssid'] is String ? raw['ssid'] as String : '',
      bssid: bssid.toLowerCase(),
      frequency: n(raw['frequency']),
      level: n(raw['level']),
      capabilities: raw['capabilities'] is String
          ? raw['capabilities'] as String
          : '',
    );
  }
}

class WifiScanSnapshot {
  const WifiScanSnapshot({
    required this.status,
    this.results = const [],
    this.connectedBssid,
    this.connectedSsid,
    this.at,
    this.message,
  });

  final WifiScanStatus status;
  final List<WifiScanResult> results;

  /// BSSID of the access point this phone is joined to, when known.
  final String? connectedBssid;
  final String? connectedSsid;
  final DateTime? at;
  final String? message;

  static WifiScanSnapshot fromChannel(Map<String, dynamic> raw, DateTime at) {
    if (raw['wifiEnabled'] == false) {
      return WifiScanSnapshot(status: WifiScanStatus.wifiOff, at: at);
    }
    final list = raw['results'];
    String? clean(Object? v) {
      if (v is! String) return null;
      final s = v.trim().replaceAll('"', '');
      // Android masks these without permission or when not connected.
      if (s.isEmpty || s == '02:00:00:00:00:00' || s == '<unknown ssid>') {
        return null;
      }
      return s;
    }

    return WifiScanSnapshot(
      status: WifiScanStatus.ok,
      at: at,
      connectedBssid: clean(raw['connectedBssid'])?.toLowerCase(),
      connectedSsid: clean(raw['connectedSsid']),
      results: [
        if (list is List)
          for (final r in list) ?WifiScanResult.parse(r),
      ],
    );
  }
}

/// Reads nearby Wi-Fi networks heard by this phone. Read-only: it never
/// joins, changes or forgets a network.
abstract class WifiScanner {
  /// Without [requestPermission] it never shows a permission prompt.
  Future<WifiScanSnapshot> scan({bool requestPermission = false});
}

class PlatformWifiScanner implements WifiScanner {
  const PlatformWifiScanner({
    this._channel = const MethodChannel('tt_router/wifi_scan'),
  });

  final MethodChannel _channel;

  @override
  Future<WifiScanSnapshot> scan({bool requestPermission = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const WifiScanSnapshot(
        status: WifiScanStatus.unsupported,
        message: 'Nearby network scanning is available on Android only.',
      );
    }
    try {
      var permission = await Permission.locationWhenInUse.status;
      if (!permission.isGranted && requestPermission) {
        permission = await Permission.locationWhenInUse.request();
      }
      if (permission.isPermanentlyDenied) {
        return const WifiScanSnapshot(status: WifiScanStatus.permissionBlocked);
      }
      if (!permission.isGranted) {
        return const WifiScanSnapshot(status: WifiScanStatus.permissionDenied);
      }
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('scan')
          .timeout(const Duration(seconds: 15));
      return WifiScanSnapshot.fromChannel(raw ?? const {}, DateTime.now());
    } on PlatformException catch (e) {
      if (e.code == 'permission') {
        return const WifiScanSnapshot(status: WifiScanStatus.permissionDenied);
      }
      return WifiScanSnapshot(
        status: WifiScanStatus.failed,
        message: e.message ?? 'Wi-Fi scan failed.',
      );
    } on MissingPluginException {
      return const WifiScanSnapshot(
        status: WifiScanStatus.unsupported,
        message: 'Nearby network scanning is not available on this device.',
      );
    } catch (_) {
      return const WifiScanSnapshot(
        status: WifiScanStatus.failed,
        message: 'Wi-Fi scan failed.',
      );
    }
  }
}
