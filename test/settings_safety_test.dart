import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/router_settings_screens.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';

import 'support/fake_mqtt_transport.dart';

Future<(RouterProvider, FakeTransportFactory)> _provider(
  WidgetTester tester,
  Map<String, dynamic>? Function(String, dynamic) responder,
) async {
  SharedPreferences.setMockInitialValues({});
  final factory = FakeTransportFactory()..responder = responder;
  final provider = RouterProvider(
    mqtt: MqttService(
      transportFactory: factory.call,
      appIdLoader: () async => 'app',
    ),
    authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
    autoStart: false,
  );
  await tester.runAsync(
    () => provider.selectRouter(
      MeshEntity(meshId: 'm', ssid: 'm', ipAddress: '10.0.0.1'),
    ),
  );
  return (provider, factory);
}

Future<void> _pump(WidgetTester tester, RouterProvider p, Widget screen) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  // Let the screen's load request reach the fake router and return.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

void main() {
  testWidgets('settings whose load failed cannot be saved', (tester) async {
    final (provider, _) = await _provider(
      tester,
      (path, data) => path == '/GetFirewallInfo'
          ? {'ErrorCode': 9}
          : {'ErrorCode': 0, 'Data': {}},
    );
    await _pump(tester, provider, const SecuritySettingsScreen());

    expect(find.text('Could not read the current settings'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await tester.runAsync(() async => provider.dispose());
  });

  testWidgets('invalid LAN values are rejected before sending', (tester) async {
    final (provider, factory) = await _provider(
      tester,
      (path, data) => path == '/GetLanInfoV3'
          ? {
              'ErrorCode': 0,
              'Data': [
                {'LanIp': '192.168.10.1', 'LanMask': '255.255.255.0'},
                {
                  'DhcpStartAddr': '192.168.10.100',
                  'DhcpEndAddr': '192.168.10.200',
                },
                {'VlanEnable': 0, 'Vlanid': 0},
              ],
            }
          : null,
    );
    await _pump(tester, provider, const LanSettingsScreen());
    expect(find.text('Save'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Start address'),
      '10.1.1.5',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Must be in the router\'s subnet'), findsOneWidget);
    expect(
      factory.last.published.where((p) => p.topic.endsWith('SetLanInfoV3')),
      isEmpty,
    );
    await tester.runAsync(() async => provider.dispose());
  });
}
