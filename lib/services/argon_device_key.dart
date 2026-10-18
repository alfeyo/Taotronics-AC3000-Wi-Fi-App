import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Where Android Keystore holds the phone's signing key. Not secret.
enum DeviceKeyHardware { strongBox, tee, software }

/// Android Keystore owns the non-exportable P-256 signing key. Only a public
/// key is enrolled with Argon. Each pairing has its own key (alias derived
/// from the paired device id), so a new pairing never inherits an old grant.
class ArgonDeviceKey {
  static const _channel = MethodChannel('tt_router/device_key');
  static const aliasPrefix = 'argon.vpn.';
  static final _id = RegExp(r'^[0-9a-f-]{36}$');

  /// Key alias for one pairing: `argon.vpn.<instanceId>.<deviceId>`.
  static String aliasFor(String instanceId, String deviceId) {
    if (!_id.hasMatch(instanceId) || !_id.hasMatch(deviceId)) {
      throw ArgumentError('Invalid Argon instance or device id.');
    }
    return '$aliasPrefix$instanceId.$deviceId';
  }

  /// The per-install alias used before keys were bound to a pairing.
  static String legacyAlias(String instanceId) {
    if (!_id.hasMatch(instanceId)) {
      throw ArgumentError('Invalid Argon instance id.');
    }
    return '$aliasPrefix$instanceId';
  }

  /// Lowercase hex SHA-256 of the SPKI DER, exactly as Argon displays it.
  static String fingerprint(String publicKeyBase64) =>
      sha256.convert(base64Decode(publicKeyBase64)).toString();

  /// The prefix Argon's Devices page shows ("Key 0123456789abcdef…").
  static String shortFingerprint(String fingerprint) =>
      '${fingerprint.substring(0, fingerprint.length.clamp(0, 16))}…';

  Future<String> publicKey(String alias) async =>
      (await _channel.invokeMethod<String>('publicKey', {'alias': alias}))!;
  Future<String> sign(String alias, String value) async => (await _channel
      .invokeMethod<String>('sign', {'alias': alias, 'message': value}))!;
  Future<bool> exists(String alias) async =>
      await _channel.invokeMethod<bool>('exists', {'alias': alias}) ?? false;
  Future<void> delete(String alias) =>
      _channel.invokeMethod<void>('delete', {'alias': alias});
  Future<List<String>> list() async =>
      await _channel.invokeListMethod<String>('list') ?? const [];
  Future<DeviceKeyHardware?> hardware(String alias) async =>
      switch (await _channel.invokeMethod<String>('hardware', {
        'alias': alias,
      })) {
        'strongbox' => DeviceKeyHardware.strongBox,
        'tee' => DeviceKeyHardware.tee,
        'software' => DeviceKeyHardware.software,
        _ => null,
      };

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
    required String alias,
    required String id,
    required String method,
    required String path,
    required int ts,
    required String nonce,
    required List<int> body,
  }) async {
    final signature = await sign(
      alias,
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
