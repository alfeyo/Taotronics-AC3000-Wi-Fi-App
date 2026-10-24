import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/providers/pi_provider.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/router_access_policy.dart';
import 'package:tt_router_flutter/services/router_gateway.dart';

import '../support/fake_mqtt_transport.dart';

const _appId = 'app123';

MqttService _service(FakeTransportFactory factory) => MqttService(
  transportFactory: factory.call,
  appIdLoader: () async => _appId,
  v1OnlyStore: MemoryV1OnlyStore(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RouterAccessPolicy', () {
    test('defaults allow direct control', () {
      final policy = RouterAccessPolicy();
      expect(policy.directControlEnabled, isTrue);
      expect(policy.preferPiController, isFalse);
      expect(policy.blockDirectOwnership, isFalse);
      expect(policy.diagnosticsOnly, isFalse);
      expect(policy.mayDiscover, isTrue);
      expect(policy.mayConnect, isTrue);
      expect(policy.mayAuthenticate, isTrue);
      expect(policy.mayProbe, isTrue);
      expect(policy.mayRefresh, isTrue);
      expect(policy.mayWrite, isTrue);
      expect(policy.mayAutoReconnect, isTrue);
      expect(policy.isReadOnly, isFalse);
      expect(policy.blockMessage, isNull);
    });

    test('blocked ownership refuses every direct operation', () {
      final policy = RouterAccessPolicy(blockDirectOwnership: true);
      expect(policy.mayDiscover, isFalse);
      expect(policy.mayConnect, isFalse);
      expect(policy.mayAuthenticate, isFalse);
      expect(policy.mayProbe, isFalse);
      expect(policy.mayRefresh, isFalse);
      expect(policy.maySendCommands, isFalse);
      expect(policy.mayWrite, isFalse);
      expect(policy.mayAutoReconnect, isFalse);
      expect(policy.isReadOnly, isTrue);
      expect(policy.blockMessage, RouterAccessPolicy.piOwnershipMessage);
    });

    test('direct control can be switched off independently', () {
      final policy = RouterAccessPolicy(directControlEnabled: false);
      expect(policy.mayConnect, isFalse);
      expect(policy.mayProbe, isFalse);
      expect(policy.isReadOnly, isTrue);
      expect(policy.blockMessage, isNotNull);
    });

    test('diagnosticsOnly allows reads but refuses writes', () {
      final policy = RouterAccessPolicy(diagnosticsOnly: true);
      expect(policy.mayConnect, isTrue);
      expect(policy.mayRefresh, isTrue);
      expect(policy.mayProbe, isTrue);
      expect(policy.maySendCommands, isTrue);
      expect(policy.mayWrite, isFalse);
      expect(policy.isReadOnly, isTrue);
    });

    test('setPiOwnership reports a change exactly once', () {
      final policy = RouterAccessPolicy();
      expect(policy.setPiOwnership(ownedByArgon: true), isTrue);
      expect(policy.preferPiController, isTrue);
      expect(policy.blockDirectOwnership, isTrue);
      expect(policy.setPiOwnership(ownedByArgon: true), isFalse);
      expect(policy.setPiOwnership(ownedByArgon: false), isTrue);
      expect(policy.blockDirectOwnership, isFalse);
      expect(policy.preferPiController, isFalse);
    });

    test('copyWith keeps unrelated flags', () {
      final policy = RouterAccessPolicy(preferPiController: true);
      final copy = policy.copyWith(diagnosticsOnly: true);
      expect(copy.preferPiController, isTrue);
      expect(copy.diagnosticsOnly, isTrue);
      expect(copy.directControlEnabled, isTrue);
    });
  });

  group('DirectRouterGateway', () {
    test('refuses every router operation when ownership is blocked', () async {
      final factory = FakeTransportFactory();
      final gateway = DirectRouterGateway(_service(factory));
      gateway.policy.blockDirectOwnership = true;

      expect(await gateway.connect('meshA', '10.0.0.1'), isFalse);
      expect(await gateway.sendCommand('/GetSystemState', {}), isNull);
      expect(await gateway.getDeviceList(), isNull);
      expect(await gateway.getWirelessSettings(), isNull);
      expect(
        await gateway.setQosSettings(
          enabled: true,
          upBandwidth: 1,
          downBandwidth: 1,
        ),
        isNull,
      );
      expect(await gateway.rebootRouter(), isNull);
      expect(
        factory.created,
        isEmpty,
        reason: 'no socket may be opened while the Pi owns the router',
      );
      gateway.dispose();
    });

    test('diagnosticsOnly lets reads through and blocks writes', () async {
      final factory = FakeTransportFactory();
      factory.responder = (path, data) => {'ErrorCode': 0, 'Data': []};
      final gateway = DirectRouterGateway(_service(factory));
      expect(await gateway.connect('meshA', '10.0.0.1'), isTrue);

      gateway.policy.diagnosticsOnly = true;
      await gateway.getSystemStatus();
      expect(
        factory.last.published.map((p) => p.topic.split(_appId).last),
        contains('/GetSystemState'),
      );

      final published = factory.last.published.length;
      expect(
        await gateway.setQosSettings(
          enabled: true,
          upBandwidth: 1,
          downBandwidth: 1,
        ),
        isNull,
      );
      expect(factory.last.published.length, published);
      gateway.dispose();
    });

    test('delegates reads unchanged while the policy allows them', () async {
      final factory = FakeTransportFactory();
      factory.responder = (path, data) => path == '/GetDevListInfo'
          ? {
              'ErrorCode': 0,
              'Data': [
                {'Devices': []},
              ],
            }
          : null;
      final gateway = DirectRouterGateway(_service(factory));
      expect(await gateway.connect('meshA', '10.0.0.1'), isTrue);
      final reply = await gateway.getDeviceList();
      expect(reply?['ErrorCode'], 0);
      gateway.dispose();
    });
  });

  test('RouterProvider adopts the injected gateway and its policy', () async {
    final factory = FakeTransportFactory();
    final policy = RouterAccessPolicy();
    final gateway = DirectRouterGateway(_service(factory), policy: policy);
    final provider = RouterProvider(
      gateway: gateway,
      authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
      autoStart: false,
    );

    expect(identical(provider.accessPolicy, policy), isTrue);
    expect(await provider.attemptAuthentication('meshA', '10.0.0.1'), isTrue);
    expect(provider.isConnected, isTrue);
    expect(factory.created, hasLength(1));

    provider.applyPiOwnership(ownedByArgon: true);
    expect(identical(provider.accessPolicy, policy), isTrue);
    expect(policy.blockDirectOwnership, isTrue);
    provider.dispose();
  });

  group('Pi ownership reporting', () {
    test('monitoring state alone is not ownership', () {
      // The live Argon reports state=connected for a Dell LAN observer. That is
      // telemetry, not control; treating it as ownership froze the app.
      expect(
        PiProvider.reportsRouterOwnership({
          'router': {
            'monitoring': {
              'state': 'connected',
              'label': 'Router device monitoring connected',
              'source': 'lan-observer:dell',
            },
          },
        }),
        isFalse,
      );
      for (final state in ['connected', 'active', 'owner', 'argon']) {
        expect(
          PiProvider.reportsRouterOwnership({
            'router': {
              'monitoring': {'state': state},
            },
          }),
          isFalse,
          reason: 'state $state must not imply ownership',
        );
      }
    });

    test('not-connected and missing blocks are not ownership', () {
      expect(PiProvider.reportsRouterOwnership(null), isFalse);
      expect(
        PiProvider.reportsRouterOwnership({
          'router': {
            'monitoring': {'state': 'not-connected'},
          },
        }),
        isFalse,
      );
      expect(
        PiProvider.reportsRouterOwnership({'router': <String, dynamic>{}}),
        isFalse,
      );
      expect(PiProvider.reportsRouterOwnership({'gateway': {}}), isFalse);
    });

    test('an explicit owner or control field is honoured', () {
      expect(
        PiProvider.reportsRouterOwnership({
          'router': {'owner': 'argon'},
        }),
        isTrue,
      );
      expect(
        PiProvider.reportsRouterOwnership({
          'router': {'control': 'argon'},
        }),
        isTrue,
      );
      expect(
        PiProvider.reportsRouterOwnership({
          'router': {
            'monitoring': {'owner': 'argon'},
          },
        }),
        isTrue,
      );
    });

    test('phone-supplied data is not ownership without an owner field', () {
      expect(
        PiProvider.reportsRouterOwnership({
          'router': {
            'source': 'phone-supplied',
            'monitoring': {'state': 'connected'},
          },
        }),
        isFalse,
      );
    });
  });
}
