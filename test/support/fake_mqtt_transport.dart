import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tt_router_flutter/services/mqtt_transport.dart';

/// Scriptable in-memory stand-in for the router broker.
class FakeMqttTransport implements MqttTransport {
  FakeMqttTransport(this.host, {this.connectDelay = Duration.zero});

  final String host;
  final Duration connectDelay;

  final _messages = StreamController<MqttInbound>.broadcast(sync: true);
  final published = <({String topic, Map<String, dynamic> payload})>[];
  final subscriptions = <String>[];
  VoidCallback? _onDisconnected;

  bool connected = false;
  bool disconnectCalled = false;
  bool rejectCredentials = false;
  String? username;
  String? password;

  /// Optional automatic responder: given a command path and request data,
  /// return the reply body (or null for no reply).
  Map<String, dynamic>? Function(String path, dynamic data)? responder;

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
    this.username = username;
    this.password = password;
    await Future<void>.delayed(connectDelay);
    if (disconnectCalled) throw StateError('Torn down while connecting');
    if (rejectCredentials) throw StateError('Bad credentials');
    connected = true;
  }

  @override
  void subscribe(String topic) => subscriptions.add(topic);

  @override
  void publish(String topic, String payload) {
    if (!connected) throw StateError('Not connected');
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    published.add((topic: topic, payload: decoded));
    final reply = responder;
    if (reply == null) return;
    final appId = decoded['AppId'] as String;
    final path = topic.substring(topic.indexOf(appId) + appId.length);
    final body = reply(path, decoded['Data']);
    if (body != null) {
      scheduleMicrotask(() => deliver('$appId$path', jsonEncode(body)));
    }
  }

  void deliver(String topic, String payload) {
    if (!_messages.isClosed) _messages.add(MqttInbound(topic, payload));
  }

  /// Simulates the broker dropping an established session.
  void drop() {
    connected = false;
    _onDisconnected?.call();
  }

  @override
  void disconnect() {
    disconnectCalled = true;
    connected = false;
  }
}

/// Records every transport the service creates.
class FakeTransportFactory {
  FakeTransportFactory({this.connectDelay = Duration.zero});

  final Duration connectDelay;
  final created = <FakeMqttTransport>[];
  Map<String, dynamic>? Function(String path, dynamic data)? responder;
  bool rejectCredentials = false;

  FakeMqttTransport get last => created.last;

  MqttTransport call(String host, int port) {
    final transport = FakeMqttTransport(host, connectDelay: connectDelay)
      ..responder = responder
      ..rejectCredentials = rejectCredentials;
    created.add(transport);
    return transport;
  }
}
