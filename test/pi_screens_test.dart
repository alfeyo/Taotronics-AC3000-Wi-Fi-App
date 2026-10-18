import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/home_screen.dart';
import 'package:tt_router_flutter/screens/pi_gateway_screen.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/pi_api.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';

import 'support/fake_mqtt_transport.dart';

class _Argon implements PiTransport {
  _Argon(this.routes);
  final Map<String, Map<String, dynamic>> routes;
  @override
  PiTransportKind get kind => PiTransportKind.lan;
  @override
  String get describe => '192.168.50.1';
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) async => routes[path] ?? (throw const PiApiException('unreachable'));
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async => throw const PiApiException('unreachable');
}

final _routes = <String, Map<String, dynamic>>{
  '/api/v1/identity': {
    'version': 1,
    'ok': true,
    'service': 'argon',
    'instanceId': '11111111-2222-3333-4444-555555555555',
    'apiVersions': [1],
    'access': {'monitor': true},
  },
  '/api/v1/live': {
    'version': 1,
    'ok': true,
    'traffic': {
      'stale': false,
      'aggregate': {'downloadBps': 8 * 1024 * 1024, 'uploadBps': 8 * 2048},
      'today': {
        'downloadBytes': 3 * 1024 * 1024 * 1024,
        'uploadBytes': 0,
        'vpnDownloadBytes': 3 * 1024 * 1024 * 1024,
        'vpnUploadBytes': 0,
      },
    },
  },
  '/api/v1/gateway': {
    'version': 1,
    'ok': true,
    'gateway': {
      'model': 'Raspberry Pi 4 Model B Rev 1.2',
      'uptimeSeconds': 3600,
      'cpuPercent': 12.0,
      'temperatureC': 47.2,
      'memory': {'usedPercent': 17.5},
      'activeThrottling': false,
      'upstream': {'interface': 'wlan1', 'ssid': 'Upstream', 'online': true},
      'vpn': {'state': 'connected', 'mode': 'on', 'location': 'London'},
    },
    'history': {
      'days': [
        {
          'day': '2026-10-18',
          'downloadBytes': 100,
          'uploadBytes': 10,
          'measured': true,
        },
      ],
    },
    'events': [],
  },
};

RouterProvider _router() => RouterProvider(
  mqtt: MqttService(
    transportFactory: FakeTransportFactory().call,
    appIdLoader: () async => 'app',
  ),
  authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
  autoStart: false,
);

Future<(RouterProvider, PiProvider)> _providers(
  WidgetTester tester, {
  bool argonUp = true,
}) async {
  late PiProvider pi;
  final router = _router();
  await tester.runAsync(() async {
    pi = PiProvider(
      router: router,
      autoStart: false,
      httpTransport: (uri) => argonUp ? _Argon(_routes) : _Argon(const {}),
      bluetoothStatus: () async => const {},
    );
    await pi.ready;
    await pi.discover();
    await pi.tick();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  return (router, pi);
}

Widget _app(RouterProvider router, PiProvider pi, Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: router),
    ChangeNotifierProvider.value(value: pi),
  ],
  child: MaterialApp(theme: AppTheme.dark(), home: home),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'Gateway shows the Raspberry Pi and its measurements, not a connection form',
    (tester) async {
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (router, pi) = await _providers(tester);
      await tester.pumpWidget(_app(router, pi, const PiGatewayScreen()));
      await tester.pump();
      expect(find.text('Argon'), findsOneWidget);
      expect(find.text('Raspberry Pi 4 Model B'), findsOneWidget);
      expect(find.text('Connected · Local network'), findsOneWidget);
      expect(find.text('VPN protected'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.text('47°C'), findsOneWidget);
      expect(
        find.text('1.00 MiB/s'),
        findsOneWidget,
        reason: '8 Mbit/s from Argon = 1 MiB/s',
      );
      expect(find.text('3.00 GiB'), findsOneWidget);
      expect(find.text('Enable device synchronization'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'pairing input only after Set up',
      );
      expect(tester.takeException(), isNull);
      pi.dispose();
    },
  );

  testWidgets(
    'Home labels Argon-measured traffic; falls back to labelled router data',
    (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var (router, pi) = await _providers(tester);
      await tester.pumpWidget(_app(router, pi, const HomeScreen()));
      await tester.pump();
      expect(
        find.text('Measured by Argon · household traffic · live'),
        findsOneWidget,
      );
      expect(find.textContaining('Online via Local network'), findsOneWidget);
      pi.dispose();

      (router, pi) = await _providers(tester, argonUp: false);
      await tester.pumpWidget(_app(router, pi, const HomeScreen()));
      await tester.pump();
      expect(
        find.text('Measured by Argon · household traffic · live'),
        findsNothing,
      );
      expect(find.textContaining('Unreachable'), findsWidgets);
      expect(tester.takeException(), isNull);
      pi.dispose();
    },
  );
}
