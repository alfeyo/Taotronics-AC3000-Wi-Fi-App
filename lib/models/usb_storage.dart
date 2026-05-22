class UsbStorageSettings {
  final bool usb3Enabled;
  final bool sambaEnabled;
  final bool anonymousAccess;

  const UsbStorageSettings({
    required this.usb3Enabled,
    required this.sambaEnabled,
    required this.anonymousAccess,
  });

  factory UsbStorageSettings.fromJson(Map<String, dynamic> json) {
    return UsbStorageSettings(
      usb3Enabled: _asInt(json['Usb3En']) == 1,
      sambaEnabled: _asInt(json['SambaEn']) == 1,
      anonymousAccess: _asInt(json['Anonymous']) == 1,
    );
  }

  Map<String, dynamic> toRouterPayload() {
    return {
      'Usb3En': usb3Enabled ? 1 : 0,
      'SambaEn': sambaEnabled ? 1 : 0,
      'Anonymous': anonymousAccess ? 1 : 0,
    };
  }

  UsbStorageSettings copyWith({
    bool? usb3Enabled,
    bool? sambaEnabled,
    bool? anonymousAccess,
  }) {
    return UsbStorageSettings(
      usb3Enabled: usb3Enabled ?? this.usb3Enabled,
      sambaEnabled: sambaEnabled ?? this.sambaEnabled,
      anonymousAccess: anonymousAccess ?? this.anonymousAccess,
    );
  }
}

class UsbDisk {
  final String brand;
  final String devNode;
  final String serialNumber;
  final List<UsbPartition> partitions;

  const UsbDisk({
    required this.brand,
    required this.devNode,
    required this.serialNumber,
    required this.partitions,
  });

  factory UsbDisk.fromJson(Map<String, dynamic> json) {
    final rawPartitions = json['Partions'];
    return UsbDisk(
      brand: json['Brand']?.toString() ?? 'USB disk',
      devNode: json['DevNode']?.toString() ?? '',
      serialNumber: json['Sn']?.toString() ?? '',
      partitions: rawPartitions is List
          ? rawPartitions
                .whereType<Map>()
                .map(
                  (entry) =>
                      UsbPartition.fromJson(Map<String, dynamic>.from(entry)),
                )
                .toList()
          : const [],
    );
  }

  int get totalBytes =>
      partitions.fold(0, (sum, partition) => sum + partition.totalBytes);

  int get availableBytes =>
      partitions.fold(0, (sum, partition) => sum + partition.availableBytes);
}

class UsbPartition {
  final int id;
  final int totalBytes;
  final int availableBytes;

  const UsbPartition({
    required this.id,
    required this.totalBytes,
    required this.availableBytes,
  });

  factory UsbPartition.fromJson(Map<String, dynamic> json) {
    return UsbPartition(
      id: _asInt(json['Id']),
      totalBytes: _asInt(json['Total']),
      availableBytes: _asInt(json['Available']),
    );
  }

  int get usedBytes =>
      totalBytes > availableBytes ? totalBytes - availableBytes : 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
