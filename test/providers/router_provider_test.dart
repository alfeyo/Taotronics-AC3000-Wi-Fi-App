import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/models/save_result.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/router_discovery.dart';

import '../support/fake_mqtt_transport.dart';

const _appId = 'app123';

class _FakeDiscovery extends RouterDiscoveryService {
  final controller = StreamController<DiscoveredRouter>.broadcast(sync: true);

  @override
  Stream<DiscoveredRouter> get routerStream => controller.stream;

  @override
  Future<void> startDiscovery() async {}

  void announce(String meshId, String ip) =>
      controller.add(DiscoveredRouter(meshId: meshId, ipAddress: ip));
}

class _Harness {
  _Harness({Duration connectDelay = Duration.zero})
    : factory = FakeTransportFactory(connectDelay: connectDelay) {
    provider = RouterProvider(
      discovery: discovery,
      mqtt: MqttService(
        transportFactory: factory.call,
        appIdLoader: () async => _appId,
      ),
      authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
      autoStart: false,
    );
  }

  final FakeTransportFactory factory;
  final discovery = _FakeDiscovery();
  late final RouterProvider provider;
}

MeshEntity _router(String id, String ip) =>
    MeshEntity(meshId: id, ssid: id, ipAddress: ip, state: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('live pause tokens are reference counted', () {
    final h = _Harness();
    final a = h.provider.pauseLiveUpdates('a');
    final b = h.provider.pauseLiveUpdates('b');
    expect(h.provider.isLivePaused, isTrue);
    a.release();
    a.release(); // double release must not unpause b
    expect(h.provider.isLivePaused, isTrue);
    b.release();
    expect(h.provider.isLivePaused, isFalse);
  });

  test('a stale reconnect cannot override a newer router selection', () {
    fakeAsync((async) {
      final h = _Harness(connectDelay: const Duration(milliseconds: 1500));
      final provider = h.provider;

      provider.selectRouter(_router('meshA', '10.0.0.1'));
      async.elapse(const Duration(seconds: 2));
      expect(provider.isConnected, isTrue);

      // Router A drops; a reconnect is scheduled for A in 1s.
      h.factory.last.drop();
      async.flushMicrotasks();
      expect(provider.isReconnecting, isTrue);

      // The user switches to router B before the reconnect fires.
      provider.attemptAuthentication('meshB', '10.0.0.2');
      async.elapse(const Duration(seconds: 20));

      expect(provider.isConnected, isTrue);
      expect(provider.currentRouter?.meshId, 'meshB');
      final hosts = h.factory.created.map((t) => t.host).toList();
      expect(hosts, ['10.0.0.1', '10.0.0.2']);
      provider.dispose();
    });
  });

  test('reconnects with backoff after an unexpected drop', () {
    fakeAsync((async) {
      final h = _Harness();
      final provider = h.provider;
      provider.selectRouter(_router('meshA', '10.0.0.1'));
      async.elapse(const Duration(milliseconds: 10));
      h.factory.rejectCredentials = true;
      h.factory.last.drop();
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 1, milliseconds: 10));
      expect(h.factory.created, hasLength(2), reason: 'retry after 1s');
      async.elapse(const Duration(seconds: 2, milliseconds: 10));
      expect(h.factory.created, hasLength(3), reason: 'retry after 2s');

      h.factory.rejectCredentials = false;
      async.elapse(const Duration(seconds: 4, milliseconds: 10));
      expect(provider.isConnected, isTrue);
      provider.dispose();
    });
  });

  test('rediscovering the saved router retries without waiting', () {
    fakeAsync((async) {
      final h = _Harness();
      final provider = h.provider;
      h.discovery.announce('meshA', '10.0.0.1');
      async.elapse(const Duration(milliseconds: 10));
      expect(provider.isConnected, isTrue);

      // Wi-Fi goes away: two attempts fail, backoff is now 4s.
      h.factory.rejectCredentials = true;
      h.factory.last.drop();
      async.elapse(const Duration(seconds: 3, milliseconds: 100));
      expect(h.factory.created, hasLength(3));

      // Wi-Fi is back and the router beacon arrives mid-backoff.
      h.factory.rejectCredentials = false;
      h.discovery.announce('meshA', '10.0.0.1');
      async.elapse(const Duration(milliseconds: 10));
      expect(provider.isConnected, isTrue, reason: 'no 4s wait');
      provider.dispose();
    });
  });

  test('logout stops automatic reconnects', () {
    fakeAsync((async) {
      final h = _Harness();
      final provider = h.provider;
      provider.selectRouter(_router('meshA', '10.0.0.1'));
      async.elapse(const Duration(milliseconds: 10));
      h.factory.last.drop();
      async.flushMicrotasks();
      provider.logout();
      async.elapse(const Duration(seconds: 30));
      expect(h.factory.created, hasLength(1));
      expect(provider.isConnected, isFalse);
      provider.dispose();
    });
  });

  test('one late telemetry batch does not stop live telemetry', () {
    fakeAsync((async) {
      final h = _Harness();
      var answer = false;
      h.factory.responder = (path, data) =>
          path == '/GetSysConnectInfo' && answer
          ? {
              'ErrorCode': 0,
              'Data': {'Internet': 1},
            }
          : null;
      h.provider.selectRouter(_router('meshA', '10.0.0.1'));
      async.elapse(const Duration(milliseconds: 10));

      h.provider.refreshLiveTelemetry();
      async.elapse(const Duration(seconds: 9));
      expect(h.provider.liveTelemetrySupported, isTrue);

      answer = true;
      h.provider.refreshLiveTelemetry();
      async.elapse(const Duration(seconds: 9));
      expect(h.provider.internetConnected, isTrue);

      answer = false;
      for (var i = 0; i < 3; i++) {
        h.provider.refreshLiveTelemetry();
        async.elapse(const Duration(seconds: 9));
      }
      expect(h.provider.liveTelemetrySupported, isFalse);
      h.provider.dispose();
    });
  });

  group('save results', () {
    test('ErrorCode 0 is confirmed, non-zero is failed', () {
      fakeAsync((async) {
        final h = _Harness();
        h.factory.responder = (path, data) => path == '/SetQosInfo'
            ? {'ErrorCode': 0}
            : path == '/SetFirewallInfo'
            ? {'ErrorCode': 5}
            : null;
        h.provider.selectRouter(_router('meshA', '10.0.0.1'));
        async.elapse(const Duration(milliseconds: 10));

        SaveResult? qos;
        SaveResult? firewall;
        h.provider
            .updateQosSettings(enabled: true, upBandwidth: 1, downBandwidth: 2)
            .then((r) => qos = r);
        h.provider.updateFirewallSettings(true).then((r) => firewall = r);
        async.elapse(const Duration(milliseconds: 10));

        expect(qos?.status, SaveStatus.confirmed);
        expect(firewall?.status, SaveStatus.failed);
        expect(firewall?.message, contains('error 5'));
        h.provider.dispose();
      });
    });

    test('no reply on a non-disruptive setting is a failure', () {
      fakeAsync((async) {
        final h = _Harness();
        h.provider.selectRouter(_router('meshA', '10.0.0.1'));
        async.elapse(const Duration(milliseconds: 10));

        SaveResult? result;
        h.provider.updateFirewallSettings(true).then((r) => result = r);
        async.elapse(const Duration(seconds: 11));
        expect(result?.status, SaveStatus.failed);
        h.provider.dispose();
      });
    });

    test('dropped Wi-Fi write is pending, then confirmed by re-reading', () {
      fakeAsync((async) {
        final h = _Harness();
        var applied = false;
        final networks = [
          {'Index': 0, 'Ssid': 'Old', 'Password': 'oldpass1', 'Disable': 0},
        ];
        h.factory.responder = (path, data) {
          if (path == '/SetWirelessInfoList') {
            // Router applies the change and drops before replying.
            networks[0]['Ssid'] = (data as List).first['Ssid'];
            applied = true;
            return null;
          }
          if (path == '/GetWirelessInfoListV2') {
            return {'ErrorCode': 0, 'Data': networks};
          }
          return {'ErrorCode': 0, 'Data': []};
        };
        final provider = h.provider;
        provider.selectRouter(_router('meshA', '10.0.0.1'));
        async.elapse(const Duration(milliseconds: 10));
        provider.authService.attemptPairing(
          meshId: 'meshA',
          ipAddress: '10.0.0.1',
        );
        provider.refreshWirelessSettings();
        async.elapse(const Duration(milliseconds: 10));

        SaveResult? result;
        provider
            .setWirelessSettings([
              {...networks.first, 'Ssid': 'New'},
            ])
            .then((r) => result = r);
        async.elapse(const Duration(milliseconds: 100));
        h.factory.last.drop();
        async.elapse(const Duration(seconds: 9));

        expect(applied, isTrue);
        expect(result?.status, SaveStatus.pendingVerification);
        expect(provider.pendingChanges, hasLength(1));

        // Auto-reconnect happens, then the change is read back.
        async.elapse(const Duration(seconds: 15));
        expect(provider.isConnected, isTrue);
        expect(provider.pendingChanges.single.status, ChangeStatus.confirmed);
        provider.dispose();
      });
    });

    test('dropped Wi-Fi write that the router ignored reports mismatch', () {
      fakeAsync((async) {
        final h = _Harness();
        final networks = [
          {'Index': 0, 'Ssid': 'Old', 'Password': 'oldpass1', 'Disable': 0},
        ];
        h.factory.responder = (path, data) => switch (path) {
          '/SetWirelessInfoList' => null,
          '/GetWirelessInfoListV2' => {'ErrorCode': 0, 'Data': networks},
          _ => {'ErrorCode': 0, 'Data': []},
        };
        final provider = h.provider;
        provider.selectRouter(_router('meshA', '10.0.0.1'));
        async.elapse(const Duration(milliseconds: 10));

        provider.setWirelessSettings([
          {...networks.first, 'Ssid': 'New'},
        ]);
        async.elapse(const Duration(seconds: 30));
        expect(provider.pendingChanges.single.status, ChangeStatus.mismatch);
        provider.dispose();
      });
    });

    test('reboot without acknowledgement is pending, not failed', () {
      fakeAsync((async) {
        final h = _Harness();
        h.provider.selectRouter(_router('meshA', '10.0.0.1'));
        async.elapse(const Duration(milliseconds: 10));
        SaveResult? result;
        h.provider.rebootRouter().then((r) => result = r);
        async.elapse(const Duration(seconds: 11));
        expect(result?.status, SaveStatus.pendingVerification);
        h.provider.dispose();
      });
    });

    test('writes while disconnected fail without sending', () async {
      final h = _Harness();
      final result = await h.provider.updateQosSettings(
        enabled: true,
        upBandwidth: 1,
        downBandwidth: 1,
      );
      expect(result.isFailed, isTrue);
      expect(h.factory.created, isEmpty);
    });
  });
}
