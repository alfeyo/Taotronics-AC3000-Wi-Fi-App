import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mqtt_transport.dart';
import 'router_certificate_verifier.dart';

/// Local MQTT control channel to a TaoTronics mesh router.
///
/// Guarantees:
/// * Only one connection attempt runs at a time; a new [connect] waits for the
///   previous attempt instead of tearing its client down mid-handshake, and an
///   identical concurrent [connect] shares the attempt already in flight.
/// * [connectionStream] reports `false` only for unexpected drops of an
///   established session, never for deliberate disconnects or failed attempts
///   (callers get those from the [connect] result).
/// * Replies are matched by topic. The protocol has no request id, so requests
///   to the same path run one at a time and identical concurrent requests share
///   one round trip. Every request completes exactly once: with the reply, or
///   with `null` on timeout, disconnect or malformed payload.
class MqttService {
  MqttService({MqttTransportFactory? transportFactory, this._appIdLoader}) {
    _transportFactory = transportFactory ?? _defaultTransport;
  }

  static const int mqttPort = 25678;

  late final MqttTransportFactory _transportFactory;
  final Future<String> Function()? _appIdLoader;

  MqttTransport? _transport;
  StreamSubscription<MqttInbound>? _inboundSubscription;
  String? _meshId;
  String? _currentIp;
  String? _appId;
  bool _isConnected = false;

  Future<bool>? _connectInFlight;
  String? _connectInFlightKey;
  Future<void> _connectQueue = Future.value();

  final _pendingByTopic = <String, Completer<Map<String, dynamic>?>>{};
  final _pathQueues = <String, Future<void>>{};
  final _sharedRequests = <String, Future<Map<String, dynamic>?>>{};

  CertificateVerdict? _lastCertificateVerdict;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _isConnected;
  String? get connectedMeshId => _isConnected ? _meshId : null;

  /// Outcome of the most recent router certificate check, for diagnostics.
  CertificateVerdict? get lastCertificateVerdict => _lastCertificateVerdict;

  MqttTransport _defaultTransport(String host, int port) => ServerMqttTransport(
    host,
    port,
    verifier: RouterCertificateVerifier(pinnedAuthorityDer),
    onCertificateVerdict: (verdict) => _lastCertificateVerdict = verdict,
  );

  String _generatePassword(String meshId) {
    final input = 'dazoo$meshId';
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<bool> connect(String meshId, String ipAddress, {String? password}) {
    final key = '$meshId|$ipAddress|${password ?? ''}';
    final inFlight = _connectInFlight;
    if (inFlight != null && _connectInFlightKey == key) return inFlight;

    final previous = _connectQueue;
    final attempt = previous.then(
      (_) => _connectNow(meshId, ipAddress, password: password),
    );
    _connectQueue = attempt.then<void>((_) {}, onError: (_) {});
    _connectInFlight = attempt;
    _connectInFlightKey = key;
    attempt.whenComplete(() {
      if (identical(_connectInFlight, attempt)) {
        _connectInFlight = null;
        _connectInFlightKey = null;
      }
    });
    return attempt;
  }

  Future<bool> _connectNow(
    String meshId,
    String ipAddress, {
    String? password,
  }) async {
    if (_isConnected && _meshId == meshId && _currentIp == ipAddress) {
      return true;
    }

    await disconnect();

    final appId = await _loadAppId();
    final transport = _transportFactory(ipAddress, mqttPort);
    _transport = transport;
    _meshId = meshId;
    _currentIp = ipAddress;

    try {
      debugPrint('MqttService: Connecting to $ipAddress:$mqttPort');
      await transport.connect(
        clientId: appId,
        username: meshId,
        password: password ?? _generatePassword(meshId),
      );
    } catch (e) {
      debugPrint('MqttService: Connection failed - $e');
      if (identical(_transport, transport)) {
        _transport = null;
        _meshId = null;
        _currentIp = null;
      }
      try {
        transport.disconnect();
      } catch (_) {}
      return false;
    }

    if (!identical(_transport, transport)) {
      transport.disconnect();
      return false;
    }

    _inboundSubscription = transport.messages.listen(_handleInbound);
    transport.onDisconnected = () {
      if (identical(_transport, transport)) _handleUnexpectedDrop();
    };
    transport.subscribe('$appId/+');
    debugPrint('MqttService: Connected');
    _isConnected = true;
    _connectionController.add(true);
    return true;
  }

  void _handleUnexpectedDrop() {
    debugPrint('MqttService: Disconnected unexpectedly');
    _teardown();
    _connectionController.add(false);
  }

  void _handleInbound(MqttInbound message) {
    final Object? decoded;
    try {
      decoded = jsonDecode(message.payload);
    } catch (e) {
      debugPrint(
        'MqttService: Failed to parse message on ${message.topic} - $e',
      );
      return;
    }
    final data = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    if (data != null) {
      _messageController.add({'topic': message.topic, 'data': data});
    }

    final pending = _pendingByTopic.remove(message.topic);
    if (pending == null || pending.isCompleted) return;
    if (data == null) {
      debugPrint('MqttService: Non-object reply on ${message.topic} ignored');
    }
    pending.complete(data);
  }

  /// Sends `data` to the router command `path` and waits for its reply.
  Future<Map<String, dynamic>?> sendCommand(
    String path,
    dynamic data, {
    int timeout = 10,
    int routerTimeout = 0,
  }) {
    if (!_isConnected) return Future.value(null);

    final String shareKey;
    try {
      shareKey = '$path|$routerTimeout|${jsonEncode(data)}';
    } catch (e) {
      debugPrint('MqttService: Cannot encode $path payload - $e');
      return Future.value(null);
    }
    final shared = _sharedRequests[shareKey];
    if (shared != null) return shared;

    final previous = _pathQueues[path] ?? Future<void>.value();
    final request = previous.then(
      (_) =>
          _sendNow(path, data, timeout: timeout, routerTimeout: routerTimeout),
    );
    final done = request.then<void>((_) {});
    _pathQueues[path] = done;
    _sharedRequests[shareKey] = request;
    request.whenComplete(() {
      if (identical(_sharedRequests[shareKey], request)) {
        _sharedRequests.remove(shareKey);
      }
      if (identical(_pathQueues[path], done)) _pathQueues.remove(path);
    });
    return request;
  }

  Future<Map<String, dynamic>?> _sendNow(
    String path,
    dynamic data, {
    required int timeout,
    required int routerTimeout,
  }) async {
    final transport = _transport;
    final meshId = _meshId;
    if (!_isConnected || transport == null || meshId == null) return null;

    final appId = await _loadAppId();
    final responseTopic = '$appId$path';
    final completer = Completer<Map<String, dynamic>?>();
    _pendingByTopic[responseTopic] = completer;

    final payload = {
      'AppId': appId,
      'Timeout': routerTimeout,
      'ErrorCode': 0,
      'Data': data,
      'Timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    try {
      transport.publish('$meshId/$appId$path', jsonEncode(payload));
    } catch (e) {
      debugPrint('MqttService: publish failed - $e');
      if (identical(_pendingByTopic[responseTopic], completer)) {
        _pendingByTopic.remove(responseTopic);
      }
      return null;
    }

    final timer = Timer(Duration(seconds: timeout), () {
      if (completer.isCompleted) return;
      debugPrint('MqttService: timeout waiting for $responseTopic');
      if (identical(_pendingByTopic[responseTopic], completer)) {
        _pendingByTopic.remove(responseTopic);
      }
      completer.complete(null);
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }

  Future<Map<String, dynamic>?> getSystemStatus() async {
    return sendCommand('/GetSystemState', {});
  }

  Future<Map<String, dynamic>?> getDeviceList() async {
    return sendCommand('/GetDevListInfo', [
      {
        'GroupId': '',
        'GroupName': '',
        'GroupType': 0,
        'Devices': [{}],
      },
    ]);
  }

  Future<Map<String, dynamic>?> getNodeList() async {
    return sendCommand('/GetExistNode', [
      {
        'NodeSn': '',
        'OnLine': 0,
        'NickName': '',
        'ClientNum': 0,
        'Role': '',
        'Uptime': 0,
        'Model': '',
        'LocalConn': 0,
        'AddTime': 0,
      },
    ]);
  }

  /// Routers that left GetWirelessInfoListV2 unanswered while V1 worked.
  /// The router handles commands one at a time and an unanswered V2 request
  /// blocks every other command for ~10 s, so it is only tried once.
  final _wirelessV2Unsupported = <String>{};

  Future<Map<String, dynamic>?> getWirelessSettings() async {
    final meshId = _meshId;
    if (meshId != null && _wirelessV2Unsupported.contains(meshId)) {
      return _getWirelessSettingsV1();
    }
    final v2Result = await sendCommand('/GetWirelessInfoListV2', [
      {
        'Ssid': '',
        'Encrypt': 0,
        'Password': '',
        'Vlanid': 0,
        'VlanEnable': 0,
        'SsidIsolate': 0,
        'StaIsolate': 0,
        'Index': 0,
        'Create': 0,
        'Disable': 0,
        'ConfStatus': 0,
        'NodeSn': '',
      },
    ]);

    if (v2Result != null && v2Result['ErrorCode'] == 0) {
      return v2Result;
    }

    final v1Result = await _getWirelessSettingsV1();
    if (v2Result == null &&
        v1Result != null &&
        v1Result['ErrorCode'] == 0 &&
        meshId != null &&
        meshId == _meshId) {
      debugPrint('MqttService: $meshId does not answer V2 wireless; using V1');
      _wirelessV2Unsupported.add(meshId);
    }
    return v1Result;
  }

  Future<Map<String, dynamic>?> _getWirelessSettingsV1() {
    return sendCommand('/GetWirelessInfoList', [
      {
        'Ssid': '',
        'Encrypt': 0,
        'Password': '',
        'Vlanid': 0,
        'VlanEnable': 0,
        'SsidIsolate': 0,
        'StaIsolate': 0,
        'Index': 0,
        'Create': 0,
      },
    ]);
  }

  Future<Map<String, dynamic>?> setWirelessSettings(
    List<Map<String, dynamic>> networks,
  ) async {
    return sendCommand('/SetWirelessInfoList', networks, timeout: 8);
  }

  Future<Map<String, dynamic>?> getNetworkFlowDaily() async {
    return sendCommand('/GetSumOfNetworkFlowDaily', {});
  }

  Future<Map<String, dynamic>?> getNetworkFlowMonthly() async {
    return sendCommand('/GetSumOfNetworkFlowMonthly', {});
  }

  Future<Map<String, dynamic>?> getSystemConnectionInfo() async {
    return sendCommand(
      '/GetSysConnectInfo',
      {
        'Internet': 0,
        'OnlineNodeCount': 0,
        'TotalNodeCount': 0,
        'OnlineDev': 0,
        'OnlineGuestDev': 0,
        'NetworkQuality': 0,
      },
      timeout: 4,
      routerTimeout: 2,
    );
  }

  Future<Map<String, dynamic>?> getNodeRateInfo() async {
    return sendCommand(
      '/GetNodeRateInfo',
      [
        {'MeshNodeName': '', 'Rate': 0},
      ],
      timeout: 4,
      routerTimeout: 2,
    );
  }

  Future<Map<String, dynamic>?> getWanRateInfo() async {
    return sendCommand(
      '/GetWanRateInfo',
      [
        {'UpRate': 0, 'DownRate': 0},
      ],
      timeout: 4,
      routerTimeout: 2,
    );
  }

  Future<Map<String, dynamic>?> getPrivateStorage() async {
    return sendCommand('/GetPrivateStorageV2', {
      'Usb3En': 0,
      'SambaEn': 0,
      'Anonymous': 0,
    });
  }

  Future<Map<String, dynamic>?> setPrivateStorage({
    required bool usb3Enabled,
    required bool sambaEnabled,
    required bool anonymousAccess,
  }) async {
    return sendCommand('/SetPrivateStorageV2', {
      'Usb3En': usb3Enabled ? 1 : 0,
      'SambaEn': sambaEnabled ? 1 : 0,
      'Anonymous': anonymousAccess ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>?> getDiskInfo() async {
    return sendCommand('/GetDiskInfo', []);
  }

  Future<Map<String, dynamic>?> getStorageVisitAddress() async {
    return sendCommand('/GetVisitAddress', {});
  }

  Future<Map<String, dynamic>?> getGuestWifi() async {
    return sendCommand('/GetGuestInfo', [
      {
        'Enable': 0,
        'Ssid': '',
        'EncryptionWay': 0,
        'Password': '',
        'VlanEnable': 0,
        'Vlanid': 0,
      },
    ]);
  }

  Future<Map<String, dynamic>?> setGuestWifi(Map<String, dynamic> guest) async {
    return sendCommand('/SetGuestInfo', [guest], timeout: 15);
  }

  Future<Map<String, dynamic>?> getWanSettings() async {
    return sendCommand('/GetMWanInfo', [
      {
        'WanProto': 0,
        'WanIp': '',
        'WanMask': '',
        'WanGateway': '',
        'ManualDns': 0,
        'WanDns': '',
        'WanDnsbak': '',
        'PppoeUser': '',
        'PppoePass': '',
        'PppoeServiceName': '',
        'PppoeACName': '',
        'VlanDisabled': 0,
        'VlanId': 0,
      },
      {
        'WanDisabled': 0,
        'WanProto': 0,
        'WanIp': '',
        'WanMask': '',
        'WanGateway': '',
        'ManualDns': 0,
        'WanDns': '',
        'WanDnsbak': '',
        'PppoeUser': '',
        'PppoePass': '',
        'PppoeServiceName': '',
        'PppoeACName': '',
      },
    ]);
  }

  Future<Map<String, dynamic>?> setWanSettings(
    List<Map<String, dynamic>> settings,
  ) async {
    return sendCommand('/SetMWanInfo', settings, timeout: 15);
  }

  Future<Map<String, dynamic>?> getLanSettings() async {
    final data = [
      {
        'LanMode': 0,
        'LanIp': '',
        'LanMask': '',
        'LanGateway': '',
        'LanDns': '',
        'LanDnsBak': '',
      },
      {'DhcpDisabled': 0, 'DhcpStartAddr': '', 'DhcpEndAddr': ''},
      {'VlanEnable': 0, 'Vlanid': 0},
    ];
    final v3 = await sendCommand('/GetLanInfoV3', data);
    if (v3 != null && v3['ErrorCode'] == 0) {
      return v3;
    }

    return sendCommand('/GetLanInfo', data.sublist(0, 2));
  }

  Future<Map<String, dynamic>?> setLanSettings(
    List<Map<String, dynamic>> settings,
  ) async {
    return sendCommand('/SetLanInfoV3', settings, timeout: 15);
  }

  Future<Map<String, dynamic>?> getFirewallSettings() async {
    return sendCommand('/GetFirewallInfo', {'Enable': 0});
  }

  Future<Map<String, dynamic>?> setFirewallSettings(bool enabled) async {
    return sendCommand('/SetFirewallInfo', {'Enable': enabled ? 1 : 0});
  }

  Future<Map<String, dynamic>?> getUpnpDmzSettings() async {
    return sendCommand('/GetUpnpDmz', [
      {'UpnpEnabled': 0},
      {'DmzEnabled': 0, 'HostIpaddr': ''},
    ]);
  }

  Future<Map<String, dynamic>?> setUpnpDmzSettings({
    required bool upnpEnabled,
    required bool dmzEnabled,
    required String dmzHost,
  }) async {
    return sendCommand('/SetUpnpDmz', [
      {'UpnpEnabled': upnpEnabled ? 1 : 0},
      {'DmzEnabled': dmzEnabled ? 1 : 0, if (dmzEnabled) 'HostIpaddr': dmzHost},
    ]);
  }

  Future<Map<String, dynamic>?> getQosSettings() async {
    return sendCommand('/GetQosInfo', {
      'Enable': 0,
      'UpBandwidth': 0,
      'DownBandwidth': 0,
    });
  }

  Future<Map<String, dynamic>?> setQosSettings({
    required bool enabled,
    required int upBandwidth,
    required int downBandwidth,
  }) async {
    return sendCommand('/SetQosInfo', {
      'Enable': enabled ? 1 : 0,
      'UpBandwidth': upBandwidth,
      'DownBandwidth': downBandwidth,
    });
  }

  Future<Map<String, dynamic>?> getFastNatSettings() async {
    return sendCommand('/GetFastNatInfo', {
      'FastnatEnable': 0,
      'AutoFilter': 0,
      'PortList': '',
    });
  }

  Future<Map<String, dynamic>?> setFastNatSettings({
    required bool enabled,
    required bool autoFilter,
    required String portList,
  }) async {
    return sendCommand('/SetFastNatInfo', {
      'FastnatEnable': enabled ? 1 : 0,
      'AutoFilter': autoFilter ? 1 : 0,
      'PortList': portList,
    });
  }

  Future<Map<String, dynamic>?> getVpnSettings() async {
    return sendCommand('/GetVpnInfo', [
      {
        'VpnEnable': 0,
        'VpnServer': '',
        'VpnUser': '',
        'VpnPass': '',
        'IpsecPsk': '',
        'VpnPPTPMppe': 0,
        'VpnInnerNet': '',
        'VpnInnerMask': '',
      },
    ]);
  }

  Future<Map<String, dynamic>?> getVpnStatus() async {
    return sendCommand('/GetVpnStatus', [
      {'Status': 0},
    ]);
  }

  Future<Map<String, dynamic>?> setVpnSettings(
    Map<String, dynamic> settings,
  ) async {
    return sendCommand('/SetVpnInfo', [settings], timeout: 15);
  }

  Future<Map<String, dynamic>?> getVirtualServers() async {
    return sendCommand('/GetVirServerList', [
      {
        'Index': '',
        'DeviceSystemType': 0,
        'DeviceNickName': '',
        'DeviceHostName': '',
        'DeviceMacaddr': '',
        'DeviceIpaddr': '',
        'Protocol': 0,
        'ExternalStartPort': 0,
        'ExternalEndPort': 0,
        'InternalStartPort': 0,
        'InternalEndPort': 0,
      },
    ]);
  }

  Future<Map<String, dynamic>?> addVirtualServer(
    Map<String, dynamic> rule,
  ) async {
    return sendCommand('/AddVirServerList', [rule]);
  }

  Future<Map<String, dynamic>?> updateVirtualServer(
    Map<String, dynamic> rule,
  ) async {
    return sendCommand('/SetVirServerList', [rule]);
  }

  Future<Map<String, dynamic>?> deleteVirtualServer(String index) async {
    return sendCommand('/DelVirServerList', [
      {'Index': index},
    ]);
  }

  Future<Map<String, dynamic>?> getDdnsSettings() async {
    return sendCommand('/GetDdnsInfo', [
      {
        'Enable': 0,
        'Service': 0,
        'UserName': '',
        'PassWord': '',
        'HostName': '',
      },
    ]);
  }

  Future<Map<String, dynamic>?> getDdnsStatus() async {
    return sendCommand('/GetDdnsStatus', {'Status': 0, 'UpdateTime': 0});
  }

  Future<Map<String, dynamic>?> setDdnsSettings(
    Map<String, dynamic> settings,
  ) async {
    return sendCommand('/SetDdnsInfo', [settings]);
  }

  Future<Map<String, dynamic>?> getLedSettings() async {
    return sendCommand('/GetLedList', [
      {'NodeSn': '', 'NickName': '', 'Led': 0},
    ]);
  }

  Future<Map<String, dynamic>?> setNodeLed({
    required String nodeSn,
    required int led,
  }) async {
    return sendCommand('/SetNodeLed', {'NodeSn': nodeSn, 'Led': led});
  }

  Future<Map<String, dynamic>?> getRestartSchedule() async {
    return sendCommand('/GetSystemRestartInfo', [
      {
        'RestartSwitch': 0,
        'RestartDay': '',
        'RestartHour': 0,
        'RestartMinute': 0,
      },
    ]);
  }

  Future<Map<String, dynamic>?> setRestartSchedule(
    Map<String, dynamic> schedule,
  ) async {
    return sendCommand('/SetSystemRestartInfo', [schedule]);
  }

  Future<Map<String, dynamic>?> rebootRouter() async {
    return sendCommand('/SetSystemRestartNow', [
      {'SysRebootNow': 1},
    ]);
  }

  Future<void> disconnect() async {
    _teardown();
  }

  void _teardown() {
    final transport = _transport;
    _transport = null;
    _inboundSubscription?.cancel();
    _inboundSubscription = null;
    _isConnected = false;
    _meshId = null;
    _currentIp = null;
    for (final pending in _pendingByTopic.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _pendingByTopic.clear();
    if (transport != null) {
      transport.onDisconnected = null;
      try {
        transport.disconnect();
      } catch (e) {
        debugPrint('MqttService: disconnect error - $e');
      }
    }
  }

  void dispose() {
    _teardown();
    _messageController.close();
    _connectionController.close();
  }

  Future<String> _loadAppId() async {
    if (_appId != null) return _appId!;
    final loader = _appIdLoader;
    if (loader != null) return _appId = await loader();

    const key = 'mqtt_app_id';
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(key);
    if (savedId != null && savedId.isNotEmpty) {
      _appId = savedId;
      return savedId;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(key, id);
    _appId = id;
    return id;
  }

  /// TaoTronics local MQTT CA from the original TT Router APK. The router's
  /// leaf certificate (`emailAddress=leo.li@idazoo.com`) is signed by it.
  static Uint8List get pinnedAuthorityDer =>
      RouterCertificateVerifier.pemToDer(_pinnedAuthorityPem);

  static const _pinnedAuthorityPem = '''-----BEGIN CERTIFICATE-----
MIID8TCCAtmgAwIBAgIJAPB0Pmqr17WhMA0GCSqGSIb3DQEBCwUAMIGOMQswCQYD
VQQGEwJDTjELMAkGA1UECAwCR0QxCzAJBgNVBAcMAlNaMQ8wDQYDVQQKDAZBSU1N
SVQxDDAKBgNVBAsMA0lPVDEhMB8GA1UEAwwYd2lmaWxvY2FsLnRhb3Ryb25pY3Mu
Y29tMSMwIQYJKoZIhvcNAQkBFhRkYXpvby5hcHBAaWRhem9vLmNvbTAeFw0yMDA1
MjAwOTEwMTVaFw0zMDA1MTgwOTEwMTVaMIGOMQswCQYDVQQGEwJDTjELMAkGA1UE
CAwCR0QxCzAJBgNVBAcMAlNaMQ8wDQYDVQQKDAZBSU1NSVQxDDAKBgNVBAsMA0lP
VDEhMB8GA1UEAwwYd2lmaWxvY2FsLnRhb3Ryb25pY3MuY29tMSMwIQYJKoZIhvcN
AQkBFhRkYXpvby5hcHBAaWRhem9vLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEP
ADCCAQoCggEBAJTIoedgrWC53lcbqFhaBtUYIyBGb3cPNDf460TgOdmTjS9/tz0I
YTNkoUqQEG8XOj8TeIPn3RExT85hk+q9RicKoCB3usEXbfYEBUyw5731bJs1yZw4
GqHpGuVqEIeCKVU1DZWWKT8EO18X3rQMtYQ+NW2OXgpYxkgjEvG3weCMyzwK8JZ3
ZTGZ+QahDQqVurTSjtAAKHuAXou7aFtdU9mOR2I0wg96MRejOstkvigQv12t2W4r
4gOBsc0jwhD4HYF0icV8YPZs9dHbj3K3QUfjZR9IiG+/Bt94oabNJfpUl6/8Jvsf
GzCfJF3IYLsZOB+phI0bboC7t03Dc6BG+6ECAwEAAaNQME4wHQYDVR0OBBYEFC1t
67U3TmZvaSIZQKhZIqbZQar1MB8GA1UdIwQYMBaAFC1t67U3TmZvaSIZQKhZIqbZ
Qar1MAwGA1UdEwQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAEOrmT8MrVZ+27t6
CeccSE6PAIUmOGadWIYv/gQbQdLLFQXA9CzMiHkjpxQAUhElNfllCljQT/VX7BCc
Tyxn6EgZ39Ft+Tdr0FVYqTxanzMsMCDRN8y6EEyGk4aYJjJOI6qiD2TXq2tgJU3v
E2j0P/yIJxc5rQbeCxqnQ8d6okU8k+DXFFC+XfxHAp42Atmo9S+VreGp1lOnTyWJ
HKY04dj6faJvSPvBUyV4fWhxDJlxISYUokzXIB7gl3QDqpWxdpNuz/cQXy1MlJrQ
VIJ1OjVQ119ztnCTT6YvKfq11tugKxmJN69IVQeaslf5eliwIOoEazBLP6zlDQaC
M9IwCGs=
-----END CERTIFICATE-----''';
}
