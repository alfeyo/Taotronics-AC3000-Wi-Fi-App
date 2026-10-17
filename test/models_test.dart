import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/models/device_entity.dart';
import 'package:tt_router_flutter/models/wireless_network.dart';

void main() {
  // Shapes captured from the live router (GetDevListInfo / GetExistNode).
  final tablet = {
    'NickName': '',
    'HostName': 'Tab-A9',
    'Mac': '66:d9:ea:00:00:01',
    'Ip': '192.168.10.138',
    'ConnTime': 1792242175,
    'SystemType': 0,
    'AliveOnline': 1,
    'CreateTime': 1792242171,
    'UpRate': 2505,
    'DownRate': 36336,
    'UpdateTime': 1792242961,
    'ClientType': 2,
  };

  test('device fields map to the router reply', () {
    final d = DeviceEntity.fromJson(tablet);
    expect(d.displayName, 'Tab-A9');
    expect(d.isOnline, isTrue);
    expect(d.isActive, isTrue);
    expect(d.uploadSpeed, 2505);
    expect(d.link, DeviceLink.wireless);
    expect(d.connectedSince, DateTime.fromMillisecondsSinceEpoch(1792242175000));
    expect(d.hasByteCounters, isFalse);
    expect(d.searchText, contains('192.168.10.138'));
  });

  test('wired, unknown link and string numbers', () {
    final d = DeviceEntity.fromJson({
      'Mac': '00:17:88:00:00:02',
      'ClientType': 0,
      'AliveOnline': '1',
      'UpRate': '12',
      'ConnTime': 0,
    });
    expect(d.link, DeviceLink.wired);
    expect(d.isOnline, isTrue);
    expect(d.uploadSpeed, 12);
    expect(d.connectedSince, isNull);
    expect(d.displayName, '00:17:88:00:00:02');
    expect(DeviceEntity.fromJson({'ClientType': 7}).link, DeviceLink.unknown);
  });

  test('node fields map to GetExistNode', () {
    final n = NodeEntity.fromJson({
      'NodeSn': '5702100B047E2E9D',
      'OnLine': 1,
      'NickName': '',
      'ClientNum': 3,
      'Role': 'mpp',
      'Uptime': 70929,
      'Model': 'ND001',
      'LocalConn': 1,
    });
    expect(n.isMaster, isTrue);
    expect(n.isOnline, isTrue);
    expect(n.displayName, '5702100B047E2E9D');
    expect(n.uptimeSeconds, 70929);
    expect(n.wiredBackhaul, isTrue);
    expect(n.firmwareVersion, isNull);
  });

  test('wireless network keeps unknown router fields in its payload', () {
    final n = WirelessNetwork.fromJson({
      'Ssid': 'Game labs',
      'Encrypt': 3,
      'Password': 'x' * 8,
      'Vlanid': -1,
      'Index': 0,
      'Create': 1,
      'Extra': 'kept',
    });
    final payload = n.copyWith(ssid: 'New').toRouterPayload();
    expect(payload['Ssid'], 'New');
    expect(payload['Vlanid'], -1);
    expect(payload['Extra'], 'kept');
    expect(n.isEnabled, isTrue);
  });
}
