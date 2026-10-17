import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credential_store.dart';

enum PairingState {
  notPaired,
  pairingModeRequired,
  pairingInProgress,
  paired,
  authenticationFailed,
}

class PairedRouter {
  final String meshId;
  final String ipAddress;
  final String? alias;
  final DateTime pairedAt;
  final String credentialHash;
  final String? mqttPassword;

  PairedRouter({
    required this.meshId,
    required this.ipAddress,
    this.alias,
    required this.pairedAt,
    required this.credentialHash,
    this.mqttPassword,
  });

  factory PairedRouter.fromJson(Map<String, dynamic> json) {
    return PairedRouter(
      meshId: json['meshId'] ?? '',
      ipAddress: json['ipAddress'] ?? '',
      alias: json['alias'],
      pairedAt: DateTime.tryParse(json['pairedAt'] ?? '') ?? DateTime.now(),
      credentialHash: json['credentialHash'] ?? '',
      mqttPassword: json['mqttPassword'],
    );
  }

  PairedRouter withPassword(String? password) => PairedRouter(
    meshId: meshId,
    ipAddress: ipAddress,
    alias: alias,
    pairedAt: pairedAt,
    credentialHash: credentialHash,
    mqttPassword: password,
  );

  /// Preferences form. The password is only included when it could not be
  /// stored in secure storage, so a pairing is never silently lost.
  Map<String, dynamic> toJson({bool includePassword = true}) => {
    'meshId': meshId,
    'ipAddress': ipAddress,
    'alias': alias,
    'pairedAt': pairedAt.toIso8601String(),
    'credentialHash': credentialHash,
    if (includePassword) 'mqttPassword': mqttPassword,
  };

  Map<String, dynamic> toDiagnosticsJson() => {
    'meshId': meshId,
    'ipAddress': ipAddress,
    'alias': alias,
    'pairedAt': pairedAt.toIso8601String(),
    'hasReconnectCredential': mqttPassword != null,
  };
}

class AuthPairingService {
  AuthPairingService({CredentialStore? credentialStore})
    : _credentials = credentialStore ?? SecureCredentialStore();

  static const String _pairedRoutersKey = 'paired_routers';
  static const String _lastPairedKey = 'last_paired_router';

  final CredentialStore _credentials;
  final Set<String> _securelyStored = {};
  final List<PairedRouter> _pairedRouters = [];
  PairingState _state = PairingState.notPaired;
  String? _lastError;

  List<PairedRouter> get pairedRouters => List.unmodifiable(_pairedRouters);
  PairingState get state => _state;
  String? get lastError => _lastError;

  String get stateText {
    switch (_state) {
      case PairingState.notPaired:
        return 'Not paired';
      case PairingState.pairingModeRequired:
        return 'Router pairing mode required';
      case PairingState.pairingInProgress:
        return 'Pairing in progress...';
      case PairingState.paired:
        return 'Paired';
      case PairingState.authenticationFailed:
        return 'Authentication failed';
    }
  }

  Future<void> loadSavedPairings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_pairedRoutersKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final loaded = jsonList
            .whereType<Map>()
            .map((j) => PairedRouter.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        _pairedRouters.clear();
        _securelyStored.clear();
        var migrated = false;
        for (final router in loaded) {
          final legacyPassword = router.mqttPassword;
          if (legacyPassword != null) {
            // Pre-1.1 builds kept the password in preferences. Move it.
            if (await _credentials.write(router.meshId, legacyPassword)) {
              _securelyStored.add(router.meshId);
              migrated = true;
            }
            _pairedRouters.add(router);
          } else {
            final stored = await _credentials.read(router.meshId);
            if (stored != null) _securelyStored.add(router.meshId);
            _pairedRouters.add(router.withPassword(stored));
          }
        }
        if (migrated) await _savePairings();
        if (_pairedRouters.isNotEmpty) {
          _state = PairingState.paired;
        }
      }
    } catch (e) {
      debugPrint('AuthPairingService: Failed to load pairings - $e');
    }
  }

  Future<void> _savePairings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(
        _pairedRouters
            .map(
              (r) => r.toJson(
                includePassword: !_securelyStored.contains(r.meshId),
              ),
            )
            .toList(),
      );
      await prefs.setString(_pairedRoutersKey, jsonString);
    } catch (e) {
      debugPrint('AuthPairingService: Failed to save pairings - $e');
    }
  }

  /// Whether the router password lives in secure storage (diagnostics).
  bool isPasswordStoredSecurely(String meshId) =>
      _securelyStored.contains(meshId);

  bool isPaired(String meshId) {
    return _pairedRouters.any((r) => r.meshId == meshId);
  }

  PairedRouter? getPairedRouter(String meshId) {
    try {
      return _pairedRouters.firstWhere((r) => r.meshId == meshId);
    } catch (_) {
      return null;
    }
  }

  String reconnectPassword(String meshId) {
    return getPairedRouter(meshId)?.mqttPassword ??
        generateDefaultPassword(meshId);
  }

  String generateDefaultPassword(String meshId) {
    final input = 'dazoo$meshId';
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<bool> attemptPairing({
    required String meshId,
    required String ipAddress,
    String? customPassword,
    String? alias,
  }) async {
    _state = PairingState.pairingInProgress;
    _lastError = null;

    try {
      final password = customPassword ?? generateDefaultPassword(meshId);
      final credentialHash = md5
          .convert(utf8.encode('$meshId:$password'))
          .toString();

      final pairedRouter = PairedRouter(
        meshId: meshId,
        ipAddress: ipAddress,
        alias: alias,
        pairedAt: DateTime.now(),
        credentialHash: credentialHash,
        mqttPassword: password,
      );

      final existingIndex = _pairedRouters.indexWhere(
        (r) => r.meshId == meshId,
      );
      if (existingIndex >= 0) {
        _pairedRouters[existingIndex] = pairedRouter;
      } else {
        _pairedRouters.add(pairedRouter);
      }

      if (await _credentials.write(meshId, password)) {
        _securelyStored.add(meshId);
      } else {
        _securelyStored.remove(meshId);
      }
      await _savePairings();
      await _setLastPaired(meshId);

      _state = PairingState.paired;
      return true;
    } catch (e) {
      _lastError = 'Pairing failed: $e';
      _state = PairingState.authenticationFailed;
      return false;
    }
  }

  Future<void> _setLastPaired(String meshId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPairedKey, meshId);
  }

  Future<String?> getLastPairedMeshId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastPairedKey);
  }

  Future<void> removePairing(String meshId) async {
    _pairedRouters.removeWhere((r) => r.meshId == meshId);
    _securelyStored.remove(meshId);
    await _credentials.delete(meshId);
    await _savePairings();

    if (_pairedRouters.isEmpty) {
      _state = PairingState.notPaired;
    }
  }

  Future<void> clearAllPairings() async {
    for (final router in _pairedRouters) {
      await _credentials.delete(router.meshId);
    }
    _securelyStored.clear();
    _pairedRouters.clear();
    _state = PairingState.notPaired;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairedRoutersKey);
    await prefs.remove(_lastPairedKey);
  }

  void setAuthenticationFailed(String? error) {
    _state = PairingState.authenticationFailed;
    _lastError = error;
  }

  void requirePairingMode() {
    _state = PairingState.pairingModeRequired;
    _lastError =
        'Router requires pairing mode. Factory reset or enable pairing on the router.';
  }
}
