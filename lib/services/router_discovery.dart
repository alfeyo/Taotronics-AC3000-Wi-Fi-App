import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class DiscoveredRouter {
  final String meshId;
  final String ipAddress;
  final bool supportsVlan;
  final DateTime discoveredAt;

  DiscoveredRouter({
    required this.meshId,
    required this.ipAddress,
    this.supportsVlan = false,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();
}

class RouterDiscoveryService {
  static const int discoveryPort = 52011;

  RawDatagramSocket? _socket;
  final _discoveredRouters = <String, DiscoveredRouter>{};
  final _routerStreamController =
      StreamController<DiscoveredRouter>.broadcast();

  Stream<DiscoveredRouter> get routerStream => _routerStreamController.stream;
  Map<String, DiscoveredRouter> get discoveredRouters =>
      Map.unmodifiable(_discoveredRouters);

  Future<void> startDiscovery() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
      );
      _socket!.broadcastEnabled = true;

      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _processPacket(datagram.data, datagram.address.address);
          }
        }
      });

      debugPrint('RouterDiscovery: Listening on port $discoveryPort');
    } catch (e) {
      debugPrint('RouterDiscovery: Failed to start - $e');
    }
  }

  void _processPacket(Uint8List data, String sourceIp) {
    try {
      final parsed = _parseDiscoveryPacket(data);
      if (parsed != null) {
        final router = DiscoveredRouter(
          meshId: parsed['meshId']!,
          ipAddress: parsed['ip'] ?? sourceIp,
          supportsVlan: parsed['supportsVlan'] == 'true',
        );

        _discoveredRouters[router.meshId] = router;
        _routerStreamController.add(router);

        debugPrint(
          'RouterDiscovery: Found router ${router.meshId} at ${router.ipAddress}',
        );
      }
    } catch (e) {
      debugPrint('RouterDiscovery: Failed to parse packet - $e');
    }
  }

  Map<String, String>? _parseDiscoveryPacket(Uint8List data) {
    // The APK skips a discovery envelope before parsing TaoTronics TLVs.
    // Some firmware sends the TLV body without that envelope, so accept both.
    final tlvData = _findTlvData(data);
    final result = <String, String>{};
    int offset = 0;

    while (offset < tlvData.length - 2) {
      final type = _bytesToHex(tlvData.sublist(offset, offset + 1));
      offset += 1;

      if (offset >= tlvData.length) break;

      final length = tlvData[offset];
      offset += 1;

      if (offset + length > tlvData.length) break;

      final value = tlvData.sublist(offset, offset + length);
      offset += length;

      switch (type.toUpperCase()) {
        case '0C':
          result['meshId'] = _hexToAscii(_bytesToHex(value));
          break;
        case '04':
          result['ip'] = _parseIpFromHex(_bytesToHex(value));
          break;
        case '06':
          result['status'] = _bytesToHex(value);
          break;
        case '13':
          result['supportsVlan'] = 'true';
          break;
      }
    }

    return result.containsKey('meshId') ? result : null;
  }

  Uint8List _findTlvData(Uint8List data) {
    const marker = [0xaa, 0xbb, 0xcc, 0xdd];

    for (int offset = 0; offset <= data.length - marker.length; offset++) {
      if (data[offset] == marker[0] &&
          data[offset + 1] == marker[1] &&
          data[offset + 2] == marker[2] &&
          data[offset + 3] == marker[3]) {
        final bodyOffset = offset + 12;
        if (bodyOffset < data.length) {
          return Uint8List.sublistView(data, bodyOffset);
        }
      }
    }

    return data;
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hexToAscii(String hex) {
    final buffer = StringBuffer();
    for (int i = 0; i < hex.length - 1; i += 2) {
      final charCode = int.parse(hex.substring(i, i + 2), radix: 16);
      if (charCode != 0) {
        buffer.writeCharCode(charCode);
      }
    }
    return buffer.toString();
  }

  String _parseIpFromHex(String hex) {
    if (hex.length < 8) return '';
    final parts = <int>[];
    for (int i = 6; i >= 0; i -= 2) {
      parts.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return parts.join('.');
  }

  void stopDiscovery() {
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stopDiscovery();
    _routerStreamController.close();
  }
}
