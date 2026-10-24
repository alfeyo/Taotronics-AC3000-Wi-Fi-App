import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/argon_operator.dart';
import '../services/argon_device_key.dart';
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

/// Direct Router Control: the explicit, temporary mode in which this phone
/// holds the TaoTronics router's single management session.
enum DirectControlPhase {
  /// Argon mode (default): Argon's LAN observer monitors the router.
  off,

  /// Asking Argon for a router control lease.
  requesting,

  /// Lease granted; waiting for Argon's observer to close its router session.
  waitingForObserver,

  /// Connecting with this phone's existing router pairing.
  connecting,

  /// Connected, but the router still serves the previous holder (it hands
  /// the session over about a minute after that holder stops).
  waitingForRouter,

  /// This phone controls the router; router settings are available.
  active,

  /// Releasing the router and returning to Argon mode.
  returning,

  /// The takeover could not proceed; [PiProvider.directMessage] says why.
  failed,
}

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

  /// The phone key differs from the one Argon enrolled or the owner approved.
  keyChanged,
  rateLimited,

  /// Argon does not offer the requested VPN location.
  unknownLocation,

  /// The VPN is off and Argon changes location only while it is on.
  vpnOff,
}

/// Shown when the only route to Argon is the read-only Bluetooth bridge.
const vpnNeedsIpRouteMessage =
    'Connect over Tailscale or HTTPS to change VPN mode';

const vpnLocationNeedsVpnOnMessage = 'Turn the VPN on to change location';

const vpnRateLimitedMessage =
    'Too many VPN requests. Wait a minute, then try again.';

const vpnKeyRegisteredElsewhereMessage =
    'This phone key is registered to a different pairing on Argon. Forget '
    'Argon in Network Hub, pair again, then ask the owner to allow VPN control.';

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
    ArgonDeviceKey? deviceKey,
    this.forgetServerTimeout = const Duration(seconds: 4),
  }) : _deviceKey = deviceKey ?? ArgonDeviceKey(),
       _nonce = nonce ?? ArgonOperatorAuth.nonce,
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
  final ArgonDeviceKey _deviceKey;

  /// Upper bound on the best-effort server key removal during forget().
  final Duration forgetServerTimeout;
  String? _deviceId;

  /// Device id Argon assigned at pairing, and the Keystore alias of this
  /// pairing's key. Neither is secret.
  String? _pairedDeviceId;
  String? _keyAlias;
  int _keyGeneration = -1;
  DateTime? _lastPermissionCheck;
  Future<void>? _permissionCheck;
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
  bool vpnDeviceAllowed = false;
  String? vpnKeyFingerprint;
  DeviceKeyHardware? vpnKeyHardware;
  PiTransport? _secureRoute;
  int _secureGeneration = -1;
  DateTime? _nextSecureAttempt;
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
  DateTime? _lastLive, _lastGateway, _lastSync;
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

  /// Why the last permission check could not complete, if it failed.
  String? vpnPermissionError;

  /// The VPN confirmation flow is open; further taps are ignored.
  bool vpnPrompting = false;

  // Direct Router Control.
  DirectControlPhase directPhase = DirectControlPhase.off;

  /// Progress, blocker or outcome of the current Direct Control step.
  String? directMessage;

  /// The user overrode without Argon coordinating a handover.
  bool directWithoutHandover = false;
  RouterLease? lease;
  DateTime? _leaseRenewedAt, _leaseRenewFailingSince, _directDeadline;
  bool _leaseBusy = false;
  int _directGeneration = 0;

  /// Set when Direct Control ended; cleared once Argon reports fresh router
  /// monitoring again (or after [resumeWatch]).
  DateTime? monitoringResumeSince;
  static const leaseRenewEvery = Duration(seconds: 30);
  static const observerHandoverTimeout = Duration(seconds: 45);
  static const routerConnectTimeout = Duration(seconds: 60);
  static const resumeWatch = Duration(minutes: 3);
  Duration leasePollInterval = const Duration(seconds: 3);

  // VPN exit location.
  VpnLocations? vpnLocations;
  DateTime? vpnLocationsAt;
  bool vpnLocationsLoading = false;
  String? vpnLocationsError;
  VpnCommandPhase locationPhase = VpnCommandPhase.idle;
  VpnCommandIssue locationIssue = VpnCommandIssue.none;

  /// Id of the location being switched to.
  String? locationTarget;
  String? locationMessage;
  String? locationRecovery;

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

  /// True when Argon's own report says it holds the router management session.
  ///
  /// Argon's `router.monitoring.state == "connected"` is **not** ownership: on
  /// the live system it means "router device monitoring connected", fed by a
  /// LAN observer (`source: lan-observer:<host>`), or by this phone's own
  /// snapshots. Treating that as ownership froze the app in read-only mode on
  /// 2026-10-22 while Argon controlled nothing.
  ///
  /// Only an explicit ownership field counts, so Phase 1 stays dormant until
  /// Argon actually reports that it holds the router (Phase 2 adds
  /// `router.owner = "argon"`). No API contract is required today.
  bool routerOwnedByArgon = false;

  /// Pure parser, exported for tests and for callers that hold a raw payload.
  static bool reportsRouterOwnership(Object? rawGateway) {
    final router = rawGateway is Map ? rawGateway['router'] : null;
    if (router is! Map) return false;

    if (_isArgon(router['owner']) || _isArgon(router['control'])) return true;
    final monitoring = router['monitoring'];
    if (monitoring is Map) {
      return _isArgon(monitoring['owner']) || _isArgon(monitoring['control']);
    }
    return false;
  }

  static bool _isArgon(Object? value) => '$value'.toLowerCase() == 'argon';

  /// Hands Argon's claim to `RouterProvider`, which stops bidding for the
  /// router and switches the screens to read-only.
  void _applyRouterOwnership(Map<String, dynamic> payload) {
    final owned = reportsRouterOwnership(payload);
    routerOwnedByArgon = owned;
    _router.applyPiOwnership(ownedByArgon: owned);
  }

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
      _pairedDeviceId = prefs.getString('argon.v2.deviceId');
      _keyAlias = prefs.getString('argon.v2.keyAlias');
      _alertCursor = prefs.getInt('argon.v2.alertCursor') ?? 0;
      // A credential provisioned earlier (shared token or paired device) is
      // used automatically.
      _token = await _storage.read(key: companionKey) ?? '';
      await _storage.delete(
        key: operatorKey,
      ); // retire the broad operator credential
    } catch (_) {
      _token = '';

      lastError = 'Saved Network Hub settings could not be read securely.';
    }
    _emit();
    unawaited(_pruneKeys());
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
    await put('argon.v2.deviceId', _pairedDeviceId);
    await put('argon.v2.keyAlias', _keyAlias);
    await prefs.setBool('argon.v2.sync', syncEnabled);
    await prefs.setInt('argon.v2.alertCursor', _alertCursor);
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
        if (directPhase == DirectControlPhase.active ||
            directPhase == DirectControlPhase.waitingForRouter) {
          // Renew at once: a lease that lapsed in the background ends
          // Direct Control instead of fighting Argon's observer.
          _foregroundResumed = true;
          _leaseRenewedAt = null;
        }
        _start();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // No background work: stop timers and discard in-flight results.
        _foreground = false;
        _invalidateConnection();
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _networkChanged() {
    _invalidateConnection();
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
    _advanceDirect(now);
    _watchMonitoringResume(now);
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
    if (transport!.kind != PiTransportKind.bluetooth &&
        (_lastAlerts == null || now.difference(_lastAlerts!) >= alertsEvery)) {
      jobs.add(_pollAlerts());
    }
    await Future.wait(jobs);
  }

  /// Re-run discovery now (e.g. Manage connection > Retry).
  Future<void> reconnect() async {
    _invalidateConnection();
    _attempt = 0;
    _nextDiscovery = null;
    transport = null;
    await discover();
  }

  /// Refresh network statistics and device inventory now (both come from
  /// the gateway report and the live sample).
  Future<void> refreshNow() async {
    if (transport == null) return reconnect();
    _lastLive = _lastGateway = null;
    await tick();
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
    if (e is PiSecureRouteUnavailable) {
      lastError = e.message;
      _emit();
      return;
    }
    if (e.status == null) _dropSecureRoute();
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
      final route = _readToken != null && t.kind == PiTransportKind.lan
          ? await _secureTransport()
          : t;
      final r = await route.get('/api/v1/live', token: _readToken);
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
      final route = _readToken != null && t.kind == PiTransportKind.lan
          ? await _secureTransport()
          : t;
      final r = await route.get(
        '/api/v1/gateway',
        token: _readToken,
        timeout: const Duration(seconds: 15),
      );
      if (generation != _generation || transport != t) return;
      gateway = r;
      gatewayAt = _now();
      lastContact = gatewayAt;
      _failures = 0;
      _applyRouterOwnership(r);
      _mergeServerEvents(r['events']);
      unawaited(refreshVpnPermission(force: false));
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
    // Argon mode: the observer feeds Argon; this phone has nothing to share.
    if (_router.isArgonMode) {
      syncError = null;
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
      // Cached router data only. Phase 1 removed the 5-minute
      // refreshWanSettings()/loadGuestWifiSettings() pair that ran here: the Pi
      // link was issuing router commands of its own, competing for the
      // router's single management session. Fields whose cache has expired
      // are sent as null (the snapshot schema already allows unavailable).
      final snapshot = buildPiRouterSnapshot(_router, now: _now());
      if (snapshot == null) {
        syncError = 'Waiting for a fresh router device list.';
        return;
      }
      try {
        final secure = await _secureTransport();
        if (generation != _generation || !_foreground) return;
        final r = await secure.post(
          '/api/v1/router/snapshot',
          snapshot,
          token: _token,
        );
        if (generation != _generation) return;
        sharedAt = _now();
        sharedCount = (r['count'] as num?)?.toInt();
        syncError = null;
      } on PiApiException catch (e) {
        if (e.status == null) _dropSecureRoute();
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
    final secure = await _secureTransport();
    final r = await secure.post('/api/v1/pairing/complete', {
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
    _invalidateConnection();
    _token = token;
    _deviceId = null;
    final deviceId = r['deviceId'];
    _pairedDeviceId = deviceId is String ? deviceId : null;
    _keyAlias = null;
    try {
      if (_pairedDeviceId != null && trustedId != null) {
        _keyAlias = ArgonDeviceKey.aliasFor(trustedId!, _pairedDeviceId!);
      }
    } on ArgumentError {
      _pairedDeviceId = null;
    }
    vpnKeyFingerprint = null;
    vpnKeyHardware = null;
    _keyGeneration = -1;
    vpnDeviceAllowed = false;
    _lastPermissionCheck = null;
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
    unawaited(_pruneKeys()); // keys of earlier pairings
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

  /// Removes this phone's credential, its signing key and the trusted Argon
  /// identity. Argon is first asked (best effort, bounded) to drop the
  /// enrolled key and its grants; forgetting never waits on the network
  /// longer than [forgetServerTimeout].
  Future<void> forget() async {
    final token = _token;
    final alias = _keyAlias;
    if (token.isNotEmpty) await _deleteServerKey(token);
    if (alias != null) {
      try {
        await _deviceKey.delete(alias);
      } catch (_) {
        // Pruned below or on the next start.
      }
    }
    _invalidateConnection();
    _deviceId = null;
    _pairedDeviceId = null;
    _keyAlias = null;
    vpnKeyFingerprint = null;
    vpnKeyHardware = null;
    vpnPermissionError = null;
    _keyGeneration = -1;
    vpnDeviceAllowed = false;
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
    await _pruneKeys();
    await reconnect();
  }

  Future<void> _deleteServerKey(String token) async {
    Future<void> send() async {
      final t = await _secureTransport();
      if (t is! PiOperatorTransport) return;
      await (t as PiOperatorTransport).sendRaw(
        'DELETE',
        '/api/v1/pairing/key',
        body: const [],
        headers: {'Authorization': 'Bearer $token'},
        timeout: forgetServerTimeout,
      );
    }

    try {
      await send().timeout(forgetServerTimeout);
    } catch (_) {
      // Best effort: the owner can still revoke this phone on Argon.
    }
  }

  /// Deletes Keystore keys that belong to no current pairing. While a legacy
  /// pairing has not resolved its alias yet, nothing is deleted.
  Future<void> _pruneKeys() async {
    if (_token.isNotEmpty && _keyAlias == null) return;
    try {
      for (final alias in await _deviceKey.list()) {
        if (alias.startsWith(ArgonDeviceKey.aliasPrefix) &&
            (_token.isEmpty || alias != _keyAlias)) {
          await _deviceKey.delete(alias);
        }
      }
    } catch (_) {
      // Keystore unavailable (or not Android): retried on the next start.
    }
  }

  /// The Keystore alias for the current pairing. A pairing made before keys
  /// were per pairing keeps its existing per-install key (and its grant).
  Future<String> _currentKeyAlias() async {
    final instance = trustedId!;
    final current = _keyAlias;
    if (current != null &&
        current.startsWith('${ArgonDeviceKey.aliasPrefix}$instance')) {
      return current;
    }
    final legacy = ArgonDeviceKey.legacyAlias(instance);
    final id = _pairedDeviceId;
    final alias = id == null || await _deviceKey.exists(legacy)
        ? legacy
        : ArgonDeviceKey.aliasFor(instance, id);
    _keyAlias = alias;
    await _savePrefs();
    return alias;
  }

  /// Owner-facing guidance when this phone has no VPN grant.
  String get vpnNotGrantedMessage {
    final fp = vpnKeyFingerprint;
    return 'Ask the Argon owner to allow VPN control for this phone in '
        'Devices → Phone synchronization'
        '${fp == null ? '.' : ' (key fingerprint: ${ArgonDeviceKey.shortFingerprint(fp)})'}';
  }

  String get vpnKeyChangedMessage {
    final fp = vpnKeyFingerprint;
    return 'This phone\'s key no longer matches the one the Argon owner '
        'approved. Ask the owner to allow VPN control again'
        '${fp == null ? '.' : ' (key fingerprint: ${ArgonDeviceKey.shortFingerprint(fp)})'}';
  }

  /// Non-secret label for where the signing key lives.
  String? get vpnKeyHardwareLabel => switch (vpnKeyHardware) {
    DeviceKeyHardware.strongBox => 'Hardware key: StrongBox',
    DeviceKeyHardware.tee => 'Hardware key: Secure hardware (TEE)',
    DeviceKeyHardware.software => 'Hardware key: Not hardware-backed',
    null => null,
  };

  (VpnCommandIssue, String) _issueFor(PiApiException e) => switch (e) {
    PiSecureRouteUnavailable() => (VpnCommandIssue.network, e.message),
    PiApiException(status: 409) => (
      VpnCommandIssue.keyChanged,
      vpnKeyRegisteredElsewhereMessage,
    ),
    PiApiException(status: 429) => (
      VpnCommandIssue.rateLimited,
      vpnRateLimitedMessage,
    ),
    PiApiException(status: 401 || 403) => (
      VpnCommandIssue.tokenInvalid,
      'Phone authorization was rejected. Refresh permissions or pair again.',
    ),
    _ => (VpnCommandIssue.network, e.message),
  };

  // ------------------------------------------------------------ VPN control

  bool get vpnInFlight =>
      vpnPhase == VpnCommandPhase.sending ||
      vpnPhase == VpnCommandPhase.verifying;
  bool get vpnControlRoute =>
      connected &&
      transport is PiOperatorTransport &&
      transport?.kind != PiTransportKind.bluetooth;

  // Private LAN HTTP remains available for public monitoring. Secrets and
  // privileged commands always use a normally verified HTTPS or Tailscale route.
  Future<PiTransport> _secureTransport() async {
    final t = transport;
    if (t != null &&
        (t.kind == PiTransportKind.https ||
            t.kind == PiTransportKind.tailscale)) {
      return t;
    }
    if (_secureRoute != null && _secureGeneration == _generation) {
      return _secureRoute!;
    }
    if (_nextSecureAttempt != null && _now().isBefore(_nextSecureAttempt!)) {
      throw const PiSecureRouteUnavailable();
    }
    final generation = _generation;
    for (final uri in [
      if (manualEndpoint?.scheme == 'https') manualEndpoint!,
      tailscaleDefault,
    ]) {
      final candidate = _http(uri);
      try {
        final id = PiIdentity.parse(await candidate.get('/api/v1/identity'));
        if (trustedId != null &&
            id.instanceId == trustedId &&
            generation == _generation &&
            !_disposed) {
          _secureGeneration = generation;
          return _secureRoute = candidate;
        }
      } on PiApiException {
        continue;
      }
    }
    _nextSecureAttempt = _now().add(const Duration(seconds: 30));
    throw const PiSecureRouteUnavailable();
  }

  Future<void> _enrollKey(PiTransport t) async {
    if (_deviceId != null && _keyGeneration == _generation) return;
    final instance = trustedId;
    if (instance == null || !paired) {
      throw const PiApiException('Pair this phone first.');
    }
    final generation = _generation;
    final alias = await _currentKeyAlias();
    final publicKey = await _deviceKey.publicKey(alias);
    final fingerprint = ArgonDeviceKey.fingerprint(publicKey);
    final r = await t.post('/api/v1/pairing/key', {
      'publicKey': publicKey,
    }, token: _token);
    if (generation != _generation || _disposed) {
      throw const PiApiException('Connection changed. Retry.');
    }
    if (r['id'] is! String) {
      throw const PiApiException('Phone key registration failed.');
    }
    _deviceId = r['id'] as String;
    // Computed on the phone, so the owner can compare it with Argon's value.
    vpnKeyFingerprint = fingerprint;
    if (_pairedDeviceId == null) {
      _pairedDeviceId = _deviceId;
      await _savePrefs();
    }
    try {
      vpnKeyHardware = await _deviceKey.hardware(alias);
    } catch (_) {
      vpnKeyHardware = null;
    }
    _keyGeneration = generation;
  }

  void _dropSecureRoute() {
    _secureRoute = null;
    _secureGeneration = -1;
  }

  void _invalidateConnection() {
    _generation++;
    _nextSecureAttempt = null;
    _dropSecureRoute();
    _lastPermissionCheck = null;
    if (vpnInFlight) {
      vpnPhase = VpnCommandPhase.failed;
      vpnIssue = VpnCommandIssue.unconfirmed;
      vpnMessage =
          'Connection changed while checking the VPN. Refresh its actual state before retrying.';
    }
    if (locationInFlight) {
      locationPhase = VpnCommandPhase.failed;
      locationIssue = VpnCommandIssue.unconfirmed;
      locationMessage =
          'Connection changed while checking the VPN location. Refresh before retrying.';
      locationRecovery = null;
    }
  }

  Future<void> refreshVpnPermission({bool force = true}) async {
    if (_permissionCheck != null) {
      await _permissionCheck;
      return;
    }
    if (!force &&
        _lastPermissionCheck != null &&
        _now().difference(_lastPermissionCheck!).inSeconds < 60) {
      return;
    }
    _lastPermissionCheck = _now();
    _permissionCheck = _checkVpnPermission();
    try {
      await _permissionCheck;
    } finally {
      _permissionCheck = null;
    }
  }

  Future<void> _checkVpnPermission() async {
    var allowed = false;
    if (!paired) {
      vpnDeviceAllowed = false;
      return;
    }
    final generation = _generation;
    String? error;
    try {
      final t = await _secureTransport();
      await _enrollKey(t);
      final r = await t.get('/api/v1/vpn', token: _token);
      if (generation != _generation || _disposed) return;
      if (r['deviceAllowed'] == true && t is PiOperatorTransport) {
        const path = '/api/v1/vpn/authorize';
        final body = utf8.encode('{}');
        final proof = await (t as PiOperatorTransport).sendRaw(
          'POST',
          path,
          body: body,
          headers: {
            'Authorization': await _deviceKey.header(
              alias: _keyAlias!,
              id: _deviceId!,
              method: 'POST',
              path: path,
              ts: _now().millisecondsSinceEpoch ~/ 1000,
              nonce: _nonce(),
              body: body,
            ),
          },
        );
        if (generation != _generation || _disposed) return;
        allowed = proof.status == 200 && proof.data?['authorized'] == true;
      }
      _absorbVpn(r['vpn']);
    } on PiApiException catch (e) {
      if (e.status == null) _dropSecureRoute();
      error = _issueFor(e).$2;
    } catch (_) {
      _dropSecureRoute();
      error =
          'Phone signing key is unavailable. Retry after unlocking the phone.';
    }
    if (generation != _generation || _disposed) return;
    vpnDeviceAllowed = allowed;
    vpnPermissionError = error;
    _emit();
  }

  void _resetVpnCommand() {
    if (vpnInFlight) return;
    vpnPhase = VpnCommandPhase.idle;
    vpnIssue = VpnCommandIssue.none;
    vpnMessage = vpnRecovery = vpnTarget = null;
  }

  void setVpnPrompting(bool value) {
    if (vpnPrompting == value) return;
    vpnPrompting = value;
    _emit();
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
    if (vpnInFlight || locationInFlight || _disposed) return false;
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
    if (!paired) {
      return _vpnFail(
        VpnCommandIssue.needsToken,
        'Pair this phone once, then ask the Argon owner to allow VPN control.',
      );
    }
    vpnPhase = VpnCommandPhase.sending;
    vpnMessage = on ? 'Turning VPN on…' : 'Turning VPN off…';
    _emit();
    final generation = _generation;
    const path = '/api/v1/vpn';
    final body = utf8.encode(
      jsonEncode({'state': target, 'confirm': 'VPN_MODE'}),
    );
    final PiRawResponse r;
    try {
      final signed = await _signedPost(path, body, generation);
      if (signed == null) return false;
      r = signed;
    } on PiApiException catch (e) {
      if (e.status == null) _dropSecureRoute();
      final (issue, message) = _issueFor(e);
      return _vpnFail(issue, message);
    } catch (_) {
      return _vpnFail(
        VpnCommandIssue.network,
        'Phone signing key is unavailable. Retry after unlocking the phone.',
      );
    }
    if (_disposed || generation != _generation) return false;
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
        return _verifyVpn(target, generation);
      case 401:
        return _vpnFail(
          VpnCommandIssue.tokenInvalid,
          'Phone authorization was rejected. Refresh permissions or pair again.',
        );
      case 403:
        vpnDeviceAllowed = false;
        return _vpnFail(VpnCommandIssue.forbidden, vpnNotGrantedMessage);
      case 409:
        _absorbVpn(data?['observed']);
        final reason = '${data?['code'] ?? ''} ${data?['error'] ?? ''}'
            .toLowerCase();
        if (reason.contains('key')) {
          vpnDeviceAllowed = false;
          _keyGeneration = -1; // re-enroll on the next attempt
          return _vpnFail(VpnCommandIssue.keyChanged, vpnKeyChangedMessage);
        }
        return _vpnFail(
          VpnCommandIssue.busy,
          'A change is already in progress.',
        );
      case 429:
        return _vpnFail(VpnCommandIssue.rateLimited, vpnRateLimitedMessage);
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

  /// Sends [body] to [path] signed with this pairing's `ArgonDevice v2` key
  /// over a secure route. Null when the connection changed meanwhile.
  Future<PiRawResponse?> _signedPost(
    String path,
    List<int> body,
    int generation,
  ) async {
    final secure = await _secureTransport();
    if (generation != _generation || _disposed) return null;
    await _enrollKey(secure);
    if (generation != _generation || _disposed) return null;
    return (secure as PiOperatorTransport).sendRaw(
      'POST',
      path,
      body: body,
      headers: {
        'Authorization': await _deviceKey.header(
          alias: _keyAlias!,
          id: _deviceId!,
          method: 'POST',
          path: path,
          body: body,
          ts: _now().millisecondsSinceEpoch ~/ 1000,
          nonce: _nonce(),
        ),
      },
    );
  }

  // ----------------------------------------------------- VPN exit location

  bool get locationInFlight =>
      locationPhase == VpnCommandPhase.sending ||
      locationPhase == VpnCommandPhase.verifying;

  /// Reads `/api/v1/vpn/locations` with the companion credential, the same
  /// way as the gateway report (secure route when a credential travels).
  Future<VpnLocations> _readLocations() async {
    final t = transport;
    if (!connected || t == null) {
      throw const PiApiException('Network Hub is not reachable right now.');
    }
    final token = paired ? _token : _readToken;
    final route = token != null && t.kind == PiTransportKind.lan
        ? await _secureTransport()
        : t;
    final r = await route.get('/api/v1/vpn/locations', token: token);
    final parsed = VpnLocations.parse(r);
    if (parsed == null) {
      throw const PiApiException('Argon returned an invalid location list.');
    }
    return parsed;
  }

  /// Refreshes the exit-location list. Unless [force], skips when the list
  /// is under 30 s old. Failures only affect the location list.
  Future<void> refreshVpnLocations({bool force = true}) async {
    if (vpnLocationsLoading || _disposed) return;
    if (!force &&
        vpnLocationsAt != null &&
        _now().difference(vpnLocationsAt!).inSeconds < 30) {
      return;
    }
    final generation = _generation;
    vpnLocationsLoading = true;
    _emit();
    try {
      final list = await _readLocations();
      if (generation != _generation || _disposed) return;
      vpnLocations = list;
      vpnLocationsAt = _now();
      vpnLocationsError = null;
    } on PiApiException catch (e) {
      if (generation != _generation || _disposed) return;
      if (e is PiSecureRouteUnavailable) {
        vpnLocationsError = e.message;
      } else if (e.status == 404) {
        vpnLocationsError = 'This Argon does not offer location selection yet.';
      } else {
        vpnLocationsError = 'Could not load VPN locations: ${e.message}';
      }
    } finally {
      vpnLocationsLoading = false;
      _emit();
    }
  }

  void dismissLocationResult() {
    if (locationInFlight) return;
    locationPhase = VpnCommandPhase.idle;
    locationIssue = VpnCommandIssue.none;
    locationMessage = locationRecovery = locationTarget = null;
    _emit();
  }

  bool _locationFail(
    VpnCommandIssue issue,
    String message, {
    String? recovery,
  }) {
    locationPhase = VpnCommandPhase.failed;
    locationIssue = issue;
    locationMessage = message;
    locationRecovery = recovery;
    _emit();
    return false;
  }

  String _locationLabel(String id) =>
      vpnLocations?.locations.where((l) => l.id == id).firstOrNull?.label ?? id;

  /// Switches the VPN exit location with the same device-key authority as
  /// the mode switch, then re-reads Argon until it reports the new location.
  /// Returns true only when confirmed. Never overlaps with another location
  /// or mode change.
  Future<bool> setVpnLocation(String id) async {
    if (locationInFlight || vpnInFlight || _disposed) return false;
    locationTarget = id;
    locationMessage = locationRecovery = null;
    locationIssue = VpnCommandIssue.none;
    final t = transport;
    if (!connected || t == null) {
      return _locationFail(
        VpnCommandIssue.unreachable,
        'Network Hub is not reachable right now.',
      );
    }
    if (t.kind == PiTransportKind.bluetooth || t is! PiOperatorTransport) {
      return _locationFail(
        VpnCommandIssue.bluetooth,
        'Connect over Tailscale or HTTPS to change VPN location',
      );
    }
    if (!paired) {
      return _locationFail(
        VpnCommandIssue.needsToken,
        'Pair this phone once, then ask the Argon owner to allow VPN control.',
      );
    }
    final known = vpnLocations;
    if (known != null && known.vpnOff && !known.canSwitchWhileOff) {
      return _locationFail(
        VpnCommandIssue.vpnOff,
        vpnLocationNeedsVpnOnMessage,
      );
    }
    final label = _locationLabel(id);
    locationPhase = VpnCommandPhase.sending;
    locationMessage = 'Switching to $label…';
    _emit();
    final generation = _generation;
    const path = '/api/v1/vpn/location';
    final body = utf8.encode(
      jsonEncode({'location': id, 'confirm': 'VPN_LOCATION'}),
    );
    final PiRawResponse r;
    try {
      final signed = await _signedPost(path, body, generation);
      if (signed == null) return false;
      r = signed;
    } on PiApiException catch (e) {
      if (e.status == null) _dropSecureRoute();
      final (issue, message) = _issueFor(e);
      return _locationFail(issue, message);
    } catch (_) {
      return _locationFail(
        VpnCommandIssue.network,
        'Phone signing key is unavailable. Retry after unlocking the phone.',
      );
    }
    if (_disposed || generation != _generation) return false;
    final data = r.data;
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    switch (r.status) {
      case 200:
      case 202:
        locationPhase = VpnCommandPhase.verifying;
        locationMessage = r.status == 202
            ? 'Argon accepted the change · waiting for $label…'
            : 'Confirming $label with Argon…';
        _emit();
        return _verifyLocation(id, label, generation);
      case 400:
        unawaited(refreshVpnLocations());
        return _locationFail(
          VpnCommandIssue.unknownLocation,
          text(data?['error']) ??
              'Argon does not offer that location. Refresh the list and '
                  'choose another.',
        );
      case 401:
        return _locationFail(
          VpnCommandIssue.tokenInvalid,
          'Phone authorization was rejected. Refresh permissions or pair again.',
        );
      case 403:
        vpnDeviceAllowed = false;
        return _locationFail(VpnCommandIssue.forbidden, vpnNotGrantedMessage);
      case 409:
        final reason = '${data?['code'] ?? ''} ${data?['error'] ?? ''}'
            .toLowerCase();
        if (reason.contains('key')) {
          vpnDeviceAllowed = false;
          _keyGeneration = -1; // re-enroll on the next attempt
          return _locationFail(
            VpnCommandIssue.keyChanged,
            vpnKeyChangedMessage,
          );
        }
        if (reason.contains('turn the vpn on') ||
            reason.contains('vpn_off') ||
            reason.contains('vpn is off')) {
          unawaited(refreshVpnLocations());
          return _locationFail(
            VpnCommandIssue.vpnOff,
            vpnLocationNeedsVpnOnMessage,
          );
        }
        return _locationFail(
          VpnCommandIssue.busy,
          text(data?['error']) ?? 'A VPN change is already in progress.',
        );
      case 429:
        return _locationFail(
          VpnCommandIssue.rateLimited,
          vpnRateLimitedMessage,
        );
      case 502:
        unawaited(refreshVpnLocations());
        return _locationFail(
          VpnCommandIssue.upstream,
          text(data?['error']) ?? 'Argon could not switch location.',
          recovery: text(data?['recovery']),
        );
      default:
        return _locationFail(
          VpnCommandIssue.network,
          text(data?['error']) ?? 'Argon request failed (${r.status}).',
        );
    }
  }

  Future<bool> _verifyLocation(String id, String label, int generation) async {
    for (var i = 0; i < vpnVerifyAttempts; i++) {
      if (i > 0) await Future<void>.delayed(vpnVerifyInterval);
      if (_disposed || generation != _generation) return false;
      try {
        final list = await _readLocations();
        if (generation != _generation || _disposed) return false;
        vpnLocations = list;
        vpnLocationsAt = _now();
        vpnLocationsError = null;
      } on PiApiException {
        _dropSecureRoute();
        // Keep waiting: the route may blip while the tunnel reconnects.
        continue;
      }
      final now = vpnLocations!;
      if (now.current?.id == id &&
          !now.busy &&
          (now.mode != 'on' || now.state == 'connected' || now.state == 'on')) {
        locationPhase = VpnCommandPhase.confirmed;
        locationMessage =
            'Exit location is ${now.current!.label} · '
            'confirmed by Argon';
        _addEvent(
          'vpn',
          'VPN location changed',
          'Household VPN traffic now exits via ${now.current!.label}.',
          'success',
        );
        unawaited(_refreshVpnObservation(generation));
        _lastGateway = null; // refresh the full report promptly
        _emit();
        return true;
      }
      _emit();
    }
    return _locationFail(
      VpnCommandIssue.unconfirmed,
      'Argon has not confirmed $label yet. Check the VPN location again '
      'shortly.',
    );
  }

  /// Best-effort /api/v1/vpn read so the card shows the new exit location.
  Future<void> _refreshVpnObservation(int generation) async {
    try {
      final t = await _secureTransport();
      final r = await t.get('/api/v1/vpn', token: _token);
      if (generation != _generation || _disposed) return;
      _absorbVpn(r['vpn']);
      _emit();
    } on PiApiException {
      // The next gateway poll carries it anyway.
    }
  }

  Future<bool> _verifyVpn(String target, int generation) async {
    for (var i = 0; i < vpnVerifyAttempts; i++) {
      if (i > 0) await Future<void>.delayed(vpnVerifyInterval);
      if (_disposed) return false;
      if (generation != _generation) return false;
      try {
        final t = await _secureTransport();
        final r = await t.get('/api/v1/vpn', token: _token);
        if (generation != _generation || _disposed) return false;
        _absorbVpn(r['vpn']);
      } on PiApiException {
        _dropSecureRoute();
        // Keep waiting: the route may blip while the tunnel changes.
      }
      if (_disposed) return false;
      final now = vpn;
      if (now?.mode == target &&
          now?.busy != true &&
          (target == 'on'
              ? now?.connected == true
              : (now?.state == 'disconnected' || now?.state == 'off')) &&
          now?.healthOk != false) {
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
        if (vpnLocations != null) unawaited(refreshVpnLocations());
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

  // --------------------------------------------------- Direct Router Control

  /// A handover can be coordinated: Argon reachable over IP and this phone
  /// paired with an enrolled key.
  bool get canCoordinateHandover =>
      connected &&
      paired &&
      transport is PiOperatorTransport &&
      transport?.kind != PiTransportKind.bluetooth;

  bool get directInProgress =>
      directPhase != DirectControlPhase.off &&
      directPhase != DirectControlPhase.failed;

  /// Why Argon cannot coordinate a handover right now (null when it can).
  String? get handoverBlocker {
    if (!connected) {
      return 'Argon is not reachable, so its observer cannot be asked to '
          'release the router.';
    }
    if (transport?.kind == PiTransportKind.bluetooth) {
      return 'Argon is reachable only over Bluetooth, which cannot coordinate '
          'router control.';
    }
    if (!paired) {
      return 'This phone is not paired with Argon, so it cannot ask the '
          'observer to release the router. Pair it in Network Hub.';
    }
    return null;
  }

  void _directFail(String message, {bool release = true}) {
    directPhase = DirectControlPhase.failed;
    directMessage = message;
    if (release && lease != null && !directWithoutHandover) {
      unawaited(_leaseCommand('release').then((_) {}, onError: (_) {}));
    }
    lease = null;
    _emit();
  }

  void dismissDirectResult() {
    if (directPhase != DirectControlPhase.failed) return;
    directPhase = DirectControlPhase.off;
    directMessage = null;
    _emit();
  }

  /// Takes Direct Router Control: asks Argon's observer to step aside (a
  /// lease), waits until it has, then connects with this phone's existing
  /// router pairing. With [withoutHandover] (only offered when Argon cannot
  /// coordinate) the phone connects directly; the observer then backs off on
  /// its own when the router keeps closing its sessions.
  /// Household internet, VPN, NAT, DHCP, Tailscale and traffic accounting on
  /// Argon are never touched.
  Future<bool> takeDirectControl({bool withoutHandover = false}) async {
    if (directInProgress || _disposed) return false;
    final gen = ++_directGeneration;
    directWithoutHandover = withoutHandover;
    lease = null;
    if (!withoutHandover) {
      final blocker = handoverBlocker;
      if (blocker != null) {
        _directFail(blocker, release: false);
        return false;
      }
      directPhase = DirectControlPhase.requesting;
      directMessage = 'Asking Argon to release the router…';
      _emit();
      final PiRawResponse? r;
      try {
        r = await _leaseCommand('acquire');
      } on PiApiException catch (e) {
        if (gen != _directGeneration) return false;
        _directFail(e.message, release: false);
        return false;
      } catch (_) {
        if (gen != _directGeneration) return false;
        _directFail(
          'Phone signing key is unavailable. Unlock the phone and try again.',
          release: false,
        );
        return false;
      }
      if (gen != _directGeneration || _disposed) return false;
      if (r == null) {
        _directFail('Connection to Argon changed. Try again.', release: false);
        return false;
      }
      if (r.status != 200) {
        _directFail(_leaseError(r), release: false);
        return false;
      }
      lease = RouterLease.parse(r.data?['lease']);
      directPhase = DirectControlPhase.waitingForObserver;
      directMessage =
          'Waiting for Argon\'s observer to close its router '
          'session…';
      _emit();
      final deadline = _now().add(observerHandoverTimeout);
      while (lease?.handedOver != true) {
        if (_now().isAfter(deadline)) {
          _directFail(
            'Argon\'s observer did not release the router within '
            '${observerHandoverTimeout.inSeconds} s. Argon keeps monitoring; '
            'nothing was changed.',
          );
          return false;
        }
        await Future<void>.delayed(leasePollInterval);
        if (gen != _directGeneration || _disposed) return false;
        try {
          final view = RouterLease.parse(
            (await _readPath('/api/v1/router/lease'))['lease'],
          );
          if (gen != _directGeneration || _disposed) return false;
          if (view != null) lease = view;
          if (view != null && !view.active) {
            _directFail('The router control lease ended unexpectedly.');
            return false;
          }
        } on PiApiException {
          // Keep waiting until the deadline.
        }
        _emit();
      }
      _leaseRenewedAt = _now();
      _leaseRenewFailingSince = null;
    }
    directPhase = DirectControlPhase.connecting;
    directMessage = 'Connecting with this phone\'s router pairing…';
    _directDeadline = _now().add(routerConnectTimeout);
    _addEvent(
      'direct',
      'Direct router control',
      withoutHandover
          ? 'Connecting to the router without an Argon handover.'
          : 'Argon\'s observer released the router; this phone is connecting.',
      'info',
    );
    _emit();
    await _router.enterDirectMode();
    if (gen != _directGeneration) return false;
    _advanceDirect(_now());
    return true;
  }

  /// Leaves Direct Router Control: stops phone-side router polling, closes the
  /// MQTT session, releases the lease and resumes Argon-backed screens. Never
  /// clears the router pairing.
  Future<void> returnToArgon({String? reason}) async {
    if (directPhase == DirectControlPhase.off ||
        directPhase == DirectControlPhase.returning) {
      return;
    }
    _directGeneration++;
    directPhase = DirectControlPhase.returning;
    directMessage = 'Releasing the router…';
    _emit();
    await _router.exitDirectMode();
    if (lease != null && !directWithoutHandover) {
      try {
        await _leaseCommand('release').timeout(const Duration(seconds: 10));
      } catch (_) {
        // The lease expires on its own within two minutes.
      }
    }
    lease = null;
    directWithoutHandover = false;
    _leaseRenewedAt = _leaseRenewFailingSince = _directDeadline = null;
    directPhase = DirectControlPhase.off;
    directMessage = null;
    monitoringResumeSince = _now();
    _lastGateway = _lastLive = null; // refresh the Argon view promptly
    _addEvent(
      'direct',
      'Back in Argon mode',
      reason ?? 'This phone released the router; Argon\'s observer resumes.',
      reason == null ? 'success' : 'warning',
    );
    _emit();
    unawaited(tick());
  }

  /// One scheduler step of the Direct Control state machine.
  void _advanceDirect(DateTime now) {
    switch (directPhase) {
      case DirectControlPhase.connecting:
      case DirectControlPhase.waitingForRouter:
      case DirectControlPhase.active:
        break;
      default:
        return;
    }
    if (!_router.isDirectMode) {
      directPhase = DirectControlPhase.off;
      directMessage = null;
      _emit();
      return;
    }
    final before = directPhase;
    if (_router.isConnected && !_router.managedElsewhere) {
      directPhase = DirectControlPhase.active;
      directMessage = null;
      if (before != DirectControlPhase.active) {
        _addEvent(
          'direct',
          'Direct router control active',
          'Router settings can be changed from this phone. Return to Argon '
              'mode when you are done.',
          'success',
        );
      }
    } else if (_router.isConnected) {
      directPhase = DirectControlPhase.waitingForRouter;
      directMessage =
          'The router is still serving its previous controller. '
          'It hands over about a minute after that session stops.';
    } else if (before == DirectControlPhase.connecting &&
        _directDeadline != null &&
        now.isAfter(_directDeadline!) &&
        !_router.isReconnecting) {
      final why = _router.errorMessage;
      unawaited(
        returnToArgon(
          reason:
              'Direct control could not connect to the router'
              '${why == null ? '.' : ': $why'}',
        ),
      );
      return;
    }
    if (directPhase != before) _emit();
    _renewLease(now);
  }

  void _renewLease(DateTime now) {
    if (directWithoutHandover ||
        lease == null ||
        _leaseBusy ||
        (_leaseRenewedAt != null &&
            now.difference(_leaseRenewedAt!) < leaseRenewEvery)) {
      return;
    }
    _leaseBusy = true;
    final gen = _directGeneration;
    _leaseCommand('renew')
        .then((r) {
          if (gen != _directGeneration) return;
          if (r != null && r.status == 200) {
            lease = RouterLease.parse(r.data?['lease']) ?? lease;
            _leaseRenewedAt = _now();
            _leaseRenewFailingSince = null;
          } else if (r != null && r.status == 409) {
            unawaited(
              returnToArgon(
                reason: _foregroundResumed
                    ? 'Direct control expired while TT Router was in the '
                          'background. Argon monitors the router again.'
                    : _leaseError(r),
              ),
            );
          } else {
            _leaseRenewFailingSince ??= _now();
          }
        })
        .catchError((Object _) {
          if (gen == _directGeneration) _leaseRenewFailingSince ??= _now();
        })
        .whenComplete(() {
          _leaseBusy = false;
          _foregroundResumed = false;
          _emit();
        });
  }

  bool _foregroundResumed = false;

  /// Renewals have failed for a while; the lease may lapse and Argon's
  /// observer may resume.
  bool get leaseAtRisk =>
      _leaseRenewFailingSince != null &&
      _now().difference(_leaseRenewFailingSince!).inSeconds >= 60;

  void _watchMonitoringResume(DateTime now) {
    final since = monitoringResumeSince;
    if (since == null) return;
    final view = routerView;
    if (view?.live == true &&
        view?.observedAt != null &&
        view!.observedAt!.isAfter(since)) {
      monitoringResumeSince = null;
      _addEvent(
        'monitoring',
        'Argon monitoring resumed',
        'Router data from ${view.sourceLabel} is current again.',
        'success',
      );
      _emit();
    } else if (now.difference(since) > resumeWatch) {
      monitoringResumeSince = null;
      _addEvent(
        'monitoring',
        'Argon monitoring has not resumed',
        'No fresh router observation for ${resumeWatch.inMinutes} minutes '
            'after Direct Control ended. Check the collector in Network Hub.',
        'warning',
      );
      _emit();
    }
  }

  String _leaseError(PiRawResponse r) {
    final e = r.data?['error'];
    final text = e is String && e.trim().isNotEmpty ? e : null;
    return switch (r.status) {
      401 || 403 =>
        'Argon did not accept this phone\'s signature. Pair the phone with '
            'Argon again in Network Hub.',
      404 => 'This Argon does not support router handover yet.',
      429 => 'Too many requests. Wait a minute and try again.',
      _ => text ?? 'Argon refused the router control request (${r.status}).',
    };
  }

  /// Signed `POST /api/v1/router/lease`.
  Future<PiRawResponse?> _leaseCommand(String action) => _deviceRequest(
    'POST',
    '/api/v1/router/lease',
    utf8.encode(
      jsonEncode({'action': action, 'confirm': 'DIRECT_ROUTER_CONTROL'}),
    ),
  );

  /// A request signed with this pairing's `ArgonDevice v2` key. Uses the
  /// current route when the key is known (no secret travels, so LAN works);
  /// otherwise enrolls the key over a secure route first. Null when the
  /// connection changed meanwhile.
  Future<PiRawResponse?> _deviceRequest(
    String method,
    String path,
    List<int> body,
  ) async {
    final generation = _generation;
    Future<PiRawResponse> send(PiTransport t, String id, String alias) async =>
        (t as PiOperatorTransport).sendRaw(
          method,
          path,
          body: body,
          timeout: const Duration(seconds: 15),
          headers: {
            'Authorization': await _deviceKey.header(
              alias: alias,
              id: id,
              method: method,
              // Argon signs the pathname only, never the query string.
              path: Uri.parse(path).path,
              body: body,
              ts: _now().millisecondsSinceEpoch ~/ 1000,
              nonce: _nonce(),
            ),
          },
        );
    final t = transport;
    final id = _deviceId ?? _pairedDeviceId;
    if (t is PiOperatorTransport &&
        t != null &&
        t.kind != PiTransportKind.bluetooth &&
        id != null &&
        _keyAlias != null) {
      final r = await send(t, id, _keyAlias!);
      if (generation != _generation || _disposed) return null;
      if (r.status != 403 || _deviceId != null) return r;
      // Key not enrolled yet on Argon: enroll over a secure route and retry.
    }
    final secure = await _secureTransport();
    if (generation != _generation || _disposed) return null;
    await _enrollKey(secure);
    if (generation != _generation || _disposed) return null;
    return send(secure, _deviceId!, _keyAlias!);
  }

  // ------------------------------------------------------- usage alerts

  static const alertsEvery = Duration(seconds: 60);
  DateTime? _lastAlerts;
  bool _pollingAlerts = false;
  int _alertCursor = 0;

  /// Why usage alerts are not being received, or null when they are.
  String? alertsError;

  /// Argon's sustained-usage alerts, fetched while the app is open with this
  /// phone's device signature, shown in the notification center and then
  /// acknowledged. Not a background push.
  Future<void> _pollAlerts() async {
    if (_pollingAlerts || !paired || trustedId == null) return;
    _pollingAlerts = true;
    _lastAlerts = _now();
    try {
      final r = await _deviceRequest(
        'GET',
        '/api/v1/alerts?after=$_alertCursor&limit=50',
        const [],
      );
      if (r == null) return;
      if (r.status != 200 || r.data?['alerts'] is! List) {
        alertsError = r.status == 404
            ? 'This Argon does not offer usage alerts.'
            : 'Usage alerts unavailable (${r.status}).';
        return;
      }
      alertsError = null;
      final shown = <int>[];
      for (final a in (r.data!['alerts'] as List).whereType<Map>()) {
        final id = a['id'];
        if (id is! int) continue;
        if (id > _alertCursor) _alertCursor = id;
        if (a['status'] != 'pending') continue;
        final at = a['createdAt'];
        final name = (a['deviceName'] as String?) ?? (a['mac'] as String?);
        final avg = a['avgBps'];
        final share = a['share'];
        final bytes = [a['downloadBytes'], a['uploadBytes']]
            .whereType<num>()
            .fold<num>(0, (x, y) => x + y);
        _events.add(
          PiEvent(
            id: 'argon:alert:$id',
            at: at is num
                ? DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000)
                : _now(),
            title: 'High usage: ${name ?? 'a device'}',
            message: [
              if (avg is num) 'averaged ${formatBitRateLabel(avg)}',
              if (share is num)
                '${(share * 100).toStringAsFixed(0)}% of household traffic',
              if (bytes > 0)
                '${a['estimated'] == true ? '≈ ' : ''}${_bytesLabel(bytes.toInt())} in the window',
            ].join(' · '),
            severity: 'warning',
            source: 'argon',
          ),
        );
        unreadEvents++;
        shown.add(id);
      }
      if (shown.isEmpty) return;
      _sortEvents();
      _emit();
      await _savePrefs();
      final ack = await _deviceRequest(
        'POST',
        '/api/v1/alerts/ack',
        utf8.encode(jsonEncode({'ids': shown})),
      );
      if (ack != null && ack.status != 200) {
        alertsError = 'Alerts shown but not acknowledged (${ack.status}).';
      }
    } on PiApiException catch (e) {
      alertsError = e is PiSecureRouteUnavailable
          ? 'Usage alerts need the phone key; enroll it over Tailscale once.'
          : e.message;
    } catch (_) {
      alertsError = 'Phone signing key is unavailable.';
    } finally {
      _pollingAlerts = false;
    }
  }

  static String formatBitRateLabel(num bps) => bps >= 1e6
      ? '${(bps / 1e6).toStringAsFixed(1)} Mbit/s'
      : '${(bps / 1e3).toStringAsFixed(0)} kbit/s';

  static String _bytesLabel(int b) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var v = b.toDouble();
    var u = 0;
    while (v >= 1023.5 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[u]}';
  }

  /// Monitoring GET with the same credential rules as the gateway report.
  Future<Map<String, dynamic>> _readPath(String path) async {
    final t = transport;
    if (t == null) throw const PiApiException('Argon is not reachable.');
    final route = _readToken != null && t.kind == PiTransportKind.lan
        ? await _secureTransport()
        : t;
    return route.get(path, token: _readToken);
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
