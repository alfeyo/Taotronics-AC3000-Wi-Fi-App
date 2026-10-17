import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/services/network_probe.dart';

void main() {
  test('open port means reachable', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((s) => s.destroy());
    final probe = NetworkProbe();
    expect(await probe.probe('127.0.0.1', server.port), ProbeOutcome.open);
  });

  test('refused port still proves the host is reachable', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    final probe = NetworkProbe();
    expect(await probe.probe('127.0.0.1', port), ProbeOutcome.refused);
    expect(await probe.isHostReachable('127.0.0.1', ports: [port]), isTrue);
  });

  test('timeouts and routing errors mean unreachable', () async {
    final timingOut = NetworkProbe(
      connector: (host, port, {timeout}) async =>
          throw const SocketException('Connection timed out'),
    );
    expect(await timingOut.probe('10.255.255.1', 80), ProbeOutcome.timeout);
    expect(await timingOut.isHostReachable('10.255.255.1'), isFalse);

    final noRoute = NetworkProbe(
      connector: (host, port, {timeout}) async => throw const SocketException(
        'No route to host',
        osError: OSError('No route to host', 113),
      ),
    );
    expect(await noRoute.isHostReachable('10.0.0.1'), isFalse);
  });

  test('an IP literal is not reachable just because it parses', () async {
    final silent = NetworkProbe(
      connector: (host, port, {timeout}) async =>
          throw const SocketException('Connection timed out'),
    );
    expect(await silent.isHostReachable('192.168.10.1'), isFalse);
  });
}
