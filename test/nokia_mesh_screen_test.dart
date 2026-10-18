import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/providers/nokia_provider.dart';
import 'package:tt_router_flutter/screens/nokia_mesh_screen.dart';
import 'package:tt_router_flutter/services/nokia_service.dart';
import 'nokia_service_test.dart' show Transport, Scanner;

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(673, 841),
    const Size(800, 330),
  ]) {
    testWidgets(
      'Nokia bridge and source data render at $size without overflow',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transport = Transport()..web = true;
        final n = NokiaProvider(
          service: NokiaService(transport: transport),
          scanner: Scanner(),
        );
        await n.service.select(Uri.parse('http://192.168.10.97'));
        await n.service.login('owner', 'test-only');
        n.mode = 'AP_BRIDGE';
        n.observedAt = DateTime.now();
        n.device = {
          'ModelName': 'Nokia WiFi Beacon 2',
          'SoftwareVersion': '3FE49334IJJJ09',
          'UpTime': 12,
        };
        n.extenders = {'beacon_detail': []};
        n.clients = {
          'device_cfg': [
            {
              'HostName': 'Test phone',
              'IPAddress': '192.168.10.2',
              'Active': 1,
              'InterfaceType': '802.11',
            },
          ],
        };
        n.wlan5 = {
          'wlan_config_glb11ac': [
            {
              'SSID': 'Test Nokia',
              'BSSID': 'b4:63:6f:db:e6:cd',
              'Enable': 1,
              'Channel': 112,
              'Standard': 'a,n,ac,ax',
            },
          ],
        };
        await tester.pumpWidget(
          MaterialApp(home: NokiaMeshScreen(controller: n)),
        );
        expect(find.text('AP bridge read-back verified'), findsOneWidget);
        expect(find.text('Requires wired root uplink'), findsOneWidget);
        expect(find.text('Not reported by the local API'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 10; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -500));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('Test Nokia'), findsOneWidget);
        expect(find.text('Test phone'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        n.dispose();
      },
    );
  }
}
