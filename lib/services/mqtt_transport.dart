import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'router_certificate_verifier.dart';

/// A raw message received from the router broker.
class MqttInbound {
  const MqttInbound(this.topic, this.payload);

  final String topic;
  final String payload;
}

/// The minimal broker connection [MqttService] needs. Separated from
/// `mqtt_client` so the request/response and connection lifecycle logic can be
/// tested against a fake router.
abstract class MqttTransport {
  Stream<MqttInbound> get messages;

  /// Called once if the broker connection drops after [connect] succeeded.
  set onDisconnected(VoidCallback? callback);

  /// Connects and authenticates. Throws if the connection is not established.
  Future<void> connect({
    required String clientId,
    required String username,
    required String password,
  });

  void subscribe(String topic);

  void publish(String topic, String payload);

  void disconnect();
}

typedef MqttTransportFactory = MqttTransport Function(String host, int port);

/// TLS MQTT connection to the router using `mqtt_client`.
class ServerMqttTransport implements MqttTransport {
  ServerMqttTransport(
    this.host,
    this.port, {
    required this._verifier,
    this.onCertificateVerdict,
  });

  final String host;
  final int port;
  final RouterCertificateVerifier _verifier;
  final void Function(CertificateVerdict verdict)? onCertificateVerdict;

  final _messages = StreamController<MqttInbound>.broadcast();
  MqttServerClient? _client;
  StreamSubscription? _updates;
  VoidCallback? _onDisconnected;
  bool _connected = false;

  @override
  Stream<MqttInbound> get messages => _messages.stream;

  @override
  set onDisconnected(VoidCallback? callback) => _onDisconnected = callback;

  @override
  Future<void> connect({
    required String clientId,
    required String username,
    required String password,
  }) async {
    final client = MqttServerClient.withPort(host, clientId, port)
      ..logging(on: false)
      ..keepAlivePeriod = 30
      ..connectTimeoutPeriod = 10000
      ..secure = true
      ..securityContext = (SecurityContext()
        ..setTrustedCertificatesBytes(_verifier.authorityPem))
      ..onBadCertificate = _checkCertificate
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(username, password)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
    client.onDisconnected = () {
      if (!identical(_client, client)) return;
      final wasConnected = _connected;
      _connected = false;
      if (wasConnected) _onDisconnected?.call();
    };
    _client = client;

    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError(
        'Broker refused the connection: ${client.connectionStatus}',
      );
    }
    _connected = true;
    _updates = client.updates?.listen(
      (messages) {
        for (final message in messages) {
          final payload = message.payload;
          if (payload is! MqttPublishMessage) continue;
          _messages.add(
            MqttInbound(
              message.topic,
              MqttPublishPayload.bytesToStringAsString(payload.payload.message),
            ),
          );
        }
      },
      onError: (Object error) {
        debugPrint('MqttTransport: update stream error - $error');
      },
    );
  }

  bool _checkCertificate(Object certificate) {
    if (certificate is! X509Certificate) {
      debugPrint('MqttTransport: rejected certificate of unknown type');
      onCertificateVerdict?.call(CertificateVerdict.malformed);
      return false;
    }
    final verdict = _verifier.verify(certificate.der);
    onCertificateVerdict?.call(verdict);
    debugPrint(
      'MqttTransport: router certificate ${verdict.trusted ? 'accepted' : 'REJECTED'} '
      '(${verdict.name}) for ${certificate.subject}',
    );
    return verdict.trusted;
  }

  @override
  void subscribe(String topic) {
    _client?.subscribe(topic, MqttQos.exactlyOnce);
  }

  @override
  void publish(String topic, String payload) {
    final client = _client;
    if (client == null) throw StateError('Not connected');
    final builder = MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
  }

  @override
  void disconnect() {
    final client = _client;
    _client = null;
    _connected = false;
    _updates?.cancel();
    _updates = null;
    try {
      client?.disconnect();
    } catch (e) {
      debugPrint('MqttTransport: disconnect error - $e');
    }
    _messages.close();
  }
}
