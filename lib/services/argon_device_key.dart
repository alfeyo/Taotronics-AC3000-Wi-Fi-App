import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Android Keystore owns the non-exportable P-256 signing key. Only a public
/// key is enrolled with Argon. Rotation requires a fresh owner grant.
class ArgonDeviceKey {
  static const _channel = MethodChannel('tt_router/device_key');
  Future<String> publicKey(String instance) async => (await _channel
      .invokeMethod<String>('publicKey', {'instance': instance}))!;
  Future<String> sign(String instance, String value) async => (await _channel
      .invokeMethod<String>('sign', {'instance': instance, 'message': value}))!;
  static String canonical({
    required String id,
    required String method,
    required String path,
    required int ts,
    required String nonce,
    required List<int> body,
  }) =>
      'argon-device-v2\n$id\n${method.toUpperCase()}\n$path\n$ts\n$nonce\n${sha256.convert(body)}';
  Future<String> header({
    required String instance,
    required String id,
    required String method,
    required String path,
    required int ts,
    required String nonce,
    required List<int> body,
  }) async {
    final signature = await sign(
      instance,
      canonical(
        id: id,
        method: method,
        path: path,
        ts: ts,
        nonce: nonce,
        body: body,
      ),
    );
    return 'ArgonDevice v2 id=$id,ts=$ts,nonce=$nonce,sig=${base64Url.encode(base64Decode(signature)).replaceAll('=', '')}';
  }
}
