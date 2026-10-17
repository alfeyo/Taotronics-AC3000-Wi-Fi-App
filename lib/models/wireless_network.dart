class WirelessNetwork {
  final int index;
  final String ssid;
  final String password;
  final int encrypt;
  final int vlanId;
  final int vlanEnabled;
  final int ssidIsolate;
  final int staIsolate;
  final int create;
  final int disable;
  final int confStatus;
  final String? nodeSn;
  final Map<String, dynamic> rawData;

  WirelessNetwork({
    required this.index,
    required this.ssid,
    required this.password,
    required this.encrypt,
    this.vlanId = 0,
    this.vlanEnabled = 0,
    this.ssidIsolate = 0,
    this.staIsolate = 0,
    this.create = 1,
    this.disable = 0,
    this.confStatus = 0,
    this.nodeSn,
    this.rawData = const {},
  });

  factory WirelessNetwork.fromJson(Map<String, dynamic> json) {
    return WirelessNetwork(
      index: _int(json['Index'] ?? json['index']),
      ssid: '${json['Ssid'] ?? json['ssid'] ?? ''}',
      password: '${json['Password'] ?? json['password'] ?? ''}',
      encrypt: _int(json['Encrypt'] ?? json['encrypt']),
      vlanId: _int(json['Vlanid'] ?? json['VlanId'] ?? json['vlanId']),
      vlanEnabled: _int(json['VlanEnable'] ?? json['vlanEnable']),
      ssidIsolate: _int(json['SsidIsolate'] ?? json['ssidIsolate']),
      staIsolate: _int(json['StaIsolate'] ?? json['staIsolate']),
      create: _int(json['Create'] ?? json['create'], fallback: 1),
      disable: _int(json['Disable'] ?? json['disable']),
      confStatus: _int(json['ConfStatus'] ?? json['confStatus']),
      nodeSn: (json['NodeSn'] ?? json['nodeSn'])?.toString(),
      rawData: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toRouterPayload() {
    final payload = Map<String, dynamic>.from(rawData);
    payload['Index'] = index;
    payload['Ssid'] = ssid;
    payload['Password'] = password;
    payload['Encrypt'] = encrypt;
    payload['Vlanid'] = vlanId;
    payload['VlanEnable'] = vlanEnabled;
    payload['SsidIsolate'] = ssidIsolate;
    payload['StaIsolate'] = staIsolate;
    payload['Create'] = create;
    payload['Disable'] = disable;
    payload['ConfStatus'] = confStatus;
    if (nodeSn != null) payload['NodeSn'] = nodeSn;
    return payload;
  }

  WirelessNetwork copyWith({
    int? index,
    String? ssid,
    String? password,
    int? encrypt,
    int? vlanId,
    int? vlanEnabled,
    int? ssidIsolate,
    int? staIsolate,
    int? create,
    int? disable,
    int? confStatus,
    String? nodeSn,
    Map<String, dynamic>? rawData,
  }) {
    return WirelessNetwork(
      index: index ?? this.index,
      ssid: ssid ?? this.ssid,
      password: password ?? this.password,
      encrypt: encrypt ?? this.encrypt,
      vlanId: vlanId ?? this.vlanId,
      vlanEnabled: vlanEnabled ?? this.vlanEnabled,
      ssidIsolate: ssidIsolate ?? this.ssidIsolate,
      staIsolate: staIsolate ?? this.staIsolate,
      create: create ?? this.create,
      disable: disable ?? this.disable,
      confStatus: confStatus ?? this.confStatus,
      nodeSn: nodeSn ?? this.nodeSn,
      rawData: rawData ?? this.rawData,
    );
  }

  bool get isEnabled => create == 1 && disable == 0;

  String get bandLabel {
    switch (index) {
      case 0:
        return '2.4 GHz';
      case 1:
        return '5 GHz';
      case 2:
        return '5 GHz (DFS)';
      case 3:
        return 'Guest';
      default:
        return 'Network ${index + 1}';
    }
  }

  String get encryptionLabel {
    switch (encrypt) {
      case 0:
        return 'None';
      case 1:
        return 'WEP';
      case 2:
        return 'WPA-PSK';
      case 3:
        return 'WPA2-PSK';
      case 4:
        return 'WPA/WPA2';
      case 5:
        return 'WPA3';
      default:
        return 'Unknown';
    }
  }

  @override
  String toString() {
    return 'WirelessNetwork(index: $index, ssid: $ssid, enabled: $isEnabled, band: $bandLabel)';
  }
}

int _int(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}
