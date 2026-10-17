import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/home_screen.dart';
import 'package:tt_router_flutter/screens/statistics_screen.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';
import 'package:tt_router_flutter/widgets/home_widgets.dart';

import 'support/fake_mqtt_transport.dart';

/// How the fake router reacts to SetNodeLed.
enum _LedMode { applies, ignored, rejected }

class _FakeRouter {
  int led = 0;
  _LedMode mode = _LedMode.applies;
  final ledWrites = <int>[];

  Map<String, dynamic>? call(String path, dynamic data) => switch (path) {
    '/GetExistNode' => {
      'ErrorCode': 0,
      'Data': [
        {'NodeSn': 'SN1', 'OnLine': 1, 'Role': 'mpp', 'Model': 'ND001'},
      ],
    },
    '/GetSysConnectInfo' => {
      'ErrorCode': 0,
      'Data': {'OnlineNodeCount': 1, 'TotalNodeCount': 1, 'Internet': 1},
    },
    '/GetLedList' => {
      'ErrorCode': 0,
      'Data': [
        {'NodeSn': 'SN1', 'NickName': '', 'Led': led},
      ],
    },
    '/SetNodeLed' => _setLed(data as Map),
    '/GetWirelessInfoListV2' => {'ErrorCode': 1},
    _ => {'ErrorCode': 0, 'Data': []},
  };

  Map<String, dynamic> _setLed(Map data) {
    ledWrites.add(data['Led'] as int);
    switch (mode) {
      case _LedMode.applies:
        led = data['Led'] as int;
        return {'ErrorCode': 0};
      case _LedMode.ignored:
        return {'ErrorCode': 0};
      case _LedMode.rejected:
        return {'ErrorCode': 1};
    }
  }
}

Future<RouterProvider> _provider(
  WidgetTester tester,
  _FakeRouter router,
) async {
  SharedPreferences.setMockInitialValues({});
  final factory = FakeTransportFactory()..responder = router.call;
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
    await provider.refreshNodes();
    await provider.refreshLeds();
  });
  return provider;
}

Widget _app(RouterProvider provider, Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: provider),
    ChangeNotifierProvider(create: (_) => PiProvider()),
  ],
  child: MaterialApp(theme: AppTheme.dark(), home: home),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});
  Future<(RouterProvider, List<int?>)> pumpHome(
    WidgetTester tester,
    _FakeRouter router,
  ) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = await _provider(tester, router);
    final requested = <int?>[];
    provider.addListener(() => requested.add(provider.ledRequested('SN1')));
    await tester.pumpWidget(_app(provider, const HomeScreen()));
    await tester.pump();
    return (provider, requested);
  }

  testWidgets('tapping the router light shows pending, then the read-back', (
    tester,
  ) async {
    final router = _FakeRouter();
    final (provider, requested) = await pumpHome(tester, router);

    expect(find.byType(RouterHero), findsOneWidget);
    expect(find.byTooltip('Router LED off'), findsOneWidget);

    await tester.tap(find.byTooltip('Router LED off'));
    await _settle(tester);

    expect(router.ledWrites, [1]);
    // The requested state was shown as pending before being confirmed.
    expect(requested, contains(1));
    expect(provider.ledRequested('SN1'), isNull);
    expect(find.byTooltip('Router LED on'), findsOneWidget);
    expect(find.text('Router LED turned on.'), findsOneWidget);
    await tester.runAsync(() async => provider.dispose());
  });

  testWidgets('an ignored LED change restores the confirmed state', (
    tester,
  ) async {
    final router = _FakeRouter()..mode = _LedMode.ignored;
    final (provider, _) = await pumpHome(tester, router);

    await tester.tap(find.byTooltip('Router LED off'));
    await tester.pump();
    // Read-backs are retried for a few seconds before the change fails.
    expect(provider.ledRequested('SN1'), 1);
    for (var i = 0; i < 4; i++) {
      await _settle(tester);
    }

    expect(provider.ledRequested('SN1'), isNull);
    expect(router.ledWrites, [1]);
    expect(find.byTooltip('Router LED off'), findsOneWidget);
    expect(find.byTooltip('Router LED on'), findsNothing);
    expect(
      provider.events.map((e) => e.title),
      contains('LED change not applied'),
    );
    await tester.runAsync(() async => provider.dispose());
  });

  testWidgets('a rejected LED command keeps the previous state', (
    tester,
  ) async {
    final router = _FakeRouter()
      ..led = 1
      ..mode = _LedMode.rejected;
    final (provider, _) = await pumpHome(tester, router);

    expect(find.byTooltip('Router LED on'), findsOneWidget);
    await tester.tap(find.byTooltip('Router LED on'));
    await _settle(tester);

    expect(router.ledWrites, [0]);
    expect(find.byTooltip('Router LED on'), findsOneWidget);
    await tester.runAsync(() async => provider.dispose());
  });

  testWidgets('overlapping LED commands are refused', (tester) async {
    final router = _FakeRouter();
    final provider = await _provider(tester, router);
    await tester.runAsync(() async {
      final first = provider.updateNodeLed(nodeSn: 'SN1', led: 1);
      final second = await provider.updateNodeLed(nodeSn: 'SN1', led: 0);
      expect(second.isConfirmed, isFalse);
      expect((await first).isConfirmed, isTrue);
    });
    expect(router.ledWrites, [1]);
    await tester.runAsync(() async => provider.dispose());
  });

  testWidgets('five-item navigation opens Statistics', (tester) async {
    final router = _FakeRouter();
    final (provider, _) = await pumpHome(tester, router);

    final nav = find.byType(FloatingNavBar);
    expect(nav, findsOneWidget);
    for (final tab in HomeTab.values) {
      expect(
        find.descendant(of: nav, matching: find.text(tab.label)),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(of: nav, matching: find.text('Statistics')),
    );
    await _settle(tester);
    expect(find.byType(StatisticsScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Technical details'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Technical details'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async => provider.dispose());
  });
}
