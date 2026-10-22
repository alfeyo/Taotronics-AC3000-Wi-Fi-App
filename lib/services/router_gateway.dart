import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mqtt_service.dart';
import 'router_access_policy.dart';
import 'router_certificate_verifier.dart';

/// The only object the app uses to reach the TaoTronics router.
///
/// Phase 1 of `docs/ROUTER_CONTROL_MIGRATION_PLAN.md` ships exactly one
/// production implementation, [DirectRouterGateway], so behaviour is unchanged.
/// Later phases add a `PiRouterGateway` that implements this same interface
/// against Argon's API; `RouterProvider` does not change when that happens.
///
/// Every member is checked against [policy] before any traffic leaves the app.
abstract interface class RouterGateway {
  /// Ownership policy shared with `RouterProvider`. Mutable by design: Argon's
  /// ownership claim flips it at runtime.
  RouterAccessPolicy get policy;

  bool get isConnected;
  bool get managedElsewhere;
  CertificateVerdict? get lastCertificateVerdict;

  /// Emits `false` only for an unexpected drop of an established session.
  Stream<bool> get connectionStream;

  /// Emits when the router starts or stops refusing this client
  /// (`ErrorCode 5` = another client manages the router).
  Stream<bool> get managementStream;

  Future<bool> connect(String meshId, String ipAddress, {String? password});
  Future<void> disconnect();
  void dispose();

  Future<Map<String, dynamic>?> sendCommand(
    String path,
    dynamic data, {
    int timeout = 10,
    int routerTimeout = 0,
  });

  // Reads.
  Future<Map<String, dynamic>?> getSystemStatus();
  Future<Map<String, dynamic>?> getDeviceList();
  Future<Map<String, dynamic>?> getNodeList();
  Future<Map<String, dynamic>?> getWirelessSettings();
  Future<Map<String, dynamic>?> getNetworkFlowDaily();
  Future<Map<String, dynamic>?> getNetworkFlowMonthly();
  Future<Map<String, dynamic>?> getSystemConnectionInfo();
  Future<Map<String, dynamic>?> getNodeRateInfo();
  Future<Map<String, dynamic>?> getWanRateInfo();
  Future<Map<String, dynamic>?> getPrivateStorage();
  Future<Map<String, dynamic>?> getDiskInfo();
  Future<Map<String, dynamic>?> getStorageVisitAddress();
  Future<Map<String, dynamic>?> getGuestWifi();
  Future<Map<String, dynamic>?> getWanSettings();
  Future<Map<String, dynamic>?> getLanSettings();
  Future<Map<String, dynamic>?> getFirewallSettings();
  Future<Map<String, dynamic>?> getUpnpDmzSettings();
  Future<Map<String, dynamic>?> getQosSettings();
  Future<Map<String, dynamic>?> getFastNatSettings();
  Future<Map<String, dynamic>?> getVpnSettings();
  Future<Map<String, dynamic>?> getVpnStatus();
  Future<Map<String, dynamic>?> getVirtualServers();
  Future<Map<String, dynamic>?> getDdnsSettings();
  Future<Map<String, dynamic>?> getDdnsStatus();
  Future<Map<String, dynamic>?> getLedSettings();
  Future<Map<String, dynamic>?> getRestartSchedule();

  // Writes.
  Future<Map<String, dynamic>?> setWirelessSettings(
    List<Map<String, dynamic>> networks,
  );
  Future<Map<String, dynamic>?> setPrivateStorage({
    required bool usb3Enabled,
    required bool sambaEnabled,
    required bool anonymousAccess,
  });
  Future<Map<String, dynamic>?> setGuestWifi(Map<String, dynamic> guest);
  Future<Map<String, dynamic>?> setWanSettings(
    List<Map<String, dynamic>> settings,
  );
  Future<Map<String, dynamic>?> setLanSettings(
    List<Map<String, dynamic>> settings,
  );
  Future<Map<String, dynamic>?> setFirewallSettings(bool enabled);
  Future<Map<String, dynamic>?> setUpnpDmzSettings({
    required bool upnpEnabled,
    required bool dmzEnabled,
    required String dmzHost,
  });
  Future<Map<String, dynamic>?> setQosSettings({
    required bool enabled,
    required int upBandwidth,
    required int downBandwidth,
  });
  Future<Map<String, dynamic>?> setFastNatSettings({
    required bool enabled,
    required bool autoFilter,
    required String portList,
  });
  Future<Map<String, dynamic>?> setVpnSettings(Map<String, dynamic> settings);
  Future<Map<String, dynamic>?> addVirtualServer(Map<String, dynamic> rule);
  Future<Map<String, dynamic>?> updateVirtualServer(Map<String, dynamic> rule);
  Future<Map<String, dynamic>?> deleteVirtualServer(String index);
  Future<Map<String, dynamic>?> setDdnsSettings(Map<String, dynamic> settings);
  Future<Map<String, dynamic>?> setNodeLed({
    required String nodeSn,
    required int led,
  });
  Future<Map<String, dynamic>?> setRestartSchedule(
    Map<String, dynamic> schedule,
  );
  Future<Map<String, dynamic>?> rebootRouter();
}

/// The Phase 1 implementation: the existing MQTT session, behind the policy.
///
/// Reads, writes and connection attempts are refused (null / false) when
/// [policy] forbids them, so no caller can bypass the decision point.
class DirectRouterGateway implements RouterGateway {
  DirectRouterGateway(this._mqtt, {RouterAccessPolicy? policy})
    : policy = policy ?? RouterAccessPolicy();

  final MqttService _mqtt;

  @override
  final RouterAccessPolicy policy;

  @override
  bool get isConnected => _mqtt.isConnected;

  @override
  bool get managedElsewhere => _mqtt.managedElsewhere;

  @override
  CertificateVerdict? get lastCertificateVerdict =>
      _mqtt.lastCertificateVerdict;

  @override
  Stream<bool> get connectionStream => _mqtt.connectionStream;

  @override
  Stream<bool> get managementStream => _mqtt.managementStream;

  @override
  Future<bool> connect(String meshId, String ipAddress, {String? password}) {
    if (!policy.mayConnect) {
      debugPrint('RouterGateway: connect refused - $policy');
      return Future.value(false);
    }
    return _mqtt.connect(meshId, ipAddress, password: password);
  }

  @override
  Future<void> disconnect() => _mqtt.disconnect();

  @override
  void dispose() => _mqtt.dispose();

  /// Read-level backstop. Write methods below are separately gated by
  /// [RouterAccessPolicy.mayWrite]; `RouterProvider` also gates semantics.
  Future<Map<String, dynamic>?> _read(
    Future<Map<String, dynamic>?> Function() op,
  ) => policy.maySendCommands ? op() : Future.value(null);

  Future<Map<String, dynamic>?> _write(
    Future<Map<String, dynamic>?> Function() op,
  ) => policy.mayWrite ? op() : Future.value(null);

  @override
  Future<Map<String, dynamic>?> sendCommand(
    String path,
    dynamic data, {
    int timeout = 10,
    int routerTimeout = 0,
  }) => policy.maySendCommands
      ? _mqtt.sendCommand(
          path,
          data,
          timeout: timeout,
          routerTimeout: routerTimeout,
        )
      : Future.value(null);

  @override
  Future<Map<String, dynamic>?> getSystemStatus() =>
      _read(_mqtt.getSystemStatus);

  @override
  Future<Map<String, dynamic>?> getDeviceList() => _read(_mqtt.getDeviceList);

  @override
  Future<Map<String, dynamic>?> getNodeList() => _read(_mqtt.getNodeList);

  @override
  Future<Map<String, dynamic>?> getWirelessSettings() =>
      _read(_mqtt.getWirelessSettings);

  @override
  Future<Map<String, dynamic>?> getNetworkFlowDaily() =>
      _read(_mqtt.getNetworkFlowDaily);

  @override
  Future<Map<String, dynamic>?> getNetworkFlowMonthly() =>
      _read(_mqtt.getNetworkFlowMonthly);

  @override
  Future<Map<String, dynamic>?> getSystemConnectionInfo() =>
      _read(_mqtt.getSystemConnectionInfo);

  @override
  Future<Map<String, dynamic>?> getNodeRateInfo() =>
      _read(_mqtt.getNodeRateInfo);

  @override
  Future<Map<String, dynamic>?> getWanRateInfo() =>
      _read(_mqtt.getWanRateInfo);

  @override
  Future<Map<String, dynamic>?> getPrivateStorage() =>
      _read(_mqtt.getPrivateStorage);

  @override
  Future<Map<String, dynamic>?> getDiskInfo() => _read(_mqtt.getDiskInfo);

  @override
  Future<Map<String, dynamic>?> getStorageVisitAddress() =>
      _read(_mqtt.getStorageVisitAddress);

  @override
  Future<Map<String, dynamic>?> getGuestWifi() => _read(_mqtt.getGuestWifi);

  @override
  Future<Map<String, dynamic>?> getWanSettings() =>
      _read(_mqtt.getWanSettings);

  @override
  Future<Map<String, dynamic>?> getLanSettings() =>
      _read(_mqtt.getLanSettings);

  @override
  Future<Map<String, dynamic>?> getFirewallSettings() =>
      _read(_mqtt.getFirewallSettings);

  @override
  Future<Map<String, dynamic>?> getUpnpDmzSettings() =>
      _read(_mqtt.getUpnpDmzSettings);

  @override
  Future<Map<String, dynamic>?> getQosSettings() => _read(_mqtt.getQosSettings);

  @override
  Future<Map<String, dynamic>?> getFastNatSettings() =>
      _read(_mqtt.getFastNatSettings);

  @override
  Future<Map<String, dynamic>?> getVpnSettings() =>
      _read(_mqtt.getVpnSettings);

  @override
  Future<Map<String, dynamic>?> getVpnStatus() => _read(_mqtt.getVpnStatus);

  @override
  Future<Map<String, dynamic>?> getVirtualServers() =>
      _read(_mqtt.getVirtualServers);

  @override
  Future<Map<String, dynamic>?> getDdnsSettings() =>
      _read(_mqtt.getDdnsSettings);

  @override
  Future<Map<String, dynamic>?> getDdnsStatus() => _read(_mqtt.getDdnsStatus);

  @override
  Future<Map<String, dynamic>?> getLedSettings() => _read(_mqtt.getLedSettings);

  @override
  Future<Map<String, dynamic>?> getRestartSchedule() =>
      _read(_mqtt.getRestartSchedule);

  @override
  Future<Map<String, dynamic>?> setWirelessSettings(
    List<Map<String, dynamic>> networks,
  ) => _write(() => _mqtt.setWirelessSettings(networks));

  @override
  Future<Map<String, dynamic>?> setPrivateStorage({
    required bool usb3Enabled,
    required bool sambaEnabled,
    required bool anonymousAccess,
  }) => _write(
    () => _mqtt.setPrivateStorage(
      usb3Enabled: usb3Enabled,
      sambaEnabled: sambaEnabled,
      anonymousAccess: anonymousAccess,
    ),
  );

  @override
  Future<Map<String, dynamic>?> setGuestWifi(Map<String, dynamic> guest) =>
      _write(() => _mqtt.setGuestWifi(guest));

  @override
  Future<Map<String, dynamic>?> setWanSettings(
    List<Map<String, dynamic>> settings,
  ) => _write(() => _mqtt.setWanSettings(settings));

  @override
  Future<Map<String, dynamic>?> setLanSettings(
    List<Map<String, dynamic>> settings,
  ) => _write(() => _mqtt.setLanSettings(settings));

  @override
  Future<Map<String, dynamic>?> setFirewallSettings(bool enabled) =>
      _write(() => _mqtt.setFirewallSettings(enabled));

  @override
  Future<Map<String, dynamic>?> setUpnpDmzSettings({
    required bool upnpEnabled,
    required bool dmzEnabled,
    required String dmzHost,
  }) => _write(
    () => _mqtt.setUpnpDmzSettings(
      upnpEnabled: upnpEnabled,
      dmzEnabled: dmzEnabled,
      dmzHost: dmzHost,
    ),
  );

  @override
  Future<Map<String, dynamic>?> setQosSettings({
    required bool enabled,
    required int upBandwidth,
    required int downBandwidth,
  }) => _write(
    () => _mqtt.setQosSettings(
      enabled: enabled,
      upBandwidth: upBandwidth,
      downBandwidth: downBandwidth,
    ),
  );

  @override
  Future<Map<String, dynamic>?> setFastNatSettings({
    required bool enabled,
    required bool autoFilter,
    required String portList,
  }) => _write(
    () => _mqtt.setFastNatSettings(
      enabled: enabled,
      autoFilter: autoFilter,
      portList: portList,
    ),
  );

  @override
  Future<Map<String, dynamic>?> setVpnSettings(
    Map<String, dynamic> settings,
  ) => _write(() => _mqtt.setVpnSettings(settings));

  @override
  Future<Map<String, dynamic>?> addVirtualServer(Map<String, dynamic> rule) =>
      _write(() => _mqtt.addVirtualServer(rule));

  @override
  Future<Map<String, dynamic>?> updateVirtualServer(
    Map<String, dynamic> rule,
  ) => _write(() => _mqtt.updateVirtualServer(rule));

  @override
  Future<Map<String, dynamic>?> deleteVirtualServer(String index) =>
      _write(() => _mqtt.deleteVirtualServer(index));

  @override
  Future<Map<String, dynamic>?> setDdnsSettings(
    Map<String, dynamic> settings,
  ) => _write(() => _mqtt.setDdnsSettings(settings));

  @override
  Future<Map<String, dynamic>?> setNodeLed({
    required String nodeSn,
    required int led,
  }) => _write(() => _mqtt.setNodeLed(nodeSn: nodeSn, led: led));

  @override
  Future<Map<String, dynamic>?> setRestartSchedule(
    Map<String, dynamic> schedule,
  ) => _write(() => _mqtt.setRestartSchedule(schedule));

  @override
  Future<Map<String, dynamic>?> rebootRouter() => _write(_mqtt.rebootRouter);
}
