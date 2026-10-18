import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Argon operator authorization (`ArgonOperator v1`).
///
/// Operator commands (VPN mode) are signed with the operator token, which is
/// never sent itself and is distinct from the companion (monitoring) token:
///
///     sig = HMAC-SHA256(utf8(token),
///       "v1\n<METHOD>\n<path>\n<ts>\n<nonce>\n<hex sha256(raw body)>")
///
/// encoded as base64url without padding.
abstract final class ArgonOperatorAuth {
  static final _hex = RegExp(r'^[0-9a-f]{32}$');

  /// 32 lowercase hex characters from a secure random source.
  static String nonce([Random? random]) {
    final r = random ?? Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static String canonical({
    required String method,
    required String path,
    required int ts,
    required String nonce,
    required List<int> body,
  }) =>
      'v1\n${method.toUpperCase()}\n$path\n$ts\n$nonce\n'
      '${sha256.convert(body)}';

  static String signature({
    required String token,
    required String method,
    required String path,
    required int ts,
    required String nonce,
    required List<int> body,
  }) {
    final mac = Hmac(sha256, utf8.encode(token)).convert(
      utf8.encode(
        canonical(method: method, path: path, ts: ts, nonce: nonce, body: body),
      ),
    );
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }

  /// The complete `Authorization` header value.
  static String header({
    required String token,
    required String method,
    required String path,
    required List<int> body,
    required int ts,
    required String nonce,
  }) {
    if (!_hex.hasMatch(nonce)) {
      throw ArgumentError.value(nonce, 'nonce', 'must be 32 lowercase hex');
    }
    final sig = signature(
      token: token,
      method: method,
      path: path,
      ts: ts,
      nonce: nonce,
      body: body,
    );
    return 'ArgonOperator v1 ts=$ts,nonce=$nonce,sig=$sig';
  }
}
