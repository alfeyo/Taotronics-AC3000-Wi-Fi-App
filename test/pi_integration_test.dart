import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/pi_api.dart';

import 'support/fake_mqtt_transport.dart';

const _id = '11111111-2222-3333-4444-555555555555';
const _otherId = '99999999-8888-7777-6666-555555555555';

Map<String, dynamic> _identity([String id = _id]) => {
  'version': 1,
  'ok': true,
  'service': 'argon',
  'host': 'argon',
  'instanceId': id,
  'apiVersions': [1],
  'access': {'monitor': true},
  'bluetooth': {'address': 'DC:A6:32:00:00:01'},
};

Map<String, dynamic> _live({int down = 8000000, int up = 800000}) => {
  'version': 1,
  'ok': true,
  'traffic': {
    'stale': false,
    'sampleAt': 1,
    'aggregate': {'downloadBps': down, 'uploadBps': up},
    'today': {
      'downloadBytes': 1000,
      'uploadBytes': 100,
      'vpnDownloadBytes': 900,
      'vpnUploadBytes': 0,
    },
  },
};

Map<String, dynamic> _gateway({List<Map<String, dynamic>> events = const []}) =>
    {
      'version': 1,
      'ok': true,
      'gateway': {
        'host': 'argon',
        'cpuPercent': 7.5,
        'temperatureC': 47.0,
        'memory': {'usedPercent': 17.5},
        'activeThrottling': false,
        'upstream': {'interface': 'wlan1', 'ssid': 'Nokia', 'online': true},
        'vpn': {'state': 'connected', 'mode': 'on', 'location': 'London'},
      },
      'events': events,
    };

typedef FakeHandler =
    Map<String, dynamic> Function(Map<String, dynamic>? body, String? token);

class FakePi implements PiTransport {
  FakePi(this.kind, this.routes);
  FakePi.down(this.kind) : routes = const {};
  @override
  final PiTransportKind kind;
  final Map<String, FakeHandler> routes;
  final calls =
      <
        ({
          String method,
          String path,
          String? token,
          Map<String, dynamic>? body,
        })
      >[];
  @override
  String get describe => kind.label;

  Map<String, dynamic> _run(
    String method,
    String path,
    Map<String, dynamic>? body,
    String? token,
  ) {
    calls.add((method: method, path: path, token: token, body: body));
    final h = routes['$method $path'];
    if (h == null) {
      throw const PiApiException('Argon is not reachable on this route.');
    }
    return h(body, token);
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) async => _run('GET', path, null, token);

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async => _run('POST', path, body, token);
}

Map<String, FakeHandler> _argon({String id = _id}) => {
  'GET /api/v1/identity': (_, _) => _identity(id),
  'GET /api/v1/live': (_, _) => _live(),
  'GET /api/v1/gateway': (_, _) => _gateway(),
};

RouterProvider _offlineRouter() => RouterProvider(
  mqtt: MqttService(
    transportFactory: FakeTransportFactory().call,
    appIdLoader: () async => 'app',
  ),
  authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
  autoStart: false,
);

class _Clock {
  DateTime now = DateTime(2026, 10, 18, 9);
  DateTime call() => now;
  void advance(int seconds) => now = now.add(Duration(seconds: seconds));
}

PiProvider _pi(
  RouterProvider router,
  Map<String, PiTransport> hosts, {
  _Clock? clock,
  PiTransport? bluetooth,
  Map<String, dynamic> btStatus = const {'enabled': true, 'permission': true},
}) => PiProvider(
  router: router,
  autoStart: false,
  clock: clock?.call,
  httpTransport: (uri) => hosts[uri.host] ?? FakePi.down(kindForEndpoint(uri)),
  bluetoothTransport: (_) =>
      bluetooth ?? FakePi.down(PiTransportKind.bluetooth),
  bluetoothStatus: () async => btStatus,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'endpoint policy: HTTPS anywhere, HTTP only to private LAN or Tailscale IPs',
    () {
      for (final ok in [
        'http://192.168.50.1',
        'http://10.0.0.5',
        'http://172.20.1.1',
        'http://100.94.137.17',
        'https://argon.example',
      ]) {
        expect(
          validatePiEndpoint(ok).toString().startsWith(ok.split(':').first),
          true,
          reason: ok,
        );
      }
      for (final bad in [
        'http://8.8.8.8',
        'http://argon.local',
        'http://100.128.0.1',
        'ftp://192.168.50.1',
        'https://user:pw@argon.example',
        'https://argon.example?token=x',
        'https://argon.example/path',
      ]) {
        expect(
          () => validatePiEndpoint(bad),
          throwsFormatException,
          reason: bad,
        );
      }
      expect(
        kindForEndpoint(Uri.parse('http://192.168.50.1')),
        PiTransportKind.lan,
      );
      expect(
        kindForEndpoint(Uri.parse('http://100.94.137.17')),
        PiTransportKind.tailscale,
      );
    },
  );

  test('identity must be an Argon with API v1', () {
    expect(PiIdentity.parse(_identity()).bluetoothAddress, 'DC:A6:32:00:00:01');
    expect(
      () => PiIdentity.parse({..._identity(), 'service': 'nginx'}),
      throwsA(isA<PiApiException>()),
    );
    expect(
      () => PiIdentity.parse({
        ..._identity(),
        'apiVersions': [2],
      }),
      throwsA(isA<PiApiException>()),
    );
  });

  test(
    'startup discovery prefers the LAN, pins identity, and needs no setup',
    () async {
      final lan = FakePi(PiTransportKind.lan, _argon());
      final ts = FakePi(PiTransportKind.tailscale, _argon());
      final pi = _pi(_offlineRouter(), {
        '192.168.50.1': lan,
        '100.94.137.17': ts,
      });
      await pi.ready;
      await pi.discover();
      expect(pi.state, PiLinkState.connected);
      expect(pi.transportKind, PiTransportKind.lan);
      expect(pi.trustedId, _id);
      expect(
        ts.calls,
        isEmpty,
        reason: 'no competing Tailscale request when LAN works',
      );
      await pi.tick();
      expect(
        pi.householdDownBytesPerSec,
        1000000,
        reason: 'Argon bits/s -> app bytes/s',
      );
      expect(pi.householdUpBytesPerSec, 100000);
      expect(pi.gatewayInfo?['cpuPercent'], 7.5);
      expect(
        lan.calls
            .where((c) => c.path != '/api/v1/identity')
            .every((c) => c.token == null),
        true,
        reason: 'no credential sent for anonymous-allowed monitoring',
      );
      pi.dispose();
    },
  );

  test(
    'falls back to Tailscale when the LAN route is unavailable; restart restores trust',
    () async {
      final ts = FakePi(PiTransportKind.tailscale, _argon());
      final pi = _pi(_offlineRouter(), {'100.94.137.17': ts});
      await pi.ready;
      await pi.discover();
      expect(pi.transportKind, PiTransportKind.tailscale);
      pi.dispose();
      final restarted = _pi(_offlineRouter(), {
        '100.94.137.17': FakePi(PiTransportKind.tailscale, _argon()),
      });
      await restarted.ready;
      expect(restarted.trustedId, _id, reason: 'trusted identity persisted');
      await restarted.discover();
      expect(restarted.connected, true);
      restarted.dispose();
    },
  );

  test('a different server at the LAN address is not trusted', () async {    final first = _pi(_offlineRouter(), {
      '192.168.50.1': FakePi(PiTransportKind.lan, _argon()),
    });
    await first.ready;
    await first.discover();
    first.dispose();
    final impostor = FakePi(PiTransportKind.lan, _argon(id: _otherId));
    final ts = FakePi(PiTransportKind.tailscale, _argon());
    final pi = _pi(_offlineRouter(), {
      '192.168.50.1': impostor,
      '100.94.137.17': ts,
    });
    await pi.ready;
    await pi.discover();
    expect(pi.transportKind, PiTransportKind.tailscale);
    expect(pi.identity!.instanceId, _id);
    pi.dispose();
  });

  test('Argon router ownership reaches the router policy', () async {
    final router = _offlineRouter();
    final gateway = FakePi(PiTransportKind.lan, {
      ..._argon(),
      'GET /api/v1/gateway': (_, _) => {
        ..._gateway(),
        'router': {
          'name': 'TaoTronics',
          'monitoring': {'state': 'connected'},
        },
      },
    });
    final pi = _pi(router, {'192.168.50.1': gateway});
    await pi.ready;
    await pi.discover();
    await pi.tick();

    expect(pi.routerOwnedByArgon, isTrue);
    expect(router.isRouterControlledByPi, isTrue);
    expect(router.isReadOnly, isTrue);
    expect(router.accessPolicy.mayConnect, isFalse);
    expect(router.accessPolicy.mayWrite, isFalse);
    pi.dispose();
    router.dispose();
  });

  test(
    'unreachable: backoff, events, and recovery when a route returns',
    () async {
      final clock = _Clock();
      final first = FakePi(PiTransportKind.lan, _argon());
      final hosts = <String, PiTransport>{'192.168.50.1': first};
      final pi = _pi(_offlineRouter(), hosts, clock: clock);
      await pi.ready;
      await pi.discover();
      await pumpEventQueue();
      hosts.clear();
      first.routes.clear(); // the adopted route stops answering
      clock.advance(6);
      await pi.tick(); // poll fails once
      await pumpEventQueue();
      clock.advance(6);
      await pi.tick(); // second failure -> rediscover
      await pumpEventQueue();
      await pi.tick();
      expect(pi.state, PiLinkState.unreachable);
      expect(pi.events.first.title, 'Argon unreachable');
      final probes = first.calls.length;
      await pi.tick(); // within backoff: no new discovery
      expect(first.calls.length, probes);
      hosts['192.168.50.1'] = FakePi(PiTransportKind.lan, _argon());
      clock.advance(6);
      await pi.tick();
      expect(pi.connected, true);
      expect(pi.events.first.title, 'Argon reachable again');
      pi.dispose();
    },
  );

  test('Bluetooth fallback only when enabled, paired and permitted', () async {
    FlutterSecureStorage.setMockInitialValues({
      'argon.companion.v1': 'paired-credential-0123456789abcdefghij',
    });
    SharedPreferences.setMockInitialValues({
      'argon.v2.trustedId': _id,
      'argon.v2.bluetooth': 'DC:A6:32:00:00:01',
    });
    final bt = FakePi(PiTransportKind.bluetooth, _argon());
    var pi = _pi(_offlineRouter(), {}, bluetooth: bt);
    await pi.ready;
    await pi.discover();
    expect(pi.connected, false, reason: 'fallback is opt-in');
    await pi.setBluetoothFallback(true);
    await pi.reconnect();
    expect(pi.transportKind, PiTransportKind.bluetooth);
    await pi.tick();
    expect(
      bt.calls.where((c) => c.path == '/api/v1/gateway').single.token,
      isNotNull,
      reason: 'Bluetooth reads always carry the paired credential',
    );
    pi.dispose();
    pi = _pi(
      _offlineRouter(),
      {},
      bluetooth: FakePi(PiTransportKind.bluetooth, _argon()),
      btStatus: const {'enabled': true, 'permission': false},
    );
    await pi.ready;
    await pi.discover();
    expect(
      pi.connected,
      false,
      reason: 'no permission prompt, no Bluetooth use',
    );
    pi.dispose();
  });

  test('pairing stores the credential only in secure storage', () async {
    final lan = FakePi(PiTransportKind.lan, {
      ..._argon(),
      'POST /api/v1/pairing/complete': (body, _) => body?['code'] == '123456'
          ? {
              'version': 1,
              'ok': true,
              'token': 'issued-credential-0123456789abcdefghijk',
              'name': 'TT Router · Home',
              'deviceId': 'x',
            }
          : throw const PiApiException('That code is not valid.', status: 401),
    });
    final pi = _pi(_offlineRouter(), {
      '192.168.50.1': lan,
      '100.94.137.17': lan,
    });
    await pi.ready;
    await pi.discover();
    await expectLater(pi.pair('000000'), throwsA(isA<PiApiException>()));
    expect(pi.paired, false);
    await pi.pair('123456', deviceName: 'TT Router · Home');
    expect(pi.paired, true);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().any(
        (k) => prefs.get(k).toString().contains('issued-credential'),
      ),
      false,
    );
    expect(
      await const FlutterSecureStorage().read(key: 'argon.companion.v1'),
      'issued-credential-0123456789abcdefghijk',
    );
    pi.dispose();
  });

  testWidgets(
    'sync: a real router device list reaches Argon from any screen; revoked credential stops it',
    (tester) async {
      final factory = FakeTransportFactory()
        ..responder = (path, _) => switch (path) {
          '/GetDevListInfo' => {
            'ErrorCode': 0,
            'Data': [
              {
                'HostName': 'tablet',
                'Mac': '02:00:00:00:00:01',
                'Ip': '192.168.10.138',
                'AliveOnline': 1,
                'DownRate': 1000,
                'UpRate': 100,
                'ClientType': 2,
              },
            ],
          },
          _ => {'ErrorCode': 0, 'Data': []},
        };
      final router = RouterProvider(
        mqtt: MqttService(
          transportFactory: factory.call,
          appIdLoader: () async => 'app',
        ),
        authService: AuthPairingService(
          credentialStore: MemoryCredentialStore(),
        ),
        autoStart: false,
      );
      var accept = true;
      final lan = FakePi(PiTransportKind.lan, {
        ..._argon(),
        'POST /api/v1/router/snapshot': (body, token) => accept
            ? {
                'version': 1,
                'ok': true,
                'count': (body!['clients'] as List).length,
              }
            : throw const PiApiException('refused', status: 401),
      });
      FlutterSecureStorage.setMockInitialValues({
        'argon.companion.v1': 'paired-credential-0123456789abcdefghij',
      });
      late PiProvider pi;
      await tester.runAsync(() async {
        // Created in the real async zone: its storage load must complete here.
        pi = _pi(router, {'192.168.50.1': lan, '100.94.137.17': lan});
        await router.selectRouter(
          MeshEntity(meshId: 'm', ssid: 'm', ipAddress: '10.0.0.1'),
        );
        await router.refreshDevices();
        await pi.ready;
        await pi.discover();
        await pi.tick();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      final post = lan.calls
          .where((c) => c.path == '/api/v1/router/snapshot')
          .single;
      expect(post.token, 'paired-credential-0123456789abcdefghij');
      final client = (post.body!['clients'] as List).single as Map;
      expect(client['mac'], '02:00:00:00:00:01');
      expect(client['rateRxBps'], 8000, reason: 'router bytes/s -> bits/s');
      expect(post.body.toString().contains('assword'), false);
      expect(pi.sharedCount, 1);
      accept = false;
      await tester.runAsync(() async {
        await router.refreshDevices();
        await pi.reconnect();
        await pi.tick();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      expect(pi.credentialRejected, true);
      expect(pi.paired, false);
      pi.dispose();
      await tester.runAsync(() async => router.dispose());
    },
  );

  test(
    'server events are deduplicated; history before the session is not unread',
    () async {
      var events = [
        {
          'id': '1:vpn',
          'at': 1792300000,
          'kind': 'vpn',
          'severity': 'warning',
          'message': 'VPN is disconnected or degraded.',
        },
      ];
      final clock = _Clock();
      final pi = _pi(_offlineRouter(), {
        '192.168.50.1': FakePi(PiTransportKind.lan, {
          ..._argon(),
          'GET /api/v1/gateway': (_, _) => _gateway(events: events),
        }),
      }, clock: clock);
      await pi.ready;
      await pi.discover();
      await pi.tick();
      final unreadAfterFirst = pi.unreadEvents;
      expect(pi.events.where((e) => e.source == 'argon').length, 1);
      events = [
        ...events,
        {
          'id': '2:vpn',
          'at': 1792300100,
          'kind': 'vpn',
          'severity': 'info',
          'message': 'VPN recovered.',
        },
      ];
      clock.advance(16);
      await pi.tick();
      clock.advance(16);
      await pi.tick();
      expect(pi.events.where((e) => e.source == 'argon').length, 2);
      expect(pi.unreadEvents, unreadAfterFirst + 1);
      pi.dispose();
    },
  );
}
