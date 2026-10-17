import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Result of checking a certificate presented by the router.
enum CertificateVerdict {
  /// The presented certificate is the pinned CA itself.
  pinnedAuthority,

  /// The presented certificate is signed by the pinned CA and is in date.
  signedByPinnedAuthority,

  /// The certificate could not be parsed.
  malformed,

  /// The issuer name does not match the pinned CA.
  wrongIssuer,

  /// The signature algorithm is not sha256WithRSAEncryption.
  unsupportedAlgorithm,

  /// The signature does not verify against the pinned CA key.
  badSignature,

  /// The certificate (or the pinned CA) is outside its validity period.
  expired,
}

extension CertificateVerdictX on CertificateVerdict {
  bool get trusted =>
      this == CertificateVerdict.pinnedAuthority ||
      this == CertificateVerdict.signedByPinnedAuthority;
}

/// Verifies router TLS certificates against the TaoTronics local CA.
///
/// The router presents a leaf certificate for `wifilocal.taotronics.com`
/// signed by the CA bundled with the original app. Because the app connects by
/// IP address, the platform hostname check always fails and the TLS layer asks
/// the app to decide. This class makes that decision cryptographically: the
/// leaf must carry a valid RSA/SHA-256 signature from the pinned CA key, name
/// the CA as its issuer, and be within its validity period. Matching names
/// alone is never enough.
class RouterCertificateVerifier {
  RouterCertificateVerifier(
    Uint8List authorityDer, {
    DateTime Function()? clock,
  }) : _authorityDer = authorityDer,
       _authority = _ParsedCertificate.parse(authorityDer),
       _clock = clock ?? DateTime.now {
    final key = _authority.rsaPublicKey;
    if (key == null) {
      throw ArgumentError('Pinned authority must carry an RSA public key');
    }
    _authorityKey = key;
  }

  factory RouterCertificateVerifier.fromPem(
    String pem, {
    DateTime Function()? clock,
  }) {
    return RouterCertificateVerifier(pemToDer(pem), clock: clock);
  }

  final Uint8List _authorityDer;
  final _ParsedCertificate _authority;
  final DateTime Function() _clock;
  late final _RsaPublicKey _authorityKey;

  /// The pinned CA as PEM bytes, for `SecurityContext` trust anchors.
  Uint8List get authorityPem {
    final body = base64.encode(_authorityDer);
    final lines = [
      for (var i = 0; i < body.length; i += 64)
        body.substring(i, i + 64 > body.length ? body.length : i + 64),
    ];
    return Uint8List.fromList(
      utf8.encode(
        '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
        '-----END CERTIFICATE-----\n',
      ),
    );
  }

  CertificateVerdict verify(Uint8List presentedDer) {
    if (_bytesEqual(presentedDer, _authorityDer)) {
      return _authority.isValidAt(_clock())
          ? CertificateVerdict.pinnedAuthority
          : CertificateVerdict.expired;
    }

    final _ParsedCertificate leaf;
    try {
      leaf = _ParsedCertificate.parse(presentedDer);
    } catch (_) {
      // Any parse failure (format, range, encoding) means an untrusted cert.
      return CertificateVerdict.malformed;
    }

    if (!_bytesEqual(leaf.issuerDer, _authority.subjectDer)) {
      return CertificateVerdict.wrongIssuer;
    }
    if (!_bytesEqual(leaf.signatureAlgorithmDer, _sha256WithRsaDer) ||
        !_bytesEqual(leaf.tbsSignatureAlgorithmDer, _sha256WithRsaDer)) {
      return CertificateVerdict.unsupportedAlgorithm;
    }
    if (!_authorityKey.verifyPkcs1Sha256(leaf.tbsDer, leaf.signature)) {
      return CertificateVerdict.badSignature;
    }
    final now = _clock();
    if (!leaf.isValidAt(now) || !_authority.isValidAt(now)) {
      return CertificateVerdict.expired;
    }
    return CertificateVerdict.signedByPinnedAuthority;
  }

  static Uint8List pemToDer(String pem) {
    final body = pem
        .replaceAll(RegExp(r'-----(BEGIN|END) CERTIFICATE-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    return base64.decode(body);
  }
}

// AlgorithmIdentifier { sha256WithRSAEncryption, NULL }
final Uint8List _sha256WithRsaDer = Uint8List.fromList([
  0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, //
  0x0b, 0x05, 0x00,
]);

// OID 1.2.840.113549.1.1.1 rsaEncryption
final Uint8List _rsaEncryptionOid = Uint8List.fromList([
  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, //
]);

// DigestInfo prefix for SHA-256 (RFC 8017 section 9.2, note 1)
final Uint8List _sha256DigestInfoPrefix = Uint8List.fromList([
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, //
  0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
]);

class _ParsedCertificate {
  _ParsedCertificate({
    required this.tbsDer,
    required this.tbsSignatureAlgorithmDer,
    required this.issuerDer,
    required this.subjectDer,
    required this.notBefore,
    required this.notAfter,
    required this.subjectPublicKeyInfo,
    required this.signatureAlgorithmDer,
    required this.signature,
  });

  final Uint8List tbsDer;
  final Uint8List tbsSignatureAlgorithmDer;
  final Uint8List issuerDer;
  final Uint8List subjectDer;
  final DateTime notBefore;
  final DateTime notAfter;
  final _Der subjectPublicKeyInfo;
  final Uint8List signatureAlgorithmDer;
  final Uint8List signature;

  bool isValidAt(DateTime now) =>
      !now.isBefore(notBefore) && !now.isAfter(notAfter);

  _RsaPublicKey? get rsaPublicKey {
    final parts = subjectPublicKeyInfo.children();
    if (parts.length != 2) return null;
    final algorithm = parts[0].children();
    if (algorithm.isEmpty ||
        algorithm[0].tag != 0x06 ||
        !_bytesEqual(algorithm[0].content, _rsaEncryptionOid)) {
      return null;
    }
    final keyBits = parts[1];
    if (keyBits.tag != 0x03 || keyBits.content.isEmpty) return null;
    final keySequence = _Der.read(keyBits.content.sublist(1), 0);
    final numbers = keySequence.children();
    if (numbers.length != 2) return null;
    return _RsaPublicKey(
      modulus: _unsigned(numbers[0].content),
      exponent: _unsigned(numbers[1].content),
    );
  }

  static _ParsedCertificate parse(Uint8List der) {
    final certificate = _Der.read(der, 0);
    if (certificate.tag != 0x30 || certificate.end != der.length) {
      throw const FormatException('Not a DER certificate');
    }
    final top = certificate.children();
    if (top.length != 3 || top[2].tag != 0x03) {
      throw const FormatException('Unexpected certificate layout');
    }
    final tbs = top[0];
    var fields = tbs.children();
    // Skip the optional explicit [0] version field.
    if (fields.isNotEmpty && fields[0].tag == 0xa0) fields = fields.sublist(1);
    if (fields.length < 6) {
      throw const FormatException('Truncated TBSCertificate');
    }
    final validity = fields[3].children();
    if (validity.length != 2) throw const FormatException('Bad validity');
    final signatureBits = top[2].content;
    if (signatureBits.isEmpty || signatureBits[0] != 0) {
      throw const FormatException('Bad signature bit string');
    }
    return _ParsedCertificate(
      tbsDer: tbs.encoded,
      tbsSignatureAlgorithmDer: fields[1].encoded,
      issuerDer: fields[2].encoded,
      subjectDer: fields[4].encoded,
      notBefore: _parseTime(validity[0]),
      notAfter: _parseTime(validity[1]),
      subjectPublicKeyInfo: fields[5],
      signatureAlgorithmDer: top[1].encoded,
      signature: signatureBits.sublist(1),
    );
  }

  static DateTime _parseTime(_Der element) {
    final text = ascii.decode(element.content);
    final match = switch (element.tag) {
      0x17 => RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$'),
      0x18 => RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$'),
      _ => throw const FormatException('Unsupported time type'),
    }.firstMatch(text);
    if (match == null) throw FormatException('Bad time: $text');
    var year = int.parse(match[1]!);
    if (element.tag == 0x17) year += year >= 50 ? 1900 : 2000;
    return DateTime.utc(
      year,
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }
}

class _RsaPublicKey {
  _RsaPublicKey({required this.modulus, required this.exponent});

  final BigInt modulus;
  final BigInt exponent;

  bool verifyPkcs1Sha256(Uint8List message, Uint8List signature) {
    final k = (modulus.bitLength + 7) ~/ 8;
    if (signature.length != k) return false;
    final s = _unsigned(signature);
    if (s >= modulus) return false;
    final encoded = _toBytes(s.modPow(exponent, modulus), k);

    final digest = sha256.convert(message).bytes;
    final tLength = _sha256DigestInfoPrefix.length + digest.length;
    final padLength = k - tLength - 3;
    if (padLength < 8) return false;

    final expected = Uint8List(k)
      ..[0] = 0x00
      ..[1] = 0x01;
    for (var i = 0; i < padLength; i++) {
      expected[2 + i] = 0xff;
    }
    expected[2 + padLength] = 0x00;
    expected.setAll(3 + padLength, _sha256DigestInfoPrefix);
    expected.setAll(3 + padLength + _sha256DigestInfoPrefix.length, digest);
    return _bytesEqual(encoded, expected);
  }
}

/// A single DER TLV element inside a larger buffer.
class _Der {
  _Der(this.buffer, this.start, this.contentStart, this.end, this.tag);

  final Uint8List buffer;
  final int start;
  final int contentStart;
  final int end;
  final int tag;

  Uint8List get encoded => Uint8List.sublistView(buffer, start, end);
  Uint8List get content => Uint8List.sublistView(buffer, contentStart, end);

  static _Der read(Uint8List buffer, int offset) {
    if (offset + 2 > buffer.length) {
      throw const FormatException('Truncated DER header');
    }
    final tag = buffer[offset];
    if (tag & 0x1f == 0x1f) {
      throw const FormatException('High tag numbers are not supported');
    }
    var cursor = offset + 1;
    var length = buffer[cursor++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || cursor + count > buffer.length) {
        throw const FormatException('Unsupported DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | buffer[cursor++];
      }
    }
    final end = cursor + length;
    if (end > buffer.length) throw const FormatException('DER overrun');
    return _Der(buffer, offset, cursor, end, tag);
  }

  List<_Der> children() {
    if (tag & 0x20 == 0) throw const FormatException('Not a constructed type');
    final result = <_Der>[];
    var offset = contentStart;
    while (offset < end) {
      final child = read(buffer, offset);
      if (child.end > end) throw const FormatException('Child overrun');
      result.add(child);
      offset = child.end;
    }
    return result;
  }
}

BigInt _unsigned(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _toBytes(BigInt value, int length) {
  final result = Uint8List(length);
  var remaining = value;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    result[i] = (remaining & mask).toInt();
    remaining = remaining >> 8;
  }
  return result;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
