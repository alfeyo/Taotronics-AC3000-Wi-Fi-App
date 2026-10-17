import '../providers/router_provider.dart';
import '../models/device_entity.dart';

/// Explicit allowlist: never send raw router replies or Wi-Fi passwords.
Map<String, dynamic>? buildPiRouterSnapshot(
  RouterProvider router, {
  DateTime? now,
}) {
  final time = now ?? DateTime.now();
  bool fresh(DateTime? t) =>
      t != null &&
      time.difference(t).inSeconds >= -5 &&
      time.difference(t).inSeconds <= 20;
  if (!router.isConnected || !fresh(router.devicesUpdatedAt)) return null;
  final telemetry = fresh(router.telemetryUpdatedAt);
  final nodes = fresh(router.nodesUpdatedAt);
  final led = fresh(router.ledUpdatedAt) ? router.mainRouterLed : null;
  final wifi = fresh(router.wirelessUpdatedAt);
  final primary = router.nodes.where((n) => n.isMaster).firstOrNull;
  final wanList = fresh(router.wanUpdatedAt) && router.wanSettings is List
      ? router.wanSettings as List
      : [];
  final wan = wanList.whereType<Map>().firstOrNull;
  final guest = fresh(router.guestUpdatedAt) ? router.guestWifi : null;
  return {
    'guest': guest == null
        ? null
        : {
            'ssid': guest['Ssid'],
            'enabled': guest['Enable'] == null ? null : guest['Enable'] == 1,
          },
    'wan': wan == null
        ? null
        : {
            'ip': wan['WanIp'],
            'gateway': wan['WanGateway'],
            'protocol': wan['WanProto']?.toString(),
          },
    'version': 1,
    'observedAt': router.devicesUpdatedAt!.millisecondsSinceEpoch ~/ 1000,
    'router': {
      'name': router.currentRouter?.displayName,
      'model': nodes ? primary?.model : null,
      'internet': telemetry && router.hasInternetStatus
          ? router.internetConnected
          : null,
      'devicesOnline': telemetry ? router.reportedOnlineDeviceCount : null,
      'nodesOnline': telemetry ? router.reportedOnlineNodeCount : null,
      'nodesTotal': telemetry ? router.reportedTotalNodeCount : null,
      'ledOn': led == null ? null : RouterProvider.isLedOn(led),
    },
    'clients': router.devices
        .map(
          (d) => {
            'mac': d.mac,
            'ip': d.ipAddress,
            'hostname': d.displayName,
            'connectionType': switch (d.link) {
              DeviceLink.wired => 'wired',
              DeviceLink.wireless => 'wifi',
              _ => 'unknown',
            },
            'online': d.raw.containsKey('AliveOnline') ? d.isOnline : null,
            'rateRxBps': d.raw.containsKey('DownRate')
                ? d.downloadSpeed * 8
                : null,
            'rateTxBps': d.raw.containsKey('UpRate') ? d.uploadSpeed * 8 : null,
            'nodeSn': d.nodeSn,
          },
        )
        .toList(),
    'nodes': nodes
        ? router.nodes
              .map(
                (n) => {
                  'sn': n.sn,
                  'name': n.nickName,
                  'model': n.model,
                  'role': n.role,
                  'online': n.isOnline,
                  'clients': n.connectedDevices,
                  'uptimeSeconds': n.uptimeSeconds,
                },
              )
              .toList()
        : [],
    'wifi': wifi
        ? router.wirelessNetworksParsed
              .map(
                (w) => {
                  'index': w.index,
                  'band': w.index == 0
                      ? '2.4 GHz'
                      : w.index == 1
                      ? '5 GHz'
                      : 'Additional network',
                  'ssid': w.ssid,
                  'enabled': w.rawData.containsKey('Create')
                      ? w.isEnabled
                      : null,
                  'secured': w.rawData.containsKey('Encrypt')
                      ? w.encrypt > 0
                      : null,
                },
              )
              .toList()
        : null,
  };
}
