import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/services/pi_api.dart';
import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:tt_router_flutter/screens/pi_gateway_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'transport policy rejects LAN HTTP, credentials, queries and unsafe schemes',
    () {
      expect(validatePiEndpoint('http://100.94.137.17').host, '100.94.137.17');
      expect(validatePiEndpoint('https://argon.example').scheme, 'https');
      for (final url in [
        'http://192.168.50.1',
        'http://100.128.0.1',
        'http://100.63.0.1',
        'ftp://100.94.137.17',
        'https://user:secret@example.com',
        'https://example.com?token=x',
        'https://example.com/path',
      ]) {
        expect(() => validatePiEndpoint(url), throwsFormatException);
      }
    },
  );
  test(
    'gateway setup stores token only in secure storage; state is isolated from router pairing',
    () async {
      const token = 'companion-test-token-01234567890123456';
      final p = PiProvider();
      await p.ready;
      expect(p.configured, false);
      await p.configure('http://100.94.137.17', token, true);
      expect(p.configured, true);
      expect(p.sharing, true);
      expect(p.stale, true);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().any((k) => prefs.get(k).toString().contains(token)),
        false,
      );
      expect(
        await const FlutterSecureStorage().read(key: 'argon.companion.v1'),
        token,
      );
      final restored = PiProvider();
      await restored.ready;
      expect(restored.endpoint, p.endpoint);
      expect(restored.configured, true);
      p.dispose();
      restored.dispose();
    },
  );
  test(
    'formatters preserve unavailable values and distinguish bits from bytes',
    () {
      expect(piRate(null), '—');
      expect(piBytes(null), '—');
      expect(piRate(8000), '8 kbps');
      expect(piBytes(1073741824), '1.00 GiB');
    },
  );
}
