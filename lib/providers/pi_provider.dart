import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/argon_operator.dart';
import '../services/argon_status.dart';
import '../services/pi_api.dart';
import '../services/pi_snapshot.dart';
import 'router_provider.dart';

/// Connection state of the Argon (Raspberry Pi) gateway link.
enum PiLinkState { starting, searching, connected, unreachable }

/// How current the Network Hub data on screen is.
enum HubDataState {
  /// No response yet: nothing to show, but nothing is wrong either.
  loading,
  connected,

  /// Data exists but is older than its freshness window.
  stale,

  /// Argon has not answered on any route and nothing was received before.
  unreachable,
}

enum VpnCommandPhase { idle, sending, verifying, confirmed, failed }

enum VpnCommandIssue {
  none,
  needsToken,
  tokenInvalid,
  forbidden,
  busy,
  rejected,
  upstream,
  bluetooth,
  unreachable,
  unconfirmed,
  network,
}

/// Shown when the only route to Argon is the read-only Bluetooth bridge.
const vpnNeedsIpRouteMessage =
    'Connect over local network or Tailscale to change VPN mode';

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
    this.vpnVerifyInterval = const Duration(seconds: 3),
    this.vpnVerifyAttempts = 10,
    String Function()? nonce,
  }) : _nonce = nonce ?? ArgonOperatorAuth.nonce,
       _storage = storage ?? const FlutterSecureStorage(),
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

  /// Live samples kept for the Network Hub time series.
  static const sampleWindow = Duration(minutes: 10);
  static const companionKey = 'argon.companion.v1';

  /// Separate from the companion credential: authorizes operator commands.
  static const operatorKey = 'argon.operator.v1';

  final RouterProvider _router;
  final FlutterSecureStorage _storage;
  final HttpTransportFactory _http;
  final BluetoothTransportFactory _bt;
  final Future<Map<String, dynamic>> Function() _btStatus;
  final DateTime Function() _now;
  final bool autoStart;
  final Duration vpnVerifyInterval;
  final int vpnVerifyAttempts;
  final String Function() _nonce;
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
  String _operatorToken = '';
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

  // VPN control.
  Map<String, dynamic>? _vpnObserved;
  DateTime? _vpnObservedAt;
  VpnCommandPhase vpnPhase = VpnCommandPhase.idle;
  VpnCommandIssue vpnIssue = VpnCommandIssue.none;
  String? vpnTarget;
  String? vpnMessage;
  String? vpnRecovery;

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

  /// Household rates exactly as Argon reports them (bits per second).
  num? get householdDownBitsPerSec => _bits('downloadBps');
  num? get householdUpBitsPerSec => _bits('uploadBps');
  num? _bits(String key) {
    if (!liveFresh) return null;
    final v = (_traffic?['aggregate'] as Map?)?[key];
    return v is num && v >= 0 ? v : null;
  }

  /// Freshness of the gateway report (VPN, usage, uplink, health).
  HubDataState get hubState {
    if (gateway == null) {
      return state == PiLinkState.unreachable
          ? HubDataState.unreachable
          : HubDataState.loading;
    }
    return gatewayFresh ? HubDataState.connected : HubDataState.stale;
  }

  /// Freshness of the live household rates.
  HubDataState get liveState {
    if (live == null) {
      return state == PiLinkState.unreachable
          ? HubDataState.unreachable
          : HubDataState.loading;
    }
    return liveFresh ? HubDataState.connected : HubDataState.stale;
  }

  /// Most recent VPN observation: a direct /api/v1/vpn read when it is newer
  /// than the gateway report. Older Argons nest it under `gateway.vpn`.
  ArgonVpn? get vpn {
    if (_vpnObserved != null &&
        _vpnObservedAt != null &&
        (gatewayAt == null || !_vpnObservedAt!.isBefore(gatewayAt!))) {
      return ArgonVpn.parse(_vpnObserved);
    }
    return ArgonVpn.parse(gateway?['vpn'] ?? gatewayInfo?['vpn']);
  }

  ArgonUsage? get usage =>
      ArgonUsage.parse(gateway?['usage'], legacyHistory: gateway?['history']);
  ArgonUplink? get uplink => ArgonUplink.parse(gateway?['uplink']);
  ArgonRouterView? get routerView => ArgonRouterView.parse(gateway?['router']);

  /// Today's household usage: Argon's `usage.periods.today`, or the older
  /// live `traffic.today` counters (download/upload, VPN subset).
  UsagePeriod? get todayUsage {
    final period = usage?.today;
    if (period != null) return period;
    final t = today;
    final down = t?['downloadBytes'], up = t?['uploadBytes'];
    if (down is! num || up is! num) return null;
    final total = (down + up).round();
    final vd = t?['vpnDownloadBytes'], vu = t?['vpnUploadBytes'];
    final vpnBytes = vd is num || vu is num
        ? ((vd is num ? vd : 0) + (vu is num ? vu : 0)).round()
        : null;
    return UsagePeriod(
      downloadBytes: down.round(),
      uploadBytes: up.round(),
      totalBytes: total,
      vpnBytes: vpnBytes,
      vpnShare: vpnBytes == null || total <= 0
          ? null
          : (vpnBytes / total).clamp(0.0, 1.0),
      measured: true,
    );
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
      _token = await _storage.read(key: companionKey) ?? '';
      _operatorToken = await _storage.read(key: operatorKey) ?? '';
    } catch (_) {
      _token = '';
      _operatorToken = '';
      lastError = 'Saved Network Hub settings could not be read securely.';
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
        'Network Hub (Raspberry Pi) recognised via ${t.kind.label}.',
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
        'Network Hub route changed',
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
        'Argon no longer accepts this phone\'s pairing. Pair again from Network Hub.',
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
        liveSamples.removeWhere(
          (s) => liveAt!.difference(s.time) > sampleWindow,
        );
        if (liveSamples.length > 150) {
          liveSamples.removeRange(0, liveSamples.length - 150);
        }
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
            'error' || 'critical' => 'error',
            'success' => 'success',
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

  String _eventTitle(String? kind) {
    final k = (kind ?? '').toLowerCase();
    if (k.contains('vpn')) return 'VPN';
    if (k.contains('uplink') || k.contains('wan')) {
      return 'Internet uplink changed';
    }
    if (k.contains('link')) return 'Network link';
    if (k.contains('temp')) return 'Raspberry Pi temperature';
    if (k.contains('throttl')) return 'Raspberry Pi throttling';
    if (k == 'collector') return 'Traffic monitoring';
    return 'Network Hub';
  }

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
    await _storage.write(key: companionKey, value: token);
    if (await _storage.read(key: companionKey) != token) {
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
    await _storage.delete(key: companionKey);
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

  // ------------------------------------------------------------ VPN control

  bool get hasOperatorToken => _operatorToken.isNotEmpty;
  bool get vpnInFlight =>
      vpnPhase == VpnCommandPhase.sending ||
      vpnPhase == VpnCommandPhase.verifying;

  /// The current route can carry an operator command (not Bluetooth).
  bool get vpnControlRoute {
    final t = transport;
    return connected &&
        t != null &&
        t.kind != PiTransportKind.bluetooth &&
        t is PiOperatorTransport;
  }

  /// Stores the operator token in Android secure storage only, under its own
  /// key. The companion (pairing) token is never accepted as operator token.
  Future<void> saveOperatorToken(String value) async {
    final token = value.trim();
    if (token.length < 8 || token.contains(RegExp(r'\s'))) {
      throw const PiApiException('Enter the operator token from Argon.');
    }
    if (token == _token) {
      throw const PiApiException(
        'That is this phone\'s pairing token, not the operator token.',
      );
    }
    await _storage.write(key: operatorKey, value: token);
    if (await _storage.read(key: operatorKey) != token) {
      throw const PiApiException(
        'Secure storage failed; the operator token was not saved.',
      );
    }
    _operatorToken = token;
    if (vpnIssue == VpnCommandIssue.tokenInvalid ||
        vpnIssue == VpnCommandIssue.needsToken) {
      _resetVpnCommand();
    }
    _emit();
  }

  Future<void> forgetOperatorToken() async {
    await _storage.delete(key: operatorKey);
    _operatorToken = '';
    _resetVpnCommand();
    _emit();
  }

  void _resetVpnCommand() {
    if (vpnInFlight) return;
    vpnPhase = VpnCommandPhase.idle;
    vpnIssue = VpnCommandIssue.none;
    vpnMessage = vpnRecovery = vpnTarget = null;
  }

  void dismissVpnResult() {
    _resetVpnCommand();
    _emit();
  }

  void _absorbVpn(Object? observed) {
    if (observed is! Map || ArgonVpn.parse(observed) == null) return;
    _vpnObserved = observed.cast<String, dynamic>();
    _vpnObservedAt = _now();
  }

  bool _vpnFail(VpnCommandIssue issue, String message, {String? recovery}) {
    vpnPhase = VpnCommandPhase.failed;
    vpnIssue = issue;
    vpnMessage = message;
    vpnRecovery = recovery;
    _emit();
    return false;
  }

  /// Turns the household VPN on or off with operator authority, then
  /// re-reads Argon until the observed mode matches. Returns true only when
  /// the change is confirmed. Never overlaps: a second call while one is in
  /// flight returns false without sending anything.
  Future<bool> setVpnMode(bool on) async {
    if (vpnInFlight || _disposed) return false;
    final target = on ? 'on' : 'off';
    vpnTarget = target;
    vpnMessage = vpnRecovery = null;
    vpnIssue = VpnCommandIssue.none;
    final t = transport;
    if (!connected || t == null) {
      return _vpnFail(
        VpnCommandIssue.unreachable,
        'Network Hub is not reachable right now.',
      );
    }
    if (t.kind == PiTransportKind.bluetooth || t is! PiOperatorTransport) {
      return _vpnFail(VpnCommandIssue.bluetooth, vpnNeedsIpRouteMessage);
    }
    if (_operatorToken.isEmpty) {
      return _vpnFail(
        VpnCommandIssue.needsToken,
        'Enter the operator token to change VPN mode.',
      );
    }
    vpnPhase = VpnCommandPhase.sending;
    vpnMessage = on ? 'Turning VPN on…' : 'Turning VPN off…';
    _emit();
    const path = '/api/v1/vpn';
    final body = utf8.encode(
      jsonEncode({'state': target, 'confirm': 'VPN_MODE'}),
    );
    final PiRawResponse r;
    try {
      r = await (t as PiOperatorTransport).sendRaw(
        'POST',
        path,
        body: body,
        headers: {
          'Authorization': ArgonOperatorAuth.header(
            token: _operatorToken,
            method: 'POST',
            path: path,
            body: body,
            ts: _now().millisecondsSinceEpoch ~/ 1000,
            nonce: _nonce(),
          ),
        },
      );
    } on PiApiException catch (e) {
      return _vpnFail(VpnCommandIssue.network, e.message);
    }
    if (_disposed) return false;
    final data = r.data;
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    switch (r.status) {
      case 200:
      case 202:
        _absorbVpn(data?['observed']);
        vpnPhase = VpnCommandPhase.verifying;
        vpnMessage = r.status == 202
            ? 'Argon accepted the change · waiting for it to take effect…'
            : 'Confirming with Argon…';
        _emit();
        return _verifyVpn(target);
      case 401:
        return _vpnFail(
          VpnCommandIssue.tokenInvalid,
          'The operator token was not accepted. Enter it again.',
        );
      case 403:
        return _vpnFail(
          VpnCommandIssue.forbidden,
          'Operator authorization required.',
        );
      case 409:
        _absorbVpn(data?['observed']);
        return _vpnFail(
          VpnCommandIssue.busy,
          'A change is already in progress.',
        );
      case 502:
        _absorbVpn(data?['observed']);
        return _vpnFail(
          VpnCommandIssue.upstream,
          text(data?['error']) ?? 'Argon could not apply the change.',
          recovery: text(data?['recovery']),
        );
      case 400:
        return _vpnFail(
          VpnCommandIssue.rejected,
          text(data?['error']) ?? 'Argon rejected the request.',
        );
      default:
        return _vpnFail(
          VpnCommandIssue.network,
          text(data?['error']) ?? 'Argon request failed (${r.status}).',
        );
    }
  }

  Future<bool> _verifyVpn(String target) async {
    for (var i = 0; i < vpnVerifyAttempts; i++) {
      if (i > 0) await Future<void>.delayed(vpnVerifyInterval);
      if (_disposed) return false;
      final t = transport;
      if (t == null) continue;
      try {
        final r = await t.get('/api/v1/vpn', token: _readToken);
        _absorbVpn(r['vpn']);
      } on PiApiException {
        // Keep waiting: the route may blip while the tunnel changes.
      }
      if (_disposed) return false;
      final now = vpn;
      if (now?.mode == target && now?.busy != true) {
        vpnPhase = VpnCommandPhase.confirmed;
        vpnMessage = target == 'on'
            ? 'VPN is on · confirmed by Argon'
            : 'VPN is off · confirmed by Argon';
        _addEvent(
          'vpn',
          target == 'on' ? 'VPN turned on' : 'VPN turned off',
          target == 'on'
              ? 'Household traffic now routes through Surfshark.'
              : 'Household traffic now goes directly via your ISP.',
          'success',
        );
        _lastGateway = null; // refresh the full report promptly
        _emit();
        return true;
      }
      _emit();
    }
    return _vpnFail(
      VpnCommandIssue.unconfirmed,
      'Argon has not confirmed the change yet. Check the VPN status again shortly.',
    );
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
