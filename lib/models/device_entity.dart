class DeviceEntity {
  String mac;
  String? nickName;
  String? hostName;
  String? ipAddress;
  int deviceType;
  bool isOnline;
  int uploadSpeed;
  int downloadSpeed;
  int upBytes;
  int downBytes;
  int onlineTime;
  bool isBlocked;

  /// Router-reported link type when present (meaning not documented; shown
  /// raw in device details only).
  final int connectionType;

  /// Mesh node the client is attached to, when reported.
  final String? nodeSn;

  /// Router-reported signal value; 0 when not reported.
  final int signal;

  /// Every field the router reported, for the device detail view.
  final Map<String, dynamic> raw;

  /// GetDevListInfo `ConnTime`: when the current connection started.
  DateTime? get connectedSince => _epoch(raw['ConnTime']);

  /// GetDevListInfo `CreateTime`: when the router first saw the device.
  DateTime? get firstSeen => _epoch(raw['CreateTime']);

  /// GetDevListInfo `UpdateTime`: last time the router saw the device.
  DateTime? get lastSeen => _epoch(raw['UpdateTime']);

  /// Whether the router reports per-device byte counters at all. The
  /// TaoTronics AC3000 firmware observed does not.
  bool get hasByteCounters =>
      raw.containsKey('UpBytes') || raw.containsKey('DownBytes');

  /// Link type inferred from `ClientType`: 0 was observed for an
  /// Ethernet-only device and 2 for phones/tablets on Wi-Fi.
  DeviceLink get link => switch (raw['ClientType']) {
    0 => DeviceLink.wired,
    2 => DeviceLink.wireless,
    _ => DeviceLink.unknown,
  };

  bool get isActive => isOnline && (uploadSpeed > 0 || downloadSpeed > 0);

  DeviceEntity({
    required this.mac,
    this.nickName,
    this.hostName,
    this.ipAddress,
    this.deviceType = 0,
    this.isOnline = false,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.upBytes = 0,
    this.downBytes = 0,
    this.onlineTime = 0,
    this.isBlocked = false,
    this.connectionType = 0,
    this.nodeSn,
    this.signal = 0,
    this.raw = const {},
  });

  factory DeviceEntity.fromJson(Map<String, dynamic> json) {
    return DeviceEntity(
      mac: _string(json['Mac'] ?? json['mac']) ?? '',
      nickName: _string(json['NickName'] ?? json['nickName']),
      hostName: _string(json['HostName'] ?? json['hostName']),
      ipAddress: _string(
        json['Ip'] ?? json['IP'] ?? json['ip'] ?? json['ipAddress'],
      ),
      deviceType: _int(
        json['ClientType'] ?? json['DeviceType'] ?? json['deviceType'],
      ),
      isOnline:
          _int(json['AliveOnline'] ?? json['Online'] ?? json['online']) == 1,
      uploadSpeed: _int(
        json['UpRate'] ?? json['UploadSpeed'] ?? json['uploadSpeed'],
      ),
      downloadSpeed: _int(
        json['DownRate'] ?? json['DownloadSpeed'] ?? json['downloadSpeed'],
      ),
      upBytes: _int(json['UpBytes']),
      downBytes: _int(json['DownBytes']),
      onlineTime: _int(
        json['ConnTime'] ?? json['OnlineTime'] ?? json['onlineTime'],
      ),
      isBlocked: _int(json['Blocked'] ?? json['blocked']) == 1,
      connectionType: _int(json['ConnType'] ?? json['AccessType']),
      nodeSn: _string(json['NodeSn'] ?? json['ParentSn']),
      signal: _int(json['Rssi'] ?? json['Signal']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  String get displayName {
    if (nickName != null && nickName!.isNotEmpty) return nickName!;
    if (hostName != null && hostName!.isNotEmpty) return hostName!;
    return mac;
  }

  /// Name used for searching: nickname, host name, IP and MAC.
  String get searchText =>
      '${nickName ?? ''} ${hostName ?? ''} ${ipAddress ?? ''} $mac'
          .toLowerCase();

  String get deviceTypeIcon {
    switch (deviceType) {
      case 1:
        return 'android';
      case 2:
      case 3:
        return 'apple';
      case 4:
      case 5:
        return 'computer';
      default:
        return 'devices';
    }
  }
}

class NodeEntity {
  String sn;
  String? nickName;
  String? model;
  String? firmwareVersion;
  int routerType; // 0=master, 1=slave
  bool isOnline;
  int signalStrength;
  int connectedDevices;
  String? ipAddress;

  /// Seconds since the node started, as reported by GetExistNode (0 = n/a).
  final int uptimeSeconds;

  /// LocalConn from GetExistNode; null when the router did not report it.
  final bool? wiredBackhaul;
  final String? role;

  NodeEntity({
    required this.sn,
    this.nickName,
    this.model,
    this.firmwareVersion,
    this.routerType = 0,
    this.isOnline = false,
    this.signalStrength = 0,
    this.connectedDevices = 0,
    this.ipAddress,
    this.uptimeSeconds = 0,
    this.wiredBackhaul,
    this.role,
  });

  factory NodeEntity.fromJson(Map<String, dynamic> json) {
    return NodeEntity(
      sn: _string(json['NodeSn'] ?? json['SN'] ?? json['sn']) ?? '',
      nickName: _string(json['NickName'] ?? json['nickName']),
      model: _string(json['Model'] ?? json['model']),
      firmwareVersion: _string(
        json['FirmwareVersion'] ?? json['firmwareVersion'],
      ),
      routerType: ('mpp' == (json['Role'] ?? '')) ? 0 : 1,
      isOnline: _int(json['OnLine'] ?? json['Online'] ?? json['online']) != 0,
      signalStrength: _int(json['SignalStrength'] ?? json['signalStrength']),
      connectedDevices: _int(
        json['ClientNum'] ??
            json['ConnectedDevices'] ??
            json['connectedDevices'],
      ),
      ipAddress: _string(json['IP'] ?? json['ip']),
      uptimeSeconds: _int(json['Uptime']),
      wiredBackhaul: json['LocalConn'] == null
          ? null
          : _int(json['LocalConn']) == 1,
      role: _string(json['Role']),
    );
  }

  bool get isMaster => routerType == 0;
  String get displayName =>
      nickName == null || nickName!.isEmpty ? sn : nickName!;
}

enum DeviceLink { wired, wireless, unknown }

DateTime? _epoch(dynamic value) {
  final seconds = _int(value);
  // Ignore zero and implausible values (before 2015).
  if (seconds < 1420070400) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  if (value is bool) return value ? 1 : 0;
  return 0;
}

String? _string(dynamic value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}
