import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/utils/validators.dart';

void main() {
  test('ssid', () {
    expect(Validators.ssid('Game labs'), isNull);
    expect(Validators.ssid('  '), isNotNull);
    expect(Validators.ssid('a' * 32), isNull);
    expect(Validators.ssid('a' * 33), isNotNull);
    expect(Validators.ssid('é' * 17), isNotNull, reason: '34 bytes');
  });

  test('wifi password', () {
    expect(Validators.wifiPassword('SummerDrop3'), isNull);
    expect(Validators.wifiPassword('short'), isNotNull);
    expect(Validators.wifiPassword('z' * 64), isNotNull);
    expect(Validators.wifiPassword('ab' * 32), isNull, reason: '64 hex');
    expect(Validators.wifiPassword('pässwörd1'), isNotNull);
    expect(Validators.wifiPassword('', secured: false), isNull);
  });

  test('addresses', () {
    expect(Validators.ipv4('192.168.10.1'), isNull);
    expect(Validators.ipv4('192.168.10.256'), isNotNull);
    expect(Validators.ipv4('192.168.010.1'), isNotNull);
    expect(Validators.ipv4('', required: false), isNull);
    expect(Validators.netmask('255.255.255.0'), isNull);
    expect(Validators.netmask('255.0.255.0'), isNotNull);
    expect(Validators.netmask('0.0.0.0'), isNotNull);
    expect(
      Validators.sameSubnet('192.168.10.1', '192.168.10.200', '255.255.255.0'),
      isTrue,
    );
    expect(
      Validators.sameSubnet('192.168.10.1', '192.168.11.2', '255.255.255.0'),
      isFalse,
    );
    expect(Validators.port('8080'), isNull);
    expect(Validators.port('0'), isNotNull);
    expect(Validators.port('70000'), isNotNull);
    expect(Validators.vlanId('4094'), isNull);
    expect(Validators.vlanId('4095'), isNotNull);
  });
}
