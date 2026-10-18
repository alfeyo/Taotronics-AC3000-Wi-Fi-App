import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/services/argon_operator.dart';

void main() {
  // Expected values computed independently with Python's hmac/hashlib:
  //   body = b'{"state":"off","confirm":"VPN_MODE"}'
  //   msg  = "v1\nPOST\n/api/v1/vpn\n1792313172\n<nonce>\n" + sha256(body).hex
  //   sig  = urlsafe_b64encode(HMAC-SHA256(token, msg)).rstrip("=")
  const token = 'operator-test-token-0123456789';
  const nonce = '0123456789abcdef0123456789abcdef';
  const ts = 1792313172;
  final body = utf8.encode('{"state":"off","confirm":"VPN_MODE"}');

  test('canonical string hashes the exact raw body', () {
    expect(
      ArgonOperatorAuth.canonical(
        method: 'post',
        path: '/api/v1/vpn',
        ts: ts,
        nonce: nonce,
        body: body,
      ),
      'v1\nPOST\n/api/v1/vpn\n1792313172\n$nonce\n'
      '6ad5927c9b8e91262d14c7e8695ebc40959d12664b88e7775f46310094a36df2',
    );
  });

  test('HMAC-SHA256 signature matches the known vector', () {
    expect(
      ArgonOperatorAuth.header(
        token: token,
        method: 'POST',
        path: '/api/v1/vpn',
        body: body,
        ts: ts,
        nonce: nonce,
      ),
      'ArgonOperator v1 ts=1792313172,nonce=$nonce,'
      'sig=pVTNrW8LpzSQFbuwVAIUphpGIevb9RTBTG8qym7diaY',
    );
  });

  test('nonce is 32 lowercase hex characters; bad nonces are refused', () {
    final n = ArgonOperatorAuth.nonce(Random(1));
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(n), true);
    expect(ArgonOperatorAuth.nonce(), isNot(ArgonOperatorAuth.nonce()));
    expect(
      () => ArgonOperatorAuth.header(
        token: token,
        method: 'POST',
        path: '/api/v1/vpn',
        body: body,
        ts: ts,
        nonce: 'XYZ',
      ),
      throwsArgumentError,
    );
  });
}
