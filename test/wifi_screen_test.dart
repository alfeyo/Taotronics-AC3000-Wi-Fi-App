import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/models/wireless_network.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/wifi_screen.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/wifi_scan.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';

import 'support/fake_mqtt_transport.dart';

class _NoScan implements WifiScanner {
  @override
  Future<WifiScanSnapshot> scan({bool requestPermission = false}) async =>
      const WifiScanSnapshot(status: WifiScanStatus.unsupported);
}

final _table = [
  {
    'Ssid': 'Game labs',
    'Encrypt': 3,
    'Password': 'GamePass1',
    'Index': 0,
    'Create': 1,
  },
  {
    'Ssid': 'TT-35A0',
    'Encrypt': 3,
    'Password': 'MeshPass5',
    'Index': 1,
    'Create': 1,
  },
  {
    'Ssid': 'TT-35A0',
    'Encrypt': 3,
    'Password': 'MeshPass5',
    'Index': 2,
    'Create': 0,
  },
];

void main() {
  testWidgets('every band has its own switch; toggling asks then writes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final writes = <List<dynamic>>[];
    final factory = FakeTransportFactory()
      ..responder = (path, data) => switch (path) {
        '/GetWirelessInfoListV2' => {'ErrorCode': 1},
        '/GetWirelessInfoList' => {
          'ErrorCode': 0,
          'Data': jsonDecode(jsonEncode(_table)),
        },
        '/SetWirelessInfoList' => () {
          writes.add(data as List);
          return {'ErrorCode': 0};
        }(),
        '/GetGuestInfo' => {
          'ErrorCode': 0,
          'Data': [
            {'Enable': 0, 'Ssid': 'Visitors'},
          ],
        },
        _ => {'ErrorCode': 0, 'Data': []},
      };
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
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: WifiSettingsScreen(scanner: _NoScan()),
        ),
      ),
    );
    await tester.pump();

    // Per-entry controls live under "Advanced (per-configuration)".
    expect(find.byType(WifiNetworkCard), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('wifi-advanced-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('wifi-advanced-toggle')));
    await tester.pumpAndSettle();

    expect(find.byType(WifiNetworkCard), findsNWidgets(3));
    expect(find.byType(Switch), findsNWidgets(3));
    expect(find.text('3 networks'), findsOneWidget);
    expect(find.text('2 on'), findsOneWidget);
    expect(find.text('2 names live'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WifiNetworkCard),
        matching: find.text('Off'),
      ),
      findsOneWidget,
    );

    // Cancelling the confirmation sends nothing.
    await tester.ensureVisible(find.byType(Switch).at(1));
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Turn off "TT-35A0" (entry 2)?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);

    // Confirming turns the band off with its settings intact.
    await tester.ensureVisible(find.byType(Switch).at(1));
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(writes, hasLength(1));
    final sent = (writes.single[1] as Map);
    expect(sent['Create'], 0);
    expect(sent['Ssid'], 'TT-35A0');
    expect(sent['Password'], 'MeshPass5');
    expect(find.text('1 on'), findsOneWidget);

    await tester.runAsync(() async => provider.dispose());
  });

  testWidgets(
    'security selector never offers WPA3 (stored as open) or weak modes',
    (tester) async {
      final network = WirelessNetwork.fromJson({
        'Ssid': 'TT-35A0',
        'Encrypt': 4,
        'Password': 'p' * 10,
        'Vlanid': 0,
        'VlanEnable': 0,
        'SsidIsolate': 0,
        'StaIsolate': 0,
        'Index': 2,
        'Create': 0,
      });
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
      await tester.tap(find.text('WPA/WPA2 mixed'));
      await tester.pumpAndSettle();
      expect(find.textContaining('WPA3'), findsNothing);
      expect(find.text('WEP'), findsNothing);
      expect(find.text('None'), findsNothing);
      await tester.tap(find.text('WPA2 (AES)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final payload = result!.toRouterPayload();
      expect(payload['Encrypt'], 3);
      expect(payload['Password'], 'p' * 10);
    },
  );
}
