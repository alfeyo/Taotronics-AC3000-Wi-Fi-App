import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/home_screen.dart';
import 'package:tt_router_flutter/screens/network_hub_screen.dart';
import 'package:tt_router_flutter/services/argon_device_key.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/pi_api.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';
import 'package:tt_router_flutter/widgets/home_widgets.dart';

import 'support/fake_mqtt_transport.dart';

const _operator = 'operator-test-token-0123456789';
const _companion = 'paired-credential-0123456789abcdefghij';
const _nonce = '0123456789abcdef0123456789abcdef';
const _gib = 1024 * 1024 * 1024;

Map<String, dynamic> _identity() => {
  'version': 1,
  'ok': true,
  'service': 'argon',
  'host': 'argon',
  'instanceId': '11111111-2222-3333-4444-555555555555',
  'apiVersions': [1],
  'access': {'monitor': true},
};

Map<String, dynamic> _liveFull() => {
  'version': 1,
  'ok': true,
  'traffic': {
    'stale': false,
    'sampleAt': 1,
    'aggregate': {'downloadBps': 84200000, 'uploadBps': 78800},
    'today': {'downloadBytes': 2 * _gib, 'uploadBytes': _gib ~/ 2},
  },
};

Map<String, dynamic> _period(
  int down,
  int up, {
  double? share,
  bool measured = true,
  double coverage = 1,
}) => {
  'downloadBytes': down,
  'uploadBytes': up,
  'totalBytes': down + up,
  'vpnBytes': share == null ? null : ((down + up) * share).round(),
  'vpnShare': share,
  'coverage': coverage,
  'days': 7,
  'measured': measured,
};

Map<String, dynamic> _vpn(String mode, {bool busy = false}) => {
  'mode': mode,
  'state': mode == 'on' ? 'connected' : 'disconnected',
  'location': 'United Kingdom — London',
  'interface': mode == 'on' ? 'tun0' : null,
  'interfaceUp': mode == 'on',
  'tunnelIp': mode == 'on' ? '10.14.0.2' : null,
  'lastChangeAt': 1792310823,
  'killSwitch': {'enforced': mode == 'on', 'rejectedPackets': 12},
  'health': {'ok': true, 'detail': 'Handshake 20 s ago'},
  'control': {'busy': busy, 'requires': 'operator'},
};

Map<String, dynamic> _gatewayFull(Map<String, dynamic> vpn) => {
  'version': 1,
  'ok': true,
  'gateway': {
    'host': 'argon',
    'model': 'Raspberry Pi 4 Model B Rev 1.2',
    'uptimeSeconds': 7200,
    'temperatureC': 52.4,
    'cpuPercent': 18.0,
    'memory': {'usedPercent': 21.0},
    'activeThrottling': false,
  },
  'vpn': vpn,
  'usage': {
    'timeZone': 'Africa/Lusaka',
    'periods': {
      'today': _period(2 * _gib, _gib ~/ 2, share: 0.42),
      'yesterday': _period(3 * _gib, _gib),
      'last7': _period(20 * _gib, 4 * _gib, share: 0.5),
      'previous7': _period(16 * _gib, 4 * _gib),
      'thisMonth': _period(60 * _gib, 10 * _gib, share: 0.6),
      'lastMonth': _period(1, 1, measured: false, coverage: 0),
    },
    'days': [
      for (var i = 1; i <= 14; i++)
        {
          'day': '2026-10-${i.toString().padLeft(2, '0')}',
          'downloadBytes': i * 100000000,
          'uploadBytes': i * 10000000,
          'vpnBytes': i * 50000000,
          'coverage': i < 3 ? 0 : 1,
          'measured': i >= 3,
        },
    ],
  },
  'uplink': {
    'active': 'eth0',
    'type': 'Ethernet',
    'online': true,
    'gatewayIp': '192.168.18.1',
    'since': 1792310778,
    'fallback': {
      'profiles': [
        {'name': 'nokia', 'ssid': 'Nokia Wifi', 'priority': 10},
      ],
      'radios': [
        {'interface': 'wlan0', 'bus': 'onboard', 'ready': false},
      ],
      'ready': true,
    },
  },
  'router': {
    'monitoring': {'state': 'connected', 'snapshotAt': 1792313151},
    'router': {'name': 'Router 1', 'devicesOnline': 19, 'internet': true},
  },
  'events': [
    {
      'id': '1:vpn',
      'at': 1792310823,
      'kind': 'vpn',
      'severity': 'info',
      'message': 'VPN recovered.',
    },
    {
      'id': '2:uplink',
      'at': 1792310778,
      'kind': 'uplink',
      'severity': 'warning',
      'message': 'Internet uplink changed to wlan0.',
    },
    {
      'id': '3:temperature',
      'at': 1792310700,
      'kind': 'temperature',
      'severity': 'warning',
      'message': 'Raspberry Pi temperature is 81 °C.',
    },
  ],
};

/// Argon over an IP route: monitoring reads plus operator-signed POSTs.
class HubFake implements PiTransport, PiOperatorTransport {
  HubFake({
    this.kind = PiTransportKind.lan,
    this.minimal = false,
    String mode = 'on',
  }) : vpnState = _vpn(mode);

  @override
  final PiTransportKind kind;
  final bool minimal;
  Map<String, dynamic> vpnState;

  bool deviceAllowed = true;
  int postStatus = 200;
  Map<String, dynamic>? postReply;

  /// Number of /api/v1/vpn reads after which an accepted change shows.
  int applyAfterReads = 1;
  Completer<void>? postGate;
  String? _pending;
  int vpnReads = 0;
  final posts = <({List<int> body, Map<String, String> headers})>[];
  final tokens = <String?>[];

  @override
  String get describe => '192.168.50.1';

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) async {
    tokens.add(token);
    switch (path) {
      case '/api/v1/identity':
        return _identity();
      case '/api/v1/live':
        return minimal ? {'version': 1, 'ok': true} : _liveFull();
      case '/api/v1/gateway':
        return minimal
            ? {'version': 1, 'ok': true, 'gateway': <String, dynamic>{}}
            : _gatewayFull(vpnState);
      case '/api/v1/vpn':
        vpnReads++;
        if (_pending != null && vpnReads >= applyAfterReads) {
          vpnState = _vpn(_pending!);
          _pending = null;
        }
        return {
          'version': 1,
          'ok': true,
          'generatedAt': 1,
          'deviceAllowed': deviceAllowed,
          'vpn': vpnState,
        };
    }
    throw const PiApiException('Argon is not reachable on this route.');
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async => path == '/api/v1/pairing/key'
      ? {'version': 1, 'ok': true, 'id': '11111111-2222-3333-4444-555555555555'}
      : throw const PiApiException('not used');

  @override
  Future<PiRawResponse> sendRaw(
    String method,
    String path, {
    required List<int> body,
    required Map<String, String> headers,
    Duration? timeout,
  }) async {
    if (path == '/api/v1/vpn/authorize') {
      return PiRawResponse(deviceAllowed ? 200 : 403, {
        'ok': deviceAllowed,
        'authorized': deviceAllowed,
      });
    }
    posts.add((body: body, headers: headers));
    if (postGate != null) await postGate!.future;
    final target = (jsonDecode(utf8.decode(body)) as Map)['state'] as String;
    if (postStatus == 200 || postStatus == 202) {
      _pending = target;
      vpnReads = 0;
    }
    return PiRawResponse(
      postStatus,
      postReply ??
          {
            'ok': postStatus < 300,
            'confirmed': postStatus == 200,
            if (postStatus == 202) 'pending': true,
            'observed': vpnState,
          },
    );
  }
}

class _BtOnly implements PiTransport {
  _BtOnly(this.inner);
  final HubFake inner;
  @override
  PiTransportKind get kind => PiTransportKind.bluetooth;
  @override
  String get describe => 'Bluetooth';
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) => inner.get(path, token: token);
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async => throw const PiApiException('Not available over Bluetooth.');
}

class _TestDeviceKey extends ArgonDeviceKey {
  @override
  Future<String> publicKey(String instance) async => 'test-public-key';
  @override
  Future<String> sign(String instance, String value) async =>
      base64Encode(utf8.encode('test-signature'));
}

RouterProvider _router() => RouterProvider(
  mqtt: MqttService(
    transportFactory: FakeTransportFactory().call,
    appIdLoader: () async => 'app',
  ),
  authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
  autoStart: false,
);

class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
}

PiProvider _pi(
  PiTransport argon, {
  _Clock? clock,
  int attempts = 10,
  bool bluetooth = false,
}) => PiProvider(
  router: _router(),
  autoStart: false,
  clock: clock?.call,
  httpTransport: (uri) => bluetooth ? _Down(kindForEndpoint(uri)) : argon,
  bluetoothTransport: (_) => argon,
  bluetoothStatus: () async => const {'enabled': true, 'permission': true},
  vpnVerifyInterval: Duration.zero,
  vpnVerifyAttempts: attempts,
  nonce: () => _nonce,
  deviceKey: _TestDeviceKey(),
);

class _Down implements PiTransport {
  _Down(this.kind);
  @override
  final PiTransportKind kind;
  @override
  String get describe => kind.label;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) async => throw const PiApiException('down');
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async => throw const PiApiException('down');
}

Future<PiProvider> _connected(PiTransport argon, {_Clock? clock}) async {
  final pi = _pi(argon, clock: clock);
  await pi.ready;
  await pi.discover();
  await pi.tick();
  await pi.refreshVpnPermission();
  return pi;
}

Widget _app(PiProvider pi, Widget home, {RouterProvider? router}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: router ?? _router()),
        ChangeNotifierProvider.value(value: pi),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: home),
    );

Future<PiProvider> _connectedInWidget(
  WidgetTester tester,
  PiTransport argon, {
  _Clock? clock,
}) async {
  late PiProvider pi;
  await tester.runAsync(() async {
    pi = await _connected(argon, clock: clock);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  return pi;
}

void _size(WidgetTester tester, Size physical, double dpr) {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

Finder _text(String text) => find.text(text, skipOffstage: false);

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('parsing', () {
    test('full gateway report parses VPN, usage, uplink and router', () async {
      final pi = await _connected(HubFake());
      final vpn = pi.vpn!;
      expect(vpn.mode, 'on');
      expect(vpn.interface, 'tun0');
      expect(vpn.killSwitchEnforced, true);
      expect(vpn.rejectedPackets, 12);
      expect(vpn.healthOk, true);
      expect(pi.usage!.days, hasLength(14));
      expect(pi.usage!.last7!.vpnShare, 0.5);
      expect(
        pi.usage!.last7!.total,
        24 * _gib,
        reason: 'VPN bytes are a subset, never added to the total',
      );
      expect(pi.uplink!.type, 'Ethernet');
      expect(pi.uplink!.fallbackReady, true);
      expect(pi.uplink!.profiles!.single.ssid, 'Nokia Wifi');
      expect(pi.routerView!.devicesOnline, 19);
      expect(pi.householdDownBitsPerSec, 84200000);
      expect(pi.hubState, HubDataState.connected);
      pi.dispose();
    });

    test('an older Argon without the new fields parses to nulls', () async {
      final pi = await _connected(HubFake(minimal: true));
      expect(pi.vpn, isNull);
      expect(pi.usage, isNull);
      expect(pi.uplink, isNull);
      expect(pi.todayUsage, isNull);
      expect(pi.householdDownBitsPerSec, isNull);
      expect(pi.hubState, HubDataState.connected);
      pi.dispose();
    });

    test('Argon events surface as Network Hub notifications', () async {
      final pi = await _connected(HubFake());
      final notices = EventsButton.merged(_router(), pi);
      final titles = notices.map((n) => n.title).toList();
      expect(titles, contains('VPN'));
      expect(titles, contains('Internet uplink changed'));
      expect(titles, contains('Raspberry Pi temperature'));
      expect(
        notices
            .where((n) => n.title != 'Argon found')
            .every((n) => n.source == 'Network Hub'),
        true,
      );
      pi.dispose();
    });
  });

  group('VPN control (provider)', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        PiProvider.companionKey: _companion,
        PiProvider.operatorKey: _operator,
      });
    });

    test('200: signed with the device key, then confirmed by a '
        're-read', () async {
      final argon = HubFake();
      final pi = await _connected(argon);
      expect(await pi.setVpnMode(false), true);
      expect(pi.vpnPhase, VpnCommandPhase.confirmed);
      expect(pi.vpn!.mode, 'off');
      expect(argon.vpnReads, greaterThanOrEqualTo(1));
      final post = argon.posts.single;
      expect(utf8.decode(post.body), '{"state":"off","confirm":"VPN_MODE"}');
      final auth = post.headers['Authorization']!;
      expect(auth, startsWith('ArgonDevice v2 id='));
      expect(auth, contains('nonce=$_nonce'));
      expect(auth.contains(_companion), false);
      expect(auth.contains(_operator), false, reason: 'token never sent');
      expect(post.headers.values.any((v) => v.startsWith('Bearer')), false);
      expect(auth, contains('sig=dGVzdC1zaWduYXR1cmU'));
      expect(pi.events.first.title, 'VPN turned off');
      pi.dispose();
    });

    test('202: pending until the observed mode matches', () async {
      final argon = HubFake()
        ..postStatus = 202
        ..applyAfterReads = 3;
      final pi = await _connected(argon);
      expect(await pi.setVpnMode(false), true);
      expect(argon.vpnReads, 3);
      expect(pi.vpnPhase, VpnCommandPhase.confirmed);
      pi.dispose();
    });

    test('202 that never takes effect is not reported as success', () async {
      final argon = HubFake()
        ..postStatus = 202
        ..applyAfterReads = 99;
      final pi = _pi(argon, attempts: 3);
      await pi.ready;
      await pi.discover();
      expect(await pi.setVpnMode(false), false);
      expect(pi.vpnIssue, VpnCommandIssue.unconfirmed);
      expect(argon.vpnReads, 3);
      pi.dispose();
    });

    for (final (status, issue, text) in [
      (
        401,
        VpnCommandIssue.tokenInvalid,
        'Phone authorization was rejected. Refresh permissions or pair again.',
      ),
      (
        403,
        VpnCommandIssue.forbidden,
        'VPN permission is not granted. Ask the Argon owner to allow this phone in Devices.',
      ),
      (409, VpnCommandIssue.busy, 'A change is already in progress.'),
    ]) {
      test('$status is reported as ${issue.name}', () async {
        final argon = HubFake()..postStatus = status;
        final pi = await _connected(argon);
        expect(await pi.setVpnMode(false), false);
        expect(pi.vpnIssue, issue);
        expect(pi.vpnMessage, text);
        expect(argon.vpnReads, 1, reason: 'initial permission read only');
        pi.dispose();
      });
    }

    test('502 shows Argon\'s error and recovery text', () async {
      final argon = HubFake()
        ..postStatus = 502
        ..postReply = {
          'ok': false,
          'error': 'WireGuard did not come up.',
          'observed': _vpn('off'),
          'recovery': 'Argon restored the previous mode.',
        };
      final pi = await _connected(argon);
      expect(await pi.setVpnMode(true), false);
      expect(pi.vpnIssue, VpnCommandIssue.upstream);
      expect(pi.vpnMessage, 'WireGuard did not come up.');
      expect(pi.vpnRecovery, 'Argon restored the previous mode.');
      pi.dispose();
    });

    test('no overlapping commands', () async {
      final argon = HubFake()..postGate = Completer<void>();
      final pi = await _connected(argon);
      final first = pi.setVpnMode(false);
      await pumpEventQueue();
      expect(pi.vpnInFlight, true);
      expect(await pi.setVpnMode(true), false);
      expect(await pi.setVpnMode(false), false);
      argon.postGate!.complete();
      expect(await first, true);
      expect(argon.posts, hasLength(1));
      pi.dispose();
    });

    test(
      'backgrounding a pending VPN command leaves a recoverable unconfirmed result',
      () async {
        final argon = HubFake()..postGate = Completer<void>();
        final pi = await _connected(argon);
        final command = pi.setVpnMode(false);
        await pumpEventQueue();
        expect(pi.vpnInFlight, true);
        pi.didChangeAppLifecycleState(AppLifecycleState.paused);
        argon.postGate!.complete();
        expect(await command, false);
        expect(pi.vpnInFlight, false);
        expect(pi.vpnIssue, VpnCommandIssue.unconfirmed);
        pi.dismissVpnResult();
        expect(pi.vpnPhase, VpnCommandPhase.idle);
        pi.dispose();
      },
    );

    test('Bluetooth route explains that an IP route is needed', () async {
      SharedPreferences.setMockInitialValues({
        'argon.v2.trustedId': '11111111-2222-3333-4444-555555555555',
        'argon.v2.bluetooth': 'DC:A6:32:00:00:01',
        'argon.v2.bluetoothFallback': true,
      });
      final inner = HubFake();
      final pi = _pi(_BtOnly(inner), bluetooth: true);
      await pi.ready;
      await pi.discover();
      expect(pi.transportKind, PiTransportKind.bluetooth);
      expect(await pi.setVpnMode(false), false);
      expect(pi.vpnIssue, VpnCommandIssue.bluetooth);
      expect(pi.vpnMessage, vpnNeedsIpRouteMessage);
      expect(inner.posts, isEmpty);
      pi.dispose();
    });

    test(
      'operator token is retired; pairing remains secure and unpaired phones cannot send commands',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          PiProvider.companionKey: _companion,
          PiProvider.operatorKey: _operator,
        });
        final pi = await _connected(HubFake());
        const storage = FlutterSecureStorage();
        expect(await storage.read(key: PiProvider.operatorKey), isNull);
        expect(await storage.read(key: PiProvider.companionKey), _companion);
        await pi.refreshVpnPermission();
        expect(pi.vpnDeviceAllowed, true);
        pi.dispose();
        FlutterSecureStorage.setMockInitialValues({});
        final argon = HubFake();
        final unpaired = await _connected(argon);
        expect(await unpaired.setVpnMode(false), false);
        expect(argon.posts, isEmpty);
        unpaired.dispose();
      },
    );
  });

  group('Network Hub screen', () {
    for (final (name, physical, dpr) in [
      ('Fold4 cover', const Size(904, 2316), 2.6),
      ('Fold4 unfolded', const Size(1812, 2176), 2.625),
    ]) {
      testWidgets('full report renders without overflow on $name', (
        tester,
      ) async {
        _size(tester, physical, dpr);
        final pi = await _connectedInWidget(tester, HubFake());
        await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(_text('Network Hub'), findsOneWidget);
        expect(_text('Argon · Raspberry Pi 4 Model B'), findsOneWidget);
        expect(_text('Connected · Local network'), findsOneWidget);
        expect(_text('84.2 Mbps'), findsOneWidget);
        expect(_text('9.6 KiB/s'), findsOneWidget);
        expect(_text('2.50 GiB'), findsOneWidget, reason: 'today total');
        expect(_text('24.0 GiB'), findsOneWidget, reason: 'last 7 days');
        expect(_text('+20% vs previous 7 days'), findsOneWidget);
        expect(_text('70.0 GiB'), findsOneWidget, reason: 'this month');
        expect(
          find.textContaining('vs last month', skipOffstage: false),
          findsNothing,
          reason: 'last month was not measured: no comparison',
        );
        expect(_text('42%'), findsOneWidget, reason: 'VPN share today');
        expect(_text('Ethernet'), findsOneWidget);
        expect(_text('Configured'), findsOneWidget);
        expect(_text('Enforced · 12 packets blocked'), findsOneWidget);
        expect(_text('tun0 · up'), findsOneWidget);
        expect(_text('52°C'), findsOneWidget);
        expect(_text('Internet uplink changed'), findsOneWidget);
        expect(_text('Not reported'), findsNWidgets(3), reason: 'router MQTT');
        await tester.pumpWidget(const SizedBox());
        pi.dispose();
      });
    }

    testWidgets('missing fields read "Not reported", never 0', (tester) async {
      _size(tester, const Size(904, 2316), 2.6);
      final pi = await _connectedInWidget(tester, HubFake(minimal: true));
      await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_text('Argon · Raspberry Pi'), findsOneWidget);
      expect(_text('Not reported'), findsWidgets);
      expect(_text('0 B'), findsNothing);
      expect(_text('0 B/s'), findsNothing);
      expect(_text('0%'), findsNothing);
      expect(
        find.textContaining('Unavailable', skipOffstage: false),
        findsNothing,
      );
      expect(_text('Loading…'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    testWidgets('before the first response everything reads Loading', (
      tester,
    ) async {
      _size(tester, const Size(904, 2316), 2.6);
      late PiProvider pi;
      await tester.runAsync(() async {
        pi = _pi(HubFake());
        await pi.ready;
      });
      await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_text('Loading…'), findsWidgets);
      expect(_text('Unreachable'), findsNothing);
      expect(_text('Not reported'), findsNWidgets(3), reason: 'router only');
      expect(
        find.textContaining('Unavailable', skipOffstage: false),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    testWidgets('stale data shows its age', (tester) async {
      _size(tester, const Size(904, 2316), 2.6);
      final clock = _Clock(DateTime.now().subtract(const Duration(minutes: 2)));
      final pi = await _connectedInWidget(tester, HubFake(), clock: clock);
      clock.now = DateTime.now();
      await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
      await tester.pump();
      expect(_text('Stale · 2 min ago'), findsWidgets);
      expect(_text('Stale'), findsNWidgets(2), reason: 'live rates');
      expect(_text('84.2 Mbps'), findsNothing);
      expect(
        find.textContaining(
          'Showing the last report received',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(_text('Internet online'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    for (final (name, physical, dpr) in [
      ('Fold4 cover', const Size(904, 2316), 2.6),
      ('Fold4 unfolded', const Size(1812, 2176), 2.625),
    ]) {
      testWidgets(
        'Home shows Argon usage, Network Hub status and notices on $name',
        (tester) async {
          _size(tester, physical, dpr);
          final pi = await _connectedInWidget(tester, HubFake());
          await tester.pumpWidget(_app(pi, const HomeScreen()));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(_text('84.2 Mbps'), findsOneWidget);
          expect(_text('2.50 GiB'), findsOneWidget);
          expect(_text('24.0 GiB'), findsOneWidget);
          expect(_text('42% of today via VPN'), findsOneWidget);
          expect(
            find.textContaining(
              'Available via Local network',
              skipOffstage: false,
            ),
            findsOneWidget,
          );
          expect(_text('Recent notifications'), findsOneWidget);
          expect(_text('Devices online · router'), findsOneWidget);
          expect(_text('Network Hub'), findsWidgets);
          await tester.pumpWidget(const SizedBox());
          pi.dispose();
        },
      );
    }
  });

  group('VPN control (UI)', () {
    Future<void> tapToggle(WidgetTester tester) async {
      final toggle = find.byKey(const ValueKey('vpn-toggle'));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await _settle(tester);
    }

    testWidgets(
      'paired phone → owner grant → confirm → pending → confirmed; no token form',
      (tester) async {
        _size(tester, const Size(904, 2316), 2.6);
        FlutterSecureStorage.setMockInitialValues({
          PiProvider.companionKey: _companion,
        });
        final argon = HubFake()..postGate = Completer<void>();
        final pi = await _connectedInWidget(tester, argon);
        await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
        await tester.pump();
        expect(_text('VPN permission granted to this phone'), findsOneWidget);
        await tapToggle(tester);
        expect(
          find.byKey(const ValueKey('operator-token-field')),
          findsNothing,
        );
        expect(find.text('Turn VPN off?'), findsOneWidget);
        expect(
          find.textContaining('directly to the internet via'),
          findsOneWidget,
        );
        await tester.tap(find.text('Turn off'));
        await _settle(tester);

        expect(_text('Sending to Argon…'), findsOneWidget);
        final toggle = tester.widget<Switch>(
          find.byKey(const ValueKey('vpn-toggle')),
        );
        expect(toggle.onChanged, isNull, reason: 'disabled while in flight');
        await tester.tap(
          find.byKey(const ValueKey('vpn-toggle')),
          warnIfMissed: false,
        );
        await _settle(tester);
        expect(argon.posts, hasLength(1));

        argon.postGate!.complete();
        await _settle(tester);
        expect(_text('VPN is off · confirmed by Argon'), findsOneWidget);
        expect(argon.posts, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        pi.dispose();
      },
    );

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        PiProvider.operatorKey: _operator,
        PiProvider.companionKey: _companion,
      });
      _size(tester, const Size(904, 2316), 2.6);
      final argon = HubFake();
      final pi = await _connectedInWidget(tester, argon);
      await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
      await tester.pump();
      await tapToggle(tester);
      expect(find.text('Turn VPN off?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(argon.posts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    for (final (status, expected, extra) in [
      (202, 'VPN is off · confirmed by Argon', null),
      (
        401,
        'Phone authorization was rejected. Refresh permissions or pair again.',
        'Refresh permission',
      ),
      (
        403,
        'VPN permission is not granted. Ask the Argon owner to allow this phone in Devices.',
        null,
      ),
      (409, 'A change is already in progress.', null),
      (502, 'WireGuard did not come up.', 'Argon restored the previous mode.'),
    ]) {
      testWidgets('response $status is shown', (tester) async {
        FlutterSecureStorage.setMockInitialValues({
          PiProvider.operatorKey: _operator,
          PiProvider.companionKey: _companion,
        });
        _size(tester, const Size(904, 2316), 2.6);
        final argon = HubFake()
          ..postStatus = status
          ..applyAfterReads = 2;
        if (status == 502) {
          argon.postReply = {
            'ok': false,
            'error': 'WireGuard did not come up.',
            'recovery': 'Argon restored the previous mode.',
          };
        }
        final pi = await _connectedInWidget(tester, argon);
        await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
        await tester.pump();
        await tapToggle(tester);
        await tester.tap(find.text('Turn off'));
        await _settle(tester);
        expect(_text(expected), findsOneWidget);
        if (extra != null) expect(_text(extra), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        pi.dispose();
      });
    }
  });
}
