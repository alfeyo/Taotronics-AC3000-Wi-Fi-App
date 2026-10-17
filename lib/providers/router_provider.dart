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
    if (autoStart) _initialize();
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
  /// asking for telemetry (the full refresh keeps retrying). The router
  /// occasionally answers a few hundred ms after the 4 s timeout, so a single
  /// miss must not switch the dashboard to stale values.
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

  Future<void> _initialize() async {
    await _authService.loadSavedPairings();
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
      _authState = AuthenticationState.authenticated;
      _errorMessage = null;
      _startAutoRefresh();
      refreshAll();
    } else {
      // Only unexpected drops of an established session arrive here.
      _stopAutoRefresh();
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
      _scheduleReconnect();
    }
    notifyListeners();
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
      await Future.wait(liveWork).timeout(const Duration(seconds: 5));
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
    notifyListeners();
    return ok;
  }

  Future<SaveResult> updateWirelessNetwork(WirelessNetwork updated) {
    final payloadList = _wirelessNetworksParsed
        .map((n) => n.index == updated.index ? updated : n)
        .map((n) => n.toRouterPayload())
        .toList();
    return setWirelessSettings(payloadList);
  }

  Future<SaveResult> setWirelessSettings(
    List<Map<String, dynamic>> networks,
  ) async {
    final normalized = networks
        .map(
          (net) => <String, dynamic>{
            ...net,
            'Ssid': net['Ssid'] ?? '',
            'Encrypt': net['Encrypt'] ?? 0,
            'Password': net['Password'] ?? '',
            'Vlanid': net['Vlanid'] ?? 0,
            'SsidIsolate': net['SsidIsolate'] ?? 0,
            'StaIsolate': net['StaIsolate'] ?? 0,
            'Index': net['Index'] ?? 0,
            'Create': net['Create'] ?? 1,
            'VlanEnable': net['VlanEnable'] ?? 0,
          },
        )
        .toList();

    // The router restarts Wi-Fi when applying this and often drops the
    // session before replying, so a missing reply is verified afterwards.
    final result = await _writeRouterSetting(
      label: 'Wi-Fi change',
      failureMessage: 'Failed to update Wi-Fi settings',
      request: () => _mqtt.setWirelessSettings(normalized),
      verify: () async {
        if (!await refreshWirelessSettings()) return null;
        return _matchesByIndex(_wirelessNetworksRaw, normalized, const [
          'Ssid',
          'Password',
          'Disable',
        ]);
      },
    );
    if (result.isConfirmed) {
      _wirelessNetworksRaw = normalized;
      _wirelessNetworksParsed = normalized
          .map(WirelessNetwork.fromJson)
          .toList();
      notifyListeners();
    }
    return result;
  }

  Future<void> refreshWanSettings() async {
    final response = await _mqtt.getWanSettings();
    if (response != null && response['ErrorCode'] == 0) {
      _wanSettings = response['Data'];
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

  Future<Map<String, dynamic>?> loadGuestWifiSettings() {
    return _readRouterSetting(_mqtt.getGuestWifi);
  }

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

  Future<Map<String, dynamic>?> loadLedSettings() {
    return _readRouterSetting(_mqtt.getLedSettings);
  }

  Future<SaveResult> updateNodeLed({required String nodeSn, required int led}) {
    return _writeRouterSetting(
      failureMessage: 'Failed to update node LED',
      request: () => _mqtt.setNodeLed(nodeSn: nodeSn, led: led),
    );
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

    if (result.isFailed) _errorMessage = result.message;
    notifyListeners();
    return result;
  }

  void _startVerification(String label, Future<bool?> Function() verify) {
    final change = PendingChange(id: _nextChangeId++, label: label);
    _pendingChanges.add(change);
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
    for (var i = 0; i < sent.length; i++) {
      if (!_subsetMatches(fresh[i], sent[i], keys)) return false;
    }
    return true;
  }

  static bool _matchesByIndex(
    List<Map<String, dynamic>> fresh,
    List<Map<String, dynamic>> sent,
    List<String> keys,
  ) {
    for (final expected in sent) {
      final actual = fresh
          .where((n) => '${n['Index']}' == '${expected['Index']}')
          .firstOrNull;
      if (actual == null || !_subsetMatches(actual, expected, keys)) {
        return false;
      }
    }
    return true;
  }

  static bool _subsetMatches(
    Map<String, dynamic> actual,
    Map<String, dynamic> expected,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (!expected.containsKey(key) || !actual.containsKey(key)) continue;
      if ('${actual[key]}' != '${expected[key]}') return false;
    }
    return true;
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
    _lanSettings = null;
    _connectionInfo = null;
    _nodeRateInfo = [];
    _wanUpRate = 0;
    _wanDownRate = 0;
    _usbStorageSettings = null;
    _usbDisks = [];
    _usbVisitAddress = null;
    _usbStorageLoading = false;
    _usbStorageSaving = false;
    _liveTelemetryResponsive = true;
    _telemetryMisses = 0;
    _devicesUpdatedAt = null;
    _telemetryUpdatedAt = null;
    _nodesUpdatedAt = null;
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
