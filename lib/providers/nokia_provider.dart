import 'dart:async';
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
    this.enrollmentPollInterval = const Duration(seconds: 5),
    this.enrollmentWatchDuration = const Duration(minutes: 3),
  }) : service = service ?? NokiaService(),
       storage = storage ?? const FlutterSecureStorage();
  final NokiaService service;
  final FlutterSecureStorage storage;
  final WifiScanner scanner;
  final Duration enrollmentPollInterval, enrollmentWatchDuration;
  Timer? _enrollmentPoll, _enrollmentDeadline;
  int _enrollmentEpoch = 0;
  Completer<void>? _enrollmentRead;
  bool get enrollmentReading => _enrollmentRead != null;
  bool watchingEnrollment = false;
  String? enrollmentSerial;
  String enrollmentStatus = 'No enrollment requested';
  DateTime? meshObservedAt;
  final List<String> enrollmentEvents = [];
  bool get meshCurrent =>
      meshObservedAt != null &&
      DateTime.now().difference(meshObservedAt!) < const Duration(seconds: 90);

  // Only the fields rendered by this firmware's own mesh page are retained in
  // the observation log. No credentials, full responses or guessed radio fields.
  static String reportedValue(Object? value) {
    if (value is! String && value is! num) return 'Not reported';
    final text = '$value'.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    if (text.isEmpty) return 'Not reported';
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  void _recordEnrollment(String text) {
    if (enrollmentStatus == text && enrollmentEvents.isNotEmpty) return;
    enrollmentStatus = text;
    enrollmentEvents.add(text);
    if (enrollmentEvents.length > 12) enrollmentEvents.removeAt(0);
  }

  void stopEnrollmentObservation({String? reason}) {
    _enrollmentEpoch++;
    _enrollmentPoll?.cancel();
    _enrollmentDeadline?.cancel();
    watchingEnrollment = false;
    if (reason != null && enrollmentSerial != null) _recordEnrollment(reason);
    _emit();
  }

  /// Read-only, bounded observation. Stopping never cancels device enrollment.
  void observeExtender(String serial) {
    if (_disposed ||
        busy ||
        enrollmentReading ||
        !service.authenticated ||
        !service.usesWeb ||
        !RegExp(r'^ALCL[A-Z0-9]{8}$', caseSensitive: false).hasMatch(serial)) {
      return;
    }
    stopEnrollmentObservation();
    if (enrollmentSerial != serial.toUpperCase()) enrollmentEvents.clear();
    enrollmentSerial = serial.toUpperCase();
    final root = identity!;
    final epoch = _enrollmentEpoch;
    watchingEnrollment = true;
    _recordEnrollment(
      'Reading root reports; client internet remains unverified.',
    );
    _enrollmentDeadline = Timer(enrollmentWatchDuration, () {
      stopEnrollmentObservation(
        reason:
            'Observation window ended. Refresh to continue; this is not an enrollment failure or success.',
      );
    });
    Future<void> poll() async {
      if (_disposed || !watchingEnrollment || epoch != _enrollmentEpoch) return;
      if (!busy && !enrollmentReading) {
        final pendingRead = Completer<void>();
        _enrollmentRead = pendingRead;
        try {
          await service.checkIdentity();
          if (_disposed || epoch != _enrollmentEpoch) return;
          if (identity == null || !root.sameDevice(identity!)) {
            throw const NokiaException('The selected root changed.');
          }
          final report = await service.read('/mesh_status_web_app.cgi');
          if (_disposed || epoch != _enrollmentEpoch) return;
          if (report['beacon_detail'] is! List) {
            throw const NokiaException('Mesh inventory is unavailable.');
          }
          extenders = report;
          meshObservedAt = DateTime.now();
          final rows = meshNodes
              .where(
                (e) => '${e['SerialNumber']}'.toUpperCase() == enrollmentSerial,
              )
              .toList();
          _recordEnrollment(
            rows.length == 1
                ? 'Listed · onboarding: ${reportedValue(rows.single['OnboardStatus'])} · backhaul: ${reportedValue(rows.single['BackhaulStatus'])}'
                : rows.isEmpty
                ? 'Not listed by this root yet. Keep the extender near the root and refresh.'
                : 'Conflicting serial records. Connectivity is unverified.',
          );
        } catch (_) {
          if (!_disposed && epoch == _enrollmentEpoch) {
            meshObservedAt = null;
            stopEnrollmentObservation(
              reason:
                  'Root read-back unavailable. Reconnect to the trusted root, refresh, and observe again. Do not resend enrollment blindly.',
            );
          }
        } finally {
          _enrollmentRead = null;
          pendingRead.complete();
          _emit();
        }
      }
      if (!_disposed && watchingEnrollment && epoch == _enrollmentEpoch) {
        _enrollmentPoll = Timer(enrollmentPollInterval, poll);
      }
    }

    _emit();
    unawaited(poll());
  }

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
  // Capability review is specific to this observed firmware, not all Beacons.
  // Freshness governs live status independently of the recorded limitation.
  bool get requiresWiredRoot =>
      service.usesWeb &&
      device?['ModelName'] == 'Nokia WiFi Beacon 2' &&
      device?['SoftwareVersion'] == '3FE49334IJJJ09';
  String get uplinkHealth => !current
      ? 'Unknown · refresh Nokia'
      : wan?['gwwanup'] == 1
      ? 'Nokia reports uplink online'
      : wan?['gwwanup'] == 0
      ? 'Nokia reports uplink offline'
      : 'Not reported';
  DateTime? diagnosticAt;
  Map<String, dynamic> diagnosticPhone = {};
  String diagnosticRoot = 'Not checked', diagnosticInternet = 'Not checked';
  bool diagnosticNokiaRadio = false, diagnosticStable = false;
  bool get diagnosticsCurrent =>
      diagnosticAt != null &&
      DateTime.now().difference(diagnosticAt!) < const Duration(seconds: 90);
  String? get connectionWarning {
    if (current && wan?['gwwanup'] == 0) {
      return 'Nokia reports its uplink offline. Restore the TaoTronics LAN → Nokia WAN Ethernet cable. No wireless alternative has been verified.';
    }
    if (diagnosticsCurrent &&
        (diagnosticRoot == 'Unreachable at saved address' ||
            diagnosticNokiaRadio &&
                (diagnosticPhone['ip'] == null ||
                    diagnosticInternet != 'Passed'))) {
      return 'Nokia uplink is not verified. A broadcasting SSID does not prove internet access. Restore the root Ethernet cable, then reconnect and check again. An unreachable address may also have changed.';
    }
    return null;
  }

  /// Independent, read-only diagnostics remain usable when owner management
  /// and DHCP fail. Internet is always bound to Wi-Fi by the native transport.
  Future<void> diagnoseConnection() => run(() async {
    diagnosticAt = null;
    clientVerifiedAt = null;
    diagnosticPhone = {};
    diagnosticRoot = diagnosticInternet = 'Not checked';
    diagnosticNokiaRadio = diagnosticStable = false;
    final before = await service.transport.context();
    diagnosticPhone = before;
    final address =
        identity?.address ??
        (savedAddress == null ? null : Uri.tryParse(savedAddress!));
    final expectedMac = identity?.mac ?? savedMac;
    final expectedSerial = identity?.serial ?? savedSerial;
    if (address != null) {
      try {
        final found = await service.identify(address);
        diagnosticRoot =
            found.mac == expectedMac && found.serial == expectedSerial
            ? 'Matching root replied'
            : 'Different or untrusted identity';
      } catch (_) {
        diagnosticRoot = 'Unreachable at saved address';
      }
    }
    Map<String, dynamic>? internet;
    if (before['ip'] == null || before['network'] == null) {
      diagnosticInternet = 'No Wi-Fi address / network';
    } else {
      try {
        internet = await service.transport.internet();
        diagnosticInternet = internet['ok'] == true ? 'Passed' : 'Failed';
      } catch (_) {
        diagnosticInternet = 'Failed';
      }
    }
    final after = await service.transport.context();
    diagnosticStable = [
      'network',
      'bssid',
      'ip',
      'gateway',
      'dhcpServer',
    ].every((key) => before[key] == after[key]);
    if (!diagnosticStable ||
        internet != null && internet['network'] != before['network']) {
      diagnosticInternet = 'Network changed during check';
      diagnosticStable = false;
    }
    diagnosticNokiaRadio =
        diagnosticStable &&
        wirelessProfiles.any(
          (r) =>
              r['Enable'] == 1 &&
              r['BSSID'] is String &&
              (r['BSSID'] as String).toLowerCase() ==
                  '${before['bssid']}'.toLowerCase(),
        );
    diagnosticAt = DateTime.now();
  });
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
      // Foreground operations wait for an existing observation read instead of
      // overlapping authentication/state changes or silently dropping a tap.
      final pendingRead = _enrollmentRead;
      if (pendingRead != null) await pendingRead.future;
      if (!_disposed) await operation();
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
    stopEnrollmentObservation();
    enrollmentSerial = null;
    enrollmentEvents.clear();
    meshObservedAt = null;
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
    meshObservedAt = extenders?['beacon_detail'] is List
        ? DateTime.now()
        : null;
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
    stopEnrollmentObservation();
    if (removeMac == null && !clientVerified) {
      throw const NokiaException(
        'Verify the root’s client internet and DHCP path before adding an extender.',
      );
    }
    enrollmentSerial = serial.toUpperCase();
    enrollmentEvents.clear();
    meshObservedAt = null;
    _recordEnrollment(
      removeMac == null
          ? 'Submitting enrollment once.'
          : 'Submitting removal once.',
    );
    try {
      await service.changeExtender(serial, removeMac: removeMac);
    } catch (_) {
      _recordEnrollment(
        'Request not confirmed. Refresh the root before retrying; it may have received the request.',
      );
      rethrow;
    }
    if (_disposed) return;
    _recordEnrollment(
      'Request acknowledged. Reading the root; connectivity is unverified.',
    );
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
    stopEnrollmentObservation();
    enrollmentSerial = null;
    enrollmentEvents.clear();
    meshObservedAt = null;
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
    stopEnrollmentObservation();
    service.clearSession();
    super.dispose();
  }
}
