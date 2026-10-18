import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/models/mesh_entity.dart';
import 'package:tt_router_flutter/models/save_result.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';

import '../support/fake_mqtt_transport.dart';

/// V1 wireless table shaped like the live router's GetWirelessInfoList.
List<Map<String, dynamic>> _routerTable() => [
  {
    'Ssid': 'Game labs',
    'Encrypt': 3,
    'Password': 'GamePass1',
    'Vlanid': -1,
    'VlanEnable': 0,
    'SsidIsolate': 1,
    'StaIsolate': 0,
    'Index': 0,
    'Create': 1,
  },
  {
    'Ssid': 'TT-35A0',
    'Encrypt': 3,
    'Password': 'MeshPass5',
    'Vlanid': -1,
    'VlanEnable': 0,
    'SsidIsolate': 1,
    'StaIsolate': 0,
    'Index': 1,
    'Create': 1,
  },
  {
    'Ssid': 'TT-35A0',
    'Encrypt': 3,
    'Password': 'MeshPass5',
    'Vlanid': -1,
    'VlanEnable': 0,
    'SsidIsolate': 1,
    'StaIsolate': 0,
    'Index': 2,
    'Create': 0,
  },
];

/// Simulated router: applies SetWirelessInfoList to its table. With
/// [dropOnWrite] it drops the session without replying, like the real
/// router restarting Wi-Fi.
class _FakeRouter {
  _FakeRouter({this.dropOnWrite = false, List<Map<String, dynamic>>? table})
    : table = table ?? _routerTable();

  final bool dropOnWrite;
  bool ignoreWrite = false;
  bool normalize = false;
  bool ignoreGuestPassword = false;
  Map<String, dynamic> guest = {
    'Enable': 1,
    'Ssid': 'Visitors',
    'EncryptionWay': 3,
    'Password': 'OldPassword',
    'Vlanid': 17,
    'VlanEnable': 1,
    'FirmwareField': 'keep',
  };
  Map<String, dynamic>? guestWritten;
  List<Map<String, dynamic>> table;
  final writes = <List<Map<String, dynamic>>>[];
  late FakeTransportFactory factory;

  Map<String, dynamic>? respond(String path, dynamic data) {
    switch (path) {
      case '/GetGuestInfo':
        return {
          'ErrorCode': 0,
          'Data': [Map<String, dynamic>.from(guest)],
        };
      case '/SetGuestInfo':
        guestWritten = Map<String, dynamic>.from((data as List).first as Map);
        final oldPassword = guest['Password'];
        guest = {...guestWritten!};
        if (ignoreGuestPassword) guest['Password'] = oldPassword;
        return {'ErrorCode': 0};
      case '/GetWirelessInfoListV2':
        return null; // this router never answers V2
      case '/GetWirelessInfoList':
        return {'ErrorCode': 0, 'Data': jsonDecode(jsonEncode(table))};
      case '/SetWirelessInfoList':
        final payload = (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        writes.add(payload);
        if (!ignoreWrite) {
          table = payload;
        }
        if (normalize) {
          table[0] = {...table[0], 'FirmwareNormalized': 1};
        }
        if (dropOnWrite) {
          Future<void>.delayed(const Duration(milliseconds: 50), () {
            factory.last.drop();
          });
          return null;
        }
        return {'ErrorCode': 0};
      default:
        return {'ErrorCode': 0, 'Data': []};
    }
  }
}

class _Harness {
  _Harness(this.router) {
    factory = FakeTransportFactory()..responder = router.respond;
    router.factory = factory;
    provider = RouterProvider(
      mqtt: MqttService(
        transportFactory: factory.call,
        appIdLoader: () async => 'app',
      ),
      authService: AuthPairingService(credentialStore: MemoryCredentialStore()),
      autoStart: false,
    );
  }

  final _FakeRouter router;
  late final FakeTransportFactory factory;
  late final RouterProvider provider;

  /// Connects, pairs (so auto-reconnect works) and loads the Wi-Fi list.
  void connectAndLoad(FakeAsync async) {
    provider.selectRouter(
      MeshEntity(meshId: 'm', ssid: 'm', ipAddress: '10.0.0.1'),
    );
    async.elapse(const Duration(seconds: 1));
    provider.refreshWirelessSettings();
    async.elapse(const Duration(seconds: 12)); // V2 timeout, then V1
  }

  int get writesSent => factory.created
      .expand((t) => t.published)
      .where((p) => p.topic.endsWith('/SetWirelessInfoList'))
      .length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('guest save preserves fields and verifies password read-back', () {
    fakeAsync((async) {
      final router = _FakeRouter();
      final h = _Harness(router)..connectAndLoad(async);
      SaveResult? result;
      h.provider
          .updateGuestWifiSettings({'Password': 'NewPassword'})
          .then((v) => result = v);
      async.elapse(const Duration(seconds: 2));
      expect(router.guestWritten?['Vlanid'], 17);
      expect(router.guestWritten?['FirmwareField'], 'keep');
      expect(result?.status, SaveStatus.confirmed);
      router.ignoreGuestPassword = true;
      h.provider
          .updateGuestWifiSettings({'Password': 'AnotherPassword'})
          .then((v) => result = v);
      async.elapse(const Duration(seconds: 2));
      expect(result?.status, SaveStatus.pendingVerification);
      h.provider.dispose();
      async.elapse(const Duration(seconds: 120));
    });
  });
  test('acknowledgment without matching Wi-Fi read-back stays pending', () {
    fakeAsync((async) {
      final router = _FakeRouter()..ignoreWrite = true;
      final h = _Harness(router)..connectAndLoad(async);
      SaveResult? result;
      h.provider.setWirelessNetworkEnabled(1, false).then((v) => result = v);
      async.elapse(const Duration(seconds: 2));
      expect(result?.status, SaveStatus.pendingVerification);
      expect(h.provider.wirelessNetworksParsed[1].isEnabled, isTrue);
      async.elapse(const Duration(seconds: 4));
      expect(h.provider.pendingChanges.single.status, ChangeStatus.mismatch);
      h.provider.dispose();
    });
  });
  test(
    'Wi-Fi read-back retains firmware fields instead of submitted payload',
    () {
      fakeAsync((async) {
        final router = _FakeRouter()..normalize = true;
        final h = _Harness(router)..connectAndLoad(async);
        h.provider.setWirelessNetworkEnabled(1, false);
        async.elapse(const Duration(seconds: 2));
        expect(
          h.provider.wirelessNetworksParsed[0].rawData['FirmwareNormalized'],
          1,
        );
        h.provider.dispose();
      });
    },
  );
  test('loads all three V1 networks including the disabled one', () {
    fakeAsync((async) {
      final h = _Harness(_FakeRouter())..connectAndLoad(async);
      final nets = h.provider.wirelessNetworksParsed;
      expect(nets.map((n) => n.index), [0, 1, 2]);
      expect(nets.map((n) => n.isEnabled), [true, true, false]);
      expect(nets.every((n) => n.passwordKnown), isTrue);
      h.provider.dispose();
    });
  });

  test('disabling one band sends the router fields unchanged', () {
    fakeAsync((async) {
      final router = _FakeRouter();
      final h = _Harness(router)..connectAndLoad(async);

      SaveResult? result;
      h.provider.setWirelessNetworkEnabled(1, false).then((r) => result = r);
      async.elapse(const Duration(seconds: 2));

      expect(result?.status, SaveStatus.confirmed);
      final sent = router.writes.single;
      final original = _routerTable();
      // Untouched entries are byte-for-byte what the router reported.
      expect(sent[0], original[0]);
      expect(sent[2], original[2]);
      // The edited entry only changes Create; nothing is added.
      expect(sent[1], {...original[1], 'Create': 0});
      for (final entry in sent) {
        expect(entry.keys, isNot(contains('Disable')));
        expect(entry.keys, isNot(contains('ConfStatus')));
        expect(entry.keys, isNot(contains('NodeSn')));
      }
      expect(h.provider.wirelessNetworksParsed[1].isEnabled, isFalse);
      expect(h.provider.wirelessNetworksParsed[1].ssid, 'TT-35A0');
      h.provider.dispose();
    });
  });

  test('re-enabling a band keeps its name and password', () {
    fakeAsync((async) {
      final router = _FakeRouter();
      final h = _Harness(router)..connectAndLoad(async);

      h.provider.setWirelessNetworkEnabled(2, true);
      async.elapse(const Duration(seconds: 2));

      final entry = router.writes.single[2];
      expect(entry['Create'], 1);
      expect(entry['Ssid'], 'TT-35A0');
      expect(entry['Password'], 'MeshPass5');
      h.provider.dispose();
    });
  });

  test('editing one band changes only that band', () {
    fakeAsync((async) {
      final router = _FakeRouter();
      final h = _Harness(router)..connectAndLoad(async);

      final band0 = h.provider.wirelessNetworksParsed.first;
      h.provider.updateWirelessNetwork(
        band0.copyWith(ssid: 'Game labs 2', password: 'NewPass123'),
      );
      async.elapse(const Duration(seconds: 2));

      final sent = router.writes.single;
      final original = _routerTable();
      expect(sent[0], {
        ...original[0],
        'Ssid': 'Game labs 2',
        'Password': 'NewPass123',
      });
      expect(sent[1], original[1]);
      expect(sent[2], original[2]);
      h.provider.dispose();
    });
  });

  test('a dropped session is verified after the automatic reconnect', () {
    fakeAsync((async) {
      final router = _FakeRouter(dropOnWrite: true);
      final h = _Harness(router)..connectAndLoad(async);

      SaveResult? result;
      h.provider.setWirelessNetworkEnabled(1, false).then((r) => result = r);
      async.elapse(const Duration(seconds: 40));

      expect(result?.status, SaveStatus.pendingVerification);
      expect(h.provider.isConnected, isTrue);
      expect(h.provider.pendingChanges.single.status, ChangeStatus.confirmed);
      h.provider.dispose();
    });
  });

  test('the last enabled network cannot be switched off', () {
    fakeAsync((async) {
      final table = _routerTable()..[1]['Create'] = 0;
      final h = _Harness(_FakeRouter(table: table))..connectAndLoad(async);

      SaveResult? result;
      h.provider.setWirelessNetworkEnabled(0, false).then((r) => result = r);
      async.elapse(const Duration(seconds: 1));

      expect(result?.isFailed, isTrue);
      expect(h.writesSent, 0);
      h.provider.dispose();
    });
  });

  test('a password the router did not report is never sent blank', () {
    fakeAsync((async) {
      final table = _routerTable()..[1].remove('Password');
      final router = _FakeRouter(table: table);
      final h = _Harness(router)..connectAndLoad(async);

      expect(h.provider.wirelessNetworksParsed[1].passwordKnown, isFalse);
      SaveResult? result;
      h.provider.setWirelessNetworkEnabled(2, true).then((r) => result = r);
      async.elapse(const Duration(seconds: 1));

      expect(result?.isFailed, isTrue);
      expect(result?.message, contains('Password'));
      expect(h.writesSent, 0);

      // An untouched (empty) password field does not count as an edit.
      final blank = h.provider.wirelessNetworksParsed[1].copyWith(password: '');
      expect(blank.hasEdits, isFalse);
      expect(blank.toRouterPayload(), isNot(contains('Password')));

      // Providing a new password for that band makes the save safe.
      final band1 = h.provider.wirelessNetworksParsed[1];
      h.provider.updateWirelessNetwork(band1.copyWith(password: 'Typed1234'));
      async.elapse(const Duration(seconds: 2));
      expect(router.writes.single[1]['Password'], 'Typed1234');
      h.provider.dispose();
    });
  });

  test('nothing is sent before the Wi-Fi list has loaded', () {
    fakeAsync((async) {
      final h = _Harness(_FakeRouter());
      h.provider.selectRouter(
        MeshEntity(meshId: 'm', ssid: 'm', ipAddress: '10.0.0.1'),
      );
      async.elapse(const Duration(milliseconds: 10));
      SaveResult? result;
      h.provider.setWirelessNetworkEnabled(1, false).then((r) => result = r);
      async.elapse(const Duration(seconds: 1));
      expect(result?.isFailed, isTrue);
      expect(h.writesSent, 0);
      h.provider.dispose();
    });
  });

  test(
    'a re-read without the compared fields is unconfirmed, not confirmed',
    () {
      fakeAsync((async) {
        final router = _FakeRouter(dropOnWrite: true);
        final h = _Harness(router)..connectAndLoad(async);
        final strip = router.respond;
        // After the write the router answers without Create/Password fields.
        h.factory.responder = (path, data) {
          final reply = strip(path, data);
          if (path == '/GetWirelessInfoList' && router.writes.isNotEmpty) {
            return {
              'ErrorCode': 0,
              'Data': [
                for (final n in router.table)
                  {'Index': n['Index'], 'Ssid': n['Ssid']},
              ],
            };
          }
          return reply;
        };
        h.provider.setWirelessNetworkEnabled(1, false);
        async.elapse(const Duration(seconds: 40));
        expect(
          h.provider.pendingChanges.single.status,
          ChangeStatus.unverified,
        );
        h.provider.dispose();
      });
    },
  );
}
