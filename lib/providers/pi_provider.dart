import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pi_api.dart';
import '../services/pi_snapshot.dart';
import 'router_provider.dart';

/// Connection state of the Argon (Raspberry Pi) gateway link.
enum PiLinkState { starting, searching, connected, unreachable }

/// A Pi or link event shown in the notifications panel.
class PiEvent {
  const PiEvent({
    required this.id,
    required this.at,
    required this.title,
    required this.message,
    required this.severity,
    required this.source,
  });
  final String id;
  final DateTime at;
  final String title;
  final String message;

  /// 'info', 'success', 'warning' or 'error'.
  final String severity;

  /// 'argon' (server-observed) or 'app' (seen by this phone).
  final String source;
}

typedef HttpTransportFactory = PiTransport Function(Uri endpoint);
typedef BluetoothTransportFactory = PiTransport Function(String address);

/// App-level manager for the Argon gateway: discovery, trusted identity,
/// transport fallback (LAN -> Tailscale -> Bluetooth), foreground polling,
/// one-time pairing and router-snapshot synchronisation. Runs for the whole
/// app session in the foreground, independent of the visible tab, and never
/// in the background.
class PiProvider extends ChangeNotifier with WidgetsBindingObserver {
  PiProvider({
    required this._router,
    FlutterSecureStorage? storage,
    HttpTransportFactory? httpTransport,
    BluetoothTransportFactory? bluetoothTransport,
    Stream<List<ConnectivityResult>>? connectivityChanges,
    Future<Map<String, dynamic>> Function()? bluetoothStatus,
    this.autoStart = true,
    DateTime Function()? clock,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _http = httpTransport ?? ((uri) => HttpPiTransport(uri)),
       _bt = bluetoothTransport ?? ((a) => BluetoothPiTransport(a)),
       _btStatus = bluetoothStatus ?? (() => BluetoothPiTransport.status()),
       _now = clock ?? DateTime.now {
    ready = _load();
    if (autoStart) {
      WidgetsBinding.instance.addObserver(this);
      _connectivity =
          (connectivityChanges ?? Connectivity().onConnectivityChanged).listen(
            (_) => _networkChanged(),
          );
      ready.then((_) => _start());
    }
  }

  /// Argon's fixed downstream gateway address and Tailscale address.
  static final Uri lanDefault = Uri.parse('http://192.168.50.1');
  static final Uri tailscaleDefault = Uri.parse('http://100.94.137.17');
  static const liveEvery = Duration(seconds: 5);
  static const gatewayEvery = Duration(seconds: 15);
  static const syncEvery = Duration(seconds: 15);
  static const backoff = [5, 15, 30, 60];

  final RouterProvider _router;
  final FlutterSecureStorage _storage;
  final HttpTransportFactory _http;
  final BluetoothTransportFactory _bt;
  final Future<Map<String, dynamic>> Function() _btStatus;
  final DateTime Function() _now;
  final bool autoStart;
  late final Future<void> ready;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _timer;
  Timer? _networkDebounce;
  bool _disposed = false;
  bool _foreground = true;

  // Persisted trust and preferences.
  String? trustedId;
  String? bluetoothAddress;
  Uri? _lastEndpoint;
  Uri? manualEndpoint;
  String _token = '';
  String? pairedName;
  bool syncEnabled = true;
  bool bluetoothFallback = false;

  // Runtime.
  PiLinkState state = PiLinkState.starting;
  PiTransport? transport;
  PiIdentity? identity;
  Map<String, dynamic>? gateway;
  DateTime? gatewayAt;
  Map<String, dynamic>? live;
  DateTime? liveAt;
  DateTime? lastContact;
  String? lastError;
  bool credentialRejected = false;
  DateTime? sharedAt;
  int? sharedCount;
  String? syncError;
  int _failures = 0;
  int _attempt = 0;
  DateTime? _nextDiscovery;
  DateTime? _lastLive, _lastGateway, _lastSync, _lastRouterDetails;
  bool _discovering = false,
      _pollingLive = false,
      _pollingGateway = false,
      _syncing = false;
  int _generation = 0;
  bool _hadConnection = false;
  final List<PiEvent> _events = [];

  /// Household throughput samples received this session (bytes/s), newest last.
  final List<({DateTime time, int down, int up})> liveSamples = [];
  final Set<String> _seenServerEvents = {};
  bool _serverEventsPrimed = false;
  int unreadEvents = 0;

  bool get paired => _token.isNotEmpty && !credentialRejected;
  bool get connected => state == PiLinkState.connected && transport != null;
  bool get searching =>
      state == PiLinkState.searching || state == PiLinkState.starting;
  PiTransportKind? get transportKind => connected ? transport!.kind : null;
  List<PiEvent> get events => List.unmodifiable(_events);

  /// Live household throughput is fresh enough to display as current.
  bool get liveFresh =>
      live != null &&
      liveAt != null &&
      _now().difference(liveAt!).inSeconds <= 20 &&
      (live!['traffic'] as Map?)?['stale'] != true;
  bool get gatewayFresh =>
      gateway != null &&
      gatewayAt != null &&
      _now().difference(gatewayAt!).inSeconds <= 45;

  Map<String, dynamic>? get _traffic =>
      (live?['traffic'] as Map?)?.cast<String, dynamic>();

  /// Household download/upload measured at Argon's eth1, in BYTES per second
  /// (the app's display unit); Argon reports bits/s. Null when not fresh.
  int? get householdDownBytesPerSec => _rate('downloadBps');
  int? get householdUpBytesPerSec => _rate('uploadBps');
  int? _rate(String key) {
    if (!liveFresh) return null;
    final v = (_traffic?['aggregate'] as Map?)?[key];
    return v is num ? (v / 8).round() : null;
  }

  Map<String, dynamic>? get today =>
      (_traffic?['today'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic>? get gatewayInfo =>
      (gateway?['gateway'] as Map?)?.cast<String, dynamic>();

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------- storage

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      trustedId = prefs.getString('argon.v2.trustedId');
      bluetoothAddress = prefs.getString('argon.v2.bluetooth');
      final last = prefs.getString('argon.v2.endpoint');
      final manual =
          prefs.getString('argon.v2.manual') ??
          prefs.getString('argon.endpoint.v1');
      _lastEndpoint = last == null ? null : _tryEndpoint(last);
      manualEndpoint = manual == null ? null : _tryEndpoint(manual);
      pairedName = prefs.getString('argon.v2.pairedName');
      syncEnabled =
          prefs.getBool('argon.v2.sync') ??
          prefs.getBool('argon.sharing.v1') ??
          true;
      bluetoothFallback = prefs.getBool('argon.v2.bluetoothFallback') ?? false;
      // A credential provisioned earlier (shared token or paired device) is
      // used automatically.
      _token = await _storage.read(key: 'argon.companion.v1') ?? '';
    } catch (_) {
      _token = '';
      lastError = 'Saved gateway settings could not be read securely.';
    }
    _emit();
  }

  Uri? _tryEndpoint(String v) {
    try {
      return validatePiEndpoint(v);
    } on FormatException {
      return null;
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> put(String k, String? v) =>
        v == null ? prefs.remove(k) : prefs.setString(k, v);
    await put('argon.v2.trustedId', trustedId);
    await put('argon.v2.bluetooth', bluetoothAddress);
    await put('argon.v2.endpoint', _lastEndpoint?.toString());
    await put('argon.v2.manual', manualEndpoint?.toString());
    await put('argon.v2.pairedName', pairedName);
    await prefs.setBool('argon.v2.sync', syncEnabled);
    await prefs.setBool('argon.v2.bluetoothFallback', bluetoothFallback);
  }

  // -------------------------------------------------------------- lifecycle

  void _start() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    tick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _nextDiscovery = null;
        _start();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // No background work: stop timers and discard in-flight results.
        _foreground = false;
        _generation++;
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _networkChanged() {
    _networkDebounce?.cancel();
    _networkDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (_disposed || !_foreground) return;
      // The current route may be gone or a better one available: re-verify.
      _attempt = 0;
      _nextDiscovery = null;
      transport = null;
      if (state == PiLinkState.connected) state = PiLinkState.searching;
      _emit();
      tick();
    });
  }

  /// One scheduler step; safe to call often. Public for tests.
  Future<void> tick() async {
    if (_disposed || !_foreground) return;
    final now = _now();
    if (transport == null) {
      if (_nextDiscovery == null || !now.isBefore(_nextDiscovery!)) {
        await discover();
      }
      return;
    }
    final jobs = <Future<void>>[];
    if (_lastLive == null || now.difference(_lastLive!) >= liveEvery) {
      jobs.add(_pollLive());
    }
    if (_lastGateway == null || now.difference(_lastGateway!) >= gatewayEvery) {
      jobs.add(_pollGateway());
    }
    if (_lastSync == null || now.difference(_lastSync!) >= syncEvery) {
      jobs.add(_sync());
    }
    await Future.wait(jobs);
  }

  /// Re-run discovery now (e.g. Manage connection > Retry).
  Future<void> reconnect() async {
    _attempt = 0;
    _nextDiscovery = null;
    transport = null;
    await discover();
  }

  // -------------------------------------------------------------- discovery

  List<Uri> _candidates() {
    final list = <Uri>[lanDefault];
    void add(Uri? u) {
      if (u != null && !list.any((x) => x.toString() == u.toString())) {
        list.add(u);
      }
    }

    if (_lastEndpoint != null &&
        kindForEndpoint(_lastEndpoint!) == PiTransportKind.lan) {
      add(_lastEndpoint);
    }
    add(tailscaleDefault);
    add(_lastEndpoint);
    add(manualEndpoint);
    return list;
  }

  Future<void> discover() async {
    if (_discovering || _disposed) return;
    _discovering = true;
    final generation = _generation;
    if (state != PiLinkState.connected) {
      state = _hadConnection || state == PiLinkState.unreachable
          ? state
          : PiLinkState.searching;
    }
    _emit();
    String? reason;
    try {
      for (final uri in _candidates()) {
        final t = _http(uri);
        try {
          final id = PiIdentity.parse(
            await t.get(
              '/api/v1/identity',
              timeout: const Duration(seconds: 4),
            ),
          );
          if (trustedId != null && id.instanceId != trustedId) {
            reason =
                'A different Argon answered at ${uri.host}; it is not trusted.';
            continue;
          }
          if (generation != _generation || _disposed) return;
          await _adopt(t, id, endpoint: uri);
          return;
        } on PiApiException catch (e) {
          reason = e.message;
        }
      }
      final bt = await _bluetoothCandidate();
      if (bt != null) {
        try {
          final id = PiIdentity.parse(await bt.get('/api/v1/identity'));
          if (trustedId == null || id.instanceId == trustedId) {
            if (generation != _generation || _disposed) return;
            await _adopt(bt, id);
            return;
          }
        } on PiApiException catch (e) {
          reason = e.message;
        }
      }
      if (generation != _generation || _disposed) return;
      _unreachable(reason ?? 'Argon was not found on any route.');
    } finally {
      _discovering = false;
      _emit();
    }
  }

  Future<PiTransport?> _bluetoothCandidate() async {
    if (!bluetoothFallback || bluetoothAddress == null || !paired) return null;
    final s = await _btStatus();
    if (s['enabled'] != true || s['permission'] != true) return null;
    return _bt(bluetoothAddress!);
  }

  Future<void> _adopt(PiTransport t, PiIdentity id, {Uri? endpoint}) async {
    final previous = transport?.kind;
    final wasUnreachable = state == PiLinkState.unreachable;
    transport = t;
    identity = id;
    state = PiLinkState.connected;
    lastContact = _now();
    lastError = null;
    _failures = 0;
    _attempt = 0;
    _nextDiscovery = null;
    _lastLive = _lastGateway = _lastSync =
        null; // refresh and share promptly on (re)connect
    final firstTrust = trustedId == null;
    trustedId = id.instanceId;
    if (id.bluetoothAddress != null) bluetoothAddress = id.bluetoothAddress;
    if (endpoint != null) _lastEndpoint = endpoint;
    await _savePrefs();
    if (firstTrust) {
      _addEvent(
        'trusted',
        'Argon found',
        'Raspberry Pi gateway recognised via ${t.kind.label}.',
        'success',
      );
    } else if (wasUnreachable) {
      _addEvent(
        'restored',
        'Argon reachable again',
        'Connected via ${t.kind.label}.',
        'success',
      );
    } else if (previous != null && previous != t.kind) {
      _addEvent(
        'transport',
        'Gateway route changed',
        'Now connected via ${t.kind.label}.',
        'info',
      );
    }
    _hadConnection = true;
    _emit();
    unawaited(tick());
  }

  void _unreachable(String reason) {
    final was = state;
    transport = null;
    lastError = reason;
    state = PiLinkState.unreachable;
    final delay = backoff[_attempt.clamp(0, backoff.length - 1)];
    _attempt++;
    _nextDiscovery = _now().add(Duration(seconds: delay));
    if (was == PiLinkState.connected ||
        (was != PiLinkState.unreachable && _hadConnection)) {
      _addEvent('unreachable', 'Argon unreachable', reason, 'warning');
    }
  }

  void _requestFailed(PiApiException e, int generation) {
    if (generation != _generation) return;
    if (e.unauthorized && _token.isNotEmpty) {
      credentialRejected = true;
      _addEvent(
        'credential',
        'Synchronization paused',
        'Argon no longer accepts this phone\'s pairing. Pair again from Gateway.',
        'warning',
      );
      _emit();
      return;
    }
    _failures++;
    lastError = e.message;
    if (_failures >= 2) {
      // The route stopped working: look for another one now.
      transport = null;
      state = PiLinkState.searching;
      _nextDiscovery = null;
    }
    _emit();
  }

  /// Token for reads: omitted where Argon allows anonymous monitoring over IP,
  /// so the credential travels only when it is required.
  String? get _readToken {
    final needs =
        transport?.kind == PiTransportKind.bluetooth ||
        identity?.monitorAllowed != true;
    return needs && paired ? _token : null;
  }

  // ---------------------------------------------------------------- polling

  Future<void> _pollLive() async {
    final t = transport;
    if (_pollingLive || t == null) return;
    _pollingLive = true;
    _lastLive = _now();
    final generation = _generation;
    try {
      final r = await t.get('/api/v1/live', token: _readToken);
      if (generation != _generation || transport != t) return;
      live = r;
      liveAt = _now();
      lastContact = liveAt;
      _failures = 0;
      final down = householdDownBytesPerSec, up = householdUpBytesPerSec;
      if (down != null && up != null) {
        liveSamples.add((time: liveAt!, down: down, up: up));
        if (liveSamples.length > 120) liveSamples.removeAt(0);
      }
      _emit();
    } on PiApiException catch (e) {
      _requestFailed(e, generation);
    } finally {
      _pollingLive = false;
    }
  }

  Future<void> _pollGateway() async {
    final t = transport;
    if (_pollingGateway || t == null) return;
    _pollingGateway = true;
    _lastGateway = _now();
    final generation = _generation;
    try {
      final r = await t.get(
        '/api/v1/gateway',
        token: _readToken,
        timeout: const Duration(seconds: 15),
      );
      if (generation != _generation || transport != t) return;
      gateway = r;
      gatewayAt = _now();
      lastContact = gatewayAt;
      _failures = 0;
      _mergeServerEvents(r['events']);
      _emit();
    } on PiApiException catch (e) {
      _requestFailed(e, generation);
    } finally {
      _pollingGateway = false;
    }
  }

  void _mergeServerEvents(Object? list) {
    if (list is! List) return;
    var added = false;
    for (final e in list.whereType<Map>()) {
      final id = e['id'];
      final at = e['at'];
      if (id is! String || at is! num || _seenServerEvents.contains(id)) {
        continue;
      }
      _seenServerEvents.add(id);
      _events.add(
        PiEvent(
          id: 'argon:$id',
          at: DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000),
          title: _eventTitle(e['kind'] as String?),
          message: (e['message'] as String?) ?? '',
          severity: switch (e['severity']) {
            'warning' => 'warning',
            'error' => 'error',
            _ => 'info',
          },
          source: 'argon',
        ),
      );
      if (_serverEventsPrimed) unreadEvents++;
      added = true;
    }
    _serverEventsPrimed = true; // history from before this session is not "new"
    if (added) _sortEvents();
  }

  String _eventTitle(String? kind) => switch (kind) {
    'vpn' => 'VPN',
    'uplink' => 'Internet uplink changed',
    'collector' => 'Traffic monitoring',
    'throttled' => 'Raspberry Pi throttling',
    'temperature' => 'Raspberry Pi temperature',
    _ => 'Argon',
  };

  void _addEvent(String kind, String title, String message, String severity) {
    final at = _now();
    _events.add(
      PiEvent(
        id: 'app:$kind:${at.millisecondsSinceEpoch}',
        at: at,
        title: title,
        message: message,
        severity: severity,
        source: 'app',
      ),
    );
    unreadEvents++;
    _sortEvents();
  }

  void _sortEvents() {
    _events.sort((a, b) => b.at.compareTo(a.at));
    if (_events.length > 100) _events.removeRange(100, _events.length);
  }

  void markEventsRead() {
    if (unreadEvents == 0) return;
    unreadEvents = 0;
    _emit();
  }

  // ------------------------------------------------------------------ sync

  /// Sync health for display: null when not applicable.
  bool get syncActive =>
      paired &&
      syncEnabled &&
      connected &&
      transport!.kind != PiTransportKind.bluetooth;

  Future<void> _sync() async {
    final t = transport;
    _lastSync = _now();
    if (_syncing || t == null || !paired || !syncEnabled) return;
    if (t.kind == PiTransportKind.bluetooth) {
      syncError =
          'Router sharing needs a network route to Argon (not Bluetooth).';
      return;
    }
    // Never compete with a router configuration change in progress.
    if (!_router.isConnected || _router.isLivePaused) {
      syncError = _router.isConnected
          ? null
          : 'Waiting for the TaoTronics router connection.';
      return;
    }
    _syncing = true;
    final generation = _generation;
    try {
      if (_lastRouterDetails == null ||
          _now().difference(_lastRouterDetails!).inMinutes >= 5) {
        _lastRouterDetails = _now();
        await _router.refreshWanSettings();
        if (generation != _generation) return;
        await _router.loadGuestWifiSettings(quiet: true);
        if (generation != _generation) return;
      }
      final snapshot = buildPiRouterSnapshot(_router, now: _now());
      if (snapshot == null) {
        syncError = 'Waiting for a fresh router device list.';
        return;
      }
      try {
        final r = await t.post(
          '/api/v1/router/snapshot',
          snapshot,
          token: _token,
        );
        if (generation != _generation) return;
        sharedAt = _now();
        sharedCount = (r['count'] as num?)?.toInt();
        syncError = null;
      } on PiApiException catch (e) {
        if (generation != _generation) return;
        if (e.status == 409) return; // same observation already delivered
        if (e.unauthorized) {
          _requestFailed(e, generation);
        } else {
          syncError = e.message;
        }
      }
    } finally {
      _syncing = false;
      _emit();
    }
  }

  // ---------------------------------------------------------------- pairing

  /// Exchanges the 6-digit code shown on Argon (/devices) for this phone's
  /// own credential, stored only in Android secure storage.
  Future<void> pair(String code, {String deviceName = 'TT Router app'}) async {
    final t = transport;
    if (t == null || t.kind == PiTransportKind.bluetooth) {
      throw const PiApiException(
        'Connect to Argon over the local network or Tailscale to pair.',
      );
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const PiApiException('Enter the 6-digit code shown on Argon.');
    }
    final r = await t.post('/api/v1/pairing/complete', {
      'code': code.trim(),
      'name': deviceName,
    });
    final token = r['token'];
    if (token is! String || token.length < 32) {
      throw const PiApiException('Argon returned an invalid credential.');
    }
    await _storage.write(key: 'argon.companion.v1', value: token);
    if (await _storage.read(key: 'argon.companion.v1') != token) {
      throw const PiApiException(
        'Secure storage failed; pairing was not saved.',
      );
    }
    _token = token;
    credentialRejected = false;
    pairedName = (r['name'] as String?) ?? deviceName;
    syncEnabled = true;
    syncError = null;
    await _savePrefs();
    _addEvent(
      'paired',
      'Device synchronization enabled',
      'Router clients are shared with Argon while TT Router is open.',
      'success',
    );
    _lastSync = null;
    _emit();
    unawaited(tick());
  }

  Future<void> setSyncEnabled(bool value) async {
    syncEnabled = value;
    if (!value) syncError = null;
    await _savePrefs();
    _emit();
  }

  Future<void> setBluetoothFallback(bool value) async {
    bluetoothFallback = value;
    await _savePrefs();
    _emit();
  }

  /// Advanced: an extra address to try (HTTPS, or HTTP to a private IP).
  Future<void> setManualEndpoint(String? value) async {
    manualEndpoint = value == null || value.trim().isEmpty
        ? null
        : validatePiEndpoint(value);
    await _savePrefs();
    await reconnect();
  }

  /// Removes this phone's credential and the trusted Argon identity.
  Future<void> forget() async {
    await _storage.delete(key: 'argon.companion.v1');
    _token = '';
    credentialRejected = false;
    pairedName = null;
    trustedId = null;
    bluetoothAddress = null;
    _lastEndpoint = null;
    sharedAt = null;
    syncError = null;
    await _savePrefs();
    await reconnect();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _networkDebounce?.cancel();
    _connectivity?.cancel();
    if (autoStart) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
