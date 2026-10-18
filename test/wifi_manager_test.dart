import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/models/save_result.dart';
import 'package:tt_router_flutter/models/wifi_inventory.dart';
import 'package:tt_router_flutter/models/wireless_network.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/wifi_screen.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/wifi_scan.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';

import 'support/fake_mqtt_transport.dart';

/// The live household layout: entries 1 and 2 both "Nokia Wifi" (WPA2),
/// entry 3 left open and off after the WPA3 test.
List<Map<String, dynamic>> _household() => [
  {
    'Ssid': 'Nokia Wifi',
    'Encrypt': 3,
    'Password': 'HousePass1',
    'Vlanid': -1,
    'VlanEnable': 0,
    'SsidIsolate': 1,
    'StaIsolate': 0,
    'Index': 0,
    'Create': 1,
  },
  {
    'Ssid': 'Nokia Wifi',
    'Encrypt': 3,
    'Password': 'HousePass1',
    'Vlanid': -1,
    'VlanEnable': 0,
    'SsidIsolate': 1,
    'StaIsolate': 0,
    'Index': 1,
    'Create': 1,
  },
  {
    'Ssid': 'Argon-WPA3-Test',
    'Encrypt': 0,
    'Password': '',
    'Vlanid': -1,
    'VlanEnable': 0,
    'SsidIsolate': 1,
    'StaIsolate': 0,
    'Index': 2,
    'Create': 0,
  },
];

List<WirelessNetwork> _parsed([List<Map<String, dynamic>>? table]) =>
    (table ?? _household()).map(WirelessNetwork.fromJson).toList();

const _guest = {'Enable': 1, 'Ssid': 'Visitors'};

WifiScanResult _ap(String ssid, String bssid, int mhz, {int level = -50}) =>
    WifiScanResult(
      ssid: ssid,
      bssid: bssid,
      frequency: mhz,
      level: level,
      capabilities: ssid.isEmpty || ssid == 'Open Cafe'
          ? '[ESS]'
          : '[WPA-PSK-CCMP][RSN-PSK-CCMP][ESS]',
    );

/// What this phone heard next to the router (block 7c:10:c9:aa:bb).
WifiScanSnapshot _scan() => WifiScanSnapshot(
  status: WifiScanStatus.ok,
  at: DateTime.now(),
  connectedBssid: '7c:10:c9:aa:bb:03',
  connectedSsid: 'Nokia Wifi',
  results: [
    _ap('Nokia Wifi', '7c:10:c9:aa:bb:03', 2417),
    _ap('Nokia Wifi', '7c:10:c9:aa:bb:05', 5220),
    _ap('Nokia Wifi', '7c:10:c9:aa:bb:07', 2417),
    _ap('Game Labs-2.4G', '7c:10:c9:aa:bb:0a', 2417, level: -41),
    _ap('', '7c:10:c9:aa:bb:0e', 5745),
    _ap('Visitors', '7c:10:c9:aa:bb:0d', 2417),
    _ap('Neighbour', '11:22:33:44:55:66', 2462),
  ],
);

class _FakeScanner implements WifiScanner {
  _FakeScanner(this.answer);
  WifiScanSnapshot Function(bool request) answer;
  final requests = <bool>[];
  @override
  Future<WifiScanSnapshot> scan({bool requestPermission = false}) async {
    requests.add(requestPermission);
    return answer(requestPermission);
  }
}

/// Router that applies SetWirelessInfoList to its table, so read-back sees
/// what was written.
class _Router {
  List<Map<String, dynamic>> table = _household();
  final writes = <List<Map<String, dynamic>>>[];

  Map<String, dynamic>? respond(String path, dynamic data) => switch (path) {
    '/GetWirelessInfoListV2' => {'ErrorCode': 1},
    '/GetWirelessInfoList' => {
      'ErrorCode': 0,
      'Data': jsonDecode(jsonEncode(table)),
    },
    '/SetWirelessInfoList' => () {
      final payload = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      writes.add(payload);
      table = payload;
      return {'ErrorCode': 0};
    }(),
    '/GetGuestInfo' => {
      'ErrorCode': 0,
      'Data': [_guest],
    },
    _ => {'ErrorCode': 0, 'Data': []},
  };
}

Future<RouterProvider> _provider(WidgetTester tester, _Router router) async {
  final factory = FakeTransportFactory()..responder = router.respond;
  final provider = RouterProvider(
    mqtt: MqttService(
      transportFactory: factory.call,
      appIdLoader: () async => 'app',
    ),
    authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
    autoStart: false,
  );
  await tester.runAsync(() async {
    await provider.selectRouter(
      MeshEntity(meshId: 'm', ssid: 'm', ipAddress: '10.0.0.1'),
    );
    await provider.refreshWirelessSettings();
    await provider.loadGuestWifiSettings();
  });
  return provider;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  RouterProvider provider,
  WifiScanner scanner,
) async {
  tester.view.physicalSize = const Size(348, 4600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: WifiSettingsScreen(scanner: scanner),
      ),
    ),
  );
  await tester.pump();
  await _drain(tester);
}

/// Lets the fake router's real-time replies arrive.
Future<void> _drain(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _noException(WidgetTester tester) =>
    expect(tester.takeException(), isNull);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('grouping (pure)', () {
    test('primary network = enabled entries sharing the most common SSID', () {
      final networks = _parsed([
        ..._household(),
        {
          'Ssid': 'Workshop',
          'Encrypt': 3,
          'Password': 'x' * 8,
          'Index': 3,
          'Create': 1,
        },
      ]);
      final primary = WifiInventory.primary(networks)!;
      expect(primary.ssid, 'Nokia Wifi');
      expect(primary.entries.map((n) => n.index), [0, 1]);
      expect(primary.securityLabel, 'WPA2-PSK');
      expect(primary.entriesLabel, 'Router entries 1 and 2');
      expect(primary.anyUnsecured, false);
    });

    test('ties go to the lowest index; nothing enabled means no primary', () {
      final tie = _parsed([
        {
          'Ssid': 'B',
          'Encrypt': 3,
          'Password': 'x' * 8,
          'Index': 1,
          'Create': 1,
        },
        {
          'Ssid': 'A',
          'Encrypt': 3,
          'Password': 'x' * 8,
          'Index': 0,
          'Create': 1,
        },
      ]);
      expect(WifiInventory.primary(tie)!.ssid, 'A');
      final off = _parsed([
        {
          'Ssid': 'A',
          'Encrypt': 3,
          'Password': 'x' * 8,
          'Index': 0,
          'Create': 0,
        },
      ]);
      expect(WifiInventory.primary(off), isNull);
    });

    test(
      'duplicates need ≥2 enabled entries with the same SSID and security',
      () {
        final groups = WifiInventory.duplicates(_parsed());
        expect(groups, hasLength(1));
        expect(groups.single.keep.index, 0);
        expect(groups.single.retire.index, 1, reason: 'higher index goes');
        final mixed = _parsed()..[1] = _parsed()[1].copyWith(encrypt: 4);
        expect(WifiInventory.duplicates(mixed), isEmpty);
        final oneOff = _parsed()..[1] = _parsed()[1].withEnabled(false);
        expect(WifiInventory.duplicates(oneOff), isEmpty);
      },
    );

    test('labels: configured, disabled, guest, observed, mesh, unknown', () {
      final rows = WifiInventory.build(
        networks: _parsed([
          ..._household(),
          {
            'Ssid': '',
            'Encrypt': 3,
            'Password': 'x' * 8,
            'Index': 3,
            'Create': 0,
          },
        ]),
        guest: _guest,
        scan: _scan(),
      );
      NetworkKind kindOf(String name) =>
          rows.firstWhere((r) => r.name == name).kind;
      expect(rows.where((r) => r.name == 'Nokia Wifi').map((r) => r.kind), [
        NetworkKind.configured,
        NetworkKind.configured,
      ]);
      expect(kindOf('Argon-WPA3-Test'), NetworkKind.disabled);
      expect(
        rows.firstWhere((r) => r.name == 'Argon-WPA3-Test').unsecured,
        true,
      );
      expect(kindOf('Visitors'), NetworkKind.guest);
      expect(kindOf('Game Labs-2.4G'), NetworkKind.observed);
      expect(
        rows.firstWhere((r) => r.name == 'Game Labs-2.4G').note,
        observedOnlyReason,
      );
      expect(kindOf('Hidden network'), NetworkKind.meshInternal);
      expect(kindOf('No name set'), NetworkKind.unknown);
      expect(
        rows.any((r) => r.name == 'Neighbour'),
        false,
        reason: 'outside the router BSSID block',
      );
      expect(
        NetworkKind.observed.label,
        'Observed — not exposed by router API',
      );
      expect(rows.firstWhere((r) => r.name == 'Nokia Wifi').bandsSeen, [
        '2.4 GHz',
        '5 GHz',
      ]);
    });

    test(
      'a phone joined elsewhere does not attribute networks to the router',
      () {
        final away = WifiScanSnapshot(
          status: WifiScanStatus.ok,
          connectedBssid: '11:22:33:44:55:66',
          connectedSsid: 'Neighbour',
          results: _scan().results,
        );
        expect(WifiInventory.routerBlock(away, _parsed()), isNull);
        final rows = WifiInventory.build(networks: _parsed(), scan: away);
        expect(rows.where((r) => r.kind == NetworkKind.observed), isEmpty);
      },
    );
  });

  group('safety (provider)', () {
    testWidgets('turning on an open entry is refused before anything is sent', (
      tester,
    ) async {
      final router = _Router();
      final provider = await _provider(tester, router);
      late SaveResult result;
      await tester.runAsync(() async {
        result = await provider.setWirelessNetworkEnabled(2, true);
      });
      expect(result.isFailed, true);
      expect(result.message, unsecuredEnableMessage);
      expect(router.writes, isEmpty);
      await tester.runAsync(() async => provider.dispose());
    });
  });

  group('Wi-Fi network manager (screen)', () {
    testWidgets(
      'primary card, duplicate notice and labels; no automatic writes',
      (tester) async {
        final router = _Router();
        final provider = await _provider(tester, router);
        await _pumpScreen(tester, provider, _FakeScanner((_) => _scan()));

        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('wifi-primary-ssid')))
              .data,
          'Nokia Wifi',
        );
        expect(find.text('Primary household network'), findsOneWidget);
        expect(find.text('WPA2-PSK'), findsOneWidget);
        expect(
          find.text(
            '2.4 GHz · 5 GHz · heard here on 2.4 GHz, 5 GHz (3 radios)',
          ),
          findsOneWidget,
        );
        expect(find.text('On · entries 1 and 2'), findsOneWidget);
        expect(find.text('Duplicate configuration'), findsOneWidget);
        expect(
          find.textContaining('real clients may use either'),
          findsOneWidget,
        );
        for (final label in [
          'Configured & controllable',
          'Disabled',
          'Guest',
          'Observed — not exposed by router API',
          'Mesh/internal',
        ]) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        expect(find.text('Game Labs-2.4G'), findsOneWidget);
        expect(find.text('Neighbour'), findsNothing);
        expect(find.text('Unsecured'), findsOneWidget, reason: 'entry 3 chip');
        expect(router.writes, isEmpty);
        _noException(tester);
        await tester.runAsync(() async => provider.dispose());
      },
    );

    testWidgets(
      'consolidate: review → confirm remaining → approval → write → rollback',
      (tester) async {
        final router = _Router();
        final provider = await _provider(tester, router);
        await _pumpScreen(tester, provider, _FakeScanner((_) => _scan()));

        await _tap(tester, find.byKey(const ValueKey('wifi-consolidate')));
        expect(find.text('Consolidate "Nokia Wifi"'), findsOneWidget);
        expect(find.text('Will be turned off'), findsOneWidget);
        expect(
          find.textContaining('Router entry 2 · "Nokia Wifi" · WPA2-PSK'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Router entry 1 keeps the name'),
          findsOneWidget,
        );
        final cont = find.byKey(const ValueKey('consolidate-continue'));
        expect(
          tester.widget<FilledButton>(cont).onPressed,
          isNull,
          reason: 'remaining entry must be confirmed first',
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('consolidate-confirm-remaining')),
        );
        await _tap(tester, cont);

        // Explicit approval; cancelling sends nothing.
        expect(find.text('Turn off router entry 2?'), findsOneWidget);
        expect(
          find.textContaining('briefly disconnect and reconnect'),
          findsOneWidget,
        );
        await _tap(tester, find.text('Cancel'));
        expect(router.writes, isEmpty);

        await _tap(tester, find.byKey(const ValueKey('wifi-consolidate')));
        await _tap(
          tester,
          find.byKey(const ValueKey('consolidate-confirm-remaining')),
        );
        await _tap(tester, find.byKey(const ValueKey('consolidate-continue')));
        await tester.tap(find.text('Turn off entry 2'));
        await tester.pump();
        await _drain(tester);

        expect(router.writes, hasLength(1));
        final sent = router.writes.single;
        expect(sent, hasLength(3), reason: 'full list, as read');
        expect(sent[0]['Create'], 1);
        expect(sent[1]['Create'], 0);
        expect(sent[1]['Ssid'], 'Nokia Wifi');
        expect(sent[1]['Password'], 'HousePass1');
        expect(sent[2]['Create'], 0, reason: 'open entry untouched');

        // Rollback is offered, and only re-enables after approval.
        final undo = find.byKey(const ValueKey('wifi-rollback'));
        expect(undo, findsOneWidget);
        expect(find.text('Re-enable entry 2'), findsOneWidget);
        await _tap(tester, undo);
        expect(find.text('Turn on "Nokia Wifi" (entry 2)?'), findsOneWidget);
        await tester.tap(find.text('Turn on'));
        await tester.pump();
        await _drain(tester);
        expect(router.writes, hasLength(2));
        expect(router.writes.last[1]['Create'], 1);
        _noException(tester);
        await tester.runAsync(() async => provider.dispose());
      },
    );

    testWidgets('enabling an open entry is blocked and routes to the editor', (
      tester,
    ) async {
      final router = _Router();
      final provider = await _provider(tester, router);
      await _pumpScreen(tester, provider, _FakeScanner((_) => _scan()));
      await _tap(tester, find.byKey(const ValueKey('wifi-advanced-toggle')));
      expect(find.byType(WifiNetworkCard), findsNWidgets(3));
      await _tap(tester, find.byType(Switch).at(2));
      expect(find.text('Secure this network first'), findsOneWidget);
      expect(find.text(unsecuredEnableMessage), findsOneWidget);
      expect(router.writes, isEmpty);
      await _tap(tester, find.text('Set WPA2 & password'));
      expect(find.text('Edit router entry 3'), findsOneWidget);
      expect(find.text('This network has no password'), findsOneWidget);
      expect(router.writes, isEmpty);
      await tester.runAsync(() async => provider.dispose());
    });

    testWidgets('scan permission denied: explained, asked only on tap', (
      tester,
    ) async {
      final router = _Router();
      final provider = await _provider(tester, router);
      final scanner = _FakeScanner(
        (request) => request
            ? _scan()
            : const WifiScanSnapshot(status: WifiScanStatus.permissionDenied),
      );
      await _pumpScreen(tester, provider, scanner);
      expect(scanner.requests, [false], reason: 'no prompt on open');
      expect(
        find.text('Location permission needed for nearby networks'),
        findsOneWidget,
      );
      expect(find.text('Game Labs-2.4G'), findsNothing);
      expect(
        find.text('Configured & controllable'),
        findsWidgets,
        reason: 'router networks still listed',
      );
      await _tap(tester, find.byKey(const ValueKey('wifi-scan-allow')));
      expect(scanner.requests, [false, true]);
      expect(find.text('Game Labs-2.4G'), findsOneWidget);
      expect(find.textContaining(observedOnlyReason), findsOneWidget);
      await tester.runAsync(() async => provider.dispose());
    });
  });

  testWidgets('restore WPA2 on a disabled open network: Encrypt 3 + password', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final network = WirelessNetwork.fromJson(_household()[2]);
    WirelessNetwork? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => WifiEditSheet(network: network),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final password = find.byType(TextFormField).at(1);
    expect(tester.widget<TextFormField>(password).enabled, false);
    expect(find.text('Open — no password (current)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wifi-security-select')));
    await tester.pumpAndSettle();
    // The SSID mentions WPA3; no security option does.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').contains('WPA3') &&
            !(w.data ?? '').contains('Argon-WPA3-Test'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('WPA2 (AES)').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(password).enabled, true);

    // A password is required to secure it.
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(password, 'NewPass123');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final payload = result!.toRouterPayload();
    expect(payload['Encrypt'], 3);
    expect(payload['Password'], 'NewPass123');
    expect(payload['Create'], 0, reason: 'stays off');
    expect(payload['Index'], 2);
    expect(result!.isUnsecured, false);
  });
}
