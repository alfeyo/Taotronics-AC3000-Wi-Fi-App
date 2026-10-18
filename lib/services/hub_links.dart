import 'package:flutter/services.dart';
import 'pi_api.dart';

abstract final class HubLinks {
  static const _channel = MethodChannel('tt_router/hub_links');
  static Future<void> open(String value) async {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https') {
      validatePiEndpoint(uri.replace(path: '').toString());
      if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid dashboard link');
      }
    }
    await _channel.invokeMethod<void>('open', {'url': value});
  }
}
