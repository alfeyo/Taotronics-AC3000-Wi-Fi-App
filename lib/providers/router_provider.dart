import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/mesh_entity.dart';
import '../models/device_entity.dart';
import '../models/save_result.dart';
import '../models/usb_storage.dart';
import '../models/wireless_network.dart';
import '../services/router_certificate_verifier.dart';
import '../services/router_discovery.dart';
import '../services/mqtt_service.dart';
import '../services/auth_pairing_service.dart';

enum RouterDiscoveryState { idle, scanning, routerFound, notFound }

enum NetworkState { unknown, gatewayReachable, gatewayUnreachable }

enum MqttPortState { unknown, open, closed }

enum AuthenticationState {
  notAuthenticated,
  authenticating,
  authenticated,
  authenticationFailed,
  authenticationRequired,
}

/// Handle returned by [RouterProvider.pauseLiveUpdates]. Live polling resumes
/// once every outstanding token has been released.
class LivePauseToken {
  LivePauseToken._(this._owner, this.reason);

  final RouterProvider _owner;
  final String reason;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _owner._releasePause(this);
  }
}

/// In-app notification shown under the Home bell (no push, no background).
class AppEvent {
  AppEvent(this.title, this.message, this.tone) : time = DateTime.now();

  final String title;
  final String message;

  /// 'info', 'success', 'warning' or 'error'.
  final String tone;
  final DateTime time;
}

/// One live throughput sample collected by the app this session.
typedef RateSample = ({DateTime time, int down, int up});

class RouterProvider extends ChangeNotifier with WidgetsBindingObserver {
  RouterProvider({
    RouterDiscoveryService? discovery,
    MqttService? mqtt,
    AuthPairingService? authService,
    bool autoStart = true,
  }) : _discovery = discovery ?? RouterDiscoveryService(),
       _mqtt = mqtt ?? MqttService(),
       _authService = authService ?? AuthPairingService() {
    WidgetsBinding.instance.addObserver(this);
    _discoverySubscription = _discovery.routerStream.listen(
      _onRouterDiscovered,
    );
    _connectionSubscription = _mqtt.connectionStream.listen(
      _onConnectionChanged,
    );
    if (autoStart) {
      _initialize();
    } else {
      _ready.complete();
    }
  }

  final RouterDiscoveryService _discovery;
  final MqttService _mqtt;
  final AuthPairingService _authService;

  /// Delays used between automatic reconnect attempts.
  static const reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  /// How long a configuration change waits for the router to come back
  /// before it is reported as unverified.
  static const verificationWindow = Duration(seconds: 90);

  MeshEntity? _currentRouter;
  final List<MeshEntity> _routers = [];
  List<DeviceEntity> _devices = [];
  List<NodeEntity> _nodes = [];
  Map<String, dynamic>? _systemStatus;
  Map<String, dynamic>? _wirelessSettings;
  List<Map<String, dynamic>> _wirelessNetworksRaw = [];
  List<WirelessNetwork> _wirelessNetworksParsed = [];
  bool _wirelessLoading = false;
  bool _wirelessLoaded = false;
  dynamic _wanSettings;
  dynamic _lanSettings;
  List<Map<String, dynamic>> _dailyFlow = [];
  List<Map<String, dynamic>> _monthlyFlow = [];
  int _todayUpBytes = 0;
  int _todayDownBytes = 0;
  int _monthUpBytes = 0;
  int _monthDownBytes = 0;
  Map<String, dynamic>? _connectionInfo;
  List<Map<String, dynamic>> _nodeRateInfo = [];
  int _wanUpRate = 0;
  int _wanDownRate = 0;
  UsbStorageSettings? _usbStorageSettings;
  List<UsbDisk> _usbDisks = [];
  String? _usbVisitAddress;
  bool _usbStorageLoading = false;
  bool _usbStorageSaving = false;
  DateTime? _devicesUpdatedAt;
  DateTime? _telemetryUpdatedAt;
  DateTime? _nodesUpdatedAt;
  DateTime? _wirelessUpdatedAt;

  RouterDiscoveryState _discoveryState = RouterDiscoveryState.idle;
  NetworkState _networkState = NetworkState.unknown;
  MqttPortState _mqttPortState = MqttPortState.unknown;
  AuthenticationState _authState = AuthenticationState.notAuthenticated;

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _discoverySubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _refreshTimer;
  Timer? _liveTimer;
  Timer? _reconnectTimer;
  bool _liveRefreshing = false;
  bool _liveTelemetryResponsive = true;
  int _telemetryMisses = 0;

  /// Consecutive unanswered telemetry batches before live polling stops
  /// asking for telemetry (the full refresh keeps retrying). Router replies
  /// can take ~4-5 s while other commands or phones are queued ahead, so a
  /// single miss must not switch the dashboard to stale values.
  static const telemetryMissesBeforeBackoff = 3;
  bool _reconnectInProgress = false;
  bool _allowReconnect = true;
  bool _inBackground = false;
  int _reconnectAttempt = 0;
  bool _discoveryRetryUsed = false;
  int _sessionGeneration = 0;
  final Set<LivePauseToken> _pauseTokens = {};
  LivePauseToken? _backgroundPause;

  final List<PendingChange> _pendingChanges = [];
  int _nextChangeId = 0;

  /// Pauses the 3-second live polling until the returned token is released.
  /// Screens that write settings hold a token so polling cannot interleave
  /// with their requests.
  LivePauseToken pauseLiveUpdates(String reason) {
    final token = LivePauseToken._(this, reason);
    _pauseTokens.add(token);
    return token;
  }

  void _releasePause(LivePauseToken token) {
    _pauseTokens.remove(token);
  }

  bool get isLivePaused => _pauseTokens.isNotEmpty;

  // Getters
  MeshEntity? get currentRouter => _currentRouter;
  List<MeshEntity> get routers => List.unmodifiable(_routers);
  List<DeviceEntity> get devices => _devices;
  List<NodeEntity> get nodes => _nodes;
  Map<String, dynamic>? get systemStatus => _systemStatus;
  Map<String, dynamic>? get wirelessSettings => _wirelessSettings;
  List<Map<String, dynamic>> get wirelessNetworks => _wirelessNetworksRaw;
  List<WirelessNetwork> get wirelessNetworksParsed => _wirelessNetworksParsed;
  bool get wirelessLoading => _wirelessLoading;
  bool get wirelessLoaded => _wirelessLoaded;
  List<PendingChange> get pendingChanges => List.unmodifiable(_pendingChanges);
  DateTime? get devicesUpdatedAt => _devicesUpdatedAt;
  DateTime? get telemetryUpdatedAt => _telemetryUpdatedAt;
  DateTime? get nodesUpdatedAt => _nodesUpdatedAt;

  /// When the wireless list was last read successfully from the router.
  DateTime? get wirelessUpdatedAt => _wirelessUpdatedAt;
  CertificateVerdict? get certificateVerdict => _mqtt.lastCertificateVerdict;

  /// True when live telemetry has not refreshed for a while although the
  /// session is up, so the dashboard can mark the numbers as stale.
  bool get telemetryStale {
    final at = _telemetryUpdatedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > const Duration(seconds: 20);
  }

  /// When the live numbers on the dashboard last changed: telemetry if the
  /// router answers it, otherwise the device list (rates are summed).
  DateTime? get liveDataUpdatedAt =>
      hasLiveWanRates ? _telemetryUpdatedAt : _devicesUpdatedAt;

  bool get liveDataStale {
    final at = liveDataUpdatedAt;
    return at == null ||
        DateTime.now().difference(at) > const Duration(seconds: 20);
  }

  /// Whether the router answers the live telemetry commands at all.
  bool get liveTelemetrySupported => _liveTelemetryResponsive;

  String get currentWifiName {
    if (_wirelessNetworksParsed.isEmpty) {
      return _wirelessLoaded ? 'Wi-Fi unavailable' : 'Loading Wi-Fi...';
    }
    final primary = _wirelessNetworksParsed
        .where((n) => n.index == 0 && n.isEnabled)
        .firstOrNull;
    if (primary != null && primary.ssid.isNotEmpty) return primary.ssid;
    final firstEnabled = _wirelessNetworksParsed
        .where((n) => n.isEnabled && n.ssid.isNotEmpty)
        .firstOrNull;
    if (firstEnabled != null) return firstEnabled.ssid;
    final first = _wirelessNetworksParsed
        .where((n) => n.ssid.isNotEmpty)
        .firstOrNull;
    if (first != null) return first.ssid;
    return 'Unknown Wi-Fi';
  }

  List<String> get allSsids => _wirelessNetworksParsed
      .where((n) => n.ssid.isNotEmpty)
      .map((n) => n.ssid)
      .toList();
  dynamic get wanSettings => _wanSettings;
  dynamic get lanSettings => _lanSettings;
  List<Map<String, dynamic>> get dailyFlow => _dailyFlow;
  List<Map<String, dynamic>> get monthlyFlow => _monthlyFlow;
  int get todayUpBytes => _todayUpBytes;
  int get todayDownBytes => _todayDownBytes;
  int get todayTotalBytes => _todayUpBytes + _todayDownBytes;
  int get monthUpBytes => _monthUpBytes;
  int get monthDownBytes => _monthDownBytes;
  int get monthTotalBytes => _monthUpBytes + _monthDownBytes;
  int get totalDeviceUpBytes => _devices.fold(0, (sum, d) => sum + d.upBytes);
  int get totalDeviceDownBytes =>
      _devices.fold(0, (sum, d) => sum + d.downBytes);
  Map<String, dynamic>? get connectionInfo => _connectionInfo;
  List<Map<String, dynamic>> get nodeRateInfo => _nodeRateInfo;
  int get wanUpRate => _wanUpRate;
  int get wanDownRate => _wanDownRate;
  int get liveUpRate => _wanUpRate > 0 ? _wanUpRate : totalDeviceUpRate;
  int get liveDownRate => _wanDownRate > 0 ? _wanDownRate : totalDeviceDownRate;
  bool get hasLiveWanRates => _wanUpRate > 0 || _wanDownRate > 0;
  UsbStorageSettings? get usbStorageSettings => _usbStorageSettings;
  List<UsbDisk> get usbDisks => List.unmodifiable(_usbDisks);
  String? get usbVisitAddress => _usbVisitAddress;
  bool get usbStorageLoading => _usbStorageLoading;
  bool get usbStorageSaving => _usbStorageSaving;
  int get usbPartitionCount =>
      _usbDisks.fold(0, (sum, disk) => sum + disk.partitions.length);
  int get usbTotalBytes =>
      _usbDisks.fold(0, (sum, disk) => sum + disk.totalBytes);
  int get usbAvailableBytes =>
      _usbDisks.fold(0, (sum, disk) => sum + disk.availableBytes);

  RouterDiscoveryState get discoveryState => _discoveryState;
  NetworkState get networkState => _networkState;
  MqttPortState get mqttPortState => _mqttPortState;
  AuthenticationState get authState => _authState;
  AuthPairingService get authService => _authService;

  bool get isLoading => _isLoading;
  bool get isConnected => _authState == AuthenticationState.authenticated;
  bool get isReconnecting =>
      _authState == AuthenticationState.authenticating &&
      _shouldReconnectCurrentRouter;
  bool get isRouterFound => _discoveryState == RouterDiscoveryState.routerFound;
  bool get isNetworkReachable => _networkState == NetworkState.gatewayReachable;
  bool get isMqttPortOpen => _mqttPortState == MqttPortState.open;
  bool get canAttemptConnection =>
      isRouterFound && isNetworkReachable && isMqttPortOpen;
  String? get errorMessage => _errorMessage;

  int get onlineDeviceCount => _devices.where((d) => d.isOnline).length;
  int get onlineNodeCount => _nodes.where((n) => n.isOnline).length;
  int get reportedOnlineDeviceCount =>
      _connectionInt('OnlineDev', onlineDeviceCount);
  int get reportedGuestDeviceCount => _connectionInt('OnlineGuestDev', 0);
  int get reportedOnlineNodeCount =>
      _connectionInt('OnlineNodeCount', onlineNodeCount);
  int get reportedTotalNodeCount =>
      _connectionInt('TotalNodeCount', _nodes.length);
  int get networkQuality => _connectionInt('NetworkQuality', 0);

  /// Whether the router has reported its internet state at all.
  bool get hasInternetStatus => _connectionInfo?['Internet'] != null;
  bool get internetConnected => _connectionInt('Internet', 0) == 1;

  String get networkQualityLabel {
    if (!hasInternetStatus) return 'Unknown';
    if (!internetConnected) return 'Offline';
    return networkQuality == 2 ? 'Check' : 'Good';
  }

  String get statusSummary {
    if (_authState == AuthenticationState.authenticated) {
      return 'Connected';
    }
    if (_authState == AuthenticationState.authenticationRequired) {
      return 'Authentication Required';
    }
    if (_authState == AuthenticationState.authenticationFailed) {
      return 'Authentication Failed';
    }
    if (_authState == AuthenticationState.authenticating) {
      return 'Reconnecting...';
    }
    if (_discoveryState == RouterDiscoveryState.routerFound) {
      if (_networkState == NetworkState.gatewayReachable) {
        if (_mqttPortState == MqttPortState.open) {
          return 'Router Found - Pairing Required';
        }
        return 'Router Found - MQTT Port Closed';
      }
      return 'Router Found - Network Unreachable';
    }
    if (_discoveryState == RouterDiscoveryState.scanning) {
      return 'Scanning...';
    }
    return 'No Router Found';
  }

  String get detailedStatus {
    final parts = <String>[];

    switch (_discoveryState) {
      case RouterDiscoveryState.idle:
        parts.add('Discovery: Not started');
        break;
      case RouterDiscoveryState.scanning:
        parts.add('Discovery: Scanning');
        break;
      case RouterDiscoveryState.routerFound:
        parts.add('Discovery: Router found');
        break;
      case RouterDiscoveryState.notFound:
        parts.add('Discovery: No router');
        break;
    }

    switch (_networkState) {
      case NetworkState.unknown:
        parts.add('Network: Unknown');
        break;
      case NetworkState.gatewayReachable:
        parts.add('Network: OK');
        break;
      case NetworkState.gatewayUnreachable:
        parts.add('Network: Unreachable');
        break;
    }

    switch (_mqttPortState) {
      case MqttPortState.unknown:
        parts.add('MQTT: Unknown');
        break;
      case MqttPortState.open:
        parts.add('MQTT: Open');
        break;
      case MqttPortState.closed:
        parts.add('MQTT: Closed');
        break;
    }

    switch (_authState) {
      case AuthenticationState.notAuthenticated:
        parts.add('Auth: Not authenticated');
        break;
      case AuthenticationState.authenticating:
        parts.add('Auth: Connecting...');
        break;
      case AuthenticationState.authenticated:
        parts.add('Auth: Connected');
        break;
      case AuthenticationState.authenticationFailed:
        parts.add('Auth: Failed');
        break;
      case AuthenticationState.authenticationRequired:
        parts.add('Auth: Required');
        break;
    }

    return parts.join(' | ');
  }

  final _ready = Completer<void>();

  /// Completes once saved pairings have been loaded at start-up.
  Future<void> get ready => _ready.future;
  bool get hasSavedPairing => _authService.pairedRouters.isNotEmpty;

  final List<AppEvent> _events = [];
  int _unreadEvents = 0;
  List<AppEvent> get events => List.unmodifiable(_events.reversed);
  int get unreadEvents => _unreadEvents;

  void _addEvent(String title, String message, String tone) {
    _events.add(AppEvent(title, message, tone));
    if (_events.length > 30) _events.removeAt(0);
    _unreadEvents++;
  }

  void markEventsRead() {
    if (_unreadEvents == 0) return;
    _unreadEvents = 0;
    notifyListeners();
  }

  final List<RateSample> _rateSamples = [];

  /// Live throughput samples from this session (newest last, max 200,
  /// about 10 minutes at the 3 s polling rate).
  List<RateSample> get rateSamples => List.unmodifiable(_rateSamples);

  void _recordRates() {
    if (!isConnected) return;
    final now = DateTime.now();
    if (_rateSamples.isNotEmpty &&
        now.difference(_rateSamples.last.time) < const Duration(seconds: 2)) {
      return;
    }
    _rateSamples.add((time: now, down: liveDownRate, up: liveUpRate));
    if (_rateSamples.length > maxRateSamples) _rateSamples.removeAt(0);
  }

  static const maxRateSamples = 200;

  /// Bytes estimated to have crossed the router while this app sampled it:
  /// trapezoidal integration of the rate samples. Gaps over 15 s (app in
  /// background, reconnecting) are not counted. An estimate, not a meter.
  ({int down, int up, Duration covered}) get sessionTransferEstimate {
    var down = 0.0;
    var up = 0.0;
    var covered = Duration.zero;
    for (var i = 1; i < _rateSamples.length; i++) {
      final a = _rateSamples[i - 1];
      final b = _rateSamples[i];
      final dt = b.time.difference(a.time);
      if (dt > const Duration(seconds: 15)) continue;
      final seconds = dt.inMilliseconds / 1000;
      down += (a.down + b.down) / 2 * seconds;
      up += (a.up + b.up) / 2 * seconds;
      covered += dt;
    }
    return (down: down.round(), up: up.round(), covered: covered);
  }

  Duration? _lastResponseTime;
  DateTime? _lastResponseAt;

  /// Most recent measured router response time, if measured.
  Duration? get lastResponseTime => _lastResponseTime;
  DateTime? get lastResponseAt => _lastResponseAt;

  Map<String, dynamic>? _wanInfo;

  /// First GetMWanInfo entry (WanProto, WanIp, WanGateway…), if read.
  Map<String, dynamic>? get wanInfo => _wanInfo;

  Future<void> _refreshWanInfo() async {
    final response = await _mqtt.getWanSettings();
    final data = response?['Data'];
    if (response?['ErrorCode'] == 0 && data is List && data.isNotEmpty) {
      if (data.first is Map) {
        _wanInfo = Map<String, dynamic>.from(data.first as Map);
        notifyListeners();
      }
    }
  }

  bool _hadDrop = false;
  bool _certificateEventSent = false;

  void _noteCertificateRejection() {
    final verdict = _mqtt.lastCertificateVerdict;
    if (verdict == null || verdict.trusted || _certificateEventSent) return;
    _certificateEventSent = true;
    _addEvent(
      'Router identity not verified',
      'The device at the router address presented a certificate that is not '
          'signed by TaoTronics, so the app refused to connect.',
      'error',
    );
  }

  Future<void> _initialize() async {
    await _authService.loadSavedPairings();
    if (!_ready.isCompleted) _ready.complete();
    _discoveryState = RouterDiscoveryState.scanning;
    notifyListeners();
    await _discovery.startDiscovery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _inBackground = false;
        _backgroundPause?.release();
        _backgroundPause = null;
        if (isConnected) {
          refreshAll();
        } else if (_shouldReconnectCurrentRouter) {
          _reconnectAttempt = 0;
          _scheduleReconnect();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _inBackground = true;
        _backgroundPause ??= pauseLiveUpdates('app in background');
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onRouterDiscovered(DiscoveredRouter discovered) {
    var changed = false;
    final existing = _routers.indexWhere((r) => r.meshId == discovered.meshId);

    if (existing >= 0) {
      final router = _routers[existing];
      if (router.ipAddress != discovered.ipAddress || router.state != 1) {
        router.ipAddress = discovered.ipAddress;
        router.state = 1;
        changed = true;
      }
    } else {
      _routers.add(
        MeshEntity(
          meshId: discovered.meshId,
          ssid: 'Router ${_routers.length + 1}',
          ipAddress: discovered.ipAddress,
          state: 1,
        ),
      );
      changed = true;
    }

    if (_discoveryState != RouterDiscoveryState.routerFound) {
      _discoveryState = RouterDiscoveryState.routerFound;
      changed = true;
    }

    if (_currentRouter == null && _routers.isNotEmpty) {
      selectRouter(_routers.first);
      return;
    } else if (_currentRouter?.meshId == discovered.meshId &&
        !isConnected &&
        _authService.isPaired(discovered.meshId)) {
      if (_reconnectAttempt > 0 && !_discoveryRetryUsed && !_inBackground) {
        // The router is broadcasting again: retry now instead of waiting for
        // the backoff timer. Once per outage, so failing logins are not
        // retried at the beacon rate.
        _discoveryRetryUsed = true;
        reconnectNow();
      } else {
        _scheduleReconnect();
      }
    }

    if (changed) notifyListeners();
  }

  void _onConnectionChanged(bool connected) {
    if (connected) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectAttempt = 0;
      _discoveryRetryUsed = false;
      if (_hadDrop) {
        _hadDrop = false;
        _addEvent('Reconnected', 'The router connection is back.', 'success');
      }
      _authState = AuthenticationState.authenticated;
      _errorMessage = null;
      _startAutoRefresh();
      refreshAll();
    } else {
      // Only unexpected drops of an established session arrive here.
      _stopAutoRefresh();
      _hadDrop = true;
      _addEvent(
        'Router disconnected',
        'The connection dropped. The app is trying to reconnect.',
        'warning',
      );
      if (_shouldReconnectCurrentRouter) {
        _authState = AuthenticationState.authenticating;
        _errorMessage = null;
        _scheduleReconnect();
      } else if (_authState == AuthenticationState.authenticated ||
          _authState == AuthenticationState.authenticating) {
        _authState = AuthenticationState.authenticationRequired;
      }
    }
    notifyListeners();
  }

  void updateNetworkState({bool? gatewayReachable, bool? mqttPortOpen}) {
    if (gatewayReachable != null) {
      _networkState = gatewayReachable
          ? NetworkState.gatewayReachable
          : NetworkState.gatewayUnreachable;
    }
    if (mqttPortOpen != null) {
      _mqttPortState = mqttPortOpen ? MqttPortState.open : MqttPortState.closed;
    }

    if (_networkState == NetworkState.gatewayReachable &&
        _mqttPortState == MqttPortState.open &&
        _authState == AuthenticationState.notAuthenticated) {
      _authState = AuthenticationState.authenticationRequired;
    }

    notifyListeners();
  }

  /// Starts a new user-initiated session. Pending automatic reconnects belong
  /// to the previous session and are cancelled so they cannot override it.
  int _beginSession() {
    _sessionGeneration++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _allowReconnect = true;
    return _sessionGeneration;
  }

  Future<void> selectRouter(MeshEntity router) async {
    final session = _beginSession();
    _currentRouter = router;
    _authState = AuthenticationState.authenticating;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (router.ipAddress != null) {
      final reconnectPassword = _authService.isPaired(router.meshId)
          ? _authService.reconnectPassword(router.meshId)
          : null;
      final success = await _mqtt.connect(
        router.meshId,
        router.ipAddress!,
        password: reconnectPassword,
      );
      if (session != _sessionGeneration) return;
      if (success) {
        _authState = AuthenticationState.authenticated;
        await _authService.attemptPairing(
          meshId: router.meshId,
          ipAddress: router.ipAddress!,
          customPassword: reconnectPassword,
        );
      } else {
        _authState = AuthenticationState.authenticationRequired;
        _errorMessage =
            'Router requires authentication. Please pair the router first.';
        _noteCertificateRejection();
      }
    } else {
      _authState = AuthenticationState.authenticationFailed;
      _errorMessage = 'Router IP address not available';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> attemptAuthentication(
    String meshId,
    String ipAddress, {
    String? password,
  }) async {
    final session = _beginSession();
    _authState = AuthenticationState.authenticating;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final success = await _mqtt.connect(meshId, ipAddress, password: password);
    if (session != _sessionGeneration) return false;

    if (success) {
      final known = _routers.where((r) => r.meshId == meshId).firstOrNull;
      _currentRouter =
          known ??
          MeshEntity(
            meshId: meshId,
            ssid: 'Router',
            ipAddress: ipAddress,
            state: 1,
          );
      _currentRouter!.ipAddress = ipAddress;
      _authState = AuthenticationState.authenticated;
      await _authService.attemptPairing(
        meshId: meshId,
        ipAddress: ipAddress,
        customPassword: password,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _authState = AuthenticationState.authenticationFailed;
      _errorMessage =
          'Authentication failed. Check router pairing mode or credentials.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!isLivePaused) refreshAll();
    });
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _liveRefresh();
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  bool get _shouldReconnectCurrentRouter {
    final router = _currentRouter;
    return _allowReconnect &&
        router != null &&
        router.ipAddress != null &&
        _authService.isPaired(router.meshId);
  }

  void _scheduleReconnect() {
    if (!_shouldReconnectCurrentRouter ||
        _inBackground ||
        _reconnectInProgress ||
        _reconnectTimer?.isActive == true) {
      return;
    }

    final delay =
        reconnectDelays[_reconnectAttempt.clamp(0, reconnectDelays.length - 1)];
    _reconnectAttempt++;
    final session = _sessionGeneration;
    debugPrint(
      'RouterProvider: reconnecting saved router in ${delay.inSeconds}s '
      '(attempt $_reconnectAttempt)',
    );
    _reconnectTimer = Timer(delay, () => _reconnectCurrentRouter(session));
  }

  Future<void> _reconnectCurrentRouter(int session) async {
    _reconnectTimer = null;
    if (session != _sessionGeneration ||
        !_shouldReconnectCurrentRouter ||
        _reconnectInProgress ||
        isConnected) {
      return;
    }

    final router = _currentRouter!;
    final ipAddress = router.ipAddress!;
    _reconnectInProgress = true;
    _authState = AuthenticationState.authenticating;
    notifyListeners();

    final success = await _mqtt.connect(
      router.meshId,
      ipAddress,
      password: _authService.reconnectPassword(router.meshId),
    );

    _reconnectInProgress = false;
    if (session != _sessionGeneration) return;
    if (success) {
      _authState = AuthenticationState.authenticated;
      _errorMessage = null;
    } else if (_shouldReconnectCurrentRouter) {
      _authState = AuthenticationState.authenticating;
      _noteCertificateRejection();
      if (_reconnectAttempt == 3) {
        _addEvent(
          'Reconnection failing',
          'Several attempts to reach the router failed. Check that this '
              'phone is on the router Wi-Fi.',
          'error',
        );
      }
      _scheduleReconnect();
    }
    notifyListeners();
  }

  /// Times one lightweight router command (GetSysConnectInfo). Returns null
  /// when not connected or the router does not answer.
  Future<Duration?> measureRouterResponse() async {
    if (!isConnected) return null;
    final watch = Stopwatch()..start();
    final response = await _mqtt.getSystemConnectionInfo();
    watch.stop();
    if (response == null) return null;
    _lastResponseTime = watch.elapsed;
    _lastResponseAt = DateTime.now();
    notifyListeners();
    return watch.elapsed;
  }

  /// Retries the saved router immediately, e.g. after the phone rejoins Wi-Fi.
  void reconnectNow() {
    if (isConnected || !_shouldReconnectCurrentRouter || _reconnectInProgress) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _reconnectCurrentRouter(_sessionGeneration);
  }

  Future<void> _liveRefresh() async {
    if (!isConnected || _liveRefreshing || _refreshing || isLivePaused) return;
    _liveRefreshing = true;
    try {
      final liveWork = <Future<void>>[refreshDevices()];
      if (_liveTelemetryResponsive) {
        liveWork.add(refreshLiveTelemetry());
      }
      // Above the telemetry timeout, so a slow router reply is not discarded.
      await Future.wait(liveWork).timeout(const Duration(seconds: 10));
    } catch (_) {
    } finally {
      _liveRefreshing = false;
    }
  }

  bool _refreshing = false;

  Future<void> refreshAll() async {
    if (!isConnected || _refreshing) return;
    _refreshing = true;
    try {
      await _refreshAllInternal();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshAllInternal() async {
    if (!isConnected) return;

    try {
      await refreshSystemStatus().timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      await refreshDevices().timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      await refreshNodes().timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      await refreshWirelessSettings().timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      await refreshLiveTelemetry().timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      await refreshUsbStorage().timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (!ledsLoaded) {
      try {
        await refreshLeds().timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    if (_wanInfo == null) {
      try {
        await _refreshWanInfo().timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    // Skip traffic-flow refresh: /GetSumOfNetworkFlow* endpoints are cloud-only
    // on this router family (see APK g/c.bA list) and always time out on the
    // local MQTT broker. Live throughput is derived from device UpRate/DownRate
    // instead. Keeping refreshTrafficStats() callable for manual debug.
  }

  int get totalDeviceUpRate =>
      _devices.fold(0, (sum, d) => sum + d.uploadSpeed);
  int get totalDeviceDownRate =>
      _devices.fold(0, (sum, d) => sum + d.downloadSpeed);

  Future<void> refreshTrafficStats() async {
    final responses = await Future.wait([
      _mqtt.getNetworkFlowDaily(),
      _mqtt.getNetworkFlowMonthly(),
    ]);

    final daily = responses[0];
    if (daily != null && daily['ErrorCode'] == 0) {
      final data = daily['Data'];
      if (data is List) {
        _dailyFlow = _mapList(data);
        var up = 0;
        var down = 0;
        for (final entry in _dailyFlow) {
          up += _readInt(entry['UpBytes']);
          down += _readInt(entry['DownBytes']);
        }
        _todayUpBytes = up;
        _todayDownBytes = down;
      }
    }

    final monthly = responses[1];
    if (monthly != null && monthly['ErrorCode'] == 0) {
      final data = monthly['Data'];
      if (data is List) {
        _monthlyFlow = _mapList(data);
        var up = 0;
        var down = 0;
        for (final entry in _monthlyFlow) {
          up += _readInt(entry['UpBytes']);
          down += _readInt(entry['DownBytes']);
        }
        _monthUpBytes = up;
        _monthDownBytes = down;
      }
    }

    notifyListeners();
  }

  Future<void> refreshLiveTelemetry() async {
    final responses = await Future.wait([
      _mqtt.getSystemConnectionInfo(),
      _mqtt.getNodeRateInfo(),
      _mqtt.getWanRateInfo(),
    ]);
    if (responses.any((response) => response != null)) {
      _telemetryMisses = 0;
      _liveTelemetryResponsive = true;
    } else if (++_telemetryMisses >= telemetryMissesBeforeBackoff) {
      if (_liveTelemetryResponsive) {
        _addEvent(
          'Live statistics delayed',
          'The router missed several statistics requests. Rates use device '
              'totals until it answers again.',
          'warning',
        );
      }
      _liveTelemetryResponsive = false;
    }

    final connect = responses[0];
    if (connect != null && connect['ErrorCode'] == 0) {
      final data = connect['Data'];
      if (data is Map) {
        _connectionInfo = Map<String, dynamic>.from(data);
      }
    }

    final nodeRates = responses[1];
    if (nodeRates != null && nodeRates['ErrorCode'] == 0) {
      final data = nodeRates['Data'];
      if (data is List) {
        _nodeRateInfo = _mapList(data);
      }
    }

    final wanRates = responses[2];
    if (wanRates != null && wanRates['ErrorCode'] == 0) {
      final data = wanRates['Data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        final rate = Map<String, dynamic>.from(data.first as Map);
        _wanUpRate = _readInt(rate['UpRate']);
        _wanDownRate = _readInt(rate['DownRate']);
      }
    }

    if (_telemetryMisses == 0) _telemetryUpdatedAt = DateTime.now();
    _recordRates();
    notifyListeners();
  }

  Future<void> refreshSystemStatus() async {
    final response = await _mqtt.getSystemStatus();
    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is Map) {
        _systemStatus = Map<String, dynamic>.from(data);
      } else if (data is List && data.isNotEmpty && data.first is Map) {
        _systemStatus = Map<String, dynamic>.from(data.first as Map);
      }
      notifyListeners();
    }
  }

  Future<void> refreshDevices() async {
    final response = await _mqtt.getDeviceList();
    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is List) {
        _devices = _mapList(data).map(DeviceEntity.fromJson).toList();
      } else if (data is Map && data['ClientList'] is List) {
        _devices = _mapList(
          data['ClientList'] as List,
        ).map(DeviceEntity.fromJson).toList();
      }
      _devicesUpdatedAt = DateTime.now();
      if (!hasLiveWanRates) _recordRates();
      notifyListeners();
    }
  }

  Future<void> refreshNodes() async {
    final response = await _mqtt.getNodeList();
    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is List) {
        _nodes = _mapList(data).map(NodeEntity.fromJson).toList();
      } else if (data is Map && data['NodeList'] is List) {
        _nodes = _mapList(
          data['NodeList'] as List,
        ).map(NodeEntity.fromJson).toList();
      }
      _nodesUpdatedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Returns true when the router answered with a wireless list.
  Future<bool> refreshWirelessSettings() async {
    _wirelessLoading = true;
    notifyListeners();

    final response = await _mqtt.getWirelessSettings();
    _wirelessLoading = false;
    _wirelessLoaded = true;

    var ok = false;
    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is List) {
        _wirelessNetworksRaw = _mapList(data);
        _wirelessNetworksParsed = _wirelessNetworksRaw
            .map((n) => WirelessNetwork.fromJson(n))
            .toList();
        if (_wirelessNetworksRaw.isNotEmpty) {
          _wirelessSettings = _wirelessNetworksRaw.first;
        }
        ok = true;
      } else if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        _wirelessSettings = map;
        _wirelessNetworksRaw = [map];
        _wirelessNetworksParsed = [WirelessNetwork.fromJson(map)];
        ok = true;
      }
    }
    if (ok) _wirelessUpdatedAt = DateTime.now();
    notifyListeners();
    return ok;
  }

  /// Saves one edited network (name, password, or on/off).
  Future<SaveResult> updateWirelessNetwork(WirelessNetwork updated) =>
      saveWirelessNetworks([updated]);

  /// Turns one network on or off without changing its name or password.
  Future<SaveResult> setWirelessNetworkEnabled(int index, bool enabled) {
    final network = _wirelessNetworksParsed
        .where((n) => n.index == index)
        .firstOrNull;
    if (network == null) {
      return Future.value(
        const SaveResult.failed('That network is not in the router list.'),
      );
    }
    return saveWirelessNetworks([network.withEnabled(enabled)]);
  }

  /// Applies [changed] entries (matched by index) on top of the full list the
  /// router reported and sends it with SetWirelessInfoList. Untouched entries
  /// are sent back exactly as the router reported them.
  Future<SaveResult> saveWirelessNetworks(List<WirelessNetwork> changed) async {
    if (!_wirelessLoaded || _wirelessNetworksParsed.isEmpty) {
      return const SaveResult.failed(
        'The Wi-Fi list has not loaded from the router yet, so nothing was sent.',
      );
    }
    final unknown = changed.where(
      (c) => !_wirelessNetworksParsed.any((n) => n.index == c.index),
    );
    if (unknown.isNotEmpty) {
      return const SaveResult.failed(
        'A network changed on the router. Refresh and try again.',
      );
    }
    final merged = [
      for (final n in _wirelessNetworksParsed)
        changed.where((c) => c.index == n.index).firstOrNull ?? n,
    ];
    final missing = {
      for (final n in merged)
        for (final f in n.missingRequiredFields) '${n.bandLabel}: $f',
    };
    if (missing.isNotEmpty) {
      return SaveResult.failed(
        'The router did not report ${missing.join(', ')}, so saving could '
        'overwrite it. Nothing was sent.',
      );
    }
    if (!merged.any((n) => n.isEnabled)) {
      return const SaveResult.failed(
        'At least one Wi-Fi network must stay on, or this phone could lose '
        'access to the router.',
      );
    }
    return _sendWirelessPayload(
      merged.map((n) => n.toRouterPayload()).toList(),
    );
  }

  /// Sends a full wireless list. Kept for callers that build payload maps;
  /// every entry must carry the router's own fields (no defaults are added).
  Future<SaveResult> setWirelessSettings(
    List<Map<String, dynamic>> networks,
  ) async {
    final incomplete = networks.where(
      (n) => !n.containsKey('Index') || !n.containsKey('Ssid'),
    );
    if (networks.isEmpty || incomplete.isNotEmpty) {
      return const SaveResult.failed(
        'Wi-Fi settings are incomplete, so nothing was sent.',
      );
    }
    return _sendWirelessPayload(networks);
  }

  Future<SaveResult> _sendWirelessPayload(
    List<Map<String, dynamic>> payload,
  ) async {
    // Compare only fields this router reports: V1 has Create but no Disable.
    final keys = [
      'Ssid',
      'Password',
      'Create',
      if (payload.any((n) => n.containsKey('Disable'))) 'Disable',
    ];

    // The router restarts Wi-Fi when applying this and often drops the
    // session before replying, so a missing reply is verified afterwards.
    final result = await _writeRouterSetting(
      label: 'Wi-Fi change',
      failureMessage: 'Failed to update Wi-Fi settings',
      request: () => _mqtt.setWirelessSettings(payload),
      verify: () async {
        if (!await refreshWirelessSettings()) return null;
        return _matchesByIndex(_wirelessNetworksRaw, payload, keys);
      },
    );
    if (result.isConfirmed) {
      _wirelessNetworksRaw = payload;
      _wirelessNetworksParsed = payload.map(WirelessNetwork.fromJson).toList();
      notifyListeners();
    }
    return result;
  }

  DateTime? _wanUpdatedAt;
  DateTime? get wanUpdatedAt => _wanUpdatedAt;
  DateTime? _guestUpdatedAt;
  DateTime? get guestUpdatedAt => _guestUpdatedAt;

  Future<void> refreshWanSettings() async {
    final response = await _mqtt.getWanSettings();
    if (response != null && response['ErrorCode'] == 0) {
      _wanSettings = response['Data'];
      _wanUpdatedAt = DateTime.now();
      notifyListeners();
    }
  }

  Future<void> refreshLanSettings() async {
    final response = await _mqtt.getLanSettings();
    if (response != null && response['ErrorCode'] == 0) {
      _lanSettings = response['Data'];
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> loadWanSettings() {
    return _readRouterSetting(_mqtt.getWanSettings);
  }

  Future<SaveResult> updateWanSettings(List<Map<String, dynamic>> settings) {
    return _writeRouterSetting(
      label: 'Internet (WAN) change',
      failureMessage: 'Failed to update WAN settings',
      request: () => _mqtt.setWanSettings(settings),
      verify: () => _verifyListSubset(_mqtt.getWanSettings, settings, const [
        'WanProto',
        'ManualDns',
        'WanIp',
        'WanMask',
        'WanGateway',
        'WanDns',
        'WanDnsbak',
        'PppoeUser',
        'VlanDisabled',
        'VlanId',
        'WanDisabled',
      ]),
    );
  }

  Future<Map<String, dynamic>?> loadLanSettings() {
    return _readRouterSetting(_mqtt.getLanSettings);
  }

  Future<SaveResult> updateLanSettings(List<Map<String, dynamic>> settings) {
    return _writeRouterSetting(
      label: 'LAN change',
      failureMessage: 'Failed to update LAN settings',
      request: () => _mqtt.setLanSettings(settings),
      verify: () => _verifyListSubset(_mqtt.getLanSettings, settings, const [
        'LanIp',
        'LanMask',
        'DhcpStartAddr',
        'DhcpEndAddr',
        'VlanEnable',
        'Vlanid',
      ]),
    );
  }

  Future<Map<String, dynamic>?> loadGuestWifiSettings({
    bool quiet = false,
  }) async {
    if (quiet && !isConnected) return null;
    final response = quiet
        ? await _mqtt.getGuestWifi()
        : await _readRouterSetting(_mqtt.getGuestWifi);
    if (response == null || response['ErrorCode'] != 0) return response;
    final data = response['Data'];
    final guest = data is List && data.isNotEmpty && data.first is Map
        ? Map<String, dynamic>.from(data.first as Map)
        : data is Map
        ? Map<String, dynamic>.from(data)
        : null;
    if (guest != null) {
      _guestWifi = guest;
      _guestUpdatedAt = DateTime.now();
      notifyListeners();
    }
    return response;
  }

  Map<String, dynamic>? _guestWifi;

  /// Last guest network entry reported by GetGuestInfo, if loaded.
  Map<String, dynamic>? get guestWifi => _guestWifi;

  Future<SaveResult> updateGuestWifiSettings(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      label: 'Guest Wi-Fi change',
      failureMessage: 'Failed to update guest Wi-Fi',
      request: () => _mqtt.setGuestWifi(settings),
      verify: () => _verifyListSubset(
        _mqtt.getGuestWifi,
        [settings],
        const ['Enable', 'Ssid', 'EncryptionWay'],
      ),
    );
  }

  Future<Map<String, dynamic>?> loadFirewallSettings() {
    return _readRouterSetting(_mqtt.getFirewallSettings);
  }

  Future<SaveResult> updateFirewallSettings(bool enabled) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update firewall',
      request: () => _mqtt.setFirewallSettings(enabled),
    );
  }

  Future<Map<String, dynamic>?> loadUpnpDmzSettings() {
    return _readRouterSetting(_mqtt.getUpnpDmzSettings);
  }

  Future<SaveResult> updateUpnpDmzSettings({
    required bool upnpEnabled,
    required bool dmzEnabled,
    required String dmzHost,
  }) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update UPnP and DMZ',
      request: () => _mqtt.setUpnpDmzSettings(
        upnpEnabled: upnpEnabled,
        dmzEnabled: dmzEnabled,
        dmzHost: dmzHost,
      ),
    );
  }

  Future<Map<String, dynamic>?> loadQosSettings() {
    return _readRouterSetting(_mqtt.getQosSettings);
  }

  Future<SaveResult> updateQosSettings({
    required bool enabled,
    required int upBandwidth,
    required int downBandwidth,
  }) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update QoS',
      request: () => _mqtt.setQosSettings(
        enabled: enabled,
        upBandwidth: upBandwidth,
        downBandwidth: downBandwidth,
      ),
    );
  }

  Future<Map<String, dynamic>?> loadFastNatSettings() {
    return _readRouterSetting(_mqtt.getFastNatSettings);
  }

  Future<SaveResult> updateFastNatSettings({
    required bool enabled,
    required bool autoFilter,
    required String portList,
  }) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update Fast NAT',
      request: () => _mqtt.setFastNatSettings(
        enabled: enabled,
        autoFilter: autoFilter,
        portList: portList,
      ),
    );
  }

  Future<Map<String, dynamic>?> loadVpnSettings() {
    return _readRouterSetting(_mqtt.getVpnSettings);
  }

  Future<Map<String, dynamic>?> loadVpnStatus() {
    return _readRouterSetting(_mqtt.getVpnStatus);
  }

  Future<SaveResult> updateVpnSettings(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update VPN',
      request: () => _mqtt.setVpnSettings(settings),
    );
  }

  Future<Map<String, dynamic>?> loadVirtualServers() {
    return _readRouterSetting(_mqtt.getVirtualServers);
  }

  Future<SaveResult> addVirtualServer(Map<String, dynamic> rule) {
    return _writeRouterSetting(
      failureMessage: 'Failed to add port forwarding rule',
      request: () => _mqtt.addVirtualServer(rule),
    );
  }

  Future<SaveResult> updateVirtualServer(Map<String, dynamic> rule) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update port forwarding rule',
      request: () => _mqtt.updateVirtualServer(rule),
    );
  }

  Future<SaveResult> deleteVirtualServer(String index) {
    return _writeRouterSetting(
      failureMessage: 'Failed to delete port forwarding rule',
      request: () => _mqtt.deleteVirtualServer(index),
    );
  }

  Future<Map<String, dynamic>?> loadDdnsSettings() {
    return _readRouterSetting(_mqtt.getDdnsSettings);
  }

  Future<Map<String, dynamic>?> loadDdnsStatus() {
    return _readRouterSetting(_mqtt.getDdnsStatus);
  }

  Future<SaveResult> updateDdnsSettings(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update DDNS',
      request: () => _mqtt.setDdnsSettings(settings),
    );
  }

  Future<Map<String, dynamic>?> loadLedSettings() async {
    final response = await _readRouterSetting(_mqtt.getLedSettings);
    final data = response?['Data'];
    if (data is List) {
      _ledNodes = _mapList(data);
      _ledUpdatedAt = DateTime.now();
      notifyListeners();
    }
    return response;
  }

  /// Background LED read: no error banner when the router does not answer.
  Future<void> refreshLeds() async {
    if (!isConnected) return;
    final response = await _mqtt.getLedSettings();
    final data = response?['Data'];
    if (response?['ErrorCode'] == 0 && data is List) {
      _ledNodes = _mapList(data);
      _ledUpdatedAt = DateTime.now();
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _ledNodes = [];
  DateTime? _ledUpdatedAt;

  /// GetLedList entries ({NodeSn, NickName, Led}); empty until loaded.
  List<Map<String, dynamic>> get ledNodes => List.unmodifiable(_ledNodes);
  bool get ledsLoaded => _ledUpdatedAt != null;
  DateTime? get ledUpdatedAt => _ledUpdatedAt;

  /// LED entry of the main router: the node reported with Role `mpp`, or
  /// the only/first LED entry when roles are unknown.
  Map<String, dynamic>? get mainRouterLed {
    if (_ledNodes.isEmpty) return null;
    final master = _nodes.where((n) => n.isMaster).firstOrNull;
    return _ledNodes
            .where((l) => master != null && '${l['NodeSn']}' == master.sn)
            .firstOrNull ??
        _ledNodes.first;
  }

  static bool isLedOn(Map<String, dynamic> entry) => '${entry['Led']}' == '1';

  final Map<String, int> _ledPending = {};

  /// Waits before each LED read-back after a write.
  static const ledReadBackDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
    Duration(milliseconds: 1200),
    Duration(milliseconds: 1600),
  ];

  /// LED value requested for [nodeSn] while the change is being applied and
  /// read back; null when nothing is pending. Never a confirmed state.
  int? ledRequested(String nodeSn) => _ledPending[nodeSn];
  bool get ledBusy => _ledPending.isNotEmpty;

  /// Reads GetLedList and returns the reported LED value for [nodeSn].
  Future<int?> _readLedState(String nodeSn) async {
    final response = await _mqtt.getLedSettings();
    final data = response?['Data'];
    if (response?['ErrorCode'] != 0 || data is! List) return null;
    _ledNodes = _mapList(data);
    _ledUpdatedAt = DateTime.now();
    final entry = _ledNodes
        .where((l) => '${l['NodeSn']}' == nodeSn)
        .firstOrNull;
    return entry == null ? null : _readInt(entry['Led'], -1);
  }

  /// Sets one node's LED, then reads the state back. The displayed state
  /// only changes from the read-back; a failed or unconfirmed request
  /// leaves the previous state. Overlapping LED commands are refused.
  Future<SaveResult> updateNodeLed({
    required String nodeSn,
    required int led,
  }) async {
    if (_ledPending.isNotEmpty) {
      return const SaveResult.failed('An LED change is already in progress.');
    }
    _ledPending[nodeSn] = led;
    notifyListeners();
    try {
      final result = await _writeRouterSetting(
        label: 'LED change',
        failureMessage: 'Failed to update the router LED',
        request: () => _mqtt.setNodeLed(nodeSn: nodeSn, led: led),
      );
      if (!result.isConfirmed) return result;
      // The router acknowledges SetNodeLed before the LED changes, so an
      // immediate read can still report the old state. Re-read briefly.
      int? reported;
      for (final delay in ledReadBackDelays) {
        await Future<void>.delayed(delay);
        reported = await _readLedState(nodeSn);
        if (reported == led) break;
      }
      final wanted = led == 1 ? 'on' : 'off';
      if (reported == null) {
        return SaveResult.pending(
          'The router accepted the LED change but did not report the LED '
          'state yet. Showing the last confirmed state.',
        );
      }
      if (reported == led) {
        return SaveResult.confirmed('Router LED turned $wanted.');
      }
      _addEvent(
        'LED change not applied',
        'The router still reports the LED ${reported == 1 ? 'on' : 'off'}.',
        'error',
      );
      return SaveResult.failed(
        'The router still reports the LED ${reported == 1 ? 'on' : 'off'}.',
      );
    } finally {
      _ledPending.remove(nodeSn);
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> loadRestartSchedule() {
    return _readRouterSetting(_mqtt.getRestartSchedule);
  }

  Future<SaveResult> updateRestartSchedule(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update restart schedule',
      request: () => _mqtt.setRestartSchedule(settings),
    );
  }

  Future<Map<String, dynamic>?> _readRouterSetting(
    Future<Map<String, dynamic>?> Function() request,
  ) async {
    if (!isConnected) {
      _errorMessage = 'Authentication required for router settings';
      notifyListeners();
      return null;
    }

    final response = await request();
    if (response == null) {
      _errorMessage = 'Router did not answer the settings request';
      notifyListeners();
    } else if (response['ErrorCode'] != 0) {
      _errorMessage =
          'Router returned error ${response['ErrorCode']} for the settings request';
      notifyListeners();
      return null;
    }
    return response;
  }

  /// Sends a configuration change.
  ///
  /// With [verify], a missing reply (the session dropped while the router
  /// applied the change) becomes [SaveStatus.pendingVerification] and the
  /// result is checked by re-reading the router after it reconnects.
  /// Without [verify], a missing reply is a failure.
  Future<SaveResult> _writeRouterSetting({
    required String failureMessage,
    required Future<Map<String, dynamic>?> Function() request,
    String label = 'Change',
    Future<bool?> Function()? verify,
  }) async {
    if (!isConnected) {
      _errorMessage = 'Authentication required for router settings';
      notifyListeners();
      return const SaveResult.failed('Not connected to the router.');
    }

    _isLoading = true;
    notifyListeners();

    Map<String, dynamic>? response;
    try {
      response = await request();
    } catch (e) {
      debugPrint('RouterProvider: write failed - $e');
      response = null;
    } finally {
      _isLoading = false;
    }

    final SaveResult result;
    if (response != null) {
      final code = response['ErrorCode'];
      result = code == 0
          ? SaveResult.confirmed('$label saved.')
          : SaveResult.failed('$failureMessage (router error $code).');
    } else if (verify != null) {
      _startVerification(label, verify);
      result = SaveResult.pending(
        '$label sent. The connection may drop briefly; the app will confirm '
        'the new settings when it reconnects.',
      );
    } else {
      result = SaveResult.failed(
        '$failureMessage: the router did not answer. The change may not '
        'have been applied.',
      );
    }

    if (result.isFailed) {
      _errorMessage = result.message;
      _addEvent('$label failed', result.message, 'error');
    }
    notifyListeners();
    return result;
  }

  void _startVerification(String label, Future<bool?> Function() verify) {
    final change = PendingChange(id: _nextChangeId++, label: label);
    _pendingChanges.add(change);
    _addEvent(
      '$label pending',
      'Sent to the router. The app will confirm it after reconnecting.',
      'info',
    );
    notifyListeners();
    _runVerification(change, verify, _sessionGeneration);
  }

  Future<void> _runVerification(
    PendingChange change,
    Future<bool?> Function() verify,
    int session,
  ) async {
    // Give the router time to apply the change and drop the session first.
    await Future<void>.delayed(const Duration(seconds: 3));
    final deadline = DateTime.now().add(verificationWindow);
    while (!isConnected && DateTime.now().isBefore(deadline)) {
      if (session != _sessionGeneration) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (session != _sessionGeneration || !_pendingChanges.contains(change)) {
      return;
    }

    bool? matches;
    if (isConnected) {
      try {
        matches = await verify();
      } catch (e) {
        debugPrint('RouterProvider: verification failed - $e');
      }
    }
    change.status = switch (matches) {
      true => ChangeStatus.confirmed,
      false => ChangeStatus.mismatch,
      null => ChangeStatus.unverified,
    };
    _addEvent(
      change.label,
      change.message,
      matches == true ? 'success' : (matches == false ? 'error' : 'warning'),
    );
    notifyListeners();
  }

  void dismissPendingChange(PendingChange change) {
    _pendingChanges.remove(change);
    notifyListeners();
  }

  Future<bool?> _verifyListSubset(
    Future<Map<String, dynamic>?> Function() reader,
    List<Map<String, dynamic>> sent,
    List<String> keys,
  ) async {
    final response = await reader();
    if (response == null || response['ErrorCode'] != 0) return null;
    final data = response['Data'];
    final fresh = data is List
        ? _mapList(data)
        : data is Map
        ? [Map<String, dynamic>.from(data)]
        : null;
    if (fresh == null || fresh.length < sent.length) return null;
    var unknown = false;
    for (var i = 0; i < sent.length; i++) {
      final match = _subsetMatches(fresh[i], sent[i], keys);
      if (match == false) return false;
      if (match == null) unknown = true;
    }
    return unknown ? null : true;
  }

  /// True when every sent entry is present with the same values, false when
  /// any compared value differs, null when the router's reply lacks an entry
  /// or a compared field (the change cannot be confirmed either way).
  static bool? _matchesByIndex(
    List<Map<String, dynamic>> fresh,
    List<Map<String, dynamic>> sent,
    List<String> keys,
  ) {
    var unknown = false;
    for (final expected in sent) {
      final actual = fresh
          .where((n) => '${n['Index']}' == '${expected['Index']}')
          .firstOrNull;
      if (actual == null) {
        unknown = true;
        continue;
      }
      final match = _subsetMatches(actual, expected, keys);
      if (match == false) return false;
      if (match == null) unknown = true;
    }
    return unknown ? null : true;
  }

  /// Compares [keys] that were sent. A sent key missing from [actual] makes
  /// the result unknown (null) instead of silently counting as a match.
  static bool? _subsetMatches(
    Map<String, dynamic> actual,
    Map<String, dynamic> expected,
    List<String> keys,
  ) {
    var compared = 0;
    var unknown = false;
    for (final key in keys) {
      if (!expected.containsKey(key)) continue;
      if (!actual.containsKey(key)) {
        unknown = true;
        continue;
      }
      compared++;
      if ('${actual[key]}' != '${expected[key]}') return false;
    }
    return unknown || compared == 0 ? null : true;
  }

  Future<void> refreshUsbStorage() async {
    if (!isConnected || _usbStorageLoading) return;

    _usbStorageLoading = true;
    notifyListeners();

    try {
      final responses = await Future.wait([
        _mqtt.getPrivateStorage(),
        _mqtt.getDiskInfo(),
        _mqtt.getStorageVisitAddress(),
      ]);

      final settings = responses[0];
      if (settings != null && settings['ErrorCode'] == 0) {
        final data = settings['Data'];
        if (data is Map) {
          _usbStorageSettings = UsbStorageSettings.fromJson(
            Map<String, dynamic>.from(data),
          );
        }
      }

      final disks = responses[1];
      if (disks != null && disks['ErrorCode'] == 0) {
        final data = disks['Data'];
        if (data is List) {
          _usbDisks = _mapList(data).map(UsbDisk.fromJson).toList();
        }
      }

      final visitAddress = responses[2];
      if (visitAddress != null && visitAddress['ErrorCode'] == 0) {
        final data = visitAddress['Data'];
        if (data is Map) {
          final addr = data['Addr']?.toString().trim();
          _usbVisitAddress = addr == null || addr.isEmpty ? null : addr;
        }
      }
    } finally {
      _usbStorageLoading = false;
      notifyListeners();
    }
  }

  Future<SaveResult> updateUsbStorageSettings(
    UsbStorageSettings updated,
  ) async {
    if (_usbStorageSaving) {
      return const SaveResult.failed(
        'A storage change is already in progress.',
      );
    }
    _usbStorageSaving = true;
    notifyListeners();
    final result = await _writeRouterSetting(
      label: 'USB storage change',
      failureMessage: 'Failed to update USB storage settings',
      request: () => _mqtt.setPrivateStorage(
        usb3Enabled: updated.usb3Enabled,
        sambaEnabled: updated.sambaEnabled,
        anonymousAccess: updated.anonymousAccess,
      ),
    );
    _usbStorageSaving = false;
    if (result.isConfirmed) _usbStorageSettings = updated;
    notifyListeners();
    return result;
  }

  /// Asks every mesh node to restart. The router may drop the session before
  /// acknowledging, which is reported as pending rather than as a failure.
  Future<SaveResult> rebootRouter() async {
    if (!isConnected) {
      _errorMessage = 'Cannot reboot: Authentication required';
      notifyListeners();
      return const SaveResult.failed('Not connected to the router.');
    }

    final response = await _mqtt.rebootRouter();
    if (response == null) {
      return const SaveResult.pending(
        'Restart requested. The router did not confirm before the connection '
        'dropped; the app reconnects automatically when it is back.',
      );
    }
    if (response['ErrorCode'] == 0) {
      return const SaveResult.confirmed(
        'Router is restarting. The app reconnects automatically.',
      );
    }
    return SaveResult.failed(
      'Router refused the restart (error ${response['ErrorCode']}).',
    );
  }

  Future<void> logout() async {
    _beginSession();
    _allowReconnect = false;
    _reconnectInProgress = false;
    _stopAutoRefresh();
    await _mqtt.disconnect();

    _authState = AuthenticationState.notAuthenticated;
    _devices = [];
    _nodes = [];
    _systemStatus = null;
    _wirelessSettings = null;
    _wirelessNetworksRaw = [];
    _wirelessNetworksParsed = [];
    _wirelessLoaded = false;
    _wanSettings = null;
    _wanUpdatedAt = null;
    _guestUpdatedAt = null;
    _lanSettings = null;
    _connectionInfo = null;
    _nodeRateInfo = [];
    _wanUpRate = 0;
    _wanDownRate = 0;
    _usbStorageSettings = null;
    _usbDisks = [];
    _usbVisitAddress = null;
    _guestWifi = null;
    _wanInfo = null;
    _rateSamples.clear();
    _ledNodes = [];
    _ledUpdatedAt = null;
    _usbStorageLoading = false;
    _usbStorageSaving = false;
    _liveTelemetryResponsive = true;
    _telemetryMisses = 0;
    _devicesUpdatedAt = null;
    _telemetryUpdatedAt = null;
    _nodesUpdatedAt = null;
    _wirelessUpdatedAt = null;
    _pendingChanges.clear();
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  int _connectionInt(String key, int fallback) {
    return _readInt(_connectionInfo?[key], fallback);
  }

  int _readInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static List<Map<String, dynamic>> _mapList(List data) => data
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();

  void setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _discoverySubscription?.cancel();
    _connectionSubscription?.cancel();
    _refreshTimer?.cancel();
    _liveTimer?.cancel();
    _reconnectTimer?.cancel();
    _discovery.dispose();
    _mqtt.dispose();
    super.dispose();
  }
}
