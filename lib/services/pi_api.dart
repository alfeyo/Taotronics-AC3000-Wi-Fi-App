import 'dart:async';
import 'dart:convert';
import 'dart:io';

Uri validatePiEndpoint(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException(
      'Enter an HTTPS origin or a Tailscale IP address.',
    );
  }
  final parts = uri.host.split('.').map(int.tryParse).toList();
  final tailnet =
      parts.length == 4 &&
      parts.every((n) => n != null && n >= 0 && n <= 255) &&
      parts[0] == 100 &&
      parts[1]! >= 64 &&
      parts[1]! <= 127;
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && tailnet)) {
    throw const FormatException(
      'Use HTTPS, or HTTP only over your private Tailscale VPN (100.64.0.0/10).',
    );
  }
  return uri.replace(path: '');
}

class PiApiException implements Exception {
  const PiApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PiApi {
  PiApi(this.endpoint, this.token);
  final Uri endpoint;
  final String token;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .openUrl(body == null ? 'GET' : 'POST', endpoint.resolve(path))
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const PiApiException('Access denied. Check the companion token.');
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const PiApiException(
          'Redirect refused. Use the final secure Pi address.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const PiApiException('Pi response exceeds the size limit.');
        }
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (response.statusCode == 409 && body != null) {
        return {'ok': true, 'alreadyReceived': true};
      }
      if (response.statusCode != 200 ||
          data is! Map<String, dynamic> ||
          data['ok'] != true ||
          data['version'] != 1) {
        throw const PiApiException('Pi data is unavailable or incompatible.');
      }
      return data;
    } on PiApiException {
      rethrow;
    } on HandshakeException {
      throw const PiApiException(
        'TLS verification failed. The connection was not trusted.',
      );
    } on TimeoutException {
      throw const PiApiException(
        'Pi did not respond. Check Tailscale and try again.',
      );
    } on SocketException {
      throw const PiApiException(
        'Pi unreachable. Direct router control remains available.',
      );
    } on FormatException {
      throw const PiApiException('Pi returned an invalid response.');
    } finally {
      client.close(force: true);
    }
  }
}
