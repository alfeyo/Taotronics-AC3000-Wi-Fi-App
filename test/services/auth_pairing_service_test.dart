import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';

Future<List<dynamic>> _savedJson() async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(prefs.getString('paired_routers')!) as List<dynamic>;
}

void main() {
  final legacyEntry = {
    'meshId': 'mesh1',
    'ipAddress': '192.168.10.1',
    'alias': null,
    'pairedAt': '2026-10-01T10:00:00.000',
    'credentialHash': 'abc',
    'mqttPassword': 'secret-1',
  };

  test('migrates legacy plaintext passwords into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'paired_routers': jsonEncode([legacyEntry]),
    });
    final store = MemoryCredentialStore();
    final service = AuthPairingService(credentialStore: store);

    await service.loadSavedPairings();

    expect(store.values, {'mesh1': 'secret-1'});
    expect(service.reconnectPassword('mesh1'), 'secret-1');
    expect(service.isPasswordStoredSecurely('mesh1'), isTrue);
    final saved = await _savedJson();
    expect(saved.single, isNot(contains('mqttPassword')));
    expect(saved.single['meshId'], 'mesh1');
  });

  test(
    'loads migrated pairings with the password from secure storage',
    () async {
      final stripped = Map.of(legacyEntry)..remove('mqttPassword');
      SharedPreferences.setMockInitialValues({
        'paired_routers': jsonEncode([stripped]),
      });
      final store = MemoryCredentialStore()..values['mesh1'] = 'secret-1';
      final service = AuthPairingService(credentialStore: store);

      await service.loadSavedPairings();

      expect(service.isPaired('mesh1'), isTrue);
      expect(service.reconnectPassword('mesh1'), 'secret-1');
      expect(service.state, PairingState.paired);
    },
  );

  test('keeps the plaintext copy when secure storage is unavailable', () async {
    SharedPreferences.setMockInitialValues({
      'paired_routers': jsonEncode([legacyEntry]),
    });
    final store = MemoryCredentialStore()..failWrites = true;
    final service = AuthPairingService(credentialStore: store);

    await service.loadSavedPairings();

    expect(service.reconnectPassword('mesh1'), 'secret-1');
    expect(service.isPasswordStoredSecurely('mesh1'), isFalse);
    expect((await _savedJson()).single['mqttPassword'], 'secret-1');
  });

  test('new pairings store the password securely only', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryCredentialStore();
    final service = AuthPairingService(credentialStore: store);

    await service.attemptPairing(
      meshId: 'mesh2',
      ipAddress: '192.168.10.1',
      customPassword: 'pw',
    );

    expect(store.values['mesh2'], 'pw');
    expect((await _savedJson()).single, isNot(contains('mqttPassword')));
  });

  test('falls back to the derived default password when none is stored', () {
    final service = AuthPairingService(
      credentialStore: MemoryCredentialStore(),
    );
    expect(
      service.reconnectPassword('mesh9'),
      service.generateDefaultPassword('mesh9'),
    );
  });

  test('removing a pairing deletes its secure password', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryCredentialStore();
    final service = AuthPairingService(credentialStore: store);
    await service.attemptPairing(meshId: 'mesh3', ipAddress: '10.0.0.1');

    await service.removePairing('mesh3');

    expect(store.values, isEmpty);
    expect(service.isPaired('mesh3'), isFalse);
  });
}
