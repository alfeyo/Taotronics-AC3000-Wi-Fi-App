/// One wireless network entry from GetWirelessInfoList (V1) or
/// GetWirelessInfoListV2.
///
/// The router's own fields are kept in [rawData]. [toRouterPayload] sends
/// those fields back unchanged plus only the values the user edited, so
/// saving one band never adds fields the router did not report (V1 has no
/// `Disable`/`ConfStatus`/`NodeSn`) and never blanks values it did not
/// return.
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

  /// Router field name → value changed by the user since loading.
  final Map<String, dynamic> _edits;

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
    Map<String, dynamic> edits = const {},
  }) : _edits = Map.unmodifiable(edits);

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
      rawData: Map<String, dynamic>.unmodifiable(json),
    );
  }

  /// Whether the router reported this network's password. When it did not,
  /// the password must not be shown as empty or sent back blank.
  bool get passwordKnown =>
      rawData.isEmpty ||
      rawData.containsKey('Password') ||
      rawData.containsKey('password');

  /// V2 entries carry a `Disable` flag; V1 entries switch with `Create`.
  bool get hasDisableFlag =>
      rawData.containsKey('Disable') || rawData.containsKey('disable');

  /// Fields the router must have reported before this entry can be saved.
  List<String> get missingRequiredFields => [
    if (rawData.isNotEmpty && !rawData.containsKey('Index')) 'Index',
    if (rawData.isNotEmpty && !rawData.containsKey('Ssid')) 'Ssid',
    if (encrypt > 0 && !passwordKnown && !_edits.containsKey('Password'))
      'Password',
  ];

  bool get hasEdits => _edits.isNotEmpty;

  Map<String, dynamic> toRouterPayload() {
    final payload = rawData.isEmpty
        ? <String, dynamic>{
            'Index': index,
            'Ssid': ssid,
            'Password': password,
            'Encrypt': encrypt,
            'Vlanid': vlanId,
            'VlanEnable': vlanEnabled,
            'SsidIsolate': ssidIsolate,
            'StaIsolate': staIsolate,
            'Create': create,
          }
        : Map<String, dynamic>.from(rawData);
    payload['Index'] = index;
    payload.addAll(_edits);
    return payload;
  }

  /// Returns a copy with the given changes recorded as edits. Only edited
  /// fields differ from what the router reported in [toRouterPayload].
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
    final edits = Map<String, dynamic>.from(_edits);
    void edit(String key, Object? value, Object? current) {
      if (value != null && value != current) edits[key] = value;
    }

    edit('Ssid', ssid, this.ssid);
    // An unreported password is only replaced by a typed, non-empty one.
    if (password != null &&
        (passwordKnown ? password != this.password : password.isNotEmpty)) {
      edits['Password'] = password;
    }
    edit('Encrypt', encrypt, this.encrypt);
    edit('Vlanid', vlanId, this.vlanId);
    edit('VlanEnable', vlanEnabled, this.vlanEnabled);
    edit('SsidIsolate', ssidIsolate, this.ssidIsolate);
    edit('StaIsolate', staIsolate, this.staIsolate);
    edit('Create', create, this.create);
    // Only V2 entries have these fields; never add them to a V1 entry.
    if (hasDisableFlag || this.rawData.isEmpty) {
      edit('Disable', disable, this.disable);
    }
    if (this.rawData.containsKey('ConfStatus')) {
      edit('ConfStatus', confStatus, this.confStatus);
    }

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
      edits: edits,
    );
  }

  /// Turns the network on or off, keeping its name, password and settings.
  WirelessNetwork withEnabled(bool enabled) => copyWith(
    create: enabled ? 1 : 0,
    disable: hasDisableFlag ? (enabled ? 0 : 1) : null,
  );

  bool get isEnabled => create == 1 && disable == 0;

  /// Band label used by this app for each router index. The router does not
  /// report the band, so the mapping is the one the app has always used.
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
