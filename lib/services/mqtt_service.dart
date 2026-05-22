import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MqttService {
  static const int mqttPort = 25678;
  static const String _routerCertificateName = 'CN=wifilocal.taotronics.com';
  static const String _routerCertificateIssuer =
      '/C=CN/ST=GD/L=SZ/O=AIMMIT/OU=IOT/'
      'CN=wifilocal.taotronics.com/emailAddress=dazoo.app@idazoo.com';

  MqttServerClient? _client;
  String? _meshId;
  String? _currentIp;
  String? _appId;
  bool _isConnected = false;
  StreamSubscription? _updatesSubscription;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _isConnected;

  String _generatePassword(String meshId) {
    final input = 'dazoo$meshId';
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<bool> connect(
    String meshId,
    String ipAddress, {
    String? password,
  }) async {
    if (_isConnected && _meshId == meshId && _currentIp == ipAddress) {
      return true;
    }

    await disconnect();

    _meshId = meshId;
    _currentIp = ipAddress;
    final appId = await _loadAppId();

    try {
      _client = MqttServerClient.withPort(ipAddress, appId, mqttPort);
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 30;
      _client!.connectTimeoutPeriod = 10000;
      _client!.secure = true;
      _client!.securityContext = SecurityContext()
        ..setTrustedCertificatesBytes(_getTrustedCertificate());
      _client!.onBadCertificate = _isPinnedRouterCertificate;

      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onSubscribed = _onSubscribed;

      final mqttPassword = password ?? _generatePassword(meshId);
      final connMessage = MqttConnectMessage()
          .withClientIdentifier(appId)
          .authenticateAs(meshId, mqttPassword)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);

      _client!.connectionMessage = connMessage;

      debugPrint('MqttService: Connecting to $ipAddress:$mqttPort');
      await _client!.connect();

      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        _subscribeToTopics();
        return true;
      }
    } catch (e) {
      debugPrint('MqttService: Connection failed - $e');
      _isConnected = false;
      _connectionController.add(false);
    }

    return false;
  }

  void _onConnected() {
    debugPrint('MqttService: Connected');
    _isConnected = true;
    _connectionController.add(true);
  }

  void _onDisconnected() {
    debugPrint('MqttService: Disconnected');
    _isConnected = false;
    _connectionController.add(false);
  }

  void _onSubscribed(String topic) {
    debugPrint('MqttService: Subscribed to $topic');
  }

  void _subscribeToTopics() {
    if (_appId == null || _client == null) return;

    final topic = '$_appId/+';
    _client!.subscribe(topic, MqttQos.exactlyOnce);

    _updatesSubscription?.cancel();
    _updatesSubscription = _client!.updates?.listen(
      (List<MqttReceivedMessage<MqttMessage>> messages) {
        for (final message in messages) {
          final payload = message.payload as MqttPublishMessage;
          final data = MqttPublishPayload.bytesToStringAsString(
            payload.payload.message,
          );

          try {
            final json = jsonDecode(data);
            _messageController.add({'topic': message.topic, 'data': json});
          } catch (e) {
            debugPrint('MqttService: Failed to parse message - $e');
          }
        }
      },
      onError: (Object error) {
        debugPrint('MqttService: update stream error - $error');
      },
    );
  }

  Future<Map<String, dynamic>?> sendCommand(
    String path,
    dynamic data, {
    int timeout = 10,
    int routerTimeout = 0,
  }) async {
    if (!_isConnected || _client == null || _meshId == null) {
      return null;
    }

    final completer = Completer<Map<String, dynamic>?>();
    final appId = await _loadAppId();

    final payload = {
      'AppId': appId,
      'Timeout': routerTimeout,
      'ErrorCode': 0,
      'Data': data,
      'Timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    final topic = '$_meshId/$appId$path';
    final responseTopic = '$appId$path';

    StreamSubscription? subscription;
    Timer? timeoutTimer;

    subscription = messageStream.listen((message) {
      if (message['topic'] == responseTopic) {
        timeoutTimer?.cancel();
        subscription?.cancel();
        completer.complete(message['data']);
      }
    });

    timeoutTimer = Timer(Duration(seconds: timeout), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        debugPrint('MqttService: timeout waiting for $responseTopic');
        completer.complete(null);
      }
    });

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(payload));
      _client!.publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
    } catch (e) {
      debugPrint('MqttService: publish failed - $e');
      timeoutTimer.cancel();
      subscription.cancel();
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
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

  Future<Map<String, dynamic>?> getWirelessSettings() async {
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
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    _client?.disconnect();
    _client = null;
    _isConnected = false;
    _meshId = null;
    _currentIp = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
  }

  Future<String> _loadAppId() async {
    if (_appId != null) return _appId!;

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

  Uint8List _getTrustedCertificate() {
    // Local MQTT certificate from the TT Router APK.
    const certPem = '''-----BEGIN CERTIFICATE-----
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
    return Uint8List.fromList(utf8.encode(certPem));
  }

  bool _isPinnedRouterCertificate(Object certificate) {
    if (certificate is! X509Certificate) {
      debugPrint('MqttService: Router TLS certificate rejected: unknown type');
      return false;
    }

    final receivedPem = _normalizePem(certificate.pem);
    final pinnedPem = _normalizePem(utf8.decode(_getTrustedCertificate()));
    final hasRouterIdentity =
        certificate.subject.contains(_routerCertificateName) &&
        certificate.issuer == _routerCertificateIssuer;
    final accepted = receivedPem == pinnedPem || hasRouterIdentity;

    debugPrint(
      'MqttService: Router TLS certificate ${accepted ? 'accepted' : 'rejected'} '
      'for ${certificate.subject} issued by ${certificate.issuer}',
    );

    return accepted;
  }

  String _normalizePem(String pem) {
    return pem.replaceAll('\r\n', '\n').trim();
  }
}
