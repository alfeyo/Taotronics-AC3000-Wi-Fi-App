import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/mesh_entity.dart';
import '../models/device_entity.dart';
import '../models/usb_storage.dart';
import '../models/wireless_network.dart';
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

class RouterProvider extends ChangeNotifier {
  final RouterDiscoveryService _discovery = RouterDiscoveryService();
  final MqttService _mqtt = MqttService();
  final AuthPairingService _authService = AuthPairingService();

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
  bool _livePaused = false;
  bool _liveTelemetryResponsive = true;
  bool _reconnectInProgress = false;
  bool _allowReconnect = true;
  int _reconnectAttempt = 0;

  void pauseLive() {
    _livePaused = true;
  }

  void resumeLive() {
    _livePaused = false;
  }

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
  bool get internetConnected => _connectionInt('Internet', 0) == 1;

  String get networkQualityLabel {
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

  RouterProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _authService.loadSavedPairings();
    _discoveryState = RouterDiscoveryState.scanning;
    notifyListeners();

    _discoverySubscription = _discovery.routerStream.listen(
      _onRouterDiscovered,
    );
    _connectionSubscription = _mqtt.connectionStream.listen(
      _onConnectionChanged,
    );
    await _discovery.startDiscovery();
  }

  void _onRouterDiscovered(DiscoveredRouter discovered) {
    final existing = _routers.indexWhere((r) => r.meshId == discovered.meshId);

    if (existing >= 0) {
      _routers[existing].ipAddress = discovered.ipAddress;
      _routers[existing].state = 1;
    } else {
      _routers.add(
        MeshEntity(
          meshId: discovered.meshId,
          ssid: 'Router ${_routers.length + 1}',
          ipAddress: discovered.ipAddress,
          state: 1,
        ),
      );
    }

    _discoveryState = RouterDiscoveryState.routerFound;

    if (_currentRouter == null && _routers.isNotEmpty) {
      selectRouter(_routers.first);
    } else if (_currentRouter?.meshId == discovered.meshId &&
        !isConnected &&
        _authService.isPaired(discovered.meshId)) {
      _scheduleReconnect();
    }

    notifyListeners();
  }

  void _onConnectionChanged(bool connected) {
    if (connected) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectAttempt = 0;
      _reconnectInProgress = false;
      _authState = AuthenticationState.authenticated;
      _errorMessage = null;
      _startAutoRefresh();
      refreshAll();
    } else {
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

  Future<void> selectRouter(MeshEntity router) async {
    _allowReconnect = true;
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
    _allowReconnect = true;
    _authState = AuthenticationState.authenticating;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final success = await _mqtt.connect(meshId, ipAddress, password: password);

    if (success) {
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
      refreshAll();
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
        _reconnectInProgress ||
        _reconnectTimer?.isActive == true) {
      return;
    }

    final attempt = _reconnectAttempt;
    final seconds = switch (attempt) {
      0 => 1,
      1 => 2,
      2 => 4,
      _ => 8,
    };
    _reconnectAttempt++;
    debugPrint(
      'RouterProvider: reconnecting saved router in ${seconds}s '
      '(attempt $_reconnectAttempt)',
    );
    _reconnectTimer = Timer(
      Duration(seconds: seconds),
      _reconnectCurrentRouter,
    );
  }

  Future<void> _reconnectCurrentRouter() async {
    _reconnectTimer = null;
    if (!_shouldReconnectCurrentRouter || _reconnectInProgress) return;

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
    if (success) {
      _authState = AuthenticationState.authenticated;
      _errorMessage = null;
    } else if (_shouldReconnectCurrentRouter) {
      _authState = AuthenticationState.authenticating;
      _scheduleReconnect();
    }
    notifyListeners();
  }

  Future<void> _liveRefresh() async {
    if (!isConnected || _liveRefreshing || _refreshing || _livePaused) return;
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
        _dailyFlow = data.cast<Map<String, dynamic>>();
        var up = 0;
        var down = 0;
        for (final entry in _dailyFlow) {
          up += (entry['UpBytes'] as num?)?.toInt() ?? 0;
          down += (entry['DownBytes'] as num?)?.toInt() ?? 0;
        }
        _todayUpBytes = up;
        _todayDownBytes = down;
      }
    }

    final monthly = responses[1];
    if (monthly != null && monthly['ErrorCode'] == 0) {
      final data = monthly['Data'];
      if (data is List) {
        _monthlyFlow = data.cast<Map<String, dynamic>>();
        var up = 0;
        var down = 0;
        for (final entry in _monthlyFlow) {
          up += (entry['UpBytes'] as num?)?.toInt() ?? 0;
          down += (entry['DownBytes'] as num?)?.toInt() ?? 0;
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
    _liveTelemetryResponsive = responses.any((response) => response != null);

    final connect = responses[0];
    if (connect != null && connect['ErrorCode'] == 0) {
      final data = connect['Data'];
      if (data is Map<String, dynamic>) {
        _connectionInfo = data;
      }
    }

    final nodeRates = responses[1];
    if (nodeRates != null && nodeRates['ErrorCode'] == 0) {
      final data = nodeRates['Data'];
      if (data is List) {
        _nodeRateInfo = data.whereType<Map>().map((entry) {
          return Map<String, dynamic>.from(entry);
        }).toList();
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

    notifyListeners();
  }

  Future<void> refreshSystemStatus() async {
    final response = await _mqtt.getSystemStatus();
    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is Map<String, dynamic>) {
        _systemStatus = data;
      } else if (data is List && data.isNotEmpty) {
        _systemStatus = data.first as Map<String, dynamic>?;
      }
      notifyListeners();
    }
  }

  Future<void> refreshDevices() async {
    final response = await _mqtt.getDeviceList();
    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is List) {
        _devices = data
            .map((d) => DeviceEntity.fromJson(d as Map<String, dynamic>))
            .toList();
      } else if (data is Map && data['ClientList'] is List) {
        _devices = (data['ClientList'] as List)
            .map((d) => DeviceEntity.fromJson(d as Map<String, dynamic>))
            .toList();
      }
      notifyListeners();
    }
  }

  Future<void> refreshNodes() async {
    final response = await _mqtt.getNodeList();
    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is List) {
        _nodes = data
            .map((n) => NodeEntity.fromJson(n as Map<String, dynamic>))
            .toList();
      } else if (data is Map && data['NodeList'] is List) {
        _nodes = (data['NodeList'] as List)
            .map((n) => NodeEntity.fromJson(n as Map<String, dynamic>))
            .toList();
      }
      notifyListeners();
    }
  }

  Future<void> refreshWirelessSettings() async {
    _wirelessLoading = true;
    notifyListeners();

    final response = await _mqtt.getWirelessSettings();
    _wirelessLoading = false;
    _wirelessLoaded = true;

    if (response != null && response['ErrorCode'] == 0) {
      final data = response['Data'];
      if (data is List) {
        _wirelessNetworksRaw = data.cast<Map<String, dynamic>>();
        _wirelessNetworksParsed = _wirelessNetworksRaw
            .map((n) => WirelessNetwork.fromJson(n))
            .toList();
        if (_wirelessNetworksRaw.isNotEmpty) {
          _wirelessSettings = _wirelessNetworksRaw.first;
        }
      } else if (data is Map<String, dynamic>) {
        _wirelessSettings = data;
        _wirelessNetworksRaw = [data];
        _wirelessNetworksParsed = [WirelessNetwork.fromJson(data)];
      }
    }
    notifyListeners();
  }

  Future<bool> updateWirelessNetwork(WirelessNetwork updated) async {
    if (!isConnected) {
      _errorMessage = 'Cannot update Wi-Fi: Not connected';
      notifyListeners();
      return false;
    }

    final updatedList = _wirelessNetworksParsed.map((n) {
      if (n.index == updated.index) return updated;
      return n;
    }).toList();

    final payloadList = updatedList.map((n) => n.toRouterPayload()).toList();

    _isLoading = true;
    notifyListeners();

    Map<String, dynamic>? response;
    try {
      response = await _mqtt
          .setWirelessSettings(payloadList)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      response = null;
    }

    final success = response == null || response['ErrorCode'] == 0;

    if (!success) {
      _errorMessage = 'Failed to update Wi-Fi settings';
    } else {
      _wirelessNetworksParsed = updatedList;
      _wirelessNetworksRaw = payloadList;
    }

    _isLoading = false;
    notifyListeners();

    if (success) {
      Future.delayed(const Duration(seconds: 6), () {
        if (isConnected) refreshWirelessSettings();
      });
    }
    return success;
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

  Future<bool> updateWanSettings(List<Map<String, dynamic>> settings) {
    return _writeRouterSetting(
      'Failed to update WAN settings',
      () => _mqtt.setWanSettings(settings),
      acceptMissingResponse: true,
    );
  }

  Future<Map<String, dynamic>?> loadLanSettings() {
    return _readRouterSetting(_mqtt.getLanSettings);
  }

  Future<bool> updateLanSettings(List<Map<String, dynamic>> settings) {
    return _writeRouterSetting(
      'Failed to update LAN settings',
      () => _mqtt.setLanSettings(settings),
      acceptMissingResponse: true,
    );
  }

  Future<Map<String, dynamic>?> loadGuestWifiSettings() {
    return _readRouterSetting(_mqtt.getGuestWifi);
  }

  Future<bool> updateGuestWifiSettings(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      'Failed to update guest Wi-Fi',
      () => _mqtt.setGuestWifi(settings),
      acceptMissingResponse: true,
    );
  }

  Future<Map<String, dynamic>?> loadFirewallSettings() {
    return _readRouterSetting(_mqtt.getFirewallSettings);
  }

  Future<bool> updateFirewallSettings(bool enabled) {
    return _writeRouterSetting(
      'Failed to update firewall',
      () => _mqtt.setFirewallSettings(enabled),
    );
  }

  Future<Map<String, dynamic>?> loadUpnpDmzSettings() {
    return _readRouterSetting(_mqtt.getUpnpDmzSettings);
  }

  Future<bool> updateUpnpDmzSettings({
    required bool upnpEnabled,
    required bool dmzEnabled,
    required String dmzHost,
  }) {
    return _writeRouterSetting(
      'Failed to update UPnP and DMZ',
      () => _mqtt.setUpnpDmzSettings(
        upnpEnabled: upnpEnabled,
        dmzEnabled: dmzEnabled,
        dmzHost: dmzHost,
      ),
    );
  }

  Future<Map<String, dynamic>?> loadQosSettings() {
    return _readRouterSetting(_mqtt.getQosSettings);
  }

  Future<bool> updateQosSettings({
    required bool enabled,
    required int upBandwidth,
    required int downBandwidth,
  }) {
    return _writeRouterSetting(
      'Failed to update QoS',
      () => _mqtt.setQosSettings(
        enabled: enabled,
        upBandwidth: upBandwidth,
        downBandwidth: downBandwidth,
      ),
    );
  }

  Future<Map<String, dynamic>?> loadFastNatSettings() {
    return _readRouterSetting(_mqtt.getFastNatSettings);
  }

  Future<bool> updateFastNatSettings({
    required bool enabled,
    required bool autoFilter,
    required String portList,
  }) {
    return _writeRouterSetting(
      'Failed to update Fast NAT',
      () => _mqtt.setFastNatSettings(
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

  Future<bool> updateVpnSettings(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      'Failed to update VPN',
      () => _mqtt.setVpnSettings(settings),
    );
  }

  Future<Map<String, dynamic>?> loadVirtualServers() {
    return _readRouterSetting(_mqtt.getVirtualServers);
  }

  Future<bool> addVirtualServer(Map<String, dynamic> rule) {
    return _writeRouterSetting(
      'Failed to add port forwarding rule',
      () => _mqtt.addVirtualServer(rule),
    );
  }

  Future<bool> updateVirtualServer(Map<String, dynamic> rule) {
    return _writeRouterSetting(
      'Failed to update port forwarding rule',
      () => _mqtt.updateVirtualServer(rule),
    );
  }

  Future<bool> deleteVirtualServer(String index) {
    return _writeRouterSetting(
      'Failed to delete port forwarding rule',
      () => _mqtt.deleteVirtualServer(index),
    );
  }

  Future<Map<String, dynamic>?> loadDdnsSettings() {
    return _readRouterSetting(_mqtt.getDdnsSettings);
  }

  Future<Map<String, dynamic>?> loadDdnsStatus() {
    return _readRouterSetting(_mqtt.getDdnsStatus);
  }

  Future<bool> updateDdnsSettings(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      'Failed to update DDNS',
      () => _mqtt.setDdnsSettings(settings),
    );
  }

  Future<Map<String, dynamic>?> loadLedSettings() {
    return _readRouterSetting(_mqtt.getLedSettings);
  }

  Future<bool> updateNodeLed({required String nodeSn, required int led}) {
    return _writeRouterSetting(
      'Failed to update node LED',
      () => _mqtt.setNodeLed(nodeSn: nodeSn, led: led),
    );
  }

  Future<Map<String, dynamic>?> loadRestartSchedule() {
    return _readRouterSetting(_mqtt.getRestartSchedule);
  }

  Future<bool> updateRestartSchedule(Map<String, dynamic> settings) {
    return _writeRouterSetting(
      'Failed to update restart schedule',
      () => _mqtt.setRestartSchedule(settings),
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
    }
    return response;
  }

  Future<bool> _writeRouterSetting(
    String failureMessage,
    Future<Map<String, dynamic>?> Function() request, {
    bool acceptMissingResponse = false,
  }) async {
    if (!isConnected) {
      _errorMessage = 'Authentication required for router settings';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    Map<String, dynamic>? response;
    try {
      response = await request();
    } finally {
      _isLoading = false;
    }

    final success =
        (acceptMissingResponse && response == null) ||
        (response != null && response['ErrorCode'] == 0);
    if (!success) {
      _errorMessage = failureMessage;
    }
    notifyListeners();
    return success;
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
          _usbDisks = data.whereType<Map>().map((entry) {
            return UsbDisk.fromJson(Map<String, dynamic>.from(entry));
          }).toList();
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

  Future<bool> updateUsbStorageSettings(UsbStorageSettings updated) async {
    if (!isConnected || _usbStorageSaving) return false;

    _usbStorageSaving = true;
    notifyListeners();

    Map<String, dynamic>? response;
    try {
      response = await _mqtt.setPrivateStorage(
        usb3Enabled: updated.usb3Enabled,
        sambaEnabled: updated.sambaEnabled,
        anonymousAccess: updated.anonymousAccess,
      );
    } finally {
      _usbStorageSaving = false;
    }

    final success = response != null && response['ErrorCode'] == 0;
    if (success) {
      _usbStorageSettings = updated;
    } else {
      _errorMessage = 'Failed to update USB storage settings';
    }
    notifyListeners();
    return success;
  }

  Future<bool> setWirelessSettings(List<Map<String, dynamic>> networks) async {
    if (!isConnected) {
      _errorMessage = 'Cannot update settings: Authentication required';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    final normalized = networks
        .map(
          (net) => <String, dynamic>{
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

    Map<String, dynamic>? response;
    try {
      response = await _mqtt
          .setWirelessSettings(normalized)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      response = null;
    }

    // Router restarts Wi-Fi after this command and the MQTT session may drop
    // before a reply arrives. Treat no-reply / connection loss as success
    // (the router is applying the change). An ErrorCode != 0 is a real failure.
    final success = response == null || response['ErrorCode'] == 0;

    if (!success) {
      _errorMessage = 'Failed to update wireless settings';
    }

    _isLoading = false;
    notifyListeners();

    if (success) {
      Future.delayed(const Duration(seconds: 6), () {
        if (isConnected) refreshWirelessSettings();
      });
    }
    return success;
  }

  Future<bool> rebootRouter() async {
    if (!isConnected) {
      _errorMessage = 'Cannot reboot: Authentication required';
      notifyListeners();
      return false;
    }

    final response = await _mqtt.rebootRouter();
    return response != null && response['ErrorCode'] == 0;
  }

  Future<void> logout() async {
    _allowReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectInProgress = false;
    _reconnectAttempt = 0;
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
