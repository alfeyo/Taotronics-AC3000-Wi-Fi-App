import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nokia_home/main.dart';
import 'package:nokia_home/providers/nokia_provider.dart';
import 'package:nokia_home/services/nokia_service.dart';

class PhoneTransport implements NokiaTransport {
  Completer<void>? internetGate;
  int wifiSettingsOpened = 0, internetChecks = 0, writes = 0, contexts = 0;
  bool switchNetwork = false;
  String bssid = '80:c5:48:50:35:ae';

  @override
  Future<Map<String, dynamic>> context() async => {
    'ssid': 'Nokia Wifi',
    'bssid': switchNetwork && contexts++ > 0 ? '80:c5:48:50:35:ae' : bssid,
    'network': 'wifi-1',
    'ip': '192.168.10.69',
    'gateway': '192.168.10.1',
    'dhcpServer': '192.168.10.1',
    'rssi': -42,
  };
  @override
  Future<Map<String, dynamic>> internet() async {
    internetChecks++;
    await internetGate?.future;
    return {'ok': true, 'network': 'wifi-1'};
  }

  @override
  Future<void> openWifi() async {
    wifiSettingsOpened++;
  }

  @override
  Future<List<String>> resolve(String host) async => [];
  @override
  Future<Map<String, String>> encryptForm(
    String publicKey,
    String plain,
  ) async => {};
  @override
  Future<Map<String, dynamic>> request(
    Uri base,
    String path, {
    Map<String, String>? form,
    String? cookie,
    String? responseKey,
    String? responseIv,
  }) async {
    if (form != null) writes++;
    if (path == '/get_devmap_cap_status_app.cgi') {
      return {
        'devapp_cap_info': [
          {
            'devGwMac': 'b4:63:6f:db:e6:c0',
            'devGwSnum': 'ALCLB4392160',
            'devName': 'Nokia WiFi Beacon 2',
            'devMode': 'AP_BRIDGE',
            'devVer': '5.5',
          },
        ],
      };
    }
    return {'result': 0};
  }
}

void main() {
  late PhoneTransport transport;
  late NokiaProvider controller;
  setUp(() {
    transport = PhoneTransport();
    controller = NokiaProvider(service: NokiaService(transport: transport));
  });
  tearDown(() => controller.dispose());

  Future<void> showApp(WidgetTester tester) async {
    await tester.pumpWidget(NokiaHomeApp(controller: controller));
    await tester.pump();
  }

  Future<void> identify() async {
    await controller.service.select(Uri.parse('http://192.168.10.97'));
    controller.wlan5 = {
      'wlan_config_glb11ac': [
        {'BSSID': 'b4:63:6f:db:e6:cd', 'Enable': 1},
      ],
    };
  }

  testWidgets(
    'late check after a Wi-Fi settings transition cannot restore success',
    (tester) async {
      await identify();
      transport.bssid = 'b4:63:6f:db:e6:cd';
      transport.internetGate = Completer<void>();
      await showApp(tester);
      await tester.tap(find.byTooltip('Refresh current connection'));
      await tester.pump();
      expect(transport.internetChecks, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      transport.internetGate!.complete();
      await tester.pumpAndSettle();
      expect(controller.diagnosticsCurrent, isFalse);
      expect(controller.service.authenticated, isFalse);
      expect(find.text('Internet verified through Nokia'), findsNothing);
      expect(controller.error, contains('Connection context changed'));
    },
  );

  testWidgets('render independent setup screen preview', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('NOKIA_PREVIEW')) {
      const fontRoot = String.fromEnvironment('FLUTTER_FONT_DIR');
      if (fontRoot.isNotEmpty) {
        for (final entry in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          await tester.runAsync(() async {
            final loader = FontLoader(entry.key)
              ..addFont(
                File(
                  '$fontRoot/${entry.value}',
                ).readAsBytes().then(ByteData.sublistView),
              );
            await loader.load();
          });
        }
      }
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: NokiaHomeApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('NOKIA_PREVIEW')) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final target = File('build/nokia-home-preview.png');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('independent startup and Wi-Fi chooser send no router writes', (
    tester,
  ) async {
    await showApp(tester);
    expect(find.text('Nokia Home'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Argon'), findsNothing);
    expect(find.text('TT Router'), findsNothing);
    await tester.tap(find.text('Choose Wi-Fi'));
    await tester.pumpAndSettle();
    expect(transport.wifiSettingsOpened, 1);
    expect(transport.writes, 0);
    expect(transport.internetChecks, 0);
  });

  testWidgets('same SSID internet is not credited to Nokia', (tester) async {
    await identify();
    await controller.diagnoseConnection();
    await showApp(tester);
    await tester.scrollUntilVisible(
      find.text('Phone Wi-Fi internet passed · Nokia path unverified'),
      200,
    );
    expect(find.text('Internet verified through Nokia'), findsNothing);
    expect(transport.writes, 0);
  });

  testWidgets(
    'matching Nokia radio plus stable Wi-Fi check shows verified path',
    (tester) async {
      await identify();
      transport.bssid = 'b4:63:6f:db:e6:cd';
      await controller.diagnoseConnection();
      await showApp(tester);
      await tester.scrollUntilVisible(
        find.text('Internet verified through Nokia'),
        200,
      );
      expect(find.text('Internet verified through Nokia'), findsOneWidget);
      expect(transport.internetChecks, 1);
      expect(transport.writes, 0);
    },
  );

  testWidgets('roaming during the check prevents internet success', (
    tester,
  ) async {
    await identify();
    transport.bssid = 'b4:63:6f:db:e6:cd';
    transport.switchNetwork = true;
    await controller.diagnoseConnection();
    await showApp(tester);
    await tester.scrollUntilVisible(
      find.text('Network changed during check'),
      200,
    );
    expect(find.text('Internet verified through Nokia'), findsNothing);
  });

  testWidgets('returning from Wi-Fi settings invalidates connection evidence', (
    tester,
  ) async {
    await identify();
    transport.bssid = 'b4:63:6f:db:e6:cd';
    await controller.diagnoseConnection();
    await showApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.diagnosticsCurrent, isFalse);
    expect(controller.service.authenticated, isFalse);
    await tester.scrollUntilVisible(find.text('Connection not checked'), 200);
    expect(find.text('Internet verified through Nokia'), findsNothing);
  });

  testWidgets('stale mesh and unavailable clients are not shown as online', (
    tester,
  ) async {
    controller.extenders = {
      'beacon_detail': [
        {
          'SerialNumber': 'ALCL00000002',
          'FriendlyName': 'Upstairs',
          'BackhaulStatus': 'Connected',
          'IPAddress': '192.168.10.98',
        },
      ],
    };
    controller.meshObservedAt = DateTime.now().subtract(
      const Duration(minutes: 5),
    );
    await showApp(tester);
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory unverified or stale'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('0 connected clients'), findsNothing);
  });

  testWidgets('small display and large text retain usable navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showApp(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Beacon'));
    await tester.pumpAndSettle();
    expect(find.text('Go to connection setup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
