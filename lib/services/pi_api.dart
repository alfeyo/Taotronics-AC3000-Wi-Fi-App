import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// How the app currently reaches Argon.
enum PiTransportKind {
  lan('Local network'),
  tailscale('Tailscale'),
  https('Secure web'),
  bluetooth('Bluetooth');

  const PiTransportKind(this.label);
  final String label;
}

bool _isTailnet(List<int> p) => p[0] == 100 && p[1] >= 64 && p[1] <= 127;
bool _isPrivate(List<int> p) =>
    p[0] == 10 ||
    (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
    (p[0] == 192 && p[1] == 168);

List<int>? _ipv4(String host) {
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((n) => n == null || n < 0 || n > 255)) {
    return null;
  }
  return parts.cast<int>();
}

/// Endpoint policy. HTTPS anywhere; plain HTTP only to a literal private LAN
/// or Tailscale (100.64.0.0/10) address, and only after the server proved it
/// is the pinned Argon instance (see [PiDiscovery]).
Uri validatePiEndpoint(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException(
      'Enter an address such as http://192.168.50.1.',
    );
  }
  if (uri.scheme == 'https') return uri.replace(path: '');
  final ip = _ipv4(uri.host);
  if (uri.scheme == 'http' &&
      ip != null &&
      (_isTailnet(ip) || _isPrivate(ip))) {
    return uri.replace(path: '');
  }
  throw const FormatException(
    'Use HTTPS, or HTTP to a private LAN or Tailscale IP address.',
  );
}

PiTransportKind kindForEndpoint(Uri uri) {
  if (uri.scheme == 'https') return PiTransportKind.https;
  final ip = _ipv4(uri.host);
  return ip != null && _isTailnet(ip)
      ? PiTransportKind.tailscale
      : PiTransportKind.lan;
}

class PiApiException implements Exception {
  const PiApiException(this.message, {this.status});
  final String message;
  final int? status;
  bool get unauthorized => status == 401 || status == 403;
  @override
  String toString() => message;
}

/// A way to reach Argon's companion API.
abstract class PiTransport {
  PiTransportKind get kind;
  String get describe;
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  });
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  });
}

/// Raw status and decoded JSON body of a request whose non-200 answers are
/// meaningful to the caller (operator commands).
class PiRawResponse {
  const PiRawResponse(this.status, this.data);
  final int status;
  final Map<String, dynamic>? data;
}

/// A transport that can carry an operator-signed command. Only IP routes do:
/// the Bluetooth bridge relays reads only.
abstract class PiOperatorTransport {
  Future<PiRawResponse> sendRaw(
    String method,
    String path, {
    required List<int> body,
    required Map<String, String> headers,
    Duration? timeout,
  });
}

Map<String, dynamic> _checked(int status, Object? data) {
  if (status == 401 || status == 403) {
    throw PiApiException('Argon refused the credential.', status: status);
  }
  if (status == 409) {
    throw const PiApiException(
      'Observation already received or out of order.',
      status: 409,
    );
  }
  if (data is! Map<String, dynamic>) {
    throw PiApiException('Argon returned an invalid response.', status: status);
  }
  if (status != 200 || data['ok'] != true) {
    throw PiApiException(
      (data['error'] as String?) ?? 'Argon request failed ($status).',
      status: status,
    );
  }
  return data;
}

class HttpPiTransport implements PiTransport, PiOperatorTransport {
  HttpPiTransport(
    this.endpoint, {
    this.connectTimeout = const Duration(seconds: 3),
  }) : kind = kindForEndpoint(endpoint);

  final Uri endpoint;
  final Duration connectTimeout;
  @override
  final PiTransportKind kind;
  @override
  String get describe => endpoint.host;

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
    String? token,
    Duration timeout,
  ) async {
    final r = await _exchange(
      method,
      path,
      body == null ? null : utf8.encode(jsonEncode(body)),
      {if (token != null) HttpHeaders.authorizationHeader: 'Bearer $token'},
      timeout,
    );
    return _checked(r.status, r.data);
  }

  Future<PiRawResponse> _exchange(
    String method,
    String path,
    List<int>? body,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final request = await client
          .openUrl(method, endpoint.resolve(path))
          .timeout(timeout);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      if (response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        throw const PiApiException('Redirect refused.');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const PiApiException('Argon response exceeds the size limit.');
        }
      }
      Object? data;
      try {
        data = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        data = null;
      }
      return PiRawResponse(
        response.statusCode,
        data is Map<String, dynamic> ? data : null,
      );
    } on PiApiException {
      rethrow;
    } on HandshakeException {
      throw const PiApiException('TLS verification failed.');
    } on TimeoutException {
      throw const PiApiException('Argon did not respond in time.');
    } on SocketException {
      throw const PiApiException('Argon is not reachable on this route.');
    } on HttpException {
      throw const PiApiException('Connection to Argon was interrupted.');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<PiRawResponse> sendRaw(
    String method,
    String path, {
    required List<int> body,
    required Map<String, String> headers,
    Duration? timeout,
  }) => _exchange(
    method,
    path,
    body,
    headers,
    timeout ?? const Duration(seconds: 20),
  );

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) => _send('GET', path, null, token, timeout ?? const Duration(seconds: 8));

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) =>
      _send('POST', path, body, token, timeout ?? const Duration(seconds: 10));
}

/// Read-only fallback over Argon's Bluetooth serial bridge (argon-bt-bridge).
/// Only identity, live and gateway reads are available, and live/gateway need
/// the paired credential; uploads and pairing require an IP route.
class BluetoothPiTransport implements PiTransport {
  BluetoothPiTransport(this.address, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('tt_router/argon_bluetooth');

  final String address;
  final MethodChannel _channel;
  int _id = 0;

  @override
  PiTransportKind get kind => PiTransportKind.bluetooth;
  @override
  String get describe => 'Bluetooth';

  static Future<Map<String, dynamic>> status({MethodChannel? channel}) async {
    try {
      final r =
          await (channel ?? const MethodChannel('tt_router/argon_bluetooth'))
              .invokeMapMethod<String, dynamic>('status');
      return r ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Duration? timeout,
  }) async {
    final id = ++_id;
    final String? raw;
    try {
      raw = await _channel.invokeMethod<String>('request', {
        'address': address,
        'line': jsonEncode({
          'id': id,
          'method': 'GET',
          'path': path,
          'token': ?token,
        }),
        'timeoutMs': (timeout ?? const Duration(seconds: 12)).inMilliseconds,
      });
    } on PlatformException catch (e) {
      throw PiApiException(
        e.code == 'permission'
            ? 'Bluetooth permission is needed for the fallback.'
            : 'Bluetooth: ${e.message ?? 'request failed'}',
      );
    } on MissingPluginException {
      throw const PiApiException('Bluetooth is not available.');
    }
    Object? reply;
    try {
      reply = jsonDecode(raw ?? '');
    } on FormatException {
      reply = null;
    }
    if (reply is! Map || reply['id'] != id) {
      throw const PiApiException('Bluetooth bridge returned an invalid reply.');
    }
    return _checked(
      (reply['status'] as num?)?.toInt() ?? 500,
      reply['data'] ?? {'ok': false, 'error': reply['error']},
    );
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async => throw const PiApiException('Not available over Bluetooth.');
}

/// What /api/v1/identity proved about a server.
class PiIdentity {
  const PiIdentity({
    required this.instanceId,
    required this.host,
    required this.monitorAllowed,
    this.bluetoothAddress,
  });
  final String instanceId;
  final String host;
  final bool monitorAllowed;
  final String? bluetoothAddress;

  static PiIdentity parse(Map<String, dynamic> d) {
    final id = d['instanceId'];
    final versions = d['apiVersions'];
    if (d['service'] != 'argon' ||
        id is! String ||
        !RegExp(r'^[0-9a-f-]{36}$').hasMatch(id) ||
        versions is! List ||
        !versions.contains(1)) {
      throw const PiApiException('This server is not an Argon Network Hub.');
    }
    final bt = d['bluetooth'];
    final address = bt is Map ? bt['address'] : null;
    return PiIdentity(
      instanceId: id,
      host: (d['host'] as String?) ?? 'argon',
      monitorAllowed: (d['access'] is Map) && d['access']['monitor'] == true,
      bluetoothAddress:
          address is String &&
              RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(address)
          ? address
          : null,
    );
  }
}
