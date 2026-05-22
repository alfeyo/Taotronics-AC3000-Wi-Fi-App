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
  });

  factory DeviceEntity.fromJson(Map<String, dynamic> json) {
    return DeviceEntity(
      mac: json['Mac'] ?? json['mac'] ?? '',
      nickName: json['NickName'] ?? json['nickName'],
      hostName: json['HostName'] ?? json['hostName'],
      ipAddress: json['Ip'] ?? json['IP'] ?? json['ip'] ?? json['ipAddress'],
      deviceType: json['ClientType'] ?? json['DeviceType'] ?? json['deviceType'] ?? 0,
      isOnline: (json['AliveOnline'] ?? json['Online'] ?? json['online'] ?? 0) == 1,
      uploadSpeed: (json['UpRate'] ?? json['UploadSpeed'] ?? json['uploadSpeed'] ?? 0).toInt(),
      downloadSpeed: (json['DownRate'] ?? json['DownloadSpeed'] ?? json['downloadSpeed'] ?? 0).toInt(),
      upBytes: (json['UpBytes'] ?? 0).toInt(),
      downBytes: (json['DownBytes'] ?? 0).toInt(),
      onlineTime: (json['ConnTime'] ?? json['OnlineTime'] ?? json['onlineTime'] ?? 0).toInt(),
      isBlocked: (json['Blocked'] ?? json['blocked'] ?? 0) == 1,
    );
  }

  String get displayName {
    if (nickName != null && nickName!.isNotEmpty) return nickName!;
    if (hostName != null && hostName!.isNotEmpty) return hostName!;
    return mac;
  }

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
  });

  factory NodeEntity.fromJson(Map<String, dynamic> json) {
    return NodeEntity(
      sn: json['NodeSn'] ?? json['SN'] ?? json['sn'] ?? '',
      nickName: json['NickName'] ?? json['nickName'],
      model: json['Model'] ?? json['model'],
      firmwareVersion: json['FirmwareVersion'] ?? json['firmwareVersion'],
      routerType: ('mpp' == (json['Role'] ?? '')) ? 0 : 1,
      isOnline: (json['OnLine'] ?? json['Online'] ?? json['online'] ?? 0) != 0,
      signalStrength: json['SignalStrength'] ?? json['signalStrength'] ?? 0,
      connectedDevices: json['ClientNum'] ?? json['ConnectedDevices'] ?? json['connectedDevices'] ?? 0,
      ipAddress: json['IP'] ?? json['ip'],
    );
  }

  bool get isMaster => routerType == 0;
  String get displayName => nickName ?? sn;
}
