import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nokia_home/services/nokia_service.dart';
import 'package:nokia_home/services/wifi_scan.dart';
import 'package:nokia_home/providers/nokia_provider.dart';

Map<String, dynamic> cap({String serial = 'ROOT123', bool bridge = true}) => {
  'devapp_cap_info': [
    {
      'devGwMac': 'b4:63:6f:db:e6:c0',
      'devGwSnum': serial,
      'devName': '',
      'devMode': 'RGW',
      'devState': 'ConfigState',
      'devVer': '',
    },
  ],
  'Settings': [
    {'Bridge_Mode': bridge ? 1 : 0},
  ],
  'RGW_Onboarding': [
    {'Cloudless_Support': 1},
  ],
};

class Transport implements NokiaTransport {
  String serial = 'ROOT123', mode = 'RGW';
  bool deny = false, bridge = true, web = false;
  int capacity = 6;
  String publicKey = 'PUBLIC';
  List<Map<String, dynamic>> nodes = [];
  final plains = <Map<String, String>>[];
  Map<String, dynamic> phone = {'gateway': '192.168.18.1'};
  Map<String, dynamic> online = {'ok': false};
  final writes = <String>[];
  @override
  Future<Map<String, dynamic>> context() async => phone;
  @override
  Future<List<String>> resolve(String h) async => [];
  @override
  Future<void> openWifi() async {}
  @override
  Future<Map<String, dynamic>> internet() async => online;
  @override
  Future<Map<String, String>> encryptForm(
    String publicKey,
    String plain,
  ) async {
    plains.add(Uri.splitQueryString(plain));
    return {'encrypted': '1', 'ct': 'test', 'ck': 'test'};
  }

  @override
  Future<Map<String, dynamic>> request(
    Uri base,
    String path, {
    Map<String, String>? form,
    String? cookie,
    String? responseKey,
    String? responseIv,
  }) async {
    if (form != null) writes.add(path);
    if (path == '/get_devmap_cap_status_app.cgi') {
      final d = cap(serial: serial, bridge: bridge);
      if (web) {
        final info = (d['devapp_cap_info'] as List).first as Map;
        info['devName'] = 'Nokia WiFi Beacon 2';
        info['devVer'] = '5.5';
      }
      return d;
    }
    if (path == '/login_web_app.cgi?nonce') {
      return {
        'nonce': 'challenge==',
        'randomKey': 'random',
        'pubkey': publicKey,
      };
    }
    if (path == '/login_web_app.cgi') {
      return {'result': 0, 'sid': 'session', 'token': 'csrf'};
    }
    if (path == '/device_status_web_app.cgi') {
      return {
        'SerialNumber': serial,
        'ModelName': 'Nokia WiFi Beacon 2',
        'SoftwareVersion': 'test',
      };
    }
    if (path == '/login_app.cgi') {
      return {
        'cookie': {'sid': 'sid=test', 'lsid': 'lsid=test'},
      };
    }
    if (path == '/device_status_app.cgi') {
      return deny
          ? {'result': -1, 'reason': 403}
          : {
              'device': [
                {'model': 'Beacon 2', 'softwareVersion': 'test'},
              ],
            };
    }
    if (path == '/mesh_status_web_app.cgi') {
      return {
        'beacon_detail': nodes,
        'beaconEntries': [
          {
            'BeaconNumberofEntries': nodes.length,
            'MaxNumberOfBeacons': capacity,
          },
        ],
      };
    }
    if (path.contains('getWorkMode')) return {'result': 0, 'workMode': mode};
    return {'result': 0};
  }
}

class Scanner implements WifiScanner {
  @override
  Future<WifiScanSnapshot> scan({bool requestPermission = false}) async =>
      const WifiScanSnapshot(status: WifiScanStatus.ok);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native transport accepts Nokia HTTP 299 and rejects redirects',
    () async {
      const channel = MethodChannel('nokia_home/local');
      var status = 299;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': status, 'body': '{"result":0}'},
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const transport = PlatformNokiaTransport();
      final base = Uri.parse('http://192.168.18.1');
      expect(await transport.request(base, '/login_web_app.cgi'), {
        'result': 0,
      });
      status = 302;
      await expectLater(
        transport.request(base, '/login_web_app.cgi'),
        throwsA(isA<NokiaException>()),
      );
    },
  );
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'wired-root finding is firmware scoped and stale WAN is not online',
    () async {
      final t = Transport()..web = true;
      final n = NokiaProvider(
        service: NokiaService(transport: t),
        scanner: Scanner(),
      );
      addTearDown(n.dispose);
      await n.service.select(Uri.parse('http://192.168.10.97'));
      n.device = {
        'ModelName': 'Nokia WiFi Beacon 2',
        'SoftwareVersion': '3FE49334IJJJ09',
      };
      n.wan = {'gwwanup': 1};
      expect(n.requiresWiredRoot, isTrue);
      expect(n.uplinkHealth, 'Unknown · refresh Nokia');
      n.observedAt = DateTime.now();
      expect(n.uplinkHealth, 'Nokia reports uplink online');
      n.wan = {'gwwanup': 0};
      expect(n.uplinkHealth, 'Nokia reports uplink offline');
      n.wan = {};
      expect(n.uplinkHealth, 'Not reported');
      n.wan = {'gwwanup': 1};
      n.observedAt = DateTime.now().subtract(const Duration(seconds: 91));
      expect(n.uplinkHealth, 'Unknown · refresh Nokia');
      n.observedAt = DateTime.now();
      n.error = 'Root unreachable';
      expect(n.uplinkHealth, 'Unknown · refresh Nokia');
      n.device!['SoftwareVersion'] = 'unreviewed firmware';
      expect(n.requiresWiredRoot, isFalse);
    },
  );
  test(
    'mesh enrollment requires bridge, capacity, distinct serial and CSRF',
    () async {
      final t = Transport()..web = true;
      final s = NokiaService(transport: t);
      await s.select(Uri.parse('http://192.168.18.1'));
      await s.login('owner', 'secret');
      await expectLater(
        s.changeExtender('ALCL12345678'),
        throwsA(isA<NokiaException>()),
      );
      t.mode = 'AP_Bridge';
      t.capacity = 0;
      await expectLater(
        s.changeExtender('ALCL12345678'),
        throwsA(isA<NokiaException>()),
      );
      expect(t.writes.where((p) => p.startsWith('/mesh_web')), isEmpty);
      t.capacity = 6;
      await s.changeExtender('ALCL12345678');
      expect(t.writes.last, '/mesh_web_app.cgi?add');
      expect(t.plains.last, {
        'SerialNumber': 'ALCL12345678',
        'csrf_token': 'csrf',
      });
      t.nodes = [
        {'SerialNumber': 'ALCL12345678', 'MACAddress': 'b4:63:6f:00:11:22'},
      ];
      await expectLater(
        s.changeExtender('ALCL12345678'),
        throwsA(isA<NokiaException>()),
      );
      await expectLater(
        s.changeExtender('ALCL12345678', removeMac: 'b4:63:6f:00:11:23'),
        throwsA(isA<NokiaException>()),
      );
      await s.changeExtender('ALCL12345678', removeMac: 'b4:63:6f:00:11:22');
      expect(t.writes.last, '/mesh_web_app.cgi?del');
    },
  );
  test(
    'client verification uses 5 GHz BSSID, DHCP server and Wi-Fi-bound internet',
    () async {
      final t = Transport();
      final n = NokiaProvider(
        service: NokiaService(transport: t),
        scanner: Scanner(),
      );
      n.mode = 'AP_BRIDGE';
      n.observedAt = DateTime.now();
      n.wlan5 = {
        'wlan_config_glb11ac': [
          {'BSSID': 'b4:63:6f:db:e6:cd', 'Enable': 1},
        ],
      };
      t.phone = {
        'bssid': 'b4:63:6f:db:e6:cd',
        'ip': '192.168.10.217',
        'gateway': '192.168.10.1',
        'dhcpServer': '192.168.18.1',
        'network': 'wifi-1',
      };
      t.online = {'ok': true, 'network': 'wifi-1'};
      await n.verifyClient('192.168.10.1');
      expect(n.clientVerified, isFalse);
      t.phone['dhcpServer'] = '192.168.10.1';
      await n.verifyClient('192.168.10.1');
      expect(n.clientVerified, isTrue);
      t.online['network'] = 'another-network';
      await n.verifyClient('192.168.10.1');
      expect(n.clientVerified, isFalse);
      n.dispose();
    },
  );
  test(
    'same claimed identity with a changed RSA key never receives the saved password',
    () async {
      final t = Transport()..web = true;
      final n = NokiaProvider(
        service: NokiaService(transport: t),
        scanner: Scanner(),
      );
      await n.discover(address: 'http://192.168.18.1');
      await n.login('owner', 'secret');
      final encryptedBefore = t.plains.length;
      t.publicKey = 'ATTACKER_KEY';
      await n.reconnect();
      expect(n.error, contains('encryption key changed'));
      expect(t.plains.length, encryptedBefore);
      expect(t.writes.where((p) => p == '/login_web_app.cgi').length, 1);
      expect(n.service.authenticated, isFalse);
      n.dispose();
    },
  );
  test('identity normalizes actual post-bridge firmware mode', () {
    final value = cap();
    (value['devapp_cap_info'] as List).first['devMode'] = 'AP_Bridge';
    expect(
      NokiaIdentity(Uri.parse('http://192.168.10.97'), value).mode,
      'AP_BRIDGE',
    );
  });
  test(
    'read rejects a cross-origin path before a cookie can be sent',
    () async {
      final t = Transport();
      final s = NokiaService(transport: t);
      await s.select(Uri.parse('http://192.168.18.1'));
      await s.login('owner', 'secret');
      for (final p in [
        'https://example.com/device_status_app.cgi',
        '//192.168.10.2/device_status_app.cgi',
      ]) {
        await expectLater(s.read(p), throwsA(isA<NokiaException>()));
      }
    },
  );
  test(
    'Beacon 2 uses verified encrypted web login and normalized bridge read-back',
    () async {
      final t = Transport()..web = true;
      final s = NokiaService(transport: t);
      await s.select(Uri.parse('http://192.168.18.1'));
      await s.login('admin', 'fixture-secret');
      expect(s.usesWeb, isTrue);
      expect(s.authenticated, isTrue);
      expect(t.writes, contains('/login_web_app.cgi'));
      expect(t.writes, isNot(contains('/login_app.cgi')));
      t.mode = 'AP_Bridge';
      expect(await s.workMode(), 'AP_BRIDGE');
    },
  );
  test('factory identity is accepted without inventing model or firmware', () {
    final id = NokiaIdentity(Uri.parse('http://192.168.18.1'), cap());
    expect(id.model, isEmpty);
    expect(id.mode, 'RGW');
    expect(id.bridgeSupported, isTrue);
    expect(
      () => NokiaIdentity(Uri.parse('http://192.168.18.1'), {
        'devapp_cap_info': [
          {'devGwMac': 'b4:63:6f:db:e6:c0'},
        ],
      }),
      throwsA(isA<NokiaException>()),
    );
  });
  test(
    'local target policy accepts scoped IPv6 but refuses public and credential URLs',
    () {
      for (final u in [
        'http://192.168.18.1',
        'http://[fe80::b663:6fff:fedb:e6c0%25wlan0]',
        'https://10.1.2.3',
      ]) {
        NokiaService.validateAddress(Uri.parse(u));
      }
      for (final u in [
        'http://example.com',
        'http://8.8.8.8',
        'http://user:pw@192.168.1.1',
        'http://127.0.0.1',
        'http://192.168.1.1:8080',
        'http://192.168.1.1/?secret=x',
        'http://[fe80::1%25rmnet0]',
      ]) {
        expect(
          () => NokiaService.validateAddress(Uri.parse(u)),
          throwsA(isA<NokiaException>()),
        );
      }
    },
  );
  test('changed root never receives saved credentials or writes', () async {
    final t = Transport();
    final service = NokiaService(transport: t);
    await service.select(Uri.parse('http://192.168.18.1'));
    t.serial = 'OTHER';
    await expectLater(
      service.login('owner', 'secret'),
      throwsA(isA<NokiaException>()),
    );
    expect(t.writes, isEmpty);
    expect(service.authenticated, isFalse);
  });
  test(
    'cookie alone cannot turn authorization rejection into success',
    () async {
      final t = Transport()..deny = true;
      final s = NokiaService(transport: t);
      await s.select(Uri.parse('http://192.168.18.1'));
      await expectLater(
        s.login('owner', 'secret'),
        throwsA(isA<NokiaException>()),
      );
      expect(s.authenticated, isFalse);
    },
  );
  test('bridge request requires reported capability and routed mode', () async {
    final t = Transport();
    final s = NokiaService(transport: t);
    await s.select(Uri.parse('http://192.168.18.1'));
    await s.login('owner', 'secret');
    t.bridge = false;
    await expectLater(s.enableBridge(), throwsA(isA<NokiaException>()));
    t.bridge = true;
    t.mode = 'CFG';
    await expectLater(s.enableBridge(), throwsA(isA<NokiaException>()));
    expect(t.writes, ['/login_app.cgi']);
  });
  test(
    'bridge acknowledgment remains pending until same-root read-back',
    () async {
      final t = Transport()..web = true;
      final n = NokiaProvider(
        service: NokiaService(transport: t),
        scanner: Scanner(),
      );
      await n.discover(address: 'http://192.168.18.1');
      await n.login('owner', 'secret');
      expect(n.error, isNull);
      expect(n.savedMac, isNotNull);
      await n.enableBridge();
      expect(n.bridgeVerified, isFalse);
      expect(n.bridgeRequested, isTrue);
      expect(n.observedAt, isNull);
      t.mode = 'AP_BRIDGE';
      await n.reconnect();
      expect(n.bridgeVerified, isTrue);
      expect(n.bridgeRequested, isFalse);
      n.observedAt = DateTime.now().subtract(const Duration(minutes: 3));
      expect(n.bridgeVerified, isFalse);
      n.dispose();
    },
  );
  test('saved device mismatch refuses auto-login and all writes', () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: NokiaProvider.storageKey,
      value: jsonEncode({
        'address': 'http://192.168.18.1',
        'mac': 'b4:63:6f:db:e6:c0',
        'serial': 'OLD',
        'username': 'owner',
        'password': 'secret',
      }),
    );
    final t = Transport();
    final n = NokiaProvider(
      service: NokiaService(transport: t),
      scanner: Scanner(),
    );
    await n.load();
    await n.reconnect();
    expect(n.error, contains('another device'));
    expect(t.writes, isEmpty);
    n.dispose();
  });
  test('factory SSID is only an IPv6 candidate, never verified identity', () {
    const r = WifiScanResult(
      ssid: 'NOKIA-E6C0',
      bssid: 'b4:63:6f:db:e6:cd',
      frequency: 5180,
      level: -62,
      capabilities: 'WPA2',
    );
    final mac = NokiaProvider.factoryRootMac(r);
    expect(mac, 'b4:63:6f:db:e6:c0');
    expect(
      NokiaProvider.linkLocalCandidate(mac!),
      'http://[fe80::b663:6fff:fedb:e6c0%25wlan0]',
    );
  });
}
