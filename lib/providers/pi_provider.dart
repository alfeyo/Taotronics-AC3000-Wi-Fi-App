import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pi_api.dart';
import '../services/pi_snapshot.dart';
import 'router_provider.dart';

class PiProvider extends ChangeNotifier {
  PiProvider({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    ready = _load();
  }
  final FlutterSecureStorage _storage;
  late final Future<void> ready;
  String endpoint = '', _token = '';
  bool sharing = false, busy = false;
  Map<String, dynamic>? data;
  String? error, bridgeError;
  DateTime? receivedAt, sharedAt;
  DateTime? _routerDetailsAt;
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = false;
  void setForeground(bool active) {
    _foreground = active;
    if (!active) _generation++;
  }

  bool get configured => endpoint.isNotEmpty && _token.isNotEmpty;
  bool get stale =>
      error != null ||
      receivedAt == null ||
      DateTime.now().difference(receivedAt!).inSeconds > 45;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      endpoint = prefs.getString('argon.endpoint.v1') ?? '';
      sharing = prefs.getBool('argon.sharing.v1') ?? false;
      _token = await _storage.read(key: 'argon.companion.v1') ?? '';
      if (endpoint.isNotEmpty) validatePiEndpoint(endpoint);
    } catch (_) {
      error = 'Gateway setup could not be loaded securely.';
      _token = '';
    }
    _emit();
  }

  Future<void> configure(String address, String token, bool share) async {
    final uri = validatePiEndpoint(address);
    final secret = token.trim().isEmpty ? _token : token.trim();
    if (secret.length < 32) {
      throw const FormatException(
        'Enter the companion token provided by Argon.',
      );
    }
    await _storage.write(key: 'argon.companion.v1', value: secret);
    if (await _storage.read(key: 'argon.companion.v1') != secret) {
      throw const PiApiException(
        'Secure token storage failed. Configuration was not saved.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('argon.endpoint.v1', uri.toString());
    await prefs.setBool('argon.sharing.v1', share);
    _generation++;
    endpoint = uri.toString();
    _token = secret;
    sharing = share;
    data = null;
    receivedAt = null;
    error = null;
    sharedAt = null;
    bridgeError = null;
    _emit();
  }

  Future<void> refresh(RouterProvider router) async {
    await ready;
    if (!configured || busy || _disposed || !_foreground) return;
    busy = true;
    _emit();
    final generation = _generation;
    try {
      final api = PiApi(validatePiEndpoint(endpoint), _token);
      final result = await api.request('/api/v1/gateway');
      if (generation != _generation || _disposed || !_foreground) return;
      data = result;
      receivedAt = DateTime.now();
      error = null;
      if (sharing) {
        if (router.isConnected &&
            (_routerDetailsAt == null ||
                DateTime.now().difference(_routerDetailsAt!).inSeconds >= 60)) {
          _routerDetailsAt = DateTime.now();
          await router.refreshWanSettings();
          await router.loadGuestWifiSettings(quiet: true);
        }
        if (generation != _generation ||
            _disposed ||
            !_foreground ||
            !sharing) {
          return;
        }
        final snapshot = buildPiRouterSnapshot(router);
        if (snapshot == null) {
          bridgeError = 'Waiting for fresh, authenticated router inventory.';
        } else {
          try {
            await api.request('/api/v1/router/snapshot', body: snapshot);
            if (generation != _generation ||
                _disposed ||
                !_foreground ||
                !sharing) {
              return;
            }
            sharedAt = DateTime.now();
            bridgeError = null;
          } catch (e) {
            if (generation == _generation &&
                !_disposed &&
                _foreground &&
                sharing) {
              bridgeError = e.toString();
            }
          }
        }
      }
    } catch (e) {
      if (generation == _generation) error = e.toString();
    } finally {
      busy = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
