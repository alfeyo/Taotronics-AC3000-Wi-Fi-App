import 'dart:async';
import 'dart:io';

enum ProbeOutcome {
  /// TCP handshake completed.
  open,

  /// The host answered with a reset: it is reachable, the port is closed.
  refused,

  /// No answer before the timeout (host down, wrong network, or filtered).
  timeout,

  /// Any other failure (no route, network unreachable, ...).
  error,
}

typedef SocketConnector =
    Future<Socket> Function(String host, int port, {Duration? timeout});

/// TCP reachability checks for the router gateway.
class NetworkProbe {
  NetworkProbe({SocketConnector? connector})
    : _connect = connector ?? Socket.connect;

  final SocketConnector _connect;

  // ECONNREFUSED on Linux/Android, macOS/iOS and Windows.
  static const _refusedCodes = {111, 61, 10061};

  Future<ProbeOutcome> probe(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final socket = await _connect(host, port, timeout: timeout);
      socket.destroy();
      return ProbeOutcome.open;
    } on SocketException catch (e) {
      final code = e.osError?.errorCode;
      if (code != null && _refusedCodes.contains(code)) {
        return ProbeOutcome.refused;
      }
      if (e.message.contains('timed out') ||
          (e.osError?.message.contains('timed out') ?? false)) {
        return ProbeOutcome.timeout;
      }
      return ProbeOutcome.error;
    } on TimeoutException {
      return ProbeOutcome.timeout;
    } catch (_) {
      return ProbeOutcome.error;
    }
  }

  /// The host is reachable when any probed port completes a handshake or
  /// actively refuses it. Unlike a DNS lookup of an IP literal (which always
  /// "succeeds"), this needs a real answer from the host.
  Future<bool> isHostReachable(
    String host, {
    List<int> ports = const [80, 443],
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final outcomes = await Future.wait(
      ports.map((port) => probe(host, port, timeout: timeout)),
    );
    return outcomes.any(
      (o) => o == ProbeOutcome.open || o == ProbeOutcome.refused,
    );
  }
}
