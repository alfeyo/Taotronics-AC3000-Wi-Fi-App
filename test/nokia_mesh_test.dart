import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/nokia_mesh_screen.dart';
import 'package:tt_router_flutter/services/pi_api.dart';
import 'package:tt_router_flutter/services/argon_device_key.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final value in [
    null,
    'invalid',
    {
      'setup': 'invalid',
      'nodes': [
        null,
        1,
        {'name': 'Root Beacon', 'model': null},
      ],
      'steps': 'bad',
      'guides': [false],
      'topology': 'bad',
    },
  ]) {
    testWidgets(
      'Nokia report ${value.runtimeType} preserves unknown state without crashing',
      (tester) async {
        final router = RouterProvider(autoStart: false);
        final pi = PiProvider(router: router, autoStart: false);
        await tester.runAsync(() => pi.ready);
        pi.gateway = {'nokia': value};
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: pi,
            child: const MaterialApp(home: NokiaMeshScreen()),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Nokia Mesh'), findsOneWidget);
        expect(
          find.textContaining('verified', skipOffstage: false),
          findsWidgets,
        );
        await tester.pumpWidget(const SizedBox());
        pi.dispose();
        router.dispose();
      },
    );
  }
  test('LAN authorization is blocked before any network request', () async {
    final t = HttpPiTransport(Uri.parse('http://192.168.50.1'));
    await expectLater(
      t.get('/api/v1/gateway', token: 'test-credential'),
      throwsA(isA<PiApiException>()),
    );
    await expectLater(
      t.sendRaw(
        'POST',
        '/api/v1/vpn',
        body: [],
        headers: {'Authorization': 'signed'},
      ),
      throwsA(isA<PiApiException>()),
    );
    await expectLater(
      t.post('/api/v1/pairing/complete', {'code': '123456'}),
      throwsA(isA<PiApiException>()),
    );
  });
  test(
    'device signature domain binds phone, method, path, time, nonce and raw body',
    () {
      final value = ArgonDeviceKey.canonical(
        id: 'phone',
        method: 'post',
        path: '/api/v1/vpn',
        ts: 1,
        nonce: 'abc',
        body: [123, 125],
      );
      expect(
        value,
        'argon-device-v2\nphone\nPOST\n/api/v1/vpn\n1\nabc\n44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
      );
    },
  );
}
