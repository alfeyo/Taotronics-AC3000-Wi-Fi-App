import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/nokia_service.dart';
import '../services/wifi_scan.dart';

/// User-driven, single-flight Nokia management. No background discovery loop and
/// no second TaoTronics MQTT session. Secrets are confined to secure storage.
class NokiaProvider extends ChangeNotifier {
  NokiaProvider({
    NokiaService? service,
    FlutterSecureStorage? storage,
    this.scanner = const PlatformWifiScanner(),
  }) : service = service ?? NokiaService(),
       storage = storage ?? const FlutterSecureStorage();
  final NokiaService service;
  final FlutterSecureStorage storage;
  final WifiScanner scanner;
  bool busy = false, _disposed = false;
  String? error, message, mode;
  String? savedAddress, savedMac, savedSerial;
  DateTime? observedAt;
  Map<String, dynamic>? device, wlan, wlan5, clients, extenders, wan;
  DateTime? clientVerifiedAt;
  String? verifiedGateway;
  bool get clientVerified =>
      bridgeVerified &&
      clientVerifiedAt != null &&
      DateTime.now().difference(clientVerifiedAt!) <
          const Duration(seconds: 90);
  Map<String, dynamic> phone = {};
  WifiScanSnapshot? scan;
  bool bridgeRequested = false;
  bool get current =>
      observedAt != null &&
      DateTime.now().difference(observedAt!) < const Duration(seconds: 90) &&
      error == null;
  bool get bridgeVerified => current && mode == 'AP_BRIDGE';
  NokiaIdentity? get identity => service.identity;
  static const storageKey = 'nokia.local.owner.v1';
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    message = null;
    _emit();
    try {
      await operation();
    } catch (e) {
      error = e is NokiaException
          ? e.message
          : 'Local connection unavailable. Rejoin the Beacon network and refresh.';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> load() => run(() async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw == null) return;
      final d = jsonDecode(raw) as Map;
      savedAddress = d['address'] as String?;
      savedMac = d['mac'] as String?;
      savedSerial = d['serial'] as String?;
      message =
          'Saved Beacon available. Discover or reconnect to verify its current identity.';
    } catch (_) {
      error = 'Saved Nokia identity could not be read. Find the Beacon again.';
    }
  });

  /// Candidates are hints only. Each accepted address must return the complete
  /// Nokia root identity. IPv6 EUI-64 candidates cover factory units without DHCP.
  static String? linkLocalCandidate(String mac) {
    if (!RegExp(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$').hasMatch(mac)) {
      return null;
    }
    final b = mac.split(':').map((s) => int.parse(s, radix: 16)).toList();
    b[0] ^= 2;
    // Nokia factory SSID suffix contains the root MAC's final two octets.
    final eui = [b[0], b[1], b[2], 255, 254, b[3], b[4], b[5]];
    final groups = [
      for (var i = 0; i < 8; i += 2)
        ((eui[i] << 8) | eui[i + 1]).toRadixString(16),
    ];
    return 'http://[fe80::${groups.join(':')}%25wlan0]';
  }

  static String? factoryRootMac(WifiScanResult r) {
    final suffix = RegExp(
      r'^NOKIA-([0-9A-F]{4})$',
      caseSensitive: false,
    ).firstMatch(r.ssid)?.group(1);
    if (suffix == null) return null;
    final p = r.bssid.split(':');
    if (p.length != 6) return null;
    return [
      ...p.take(4),
      suffix.substring(0, 2),
      suffix.substring(2),
    ].join(':').toLowerCase();
  }

  Future<void> discover({
    String? address,
    List<String> candidates = const [],
  }) => run(() async {
    observedAt = null;
    clientVerifiedAt = null;
    mode = null;
    device = wlan = wlan5 = clients = extenders = wan = null;
    service.clearSession();
    phone = await service.transport.context();
    scan = await scanner.scan(requestPermission: true);
    final addresses = <String>{};
    if (address?.trim().isNotEmpty == true) addresses.add(address!.trim());
    if (savedAddress != null) addresses.add(savedAddress!);
    if (phone['ssid'] is String && phone['bssid'] is String) {
      final connectedMac = factoryRootMac(
        WifiScanResult(
          ssid: phone['ssid'] as String,
          bssid: phone['bssid'] as String,
          frequency: 0,
          level: 0,
          capabilities: '',
        ),
      );
      if (connectedMac != null) {
        addresses.add(linkLocalCandidate(connectedMac)!);
      }
    }

    for (final r in scan?.results ?? <WifiScanResult>[]) {
      if (r.ageSeconds != null && r.ageSeconds! > 120) continue;
      final mac = factoryRootMac(r);
      if (mac != null) addresses.add(linkLocalCandidate(mac)!);
    }
    for (final ip in candidates.take(4)) {
      addresses.add('http://$ip');
    }
    if (phone['gateway'] is String) addresses.add('http://${phone['gateway']}');
    for (final host in ['nokiadevice.local', 'www.webgui.Nokiawifi.com']) {
      try {
        for (final ip
            in await service.transport
                .resolve(host)
                .timeout(const Duration(seconds: 3))) {
          addresses.add('http://$ip');
        }
      } catch (_) {
        /* bounded optional discovery */
      }
    }
    for (final a in addresses.take(8)) {
      try {
        await service.select(Uri.parse(a));
        if (savedMac != null &&
            (identity!.mac != savedMac || identity!.serial != savedSerial)) {
          message =
              'Different root found. Use its own local owner credentials.';
        } else {
          message =
              'Root identified. Local owner login is required to continue.';
        }
        observedAt = DateTime.now();
        return;
      } catch (_) {
        /* candidate identity not verified */
      }
    }
    throw NokiaException(
      phone['ip'] == null
          ? 'The setup Wi-Fi has no IPv4 lease. No Nokia identity replied over its local IPv6 candidates. Stay connected and retry; this is not evidence of a cable fault.'
          : 'No verified Nokia root replied. Join its factory setup Wi-Fi or enter its observed LAN address.',
    );
  });
  Future<void> login(String user, String password) => run(() async {
    await service.login(user, password);
    await _refresh();
    await storage.write(
      key: storageKey,
      value: jsonEncode({
        'address': identity!.address.toString(),
        'mac': identity!.mac,
        'serial': identity!.serial,
        'username': user,
        if (service.serverPublicKey != null) 'password': password,
        if (service.serverPublicKey != null)
          'serverPublicKey': service.serverPublicKey,
      }),
    );
    savedAddress = identity!.address.toString();
    savedMac = identity!.mac;
    savedSerial = identity!.serial;
    message = 'Owner session verified and saved securely on this phone.';
  });
  Future<void> reconnect() => run(() async {
    final raw = await storage.read(key: storageKey);
    if (raw == null) {
      throw const NokiaException(
        'Find the root and sign in with its local owner credentials.',
      );
    }
    final d = jsonDecode(raw) as Map;
    final candidate =
        identity != null &&
            identity!.mac == d['mac'] &&
            identity!.serial == d['serial']
        ? identity!.address
        : Uri.parse(d['address'] as String);
    await service.select(candidate);
    if (identity!.mac != d['mac'] || identity!.serial != d['serial']) {
      throw const NokiaException(
        'Saved address now reports another device. Credentials were not sent.',
      );
    }
    final pinned = d['serverPublicKey'];
    if (pinned is! String || pinned.isEmpty || d['password'] is! String) {
      throw const NokiaException(
        'Enter the owner login once to establish a trusted device encryption key. Saved credentials were not sent.',
      );
    }
    await service.login(
      d['username'] as String,
      d['password'] as String,
      expectedPublicKey: pinned,
    );
    await _refresh();
    d['address'] = identity!.address.toString();
    await storage.write(key: storageKey, value: jsonEncode(d));
    savedAddress = identity!.address.toString();
  });
  Future<void> refresh() => run(_refresh);
  Future<void> _refresh() async {
    observedAt = null;
    await service.checkIdentity();
    device = await service.read('/device_status_app.cgi');
    mode = await service.workMode();
    // Optional endpoint failures remain unknown; they never manufacture zero
    // clients, firmware, bridge status or internet success.
    Future<Map<String, dynamic>?> optional(String p) async {
      try {
        return await service.read(p);
      } catch (_) {
        return null;
      }
    }

    wlan = await optional('/wlan_list_app.cgi');
    wlan5 = service.usesWeb
        ? await optional('/wlan_config_status_web_app.cgi?v=11ac')
        : null;
    clients = await optional('/device_name_status_app.cgi?gmode=all');
    extenders = await optional('/whw_zerotouchonb_status_app.cgi?gmode=get');
    wan = await optional('/wan_internet_status_app.cgi');
    phone = await service.transport.context();
    observedAt = DateTime.now();
    if (mode == 'AP_BRIDGE') bridgeRequested = false;
  }

  Future<void> enableBridge() => run(() async {
    bridgeRequested = true;
    observedAt = null;
    try {
      await service.enableBridge();
    } finally {
      service.clearSession();
      mode = null;
      message =
          'Bridge change requested; reboot and read-back are pending. Reconnect to the same root to verify. Internet and DHCP still need a client check.';
    }
  });
  List<Map<String, dynamic>> get wirelessProfiles => [
    for (final data in [wlan, wlan5])
      for (final key in ['wlan_config_glb', 'wlan_config_glb11ac'])
        if (data?[key] is List)
          for (final r in data![key] as List)
            if (r is Map) Map<String, dynamic>.from(r),
  ];
  Future<void> verifyClient(String expectedGateway) => run(() async {
    clientVerifiedAt = null;
    if (!bridgeVerified) {
      throw const NokiaException('Refresh and confirm AP bridge mode first.');
    }
    final before = await service.transport.context();
    final bssid = '${before['bssid']}'.toLowerCase();
    final rootRadios = wirelessProfiles
        .where((r) => r['Enable'] == 1)
        .map((r) => '${r['BSSID']}'.toLowerCase())
        .toSet();
    if (!rootRadios.contains(bssid)) {
      throw const NokiaException(
        'Connect this phone to a reported Nokia radio before checking the client path.',
      );
    }
    if (expectedGateway.isEmpty ||
        before['gateway'] != expectedGateway ||
        before['dhcpServer'] != expectedGateway ||
        before['ip'] == null) {
      throw const NokiaException(
        'The phone has not confirmed a TaoTronics DHCP lease and default gateway through Nokia.',
      );
    }
    final result = await service.transport.internet();
    final after = await service.transport.context();
    if (result['ok'] != true ||
        result['network'] != before['network'] ||
        after['network'] != before['network'] ||
        after['bssid'] != before['bssid'] ||
        after['ip'] != before['ip'] ||
        after['gateway'] != before['gateway']) {
      throw const NokiaException(
        'Internet was not verified over a stable Nokia Wi-Fi connection.',
      );
    }
    phone = after;
    verifiedGateway = expectedGateway;
    clientVerifiedAt = DateTime.now();
    message =
        'This phone is online through Nokia. TaoTronics supplied its network address and gateway.';
  });

  List<Map<String, dynamic>> get reportedClients => [
    if (clients?['device_cfg'] is List)
      for (final row in clients!['device_cfg'] as List)
        if (row is Map) Map<String, dynamic>.from(row),
  ];
  List<Map<String, dynamic>> get meshNodes => [
    if (extenders?['beacon_detail'] is List)
      for (final e in extenders!['beacon_detail'] as List)
        if (e is Map && '${e['MACAddress']}'.toLowerCase() != identity?.mac)
          Map<String, dynamic>.from(e),
  ];
  Future<void> changeExtender(
    String serial, {
    String? removeMac,
  }) => run(() async {
    if (removeMac == null && !clientVerified) {
      throw const NokiaException(
        'Verify the root’s client internet and DHCP path before adding an extender.',
      );
    }
    await service.changeExtender(serial, removeMac: removeMac);
    await _refresh();
    final present = meshNodes.any(
      (e) => '${e['SerialNumber']}'.toLowerCase() == serial.toLowerCase(),
    );
    message = removeMac == null
        ? present
              ? 'Enrollment is listed by the root. Connectivity and backhaul still require observation.'
              : 'Enrollment requested; the root has not listed this serial yet. Refresh to verify.'
        : present
        ? 'Removal requested but the root still lists this extender.'
        : 'The root no longer lists this extender.';
  });

  Future<void> forget() => run(() async {
    await storage.delete(key: storageKey);
    service.clearSession();
    service.identity = null;
    savedAddress = savedMac = savedSerial = null;
    observedAt = null;
    clientVerifiedAt = null;
    mode = null;
    device = wlan = wlan5 = clients = extenders = wan = null;
    message = 'Nokia login removed from this phone.';
  });
  @override
  void dispose() {
    _disposed = true;
    service.clearSession();
    super.dispose();
  }
}
