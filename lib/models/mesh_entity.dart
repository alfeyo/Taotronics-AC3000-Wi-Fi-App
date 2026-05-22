class MeshEntity {
  String meshId;
  String ssid;
  String? alias;
  String? ipAddress;
  int state; // 0=unknown, 1=online, 4=offline
  int mode;
  int authority;
  String? masterUserId;
  String? userId;
  DateTime? lastStateTime;

  MeshEntity({
    required this.meshId,
    required this.ssid,
    this.alias,
    this.ipAddress,
    this.state = 0,
    this.mode = 0,
    this.authority = 0,
    this.masterUserId,
    this.userId,
    this.lastStateTime,
  });

  factory MeshEntity.fromJson(Map<String, dynamic> json) {
    return MeshEntity(
      meshId: json['meshId'] ?? '',
      ssid: json['ssid'] ?? '',
      alias: json['alias'],
      ipAddress: json['ipAddress'],
      state: json['state'] ?? 0,
      mode: json['mode'] ?? 0,
      authority: json['authority'] ?? 0,
      masterUserId: json['masterUserId'],
      userId: json['userId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'meshId': meshId,
      'ssid': ssid,
      'alias': alias,
      'ipAddress': ipAddress,
      'state': state,
      'mode': mode,
      'authority': authority,
      'masterUserId': masterUserId,
      'userId': userId,
    };
  }

  String get displayName => alias ?? ssid;

  bool get isOnline => state == 1;

  String get statusText {
    switch (state) {
      case 1:
        return 'Online';
      case 4:
        return 'Offline';
      default:
        return 'Unknown';
    }
  }
}
