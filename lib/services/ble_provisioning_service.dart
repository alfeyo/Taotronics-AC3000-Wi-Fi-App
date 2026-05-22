import 'package:flutter/services.dart';

class BleProvisioningResult {
  final String meshId;
  final String serialNumber;
  final int wanProto;
  final bool restartRequired;

  const BleProvisioningResult({
    required this.meshId,
    required this.serialNumber,
    required this.wanProto,
    required this.restartRequired,
  });

  factory BleProvisioningResult.fromMap(Map<Object?, Object?> map) {
    return BleProvisioningResult(
      meshId: map['meshId'] as String? ?? '',
      serialNumber: map['serialNumber'] as String? ?? '',
      wanProto: map['wanProto'] as int? ?? 0,
      restartRequired: map['restartRequired'] as bool? ?? false,
    );
  }
}

class BleProvisioningService {
  static const _channel = MethodChannel('tt_router/ble_provisioning');

  Future<void> openWifiPicker() async {
    await _channel.invokeMethod<void>('openWifiPicker');
  }

  Future<BleProvisioningResult> discover() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'discoverRouter',
    );

    if (result == null) {
      throw PlatformException(
        code: 'empty_result',
        message: 'Bluetooth search returned no router details.',
      );
    }

    return BleProvisioningResult.fromMap(result);
  }

  Future<BleProvisioningResult> provision({
    required String ssid,
    required String password,
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'provisionRouter',
      {'ssid': ssid, 'password': password},
    );

    if (result == null) {
      throw PlatformException(
        code: 'empty_result',
        message: 'Bluetooth provisioning returned no router details.',
      );
    }

    return BleProvisioningResult.fromMap(result);
  }
}
