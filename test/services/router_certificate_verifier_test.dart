import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';
import 'package:tt_router_flutter/services/router_certificate_verifier.dart';

Uint8List _fixture(String name) => RouterCertificateVerifier.pemToDer(
  File('test/fixtures/certificates/$name').readAsStringSync(),
);

void main() {
  // Captured from the live router at 192.168.10.1:25678 on 2026-10-17.
  final routerLeaf = _fixture('router_leaf.pem');
  final authority = _fixture('taotronics_local_ca.pem');
  final inValidity = DateTime.utc(2026, 10, 17);

  RouterCertificateVerifier verifierAt(DateTime time) =>
      RouterCertificateVerifier(authority, clock: () => time);

  test('bundled MQTT CA matches the CA the router chains to', () {
    expect(MqttService.pinnedAuthorityDer, authority);
  });

  test('accepts the real router leaf signed by the pinned CA', () {
    expect(
      verifierAt(inValidity).verify(routerLeaf),
      CertificateVerdict.signedByPinnedAuthority,
    );
  });

  test('accepts the pinned CA certificate itself', () {
    expect(
      verifierAt(inValidity).verify(authority),
      CertificateVerdict.pinnedAuthority,
    );
  });

  test('rejects a self-signed forgery that copies the router names', () {
    final verdict = verifierAt(
      inValidity,
    ).verify(_fixture('forged_self_signed.pem'));
    expect(verdict.trusted, isFalse);
    expect(verdict, CertificateVerdict.wrongIssuer);
  });

  test('rejects a leaf from a lookalike CA with the same issuer name', () {
    final verdict = verifierAt(
      inValidity,
    ).verify(_fixture('impostor_leaf_same_issuer_name.pem'));
    expect(verdict, CertificateVerdict.badSignature);
  });

  test('rejects a router leaf whose signed contents were changed', () {
    final tampered = Uint8List.fromList(routerLeaf);
    // Flip a byte inside the subject's emailAddress (inside the TBS block).
    final marker = 'leo.li'.codeUnits;
    final index = _indexOf(tampered, marker);
    expect(index, greaterThan(0));
    tampered[index] ^= 0x01;
    expect(
      verifierAt(inValidity).verify(tampered),
      CertificateVerdict.badSignature,
    );
  });

  test('rejects a router leaf whose signature bytes were changed', () {
    final tampered = Uint8List.fromList(routerLeaf);
    tampered[tampered.length - 5] ^= 0x80;
    expect(
      verifierAt(inValidity).verify(tampered),
      CertificateVerdict.badSignature,
    );
  });

  test('rejects certificates outside their validity period', () {
    expect(
      verifierAt(DateTime.utc(2031)).verify(routerLeaf),
      CertificateVerdict.expired,
    );
    expect(
      verifierAt(DateTime.utc(2019)).verify(routerLeaf),
      CertificateVerdict.expired,
    );
  });

  test('rejects garbage and truncated input without throwing', () {
    final verifier = verifierAt(inValidity);
    expect(verifier.verify(Uint8List(0)), CertificateVerdict.malformed);
    expect(
      verifier.verify(Uint8List.fromList([0x30, 0x82, 0xff, 0xff, 0x00])),
      CertificateVerdict.malformed,
    );
    expect(
      verifier.verify(Uint8List.sublistView(routerLeaf, 0, 200)),
      CertificateVerdict.malformed,
    );
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
