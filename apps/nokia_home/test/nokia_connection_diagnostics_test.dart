import 'package:flutter_test/flutter_test.dart';
import 'package:nokia_home/providers/nokia_provider.dart';
import 'package:nokia_home/services/nokia_service.dart';
import 'nokia_service_test.dart' show Transport, Scanner;

class DiagnosticTransport extends Transport {
  bool unreachable = false, changeNetwork = false;
  int internetCalls = 0, contexts = 0;
  @override
  Future<Map<String, dynamic>> context() async {
    contexts++;
    return {
      ...phone,
      if (changeNetwork && contexts > 1) 'bssid': '80:c5:48:50:35:ae',
    };
  }

  @override
  Future<Map<String, dynamic>> internet() async {
    internetCalls++;
    return online;
  }

  @override
  Future<Map<String, dynamic>> request(
    Uri base,
    String path, {
    Map<String, String>? form,
    String? cookie,
    String? responseKey,
    String? responseIv,
  }) {
    if (unreachable) throw const NokiaException('Unreachable');
    return super.request(
      base,
      path,
      form: form,
      cookie: cookie,
      responseKey: responseKey,
      responseIv: responseIv,
    );
  }
}

void main() {
  late DiagnosticTransport t;
  late NokiaProvider n;
  setUp(() async {
    t = DiagnosticTransport()..web = true;
    n = NokiaProvider(
      service: NokiaService(transport: t),
      scanner: Scanner(),
    );
    await n.service.select(Uri.parse('http://192.168.10.97'));
    n.wlan5 = {
      'wlan_config_glb11ac': [
        {'BSSID': 'b4:63:6f:db:e6:cd', 'Enable': 1},
      ],
    };
    t.phone = {
      'ssid': 'Nokia Wifi',
      'bssid': 'b4:63:6f:db:e6:cd',
      'ip': '192.168.10.217',
      'network': 'wifi-1',
      'gateway': '192.168.10.1',
      'dhcpServer': '192.168.10.1',
    };
    t.online = {'ok': true, 'network': 'wifi-1'};
  });
  tearDown(() => n.dispose());
  test(
    'broadcasting root without DHCP is not internet and does not claim a wireless uplink',
    () async {
      t.unreachable = true;
      t.phone.remove('ip');
      t.phone.remove('network');
      await n.diagnoseConnection();
      expect(n.diagnosticNokiaRadio, isTrue);
      expect(n.diagnosticRoot, 'Unreachable at saved address');
      expect(n.diagnosticInternet, 'No Wi-Fi address / network');
      expect(
        n.connectionWarning,
        contains('No wireless upstream has been verified'),
      );
      expect(t.internetCalls, 0);
      expect(t.writes, isEmpty);
      expect(n.clientVerified, isFalse);
    },
  );
  test(
    'identical SSID on TaoTronics cannot verify a Nokia internet path',
    () async {
      t.phone['bssid'] = '80:c5:48:50:35:ae';
      await n.diagnoseConnection();
      expect(n.diagnosticInternet, 'Passed');
      expect(n.diagnosticNokiaRadio, isFalse);
      expect(n.diagnosticRoot, 'Matching root replied');
      expect(n.clientVerified, isFalse);
    },
  );
  test('network switch during HTTPS check invalidates its result', () async {
    t.changeNetwork = true;
    await n.diagnoseConnection();
    expect(n.diagnosticInternet, 'Network changed during check');
    expect(n.diagnosticNokiaRadio, isFalse);
    expect(n.diagnosticStable, isFalse);
  });
  test('different root identity never receives credentials', () async {
    t.serial = 'OTHER';
    await n.diagnoseConnection();
    expect(n.diagnosticRoot, 'Different or untrusted identity');
    expect(t.writes, isEmpty);
    expect(n.identity!.serial, 'ROOT123');
  });
  test(
    'failed Nokia HTTPS and stale observations cannot appear as current success',
    () async {
      t.online = {'ok': false, 'network': 'wifi-1'};
      await n.diagnoseConnection();
      expect(n.diagnosticInternet, 'Failed');
      expect(n.connectionWarning, isNotNull);
      n.diagnosticAt = DateTime.now().subtract(const Duration(seconds: 91));
      expect(n.diagnosticsCurrent, isFalse);
      expect(n.connectionWarning, isNull);
      n.mode = 'AP_BRIDGE';
      n.observedAt = DateTime.now();
      n.wan = {'gwwanup': 0};
      expect(n.connectionWarning, contains('uplink offline'));
    },
  );
}
