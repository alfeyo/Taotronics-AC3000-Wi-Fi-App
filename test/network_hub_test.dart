import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:tt_router_flutter/services/argon_status.dart';
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
      'last30': _period(80 * _gib, 8 * _gib, share: 0.5),
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

/// Argon's `/api/v1/vpn/locations` answer recorded in the fixture.
Map<String, dynamic> _locationsFixture() =>
    jsonDecode(File('test/fixtures/vpn_locations.json').readAsStringSync())
        as Map<String, dynamic>;

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
  int keyDeleteStatus = 200;
  List<String> log = [];
  final keyDeleteTokens = <String?>[];
  Map<String, dynamic>? postReply;

  /// Number of /api/v1/vpn reads after which an accepted change shows.
  int applyAfterReads = 1;
  Completer<void>? postGate;
  String? _pending;
  int vpnReads = 0;
  final posts = <({List<int> body, Map<String, String> headers})>[];
  final tokens = <String?>[];

  // VPN exit location.
  Map<String, dynamic> locations = _locationsFixture();
  int locationReads = 0;
  int applyLocationAfterReads = 1;
  int locationPostStatus = 200;
  Map<String, dynamic>? locationPostReply;
  Completer<void>? locationGate;
  String? _pendingLocation;
  final locationPosts =
      <({String path, List<int> body, Map<String, String> headers})>[];

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
      case '/api/v1/vpn/locations':
        locationReads++;
        if (_pendingLocation != null &&
            locationReads >= applyLocationAfterReads) {
          final next = (locations['locations'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((l) => l['id'] == _pendingLocation);
          locations['current'] = {...next}..remove('available');
          vpnState = {...vpnState, 'location': next['label']};
          _pendingLocation = null;
        }
        return {
          ...locations,
          'mode': vpnState['mode'],
          'state': vpnState['state'],
        };
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
  }) async {
    if (path == '/api/v1/pairing/key') {
      if (enrollStatus != 200) {
        throw PiApiException('enroll failed', status: enrollStatus);
      }
      return {
        'version': 1,
        'ok': true,
        'id': _device,
        'keyFingerprint': 'server-value-not-shown',
      };
    }
    if (path == '/api/v1/pairing/complete') {
      return {
        'version': 1,
        'ok': true,
        'deviceId': _device,
        'name': 'TT Router app',
        'token': _companion,
      };
    }
    throw const PiApiException('not used');
  }

  int enrollStatus = 200;
  Completer<void>? keyDeleteGate;

  @override
  Future<PiRawResponse> sendRaw(
    String method,
    String path, {
    required List<int> body,
    required Map<String, String> headers,
    Duration? timeout,
  }) async {
    if (method == 'DELETE' && path == '/api/v1/pairing/key') {
      log.add('server.delete');
      keyDeleteTokens.add(headers['Authorization']);
      if (keyDeleteGate != null) await keyDeleteGate!.future;
      return PiRawResponse(keyDeleteStatus, {'ok': keyDeleteStatus == 200});
    }
    if (path.startsWith('/api/v1/alerts')) {
      return const PiRawResponse(200, {'ok': true, 'alerts': []});
    }
    if (path == '/api/v1/vpn/authorize') {
      return PiRawResponse(deviceAllowed ? 200 : 403, {
        'ok': deviceAllowed,
        'authorized': deviceAllowed,
      });
    }
    if (path == '/api/v1/vpn/location') {
      locationPosts.add((path: path, body: body, headers: headers));
      if (locationGate != null) await locationGate!.future;
      final id = (jsonDecode(utf8.decode(body)) as Map)['location'] as String;
      if (locationPostStatus == 200 || locationPostStatus == 202) {
        _pendingLocation = id;
        locationReads = 0;
      }
      return PiRawResponse(
        locationPostStatus,
        locationPostReply ??
            {
              'ok': locationPostStatus < 300,
              if (locationPostStatus == 200) 'confirmed': true,
              if (locationPostStatus == 202) 'pending': true,
              'observed': {
                'current': locations['current'],
                'mode': vpnState['mode'],
                'state': vpnState['state'],
              },
            },
      );
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

/// Fixed P-256 SPKI (DER, base64) and its SHA-256 as Argon formats it
/// (Node: createHash('sha256').update(spkiDer).digest('hex')).
const _spki =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEPw44/8LBYZg5BUGlYFYJ+QJcgc1m63lg9AdB2l1Ew9vVaSy055dvRYDx3ioW29H13xnfBUiPKXADZ95TSyNn+g==';
const _spkiFingerprint =
    '5a7925a3d20e3b54cc0b8a191a2a86d6b9a161bca8828cce70c957fd630d99a4';
const _notGranted =
    'Ask the Argon owner to allow VPN control for this phone in Devices → '
    'Phone synchronization (key fingerprint: 5a7925a3d20e3b54…)';
const _instance = '11111111-2222-3333-4444-555555555555';
const _device = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

/// In-memory Keystore: records every call in [log] (shared with the
/// transport so ordering across both can be asserted).
class _TestDeviceKey extends ArgonDeviceKey {
  _TestDeviceKey({List<String>? log, Iterable<String> existing = const []})
    : log = log ?? [],
      keys = {...existing};
  final List<String> log;
  final Set<String> keys;
  final signedWith = <String>[];
  @override
  Future<String> publicKey(String alias) async {
    keys.add(alias);
    return _spki;
  }

  @override
  Future<String> sign(String alias, String value) async {
    signedWith.add(alias);
    return base64Encode(utf8.encode('test-signature'));
  }

  @override
  Future<bool> exists(String alias) async => keys.contains(alias);
  @override
  Future<void> delete(String alias) async {
    log.add('key.delete $alias');
    keys.remove(alias);
  }

  @override
  Future<List<String>> list() async => keys.toList();
  @override
  Future<DeviceKeyHardware?> hardware(String alias) async =>
      DeviceKeyHardware.strongBox;
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
  _TestDeviceKey? key,
  Duration forgetTimeout = const Duration(seconds: 4),
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
  deviceKey: key ?? _TestDeviceKey(),
  forgetServerTimeout: forgetTimeout,
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

Future<PiProvider> _connected(
  PiTransport argon, {
  _Clock? clock,
  _TestDeviceKey? key,
}) async {
  final pi = _pi(argon, clock: clock, key: key);
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
      await pumpEventQueue(); // background permission check settles
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
      (403, VpnCommandIssue.forbidden, _notGranted),
      (409, VpnCommandIssue.busy, 'A change is already in progress.'),
      (
        409,
        VpnCommandIssue.keyChanged,
        'This phone\'s key no longer matches the one the Argon owner approved. '
            'Ask the owner to allow VPN control again '
            '(key fingerprint: 5a7925a3d20e3b54…)',
      ),
      (429, VpnCommandIssue.rateLimited, vpnRateLimitedMessage),
    ]) {
      test('$status is reported as ${issue.name}', () async {
        final argon = HubFake()..postStatus = status;
        if (issue == VpnCommandIssue.keyChanged) {
          argon.postReply = {
            'ok': false,
            'error': 'Phone key does not match the approved key.',
          };
        }
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
          expect(
            _text('Connected to Argon — monitoring household network'),
            findsOneWidget,
          );
          expect(_text('Connected · Local network'), findsOneWidget);
          expect(_text('Downloaded'), findsOneWidget);
          expect(_text('Total today'), findsOneWidget);
          expect(
            find.textContaining('via VPN', skipOffstage: false),
            findsWidgets,
          );
          expect(_text('Managed router'), findsOneWidget);
          expect(_text('Recent events'), findsOneWidget);
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
      (403, _notGranted, 'Refresh permission'),
      (409, 'A change is already in progress.', null),
      (429, vpnRateLimitedMessage, null),
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

  group('Phone key', () {
    final perPairing = 'argon.vpn.$_instance.$_device';
    final legacy = 'argon.vpn.$_instance';

    test('alias is derived from the paired device id', () {
      expect(ArgonDeviceKey.aliasFor(_instance, _device), perPairing);
      expect(ArgonDeviceKey.legacyAlias(_instance), legacy);
      expect(
        ArgonDeviceKey.aliasFor(
          _instance,
          'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee',
        ),
        isNot(perPairing),
      );
      expect(
        () => ArgonDeviceKey.aliasFor(_instance, '../x'),
        throwsArgumentError,
      );
      expect(() => ArgonDeviceKey.aliasFor('A', _device), throwsArgumentError);
    });

    test('fingerprint is SHA-256 of the SPKI DER, formatted like Argon', () {
      expect(ArgonDeviceKey.fingerprint(_spki), _spkiFingerprint);
      expect(
        ArgonDeviceKey.shortFingerprint(_spkiFingerprint),
        '5a7925a3d20e3b54…',
      );
    });

    test('a new pairing gets its own key; older keys are removed', () async {
      final key = _TestDeviceKey(
        existing: [
          legacy,
          'argon.vpn.$_instance.ffffffff-0000-0000-0000-000000000000',
        ],
      );
      SharedPreferences.setMockInitialValues({'argon.v2.trustedId': _instance});
      final argon = HubFake(kind: PiTransportKind.tailscale);
      final pi = _pi(argon, key: key);
      await pi.ready;
      await pi.discover();
      await pi.pair('123456');
      await pumpEventQueue();
      await pi.refreshVpnPermission();
      expect(await pi.setVpnMode(false), true);
      expect(key.signedWith.toSet(), {perPairing});
      expect(key.keys, {perPairing});
      expect(
        pi.vpnKeyFingerprint,
        _spkiFingerprint,
        reason: 'computed locally',
      );
      expect(pi.vpnKeyHardwareLabel, 'Hardware key: StrongBox');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('argon.v2.keyAlias'), perPairing);
      expect(prefs.getString('argon.v2.deviceId'), _device);
      pi.dispose();
    });

    test(
      'an existing per-install key keeps working for the same pairing',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          PiProvider.companionKey: _companion,
        });
        final key = _TestDeviceKey(existing: [legacy]);
        final argon = HubFake();
        final pi = await _connected(argon, key: key);
        expect(pi.vpnDeviceAllowed, true);
        expect(await pi.setVpnMode(false), true);
        expect(key.signedWith.toSet(), {legacy});
        expect(key.log, isEmpty, reason: 'nothing deleted, no re-grant needed');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('argon.v2.keyAlias'), legacy);
        expect(prefs.getString('argon.v2.deviceId'), _device);
        pi.dispose();
      },
    );

    test(
      'forget asks Argon to delete the key, then deletes it locally',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          PiProvider.companionKey: _companion,
        });
        SharedPreferences.setMockInitialValues({
          'argon.v2.deviceId': _device,
          'argon.v2.keyAlias': perPairing,
        });
        final log = <String>[];
        final key = _TestDeviceKey(log: log, existing: [perPairing, legacy]);
        final argon = HubFake(kind: PiTransportKind.tailscale)..log = log;
        final pi = await _connected(argon, key: key);
        expect(key.keys, {perPairing}, reason: 'orphaned key pruned at start');
        log.clear();
        await pi.forget();
        expect(log.take(2), ['server.delete', 'key.delete $perPairing']);
        expect(argon.keyDeleteTokens.single, 'Bearer $_companion');
        expect(key.keys, isEmpty);
        expect(pi.paired, false);
        expect(pi.vpnKeyFingerprint, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('argon.v2.keyAlias'), isNull);
        pi.dispose();
      },
    );

    test('forget never waits on an unresponsive Argon', () async {
      FlutterSecureStorage.setMockInitialValues({
        PiProvider.companionKey: _companion,
      });
      SharedPreferences.setMockInitialValues({
        'argon.v2.deviceId': _device,
        'argon.v2.keyAlias': perPairing,
      });
      final key = _TestDeviceKey(existing: [perPairing]);
      final argon = HubFake(kind: PiTransportKind.tailscale)
        ..keyDeleteGate = Completer<void>();
      final pi = _pi(
        argon,
        key: key,
        forgetTimeout: const Duration(milliseconds: 20),
      );
      await pi.ready;
      await pi.discover();
      await pi.forget();
      expect(key.keys, isEmpty);
      expect(pi.paired, false);
      pi.dispose();
    });

    test(
      'enrolling a key bound to another pairing (409) explains the fix',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          PiProvider.companionKey: _companion,
        });
        final argon = HubFake()..enrollStatus = 409;
        final pi = await _connected(argon);
        expect(pi.vpnDeviceAllowed, false);
        expect(pi.vpnPermissionError, vpnKeyRegisteredElsewhereMessage);
        expect(await pi.setVpnMode(false), false);
        expect(pi.vpnIssue, VpnCommandIssue.keyChanged);
        expect(pi.vpnMessage, vpnKeyRegisteredElsewhereMessage);
        expect(argon.posts, isEmpty);
        pi.dispose();
      },
    );

    testWidgets('VPN off reads as direct internet; key status is shown', (
      tester,
    ) async {
      _size(tester, const Size(904, 2316), 2.6);
      FlutterSecureStorage.setMockInitialValues({
        PiProvider.companionKey: _companion,
      });
      final pi = await _connectedInWidget(tester, HubFake(mode: 'off'));
      await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
      await tester.pump();
      expect(_text('Direct internet (VPN off)'), findsWidgets);
      expect(_text('Phone key: 5a7925a3d20e3b54…'), findsOneWidget);
      expect(_text('Hardware key: StrongBox'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no token entry');
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });
  });

  group('VPN location (provider)', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        PiProvider.companionKey: _companion,
      });
    });

    test('fixture parses: real locations, current and availability', () {
      final locs = VpnLocations.parse(_locationsFixture())!;
      expect(locs.locations.map((l) => l.id), [
        'uk-lon',
        'de-fra',
        'za-jnb',
        'nl-ams',
      ]);
      expect(locs.current!.id, 'uk-lon');
      expect(locs.current!.place, 'London, United Kingdom');
      expect(locs.locations.last.available, false);
      expect(locs.mode, 'on');
      expect(locs.canSwitchWhileOff, false);
      expect(locs.selectable, true);
      expect(locs.locations.where((l) => l.matches('frank')), hasLength(1));
    });

    test('list is read with the companion credential', () async {
      final argon = HubFake();
      final pi = await _connected(argon);
      argon.tokens.clear();
      await pi.refreshVpnLocations();
      expect(argon.tokens, [_companion]);
      expect(pi.vpnLocations!.locations, hasLength(4));
      expect(pi.vpnLocationsError, isNull);
      pi.dispose();
    });

    test('200: signed POST with exact path and body, then confirmed by a '
        'read-back', () async {
      final argon = HubFake();
      final pi = await _connected(argon);
      await pi.refreshVpnLocations();
      expect(await pi.setVpnLocation('de-fra'), true);
      final post = argon.locationPosts.single;
      expect(post.path, '/api/v1/vpn/location');
      expect(
        utf8.decode(post.body),
        '{"location":"de-fra","confirm":"VPN_LOCATION"}',
      );
      final auth = post.headers['Authorization']!;
      expect(auth, startsWith('ArgonDevice v2 id='));
      expect(auth, contains('nonce=$_nonce'));
      expect(auth.contains(_companion), false);
      expect(argon.posts, isEmpty, reason: 'mode endpoint untouched');
      expect(pi.locationPhase, VpnCommandPhase.confirmed);
      expect(pi.vpnLocations!.current!.id, 'de-fra');
      expect(argon.locationReads, greaterThanOrEqualTo(1));
      expect(
        pi.locationMessage,
        'Exit location is Germany — Frankfurt · confirmed by Argon',
      );
      expect(pi.events.first.title, 'VPN location changed');
      pi.dispose();
    });

    test('202: pending until Argon reports the new location', () async {
      final argon = HubFake()
        ..locationPostStatus = 202
        ..applyLocationAfterReads = 3;
      final pi = await _connected(argon);
      await pi.refreshVpnLocations();
      expect(await pi.setVpnLocation('za-jnb'), true);
      expect(argon.locationReads, 3);
      expect(pi.vpnLocations!.current!.id, 'za-jnb');
      pi.dispose();
    });

    test('202 that never takes effect is not reported as success', () async {
      final argon = HubFake()
        ..locationPostStatus = 202
        ..applyLocationAfterReads = 99;
      final pi = _pi(argon, attempts: 3);
      await pi.ready;
      await pi.discover();
      await pumpEventQueue();
      await pi.refreshVpnLocations();
      expect(await pi.setVpnLocation('de-fra'), false);
      expect(pi.locationIssue, VpnCommandIssue.unconfirmed);
      expect(argon.locationReads, 3);
      expect(pi.vpnLocations!.current!.id, 'uk-lon');
      pi.dispose();
    });

    for (final (status, reply, issue, text) in [
      (
        400,
        {'ok': false, 'error': 'Unknown location.'},
        VpnCommandIssue.unknownLocation,
        'Unknown location.',
      ),
      (403, null, VpnCommandIssue.forbidden, _notGranted),
      (
        409,
        {'ok': false, 'error': 'A VPN change is already in progress.'},
        VpnCommandIssue.busy,
        'A VPN change is already in progress.',
      ),
      (
        409,
        {'ok': false, 'error': 'Turn the VPN on to change location'},
        VpnCommandIssue.vpnOff,
        vpnLocationNeedsVpnOnMessage,
      ),
      (429, null, VpnCommandIssue.rateLimited, vpnRateLimitedMessage),
    ]) {
      test('$status is reported as ${issue.name}', () async {
        final argon = HubFake()
          ..locationPostStatus = status
          ..locationPostReply = reply;
        final pi = await _connected(argon);
        await pi.refreshVpnLocations();
        expect(await pi.setVpnLocation('de-fra'), false);
        expect(pi.locationIssue, issue);
        expect(pi.locationMessage, text);
        expect(argon.locationPosts, hasLength(1));
        pi.dispose();
      });
    }

    test('502 shows Argon\'s error and recovery text', () async {
      final argon = HubFake()
        ..locationPostStatus = 502
        ..locationPostReply = {
          'ok': false,
          'error': 'Surfshark did not answer for Frankfurt.',
          'recovery': 'Argon kept London.',
        };
      final pi = await _connected(argon);
      await pi.refreshVpnLocations();
      expect(await pi.setVpnLocation('de-fra'), false);
      expect(pi.locationIssue, VpnCommandIssue.upstream);
      expect(pi.locationMessage, 'Surfshark did not answer for Frankfurt.');
      expect(pi.locationRecovery, 'Argon kept London.');
      pi.dispose();
    });

    test(
      'no double submit; mode switch waits for the location change',
      () async {
        final argon = HubFake()..locationGate = Completer<void>();
        final pi = await _connected(argon);
        await pi.refreshVpnLocations();
        final first = pi.setVpnLocation('de-fra');
        await pumpEventQueue();
        expect(pi.locationInFlight, true);
        expect(await pi.setVpnLocation('de-fra'), false);
        expect(await pi.setVpnLocation('za-jnb'), false);
        expect(await pi.setVpnMode(false), false);
        argon.locationGate!.complete();
        expect(await first, true);
        expect(argon.locationPosts, hasLength(1));
        expect(argon.posts, isEmpty);
        pi.dispose();
      },
    );

    test('VPN off without canSwitchWhileOff: nothing is sent', () async {
      final argon = HubFake(mode: 'off');
      final pi = await _connected(argon);
      await pi.refreshVpnLocations();
      expect(pi.vpnLocations!.selectable, false);
      expect(await pi.setVpnLocation('de-fra'), false);
      expect(pi.locationIssue, VpnCommandIssue.vpnOff);
      expect(argon.locationPosts, isEmpty);
      pi.dispose();
    });
  });

  group('VPN location (UI)', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        PiProvider.companionKey: _companion,
      });
    });

    Future<PiProvider> open(WidgetTester tester, HubFake argon) async {
      _size(tester, const Size(904, 2316), 2.6);
      final pi = await _connectedInWidget(tester, argon);
      await tester.runAsync(pi.refreshVpnLocations);
      await tester.pumpWidget(_app(pi, const NetworkHubScreen()));
      await tester.pump();
      return pi;
    }

    Future<void> tapChange(WidgetTester tester) async {
      final button = find.byKey(const ValueKey('vpn-change-location'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await _settle(tester);
    }

    testWidgets('current location and a searchable list from Argon', (
      tester,
    ) async {
      final argon = HubFake();
      final pi = await open(tester, argon);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('vpn-current-location')))
            .data,
        'United Kingdom — London',
      );
      await tapChange(tester);
      expect(find.text('Choose exit location'), findsOneWidget);
      for (final id in ['uk-lon', 'de-fra', 'za-jnb', 'nl-ams']) {
        expect(find.byKey(ValueKey('vpn-location-$id')), findsOneWidget);
      }
      final current = tester.widget<ListTile>(
        find.byKey(const ValueKey('vpn-location-uk-lon')),
      );
      expect(current.enabled, false, reason: 'current is marked, not offered');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('vpn-location-uk-lon')),
          matching: find.text('Current'),
        ),
        findsOneWidget,
      );
      final unavailable = tester.widget<ListTile>(
        find.byKey(const ValueKey('vpn-location-nl-ams')),
      );
      expect(unavailable.enabled, false);
      expect(find.textContaining('Unavailable'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('vpn-location-search')),
        'africa',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('vpn-location-za-jnb')), findsOneWidget);
      expect(find.byKey(const ValueKey('vpn-location-de-fra')), findsNothing);
      expect(argon.locationPosts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    testWidgets('choose → confirm → pending → confirmed, sent once', (
      tester,
    ) async {
      final argon = HubFake()..locationGate = Completer<void>();
      final pi = await open(tester, argon);
      await tapChange(tester);
      await tester.tap(find.byKey(const ValueKey('vpn-location-de-fra')));
      await _settle(tester);
      expect(find.text('Switch to Germany — Frankfurt?'), findsOneWidget);
      expect(find.textContaining('pause briefly'), findsOneWidget);
      await tester.tap(find.text('Switch location'));
      await _settle(tester);
      expect(_text('Sending to Argon…'), findsOneWidget);
      final change = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('vpn-change-location')),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(change.onPressed, isNull, reason: 'no duplicate requests');
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('vpn-toggle')))
            .onChanged,
        isNull,
      );
      argon.locationGate!.complete();
      await _settle(tester);
      expect(
        _text('Exit location is Germany — Frankfurt · confirmed by Argon'),
        findsOneWidget,
      );
      expect(argon.locationPosts, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final argon = HubFake();
      final pi = await open(tester, argon);
      await tapChange(tester);
      await tester.tap(find.byKey(const ValueKey('vpn-location-de-fra')));
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(argon.locationPosts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    testWidgets('VPN off: selection disabled with an explanation', (
      tester,
    ) async {
      final argon = HubFake(mode: 'off');
      final pi = await open(tester, argon);
      final change = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('vpn-change-location')),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(change.onPressed, isNull);
      expect(
        find.textContaining(vpnLocationNeedsVpnOnMessage, skipOffstage: false),
        findsOneWidget,
      );
      expect(argon.locationPosts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      pi.dispose();
    });

    for (final (status, reply, expected, extra) in [
      (
        400,
        {'ok': false, 'error': 'Unknown location.'},
        'Unknown location.',
        'Refresh locations',
      ),
      (403, null, _notGranted, 'Refresh permission'),
      (
        409,
        {'ok': false, 'error': 'A VPN change is already in progress.'},
        'A VPN change is already in progress.',
        null,
      ),
      (
        502,
        {
          'ok': false,
          'error': 'Surfshark did not answer for Frankfurt.',
          'recovery': 'Argon kept London.',
        },
        'Surfshark did not answer for Frankfurt.',
        'Argon kept London.',
      ),
    ]) {
      testWidgets('response $status is shown', (tester) async {
        final argon = HubFake()
          ..locationPostStatus = status
          ..locationPostReply = reply;
        final pi = await open(tester, argon);
        await tapChange(tester);
        await tester.tap(find.byKey(const ValueKey('vpn-location-de-fra')));
        await _settle(tester);
        await tester.tap(find.text('Switch location'));
        await _settle(tester);
        expect(_text(expected), findsOneWidget);
        if (extra != null) expect(_text(extra), findsWidgets);
        expect(argon.locationPosts, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        pi.dispose();
      });
    }
  });
}
