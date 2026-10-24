import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/argon_devices_view.dart';
import 'package:tt_router_flutter/screens/argon_statistics_view.dart';
import 'package:tt_router_flutter/screens/home_screen.dart';
import 'package:tt_router_flutter/screens/wifi_argon_gate.dart';
import 'package:tt_router_flutter/services/argon_device_key.dart';
import 'package:tt_router_flutter/services/argon_status.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/pi_api.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';

import 'support/fake_mqtt_transport.dart';

const _instance = '11111111-2222-3333-4444-555555555555';
const _device = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const _companion = 'paired-credential-0123456789abcdefghij';
const _gib = 1024 * 1024 * 1024;

/// Shaped like the live 2026-10-24 `/api/v1/gateway.router` (MACs anonymised).
Map<String, dynamic> _routerView({
  String state = 'connected',
  Map<String, dynamic>? lease,
}) => {
  'ok': true,
  'monitoring': {
    'state': state,
    'label': 'Router device monitoring connected',
    'source': 'lan-observer:dell',
    'snapshotAt': 1792853557,
    'receivedAt': 1792853557,
  },
  'control': {
    'holder': lease?['active'] == true ? 'phone' : 'observer',
    'lease': lease,
    'writes': 'direct-router-override-only',
  },
  'router': {
    'model': 'ND001',
    'wanRate': {'downloadBps': 1862528, 'uploadBps': 107528},
    'nodes': [],
    'wifi': null,
  },
  'clients': [
    {
      'mac': '32:bd:28:00:00:01',
      'ip': '192.168.10.201',
      'name': '32:bd:28:00:00:01',
      'hostname': '32:bd:28:00:00:01',
      'connectionType': 'wifi',
      'online': true,
      'rateRxBps': 239384,
      'rateTxBps': 66440,
      'lastSeen': 1792853557,
      'source': 'lan-observer:dell',
      'usage': {
        'today': {
          'day': '2026-10-24',
          'downloadBytes': 2782741504,
          'uploadBytes': 74193583,
          'totalBytes': 2856935088,
          'observedSeconds': 60266,
          'coverage': 0.9917,
          'estimated': true,
        },
        'days': [
          {
            'day': '2026-10-24',
            'totalBytes': 2856935088,
            'downloadBytes': 2782741504,
            'uploadBytes': 74193583,
            'coverage': 0.9917,
          },
          {
            'day': '2026-10-23',
            'totalBytes': 2713114720,
            'downloadBytes': 2529824087,
            'uploadBytes': 183290633,
            'coverage': 0.94,
          },
        ],
      },
    },
    {
      'mac': '66:d9:ea:00:00:02',
      'ip': '192.168.10.138',
      'name': 'Tab-A9',
      'hostname': 'Tab-A9',
      'connectionType': 'wifi',
      'online': true,
      'rateRxBps': 8000,
      'rateTxBps': 800,
      'usage': {
        'today': {'day': '2026-10-24', 'totalBytes': 500000000, 'coverage': 1},
        'days': [],
      },
    },
    {
      'mac': '00:17:88:00:00:03',
      'ip': '192.168.10.152',
      'name': 'hue-bridge',
      'connectionType': 'wired',
      'online': false,
      'rateRxBps': null,
      'rateTxBps': null,
      'usage': null,
    },
  ],
  'clientUsage': {
    'ok': true,
    'method': 'estimated',
    'stale': false,
    'lastObservationAt': 1792853562,
  },
  'counts': {'known': 3, 'online': 2, 'wifi': 2, 'wired': 1},
};

class ArgonFake implements PiTransport, PiOperatorTransport {
  ArgonFake({this.yieldAfterPolls = 1, this.leaseStatus = 200});

  /// Lease polls before the observer reports having yielded (-1: never).
  int yieldAfterPolls;
  int leaseStatus;
  final log = <String>[];
  final signedPaths = <String>[];
  bool leaseActive = false;
  int _polls = 0;
  List<Map<String, dynamic>> alerts = [];

  Map<String, dynamic> get _lease => {
    'active': leaseActive,
    'holder': leaseActive ? {'id': _device, 'name': 'Galaxy Z Fold4'} : null,
    'expiresAt': leaseActive ? 1792853700 : null,
    'handover': !leaseActive
        ? 'none'
        : (yieldAfterPolls >= 0 && _polls >= yieldAfterPolls)
        ? 'observer-yielded'
        : 'waiting-for-observer',
  };

  @override
  PiTransportKind get kind => PiTransportKind.lan;
  @override
  String get describe => 'argon';

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) async {
    log.add('GET $path');
    return switch (path) {
      '/api/v1/identity' => {
        'version': 1,
        'ok': true,
        'service': 'argon',
        'host': 'argon',
        'instanceId': _instance,
        'apiVersions': [1],
        'access': {'monitor': true},
      },
      '/api/v1/live' => {
        'ok': true,
        'traffic': {
          'stale': false,
          'aggregate': {'downloadBps': 84200000, 'uploadBps': 78800},
          'today': {'downloadBytes': 2 * _gib, 'uploadBytes': _gib ~/ 2},
          'source': 'eth1 nftables · existing collector',
        },
      },
      '/api/v1/gateway' => {
        'ok': true,
        'gateway': {
          'model': 'Raspberry Pi 4 Model B Rev 1.2',
          'uptimeSeconds': 236909,
          'temperatureC': 42.8,
          'activeThrottling': false,
          'upstream': {'interface': 'eth0', 'online': true},
        },
        'vpn': {'mode': 'off', 'state': 'off', 'location': 'UK — London'},
        'uplink': {'active': 'eth0', 'type': 'Ethernet', 'online': true},
        'usage': {
          'timeZone': 'Africa/Lusaka',
          'periods': {
            'today': {
              'downloadBytes': 21706005447,
              'uploadBytes': 1251944909,
              'totalBytes': 22957950356,
              'vpnBytes': 0,
              'vpnShare': 0,
              'coverage': 0.9994,
              'measured': true,
            },
          },
          'days': [],
        },
        'router': _routerView(lease: _lease),
        'events': [],
      },
      '/api/v1/router/lease' => () {
        _polls++;
        return {'ok': true, 'lease': _lease};
      }(),
      _ => throw PiApiException('unexpected $path', status: 404),
    };
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async {
    log.add('POST $path');
    if (path == '/api/v1/pairing/key') return {'ok': true, 'id': _device};
    throw PiApiException('unexpected $path', status: 404);
  }

  @override
  Future<PiRawResponse> sendRaw(
    String method,
    String path, {
    required List<int> body,
    required Map<String, String> headers,
    Duration? timeout,
  }) async {
    final auth = headers['Authorization'] ?? '';
    expect(auth, startsWith('ArgonDevice v2 id=$_device,'));
    signedPaths.add('$method $path');
    if (path.startsWith('/api/v1/alerts?')) {
      return PiRawResponse(200, {'ok': true, 'alerts': alerts});
    }
    if (path == '/api/v1/alerts/ack') {
      log.add('ack ${utf8.decode(body)}');
      return const PiRawResponse(200, {'ok': true});
    }
    final action = (jsonDecode(utf8.decode(body)) as Map)['action'];
    log.add('lease $action');
    if (leaseStatus != 200) {
      return PiRawResponse(leaseStatus, {
        'ok': false,
        'error': 'Direct router control is held by OnePlus 8T.',
      });
    }
    switch (action) {
      case 'acquire':
        leaseActive = true;
        _polls = 0;
      case 'release':
        leaseActive = false;
    }
    return PiRawResponse(200, {'ok': true, 'lease': _lease});
  }
}

class _Key extends ArgonDeviceKey {
  final signed = <String>[];
  @override
  Future<String> publicKey(String alias) async => base64Encode([1, 2, 3]);
  @override
  Future<String> sign(String alias, String value) async {
    signed.add(value);
    return base64Encode(utf8.encode('sig'));
  }

  @override
  Future<bool> exists(String alias) async => false;
  @override
  Future<void> delete(String alias) async {}
  @override
  Future<List<String>> list() async => const [];
  @override
  Future<DeviceKeyHardware?> hardware(String alias) async =>
      DeviceKeyHardware.strongBox;
}

Future<(RouterProvider, FakeTransportFactory)> _argonModeRouter() async {
  final auth = AuthPairingService(credentialStore: MemoryCredentialStore());
  await auth.attemptPairing(meshId: 'mesh-1', ipAddress: '192.168.10.1');
  final factory = FakeTransportFactory()
    ..responder = (path, data) => switch (path) {
      '/GetSysConnectInfo' => {
        'ErrorCode': 0,
        'Data': {'OnlineDev': 2, 'Internet': 1},
      },
      _ => {'ErrorCode': 0, 'Data': []},
    };
  final router = RouterProvider(
    mqtt: MqttService(
      transportFactory: factory.call,
      appIdLoader: () async => 'app',
    ),
    authService: auth,
    autoStart: false,
    directControl: false,
  );
  return (router, factory);
}

Future<(PiProvider, RouterProvider, FakeTransportFactory, ArgonFake, _Key)>
_setup({ArgonFake? argon, bool paired = true}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    if (paired) PiProvider.companionKey: _companion,
  });
  final (router, factory) = await _argonModeRouter();
  final fake = argon ?? ArgonFake();
  final key = _Key();
  final pi = PiProvider(
    router: router,
    autoStart: false,
    httpTransport: (_) => fake,
    nonce: () => '0123456789abcdef0123456789abcdef',
    deviceKey: key,
  )..leasePollInterval = Duration.zero;
  await pi.ready;
  await pi.discover();
  await pi.tick();
  // Discovery starts its own tick; let in-flight polls finish.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return (pi, router, factory, fake, key);
}

void main() {
  test('Argon mode: the router is never contacted', () async {
    final (pi, router, factory, _, _) = await _setup();
    expect(router.isArgonMode, isTrue);
    expect(pi.connected, isTrue);
    await router.selectRouter(
      MeshEntity(meshId: 'mesh-1', ssid: 'r', ipAddress: '192.168.10.1'),
    );
    router.reconnectNow();
    await pi.tick();
    expect(factory.created, isEmpty, reason: 'no MQTT session in Argon mode');
    expect(pi.routerView!.observedByArgon, isTrue);
    expect(pi.routerView!.onlineCount, 2);
    pi.dispose();
  });

  test('parses the live router view: clients, estimated usage, control', () {
    final v = ArgonRouterView.parse(_routerView())!;
    expect(v.live, isTrue);
    expect(v.sourceLabel, 'Dell LAN observer');
    expect(v.controlHolder, 'observer');
    expect(v.usageMethod, 'estimated');
    expect(v.wanDownBitsPerSec, 1862528);
    final unnamed = v.clients.first;
    expect(unnamed.friendlyName, isNull, reason: 'MAC-shaped names hidden');
    expect(unnamed.displayName, 'Unnamed device');
    expect(unnamed.today!.totalBytes, 2856935088);
    expect(unnamed.today!.coverage, closeTo(0.9917, 1e-6));
    expect(v.clients.last.online, isFalse);
    expect(v.clients.last.today, isNull);
  });

  test('device list filters, searches and sorts by usage', () {
    final clients = ArgonRouterView.parse(_routerView())!.clients;
    expect(
      arrangeArgonClients(
        clients,
        filter: ArgonDeviceFilter.wired,
      ).map((c) => c.ip),
      ['192.168.10.152'],
    );
    expect(
      arrangeArgonClients(clients, query: 'tab').single.displayName,
      'Tab-A9',
    );
    expect(
      arrangeArgonClients(clients, sort: ArgonDeviceSort.usage).first.ip,
      '192.168.10.201',
    );
    expect(
      arrangeArgonClients(
        clients,
        filter: ArgonDeviceFilter.offline,
      ).single.displayName,
      'hue-bridge',
    );
  });

  test(
    'direct control: lease, observer handover, connect with the saved pairing, return releases',
    () async {
      final (pi, router, factory, argon, key) = await _setup(
        argon: ArgonFake(yieldAfterPolls: 2),
      );
      final ok = await pi.takeDirectControl();
      expect(ok, isTrue);
      expect(argon.log.where((l) => l == 'lease acquire'), hasLength(1));
      expect(
        argon.log.where((l) => l == 'GET /api/v1/router/lease').length,
        greaterThanOrEqualTo(2),
        reason: 'waits until the observer has yielded',
      );
      expect(router.isDirectMode, isTrue);
      expect(factory.created, hasLength(1));
      expect(factory.last.host, '192.168.10.1');
      await pi.tick();
      expect(pi.directPhase, DirectControlPhase.active);
      // Signatures cover the pathname only.
      expect(key.signed.every((s) => s.contains('\n/api/v1/')), isTrue);

      await pi.returnToArgon();
      expect(argon.log, contains('lease release'));
      expect(router.isArgonMode, isTrue);
      expect(router.isConnected, isFalse);
      expect(factory.last.disconnectCalled, isTrue);
      expect(pi.directPhase, DirectControlPhase.off);
      expect(pi.monitoringResumeSince, isNotNull);
      // Pairing survives the round trip.
      expect(router.hasSavedPairing, isTrue);
      pi.dispose();
    },
  );

  test('direct control: a held lease is reported, nothing connects', () async {
    final (pi, router, factory, _, _) = await _setup(
      argon: ArgonFake(leaseStatus: 409),
    );
    expect(await pi.takeDirectControl(), isFalse);
    expect(pi.directPhase, DirectControlPhase.failed);
    expect(pi.directMessage, contains('OnePlus 8T'));
    expect(router.isArgonMode, isTrue);
    expect(factory.created, isEmpty);
    pi.dispose();
  });

  test(
    'direct control: an observer that never yields times out and the lease is released',
    () async {
      final argon = ArgonFake(yieldAfterPolls: -1);
      final (pi, router, factory, _, _) = await _setup(argon: argon);
      var t = DateTime(2026, 10, 24, 12);
      final timed = PiProvider(
        router: router,
        autoStart: false,
        httpTransport: (_) => argon,
        nonce: () => '0123456789abcdef0123456789abcdef',
        deviceKey: _Key(),
        clock: () => t = t.add(const Duration(seconds: 5)),
      )..leasePollInterval = Duration.zero;
      await timed.ready;
      await timed.discover();
      expect(await timed.takeDirectControl(), isFalse);
      expect(timed.directMessage, contains('did not release the router'));
      await Future<void>.delayed(Duration.zero);
      expect(argon.log, contains('lease release'));
      expect(factory.created, isEmpty);
      pi.dispose();
      timed.dispose();
    },
  );

  test('direct control without a pairing shows the real blocker', () async {
    final (pi, router, factory, _, _) = await _setup(paired: false);
    expect(pi.handoverBlocker, contains('not paired'));
    expect(await pi.takeDirectControl(), isFalse);
    expect(pi.directPhase, DirectControlPhase.failed);
    expect(factory.created, isEmpty);
    // The explicit override connects without a lease.
    pi.dismissDirectResult();
    expect(await pi.takeDirectControl(withoutHandover: true), isTrue);
    expect(router.isDirectMode, isTrue);
    expect(pi.directWithoutHandover, isTrue);
    await pi.returnToArgon();
    expect(router.isArgonMode, isTrue);
    pi.dispose();
  });

  test('usage alerts: signed fetch, shown once, then acknowledged', () async {
    final argon = ArgonFake()
      ..alerts = [
        {
          'id': 7,
          'status': 'pending',
          'createdAt': 1792853000,
          'deviceName': 'Tab-A9',
          'avgBps': 12500000,
          'share': 0.61,
          'downloadBytes': 900000000,
          'uploadBytes': 10000000,
          'estimated': true,
        },
        {'id': 6, 'status': 'delivered'},
      ];
    final (pi, _, _, _, key) = await _setup(argon: argon);
    final alert = pi.events.where((e) => e.id == 'argon:alert:7');
    expect(alert, hasLength(1));
    expect(alert.single.title, 'High usage: Tab-A9');
    expect(alert.single.message, contains('61% of household traffic'));
    expect(argon.log, contains('ack {"ids":[7]}'));
    expect(argon.signedPaths.first, 'GET /api/v1/alerts?after=0&limit=50');
    expect(
      key.signed.first.split('\n')[3],
      '/api/v1/alerts',
      reason: 'Argon verifies the pathname without the query',
    );
    pi.dispose();
  });

  for (final (name, size) in [
    ('Fold4 cover', const Size(344, 882)),
    ('Fold4 unfolded', const Size(690, 829)),
  ]) {
    testWidgets('Pi-first screens render on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late PiProvider pi;
      late RouterProvider router;
      await tester.runAsync(() async {
        (pi, router, _, _, _) = await _setup();
      });
      Widget app(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: router),
          ChangeNotifierProvider.value(value: pi),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: home),
      );
      await tester.pumpWidget(app(const HomeScreen()));
      await tester.pump();
      expect(
        find.text('Connected to Argon — monitoring household network'),
        findsOneWidget,
      );
      expect(find.text('Argon'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(const ArgonDevicesView()));
      await tester.pump();
      expect(find.text('Tab-A9'), findsOneWidget);
      expect(find.text('Unnamed device'), findsOneWidget);
      expect(find.textContaining('estimated'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(const ArgonStatisticsView()));
      await tester.pump();
      expect(find.text('Real-time'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(const WifiArgonGate()));
      await tester.pump();
      expect(
        find.text('Wi-Fi changes need Direct Router Control'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });
  }
}
