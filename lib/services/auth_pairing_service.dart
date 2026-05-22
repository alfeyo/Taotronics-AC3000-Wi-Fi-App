import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
    'meshId': meshId,
    'ipAddress': ipAddress,
    'alias': alias,
    'pairedAt': pairedAt.toIso8601String(),
    'credentialHash': credentialHash,
    'mqttPassword': mqttPassword,
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
  static const String _pairedRoutersKey = 'paired_routers';
  static const String _lastPairedKey = 'last_paired_router';

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
        _pairedRouters.clear();
        _pairedRouters.addAll(
          jsonList.map((j) => PairedRouter.fromJson(j)).toList(),
        );
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
        _pairedRouters.map((r) => r.toJson()).toList(),
      );
      await prefs.setString(_pairedRoutersKey, jsonString);
    } catch (e) {
      debugPrint('AuthPairingService: Failed to save pairings - $e');
    }
  }

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
    await _savePairings();

    if (_pairedRouters.isEmpty) {
      _state = PairingState.notPaired;
    }
  }

  Future<void> clearAllPairings() async {
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
