// Nokia protocol snapshot from TT Router; see README.md for provenance.
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

class NokiaException implements Exception {
  const NokiaException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class NokiaTransport {
  Future<Map<String, dynamic>> context();
  Future<List<String>> resolve(String host);
  Future<Map<String, dynamic>> request(
    Uri base,
    String path, {
    Map<String, String>? form,
    String? cookie,
    String? responseKey,
    String? responseIv,
  });
  Future<void> openWifi();
  Future<Map<String, dynamic>> internet();
  Future<Map<String, String>> encryptForm(String publicKey, String plain);
}

class PlatformNokiaTransport implements NokiaTransport {
  const PlatformNokiaTransport();
  static const _channel = MethodChannel('nokia_home/local');
  @override
  Future<Map<String, dynamic>> context() async =>
      await _channel.invokeMapMethod<String, dynamic>('context') ?? {};
  @override
  Future<List<String>> resolve(String host) async =>
      (await _channel.invokeListMethod<String>('resolve', {'host': host})) ??
      [];
  @override
  Future<void> openWifi() => _channel.invokeMethod('openWifi');
  @override
  Future<Map<String, dynamic>> internet() async =>
      await _channel.invokeMapMethod<String, dynamic>('internet') ?? {};
  @override
  Future<Map<String, String>> encryptForm(
    String publicKey,
    String plain,
  ) async =>
      await _channel.invokeMapMethod<String, String>('encryptForm', {
        'publicKey': publicKey,
        'plain': plain,
      }) ??
      (throw const NokiaException('Local encryption unavailable.'));
  @override
  Future<Map<String, dynamic>> request(
    Uri base,
    String path, {
    Map<String, String>? form,
    String? cookie,
    String? responseKey,
    String? responseIv,
  }) async {
    NokiaService.validateAddress(base);
    NokiaService.validateRequestPath(base, path);
    try {
      final response = await _channel
          .invokeMapMethod<String, dynamic>('request', {
            'url': base.resolve(path).toString(),
            'method': form == null ? 'GET' : 'POST',
            if (form != null) 'body': Uri(queryParameters: form).query,
            'cookie': ?cookie,
            'responseKey': ?responseKey,
            'responseIv': ?responseIv,
          })
          .timeout(const Duration(seconds: 12));
      final status = response?['status'];
      // Beacon 2 returns 299 for successful encrypted owner login.
      if (status is! int || status < 200 || status >= 300) {
        throw NokiaException(
          'Beacon returned HTTP ${response?["status"] ?? "unknown"} for ${Uri.parse(path).path}. Reconnect and retry the owner login.',
        );
      }
      final value = jsonDecode(response!['body'] as String);
      if (value is! Map<String, dynamic>) throw const FormatException();
      return value;
    } on NokiaException {
      rethrow;
    } catch (_) {
      throw const NokiaException(
        'No valid Nokia response. Check the setup Wi-Fi, address and owner login.',
      );
    }
  }
}

Map<String, dynamic> nokiaFirst(Object? value) {
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return value is Map ? Map<String, dynamic>.from(value) : {};
}

class NokiaIdentity {
  NokiaIdentity(this.address, this.capability) {
    final d = nokiaFirst(capability['devapp_cap_info']);
    mac = '${d['devGwMac'] ?? ''}'.toLowerCase().replaceAll('-', ':');
    serial = '${d['devGwSnum'] ?? ''}'.trim();
    mode = '${d['devMode'] ?? ''}'.trim().toUpperCase();
    model = '${capability['_discovery']?['gwmodel'] ?? d['devName'] ?? ''}'
        .trim();
    apiVersion = '${capability['_discovery']?['gwifver'] ?? d['devVer'] ?? ''}'
        .trim();
    if (!RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$').hasMatch(mac) ||
        serial.isEmpty ||
        !['RGW', 'AP_BRIDGE', 'AP'].contains(mode)) {
      throw const NokiaException(
        'The response did not identify a Nokia root. A MAC prefix or SSID alone is insufficient.',
      );
    }
  }
  final Uri address;
  final Map<String, dynamic> capability;
  late final String mac, serial, model, apiVersion, mode;
  bool get bridgeSupported =>
      nokiaFirst(capability['Settings'])['Bridge_Mode'] == 1;
  bool get cloudless =>
      nokiaFirst(capability['RGW_Onboarding'])['Cloudless_Support'] == 1;
  bool sameDevice(NokiaIdentity other) =>
      mac == other.mac && serial == other.serial;
}

/// Verified local CGI protocol from Nokia WiFi 3.260311.00. No cloud keys,
/// BLE receiver protocol, global network binding, or shared router credentials.
class NokiaService {
  NokiaService({this.transport = const PlatformNokiaTransport()});
  final NokiaTransport transport;
  NokiaIdentity? identity;
  String? _cookie, _csrf, _publicKey, _responseKey, _responseIv;
  bool get usesWeb =>
      identity?.model == 'Nokia WiFi Beacon 2' && identity?.apiVersion == '5.5';
  static const webPaths = {
    '/device_status_app.cgi': '/device_status_web_app.cgi',
    '/whw_beacon_mode_app.cgi?getWorkMode':
        '/whw_beacon_mode_app_status_web_app.cgi?getWorkMode',
    '/wlan_list_app.cgi': '/wlan_config_status_web_app.cgi',
    '/device_name_status_app.cgi?gmode=all': '/lan_status_web_app.cgi?wlan',
    '/whw_zerotouchonb_status_app.cgi?gmode=get': '/mesh_status_web_app.cgi',
    '/wan_internet_status_app.cgi': '/wan_internet_status_web_app.cgi',
  };
  bool get authenticated => _cookie != null;
  String? get serverPublicKey => _publicKey;
  static String canonicalKey(String value) =>
      value.replaceAll(RegExp(r"\s+"), "");

  static void validateRequestPath(Uri base, String path) {
    final target = base.resolve(path);
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        target.scheme != base.scheme ||
        target.host != base.host ||
        target.port != base.port ||
        target.userInfo.isNotEmpty ||
        target.hasFragment) {
      throw const NokiaException(
        'Nokia requests must stay on the identified device.',
      );
    }
  }

  static void validateAddress(Uri uri) {
    final p = uri.host.split('.').map(int.tryParse).toList();
    final private =
        p.length == 4 &&
        p.every((n) => n != null && n >= 0 && n <= 255) &&
        (p[0] == 10 ||
            p[0] == 192 && p[1] == 168 ||
            p[0] == 172 && p[1]! >= 16 && p[1]! <= 31);
    final scopedV6 = RegExp(
      r'^fe80:[0-9a-f:]+%(?:25)?wlan0$',
    ).hasMatch(uri.host.toLowerCase());
    if (!(private || scopedV6) ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const NokiaException(
        'Use a private LAN address or a Wi-Fi scoped link-local IPv6 address.',
      );
    }
  }

  void clearSession() {
    _cookie = _csrf = _publicKey = _responseKey = _responseIv = null;
  }

  Future<NokiaIdentity> identify(Uri address) async {
    validateAddress(address);
    final value = await transport.request(
      address,
      '/get_devmap_cap_status_app.cgi',
    );
    try {
      final probe = await transport.request(address, '/login_app.cgi?chk');
      if (probe['gwsnum'] ==
          nokiaFirst(value['devapp_cap_info'])['devGwSnum']) {
        value['_discovery'] = probe;
      }
    } catch (_) {
      /* Older devices may not provide the discovery metadata. */
    }
    return NokiaIdentity(address, value);
  }

  Future<void> select(Uri address) async {
    clearSession();
    identity = null;
    identity = await identify(address);
  }

  Future<void> checkIdentity() async {
    final trusted = identity;
    if (trusted == null) {
      throw const NokiaException('Find and identify the root first.');
    }
    final fresh = await identify(trusted.address);
    if (!trusted.sameDevice(fresh)) {
      clearSession();
      throw const NokiaException(
        'The device at this address changed. No credentials or configuration were sent.',
      );
    }
    identity = fresh;
  }

  Future<void> login(
    String username,
    String password, {
    String? expectedPublicKey,
  }) async {
    clearSession();
    if (username.trim().isEmpty || password.isEmpty) {
      throw const NokiaException(
        'Enter the local administrator credentials from your Beacon.',
      );
    }
    await checkIdentity();
    if (usesWeb) {
      await _loginWeb(
        username.trim(),
        password,
        expectedPublicKey: expectedPublicKey,
      );
      return;
    }
    if (expectedPublicKey != null) {
      throw const NokiaException(
        'The saved encrypted-login capability changed. No credentials were sent.',
      );
    }
    final reply = await transport.request(
      identity!.address,
      '/login_app.cgi',
      form: {'name': username.trim(), 'pswd': password, 'srip': ''},
    );
    final cookie = reply['cookie'];
    if (cookie is! Map ||
        cookie['sid'] is! String ||
        cookie['lsid'] is! String) {
      throw const NokiaException(
        'Owner login was not accepted. Use local administrator credentials, not a Nokia cloud account.',
      );
    }
    // Nokia returns the complete sid=... and lsid=... cookie pairs.
    final sid = cookie['sid'] as String, lsid = cookie['lsid'] as String;
    if (!RegExp(r'^sid=[^;\r\n]+$').hasMatch(sid) ||
        !RegExp(r'^lsid=[^;\r\n]+$').hasMatch(lsid)) {
      throw const NokiaException('Unsupported Nokia session response.');
    }
    _cookie = '$sid; $lsid';
    try {
      await read('/device_status_app.cgi');
    } catch (_) {
      clearSession();
      rethrow;
    }
  }

  /// Beacon 2 CGI 5.5 uses the local WebGUI nonce/RSA/AES protocol.
  /// Verified against this firmware's own crypto_page.js and login handler.
  /// This is the owner's real login; no vendor credentials or cloud service.
  Future<void> _loginWeb(
    String username,
    String password, {
    String? expectedPublicKey,
  }) async {
    final nonce = await transport.request(
      identity!.address,
      '/login_web_app.cgi?nonce',
      form: {'userName': username},
    );
    if (nonce['nonce'] is! String ||
        nonce['randomKey'] is! String ||
        nonce['pubkey'] is! String) {
      throw const NokiaException('Unsupported local login challenge.');
    }
    if (expectedPublicKey != null &&
        canonicalKey(nonce['pubkey'] as String) !=
            canonicalKey(expectedPublicKey)) {
      throw const NokiaException(
        'The Beacon encryption key changed. Saved credentials were not sent. Verify the device and enter its owner login again.',
      );
    }
    String randomKey() => base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    String escape(String s) =>
        s.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '.');
    final key = randomKey(), iv = randomKey();
    final plain = Uri(
      queryParameters: {
        'userhash': username,
        'RandomKeyhash': nonce['randomKey'] as String,
        'response': password,
        'nonce': escape(nonce['nonce'] as String),
        'enckey': escape(key),
        'enciv': escape(iv),
        'nohash': '1',
      },
    ).query;
    final wrapped = await transport.encryptForm(
      nonce['pubkey'] as String,
      plain,
    );
    final reply = await transport.request(
      identity!.address,
      '/login_web_app.cgi',
      form: wrapped,
    );
    final sid = reply['sid'], token = reply['token'];
    if (reply['result'] != 0 ||
        sid is! String ||
        token is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(sid) ||
        token.isEmpty) {
      throw const NokiaException(
        'Nokia owner login rejected. Check the printed local administrator credentials.',
      );
    }
    _cookie = 'sid=$sid';
    _csrf = token;
    _publicKey = nonce['pubkey'] as String;
    _responseKey = key;
    _responseIv = iv;
    try {
      final device = await read('/device_status_app.cgi');
      if (device['SerialNumber'] != identity!.serial) {
        throw const NokiaException(
          'Authenticated device identity did not match the discovered root.',
        );
      }
    } catch (_) {
      clearSession();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> read(String path) async {
    if (identity != null) validateRequestPath(identity!.address, path);
    if (!authenticated || identity == null) {
      throw const NokiaException('Owner login required for Nokia management.');
    }
    final d = await transport.request(
      identity!.address,
      usesWeb ? webPaths[path] ?? path : path,
      cookie: _cookie,
      responseKey: _responseKey,
      responseIv: _responseIv,
    );
    if (d['result'] == -1 || [401, 403].contains(d['reason'])) {
      clearSession();
      throw const NokiaException(
        'Nokia refused this request. Reconnect with the local owner login.',
      );
    }
    return d;
  }

  Future<String?> workMode() async {
    final d = await read('/whw_beacon_mode_app.cgi?getWorkMode');
    final mode = d['workMode'] is String
        ? (d['workMode'] as String).toUpperCase()
        : null;
    return mode == 'CFG' || mode == 'RGW' || mode == 'AP_BRIDGE'
        ? mode as String
        : null;
  }

  /// Local Beacon 2 WebGUI enrollment; acceptance is not mesh connectivity.
  Future<void> changeExtender(String serial, {String? removeMac}) async {
    await checkIdentity();
    if (!usesWeb || !authenticated || await workMode() != 'AP_BRIDGE') {
      throw const NokiaException(
        'Refresh the authorized root in AP bridge mode first.',
      );
    }
    if (!RegExp(r'^ALCL[A-Z0-9]{8}$', caseSensitive: false).hasMatch(serial) ||
        serial.toLowerCase() == identity!.serial.toLowerCase()) {
      throw const NokiaException(
        'Enter the second Beacon’s printed 12-character ALCL serial.',
      );
    }
    final mesh = await read('/mesh_status_web_app.cgi');
    if (mesh['beacon_detail'] is! List || mesh['beaconEntries'] is! List) {
      throw const NokiaException(
        'Mesh inventory is unavailable. No change was sent.',
      );
    }
    final entries = (mesh['beacon_detail'] as List).whereType<Map>().toList();
    final matches = entries
        .where(
          (e) => '${e['SerialNumber']}'.toLowerCase() == serial.toLowerCase(),
        )
        .toList();
    if (removeMac != null) {
      if (matches.length != 1 ||
          matches.single['MACAddress'] != removeMac ||
          removeMac.toLowerCase() == identity!.mac) {
        throw const NokiaException(
          'Extender identity changed. Refresh before removing it.',
        );
      }
    } else {
      final capacity = nokiaFirst(mesh['beaconEntries']);
      final count = int.tryParse('${capacity['BeaconNumberofEntries']}');
      final maximum = int.tryParse('${capacity['MaxNumberOfBeacons']}');
      if (matches.isNotEmpty ||
          count == null ||
          maximum == null ||
          count >= maximum) {
        throw const NokiaException(
          'This serial is already enrolled or mesh capacity is unavailable/full.',
        );
      }
    }
    final form = await transport.encryptForm(
      _publicKey!,
      Uri(
        queryParameters: {
          'SerialNumber': serial,
          'beaconMac': ?removeMac,
          'csrf_token': _csrf!,
        },
      ).query,
    );
    final reply = await transport.request(
      identity!.address,
      '/mesh_web_app.cgi?${removeMac == null ? 'add' : 'del'}',
      form: form,
      cookie: _cookie,
      responseKey: _responseKey,
      responseIv: _responseIv,
    );
    if (reply['result'] != 0) {
      throw const NokiaException(
        'Mesh change was not acknowledged. Refresh the root before retrying.',
      );
    }
  }

  Future<void> enableBridge() async {
    await checkIdentity();
    if (!authenticated ||
        !identity!.bridgeSupported ||
        await workMode() != 'RGW') {
      throw const NokiaException(
        'Bridge change requires owner login, a reported bridge capability and routed-mode read-back.',
      );
    }
    // Acknowledgment is deliberately not a success state. A reboot can drop
    // this response; the controller always requires a new identity/mode read.
    if (usesWeb) {
      final payload = await transport.encryptForm(
        _publicKey!,
        Uri(
          queryParameters: {
            'act': 'setWorkMode',
            'brEnable': '1',
            'csrf_token': _csrf!,
          },
        ).query,
      );
      final reply = await transport.request(
        identity!.address,
        '/whw_beacon_mode_app_web_app.cgi',
        cookie: _cookie,
        form: payload,
        responseKey: _responseKey,
        responseIv: _responseIv,
      );
      if (reply['result'] != 0) {
        throw const NokiaException(
          'Nokia rejected the bridge change. Reconnect and read the mode.',
        );
      }
      return;
    }
    await transport.request(
      identity!.address,
      '/whw_beacon_mode_app.cgi',
      cookie: _cookie,
      form: {'act': 'setWorkMode', 'brEnable': '1'},
    );
  }
}
