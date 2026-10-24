import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/device_entity.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/devices_screen.dart';
import 'package:tt_router_flutter/screens/home_screen.dart';
import 'package:tt_router_flutter/screens/overview_tab.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';
import 'package:tt_router_flutter/widgets/home_widgets.dart';

import 'support/fake_mqtt_transport.dart';

final _devices = [
  {
    'HostName': 'Tab-A9',
    'Mac': '66:d9:ea:00:00:01',
    'Ip': '192.168.10.138',
    'AliveOnline': 1,
    'UpRate': 2505,
    'DownRate': 36336,
    'ClientType': 2,
    'ConnTime': 1792242175,
  },
  {
    'HostName': 'hue-bridge',
    'Mac': '00:17:88:00:00:02',
    'Ip': '192.168.10.152',
    'AliveOnline': 1,
    'ClientType': 0,
  },
  {
    'HostName': 'OnePlus-8T',
    'Mac': 'ae:e8:00:00:00:03',
    'Ip': '192.168.10.153',
    'AliveOnline': 0,
    'ClientType': 2,
  },
];

Map<String, dynamic>? _router(String path, dynamic data) => switch (path) {
  '/GetDevListInfo' => {'ErrorCode': 0, 'Data': _devices},
  '/GetExistNode' => {
    'ErrorCode': 0,
    'Data': [
      {
        'NodeSn': 'SN1',
        'OnLine': 1,
        'ClientNum': 2,
        'Role': 'mpp',
        'Uptime': 7200,
        'Model': 'ND001',
      },
    ],
  },
  '/GetSysConnectInfo' => {
    'ErrorCode': 0,
    'Data': {
      'OnlineNodeCount': 1,
      'TotalNodeCount': 1,
      'OnlineDev': 2,
      'Internet': 1,
      'NetworkQuality': 0,
    },
  },
  '/GetWirelessInfoListV2' => {'ErrorCode': 1},
  '/GetWirelessInfoList' => {
    'ErrorCode': 0,
    'Data': [
      {'Ssid': 'Game labs', 'Encrypt': 3, 'Password': 'x' * 8, 'Index': 0},
    ],
  },
  _ => {'ErrorCode': 0, 'Data': []},
};

Future<RouterProvider> _connectedProvider(
  WidgetTester tester, {
  bool refused = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final factory = FakeTransportFactory()
    ..responder = refused ? (path, data) => {'ErrorCode': 5} : _router;
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
    await provider.refreshDevices();
    await provider.refreshNodes();
    await provider.refreshWirelessSettings();
    await provider.refreshLiveTelemetry();
  });
  return provider;
}

Widget _app(RouterProvider provider, Widget home, {ThemeMode? mode}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(
          create: (_) => PiProvider(router: provider, autoStart: false),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode ?? ThemeMode.light,
        home: home,
      ),
    );

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});
  test('device sorting', () {
    final list = _devices.map(DeviceEntity.fromJson).toList();
    expect(sortDevices(list, DeviceSort.name).first.displayName, 'hue-bridge');
    expect(sortDevices(list, DeviceSort.activity).first.displayName, 'Tab-A9');
    expect(sortDevices(list, DeviceSort.ip).map((d) => d.ipAddress).toList(), [
      '192.168.10.138',
      '192.168.10.152',
      '192.168.10.153',
    ]);
  });

  testWidgets('a phone refused by the router shows waiting, never zero', (
    tester,
  ) async {
    await _setSize(tester, const Size(344, 780));
    final provider = await _connectedProvider(tester, refused: true);
    expect(provider.managedElsewhere, isTrue);
    expect(provider.knownOnlineDeviceCount, isNull);

    await tester.pumpWidget(_app(provider, const RouterDetailsScreen()));
    await tester.pump();
    expect(find.text('Another phone is managing the router'), findsOneWidget);
    expect(find.text('Devices: waiting'), findsOneWidget);
    expect(find.text('0 devices'), findsNothing);

    await tester.pumpWidget(_app(provider, const DevicesScreen()));
    await tester.pump();
    expect(find.text('Waiting for router access'), findsWidgets);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async => provider.dispose());
  });

  for (final (name, size) in [
    ('cover screen', const Size(344, 780)),
    ('unfolded', const Size(690, 840)),
    ('tablet', const Size(1100, 800)),
    // OnePlus 8T rotated: wide enough for the rail, only ~330 dp tall.
    ('phone landscape', const Size(800, 330)),
  ]) {
    testWidgets('home shell renders on $name without overflow', (tester) async {
      await _setSize(tester, size);
      final provider = await _connectedProvider(tester);
      await tester.pumpWidget(_app(provider, const HomeScreen()));
      await tester.pump();
      // Pi-first Home: Argon is the hero, the router a secondary card.
      expect(find.text('Argon'), findsOneWidget);
      expect(find.text('Managed router', skipOffstage: false), findsOneWidget);
      expect(
        find.byType(size.width >= 600 ? NavigationRail : FloatingNavBar),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_app(provider, const RouterDetailsScreen()));
      await tester.pump();
      expect(find.text('My Router'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.byType(RouterHero), findsOneWidget);
      // Password is masked until revealed.
      expect(find.text('x' * 8), findsNothing);
      expect(find.text('Game labs'), findsWidgets);
      expect(find.text('Router lights'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async => provider.dispose());
    });
  }

  testWidgets('devices tab filters, searches and opens details', (
    tester,
  ) async {
    await _setSize(tester, const Size(400, 900));
    final provider = await _connectedProvider(tester);
    await tester.pumpWidget(_app(provider, const DevicesScreen()));
    await tester.pump();

    expect(find.text('Tab-A9'), findsOneWidget);
    expect(find.text('OnePlus-8T'), findsOneWidget);

    await tester.ensureVisible(find.text('Offline 1'));
    await tester.tap(find.text('Offline 1'));
    await tester.pump();
    expect(find.text('Tab-A9'), findsNothing);
    expect(find.text('OnePlus-8T'), findsOneWidget);

    await tester.ensureVisible(find.text('All 3'));
    await tester.tap(find.text('All 3'));
    await tester.enterText(find.byType(TextField), '152');
    await tester.pump();
    expect(find.text('hue-bridge'), findsOneWidget);
    expect(find.text('Tab-A9'), findsNothing);

    await tester.tap(find.text('hue-bridge'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Not reported by this router'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Not reported by this router'), findsOneWidget);
    expect(find.textContaining('Wired'), findsWidgets);
    await tester.runAsync(() async => provider.dispose());
  });

  for (final tab in HomeTab.values) {
    testWidgets('${tab.label} tab survives 1.6x text on the cover screen', (
      tester,
    ) async {
      await _setSize(tester, const Size(344, 780));
      final provider = await _connectedProvider(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_app(provider, HomeScreen(initialTab: tab)));
      await tester.pump();
      final scaler = MediaQuery.textScalerOf(
        tester.element(find.byType(FloatingNavBar)),
      );
      expect(scaler.scale(10), closeTo(16, 0.01));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async => provider.dispose());
    });
  }

  testWidgets('dark theme renders the dashboard', (tester) async {
    await _setSize(tester, const Size(400, 900));
    final provider = await _connectedProvider(tester);
    await tester.pumpWidget(
      _app(provider, const HomeScreen(), mode: ThemeMode.dark),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async => provider.dispose());
  });
}
