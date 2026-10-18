import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/services/mqtt_service.dart';

import '../support/fake_mqtt_transport.dart';

const _appId = 'app123';

MqttService _service(
  FakeTransportFactory factory, {
  String appId = _appId,
  V1OnlyStore? store,
}) => MqttService(
  transportFactory: factory.call,
  appIdLoader: () async => appId,
  v1OnlyStore: store ?? MemoryV1OnlyStore(),
);

void main() {
  group('connection lifecycle', () {
    test('connects with default derived password and subscribes', () async {
      final factory = FakeTransportFactory();
      final service = _service(factory);

      expect(await service.connect('mesh1', '192.168.10.1'), isTrue);
      expect(service.isConnected, isTrue);
      expect(factory.last.username, 'mesh1');
      expect(factory.last.password, hasLength(32));
      expect(factory.last.subscriptions, ['$_appId/+']);
    });

    test('a reconnect never tears down a connect still in progress', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory(
          connectDelay: const Duration(seconds: 3),
        );
        final service = _service(factory);
        bool? first;
        bool? second;

        service.connect('meshA', '10.0.0.1').then((v) => first = v);
        async.elapse(const Duration(seconds: 1));
        // Reconnect timer fires for a different router mid-handshake.
        service.connect('meshB', '10.0.0.2').then((v) => second = v);
        async.elapse(const Duration(seconds: 1));
        expect(factory.created, hasLength(1));
        expect(factory.created.first.disconnectCalled, isFalse);

        async.elapse(const Duration(seconds: 5));
        expect(first, isTrue, reason: 'first handshake completes intact');
        expect(second, isTrue);
        expect(factory.created, hasLength(2));
        expect(factory.created.first.disconnectCalled, isTrue);
        expect(service.connectedMeshId, 'meshB');
      });
    });

    test('identical concurrent connects share one attempt', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory(
          connectDelay: const Duration(seconds: 2),
        );
        final service = _service(factory);
        final a = service.connect('mesh1', '10.0.0.1');
        final b = service.connect('mesh1', '10.0.0.1');
        expect(identical(a, b), isTrue);
        async.elapse(const Duration(seconds: 3));
        expect(factory.created, hasLength(1));
      });
    });

    test('failed connect returns false and emits no drop event', () async {
      final factory = FakeTransportFactory()..rejectCredentials = true;
      final service = _service(factory);
      final events = <bool>[];
      service.connectionStream.listen(events.add);

      expect(await service.connect('mesh1', '10.0.0.1'), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(service.isConnected, isFalse);
      expect(events, isEmpty);
    });

    test('unexpected broker drop emits false once', () async {
      final factory = FakeTransportFactory();
      final service = _service(factory);
      final events = <bool>[];
      service.connectionStream.listen(events.add);

      await service.connect('mesh1', '10.0.0.1');
      factory.last.drop();
      await Future<void>.delayed(Duration.zero);
      expect(events, [true, false]);
      expect(service.isConnected, isFalse);
    });

    test('deliberate disconnect emits no drop event', () async {
      final factory = FakeTransportFactory();
      final service = _service(factory);
      final events = <bool>[];
      service.connectionStream.listen(events.add);

      await service.connect('mesh1', '10.0.0.1');
      await service.disconnect();
      factory.last.drop(); // late callback from the old client
      await Future<void>.delayed(Duration.zero);
      expect(events, [true]);
    });
  });

  group('request/response', () {
    test('returns the reply for the request topic', () async {
      final factory = FakeTransportFactory()
        ..responder = (path, data) => {'ErrorCode': 0, 'Data': path};
      final service = _service(factory);
      await service.connect('mesh1', '10.0.0.1');

      final reply = await service.sendCommand('/GetSystemState', {});
      expect(reply, {'ErrorCode': 0, 'Data': '/GetSystemState'});
      expect(
        factory.last.published.single.topic,
        'mesh1/$_appId/GetSystemState',
      );
    });

    test('identical concurrent requests share one round trip', () async {
      final factory = FakeTransportFactory()
        ..responder = (path, data) => {'ErrorCode': 0};
      final service = _service(factory);
      await service.connect('mesh1', '10.0.0.1');

      final results = await Future.wait([
        service.getDeviceList(),
        service.getDeviceList(),
      ]);
      expect(results, everyElement(isNotNull));
      expect(factory.last.published, hasLength(1));
    });

    test('different requests to one path run one at a time', () async {
      final factory = FakeTransportFactory();
      final service = _service(factory);
      await service.connect('mesh1', '10.0.0.1');
      final transport = factory.last;

      final first = service.setFirewallSettings(true);
      final second = service.setFirewallSettings(false);
      await Future<void>.delayed(Duration.zero);
      expect(transport.published, hasLength(1), reason: 'second waits');

      transport.deliver('$_appId/SetFirewallInfo', '{"ErrorCode":0,"n":1}');
      expect(await first, containsPair('n', 1));
      await Future<void>.delayed(Duration.zero);
      expect(transport.published, hasLength(2));
      expect(transport.published[1].payload['Data'], {'Enable': 0});

      transport.deliver('$_appId/SetFirewallInfo', '{"ErrorCode":0,"n":2}');
      expect(await second, containsPair('n', 2));
    });

    test('times out with null and releases the path', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory();
        final service = _service(factory);
        service.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));
        expect(service.isConnected, isTrue);

        Map<String, dynamic>? result = {'sentinel': true};
        var completed = false;
        service.sendCommand('/GetQosInfo', {}, timeout: 4).then((v) {
          result = v;
          completed = true;
        });
        async.elapse(const Duration(seconds: 5));
        expect(completed, isTrue);
        expect(result, isNull);

        service.sendCommand('/GetQosInfo', {}, timeout: 4);
        async.flushMicrotasks();
        expect(factory.last.published, hasLength(2));
      });
    });

    test('malformed and non-object replies complete with null', () async {
      final factory = FakeTransportFactory();
      final service = _service(factory);
      await service.connect('mesh1', '10.0.0.1');
      final transport = factory.last;

      final notJson = service.sendCommand('/A', {});
      await Future<void>.delayed(Duration.zero);
      transport.deliver('$_appId/A', 'not json');
      transport.deliver('$_appId/A', '[1,2]');
      expect(await notJson, isNull);
    });

    test(
      'pending requests complete with null when the session drops',
      () async {
        final factory = FakeTransportFactory();
        final service = _service(factory);
        await service.connect('mesh1', '10.0.0.1');

        final pending = service.getNodeList();
        await Future<void>.delayed(Duration.zero);
        factory.last.drop();
        expect(await pending.timeout(const Duration(seconds: 1)), isNull);
      },
    );

    test('a late write reply is not taken by the next write', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory();
        final service = _service(factory);
        service.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));
        final transport = factory.last;

        Map<String, dynamic>? first = {'sentinel': 1};
        service.setFirewallSettings(true).then((r) => first = r);
        async.elapse(const Duration(seconds: 11));
        expect(first, isNull, reason: 'first write timed out');

        Map<String, dynamic>? second;
        service.setFirewallSettings(false).then((r) => second = r);
        async.elapse(const Duration(seconds: 1));
        expect(transport.published, hasLength(1), reason: 'second waits');

        // The first write's reply finally arrives: it must be discarded.
        transport.deliver('$_appId/SetFirewallInfo', '{"ErrorCode":0,"n":1}');
        async.elapse(const Duration(milliseconds: 10));
        expect(second, isNull);
        expect(transport.published, hasLength(2));

        transport.deliver('$_appId/SetFirewallInfo', '{"ErrorCode":0,"n":2}');
        async.elapse(const Duration(milliseconds: 10));
        expect(second, containsPair('n', 2));
      });
    });

    test('reads are not held back after a read timeout', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory();
        final service = _service(factory);
        service.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));
        service.getQosSettings();
        async.elapse(const Duration(seconds: 11));
        service.getQosSettings();
        async.elapse(const Duration(milliseconds: 10));
        expect(factory.last.published, hasLength(2));
      });
    });

    test('stops sending V2 wireless queries a router never answers', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory()
          ..responder = (path, data) => path == '/GetWirelessInfoList'
              ? {'ErrorCode': 0, 'Data': []}
              : null;
        final service = _service(factory);
        service.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));

        service.getWirelessSettings();
        async.elapse(const Duration(seconds: 11));
        service.getWirelessSettings();
        async.elapse(const Duration(seconds: 1));

        final paths = factory.last.published
            .map((p) => p.topic.split(_appId).last)
            .toList();
        expect(paths, [
          '/GetWirelessInfoListV2',
          '/GetWirelessInfoList',
          '/GetWirelessInfoList',
        ]);
      });
    });

    test(
      'an unanswered V2 is recorded even when the V1 read also times out',
      () {
        fakeAsync((async) {
          // A busy router (another phone polling) leaves both reads unanswered.
          final factory = FakeTransportFactory()
            ..responder = (path, data) => null;
          final store = MemoryV1OnlyStore();
          final service = _service(factory, store: store);
          service.connect('mesh1', '10.0.0.1');
          async.elapse(const Duration(milliseconds: 1));

          service.getWirelessSettings();
          async.elapse(const Duration(seconds: 25));
          service.getWirelessSettings();
          async.elapse(const Duration(seconds: 12));

          final paths = factory.last.published
              .map((p) => p.topic.split(_appId).last)
              .toList();
          expect(
            paths.where((p) => p == '/GetWirelessInfoListV2'),
            hasLength(1),
          );
          expect(store.meshIds, {'mesh1'});
        });
      },
    );

    test('the V1-only verdict survives a new session', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory()
          ..responder = (path, data) => path == '/GetWirelessInfoList'
              ? {'ErrorCode': 0, 'Data': []}
              : null;
        final service = _service(factory, store: MemoryV1OnlyStore({'mesh1'}));
        service.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));
        service.getWirelessSettings();
        async.elapse(const Duration(seconds: 1));
        expect(factory.last.published.map((p) => p.topic.split(_appId).last), [
          '/GetWirelessInfoList',
        ]);
      });
    });

    test('a router error reply to V2 does not mark the router V1-only', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory()
          ..responder = (path, data) => path == '/GetWirelessInfoListV2'
              ? {'ErrorCode': 1}
              : {'ErrorCode': 0, 'Data': []};
        final store = MemoryV1OnlyStore();
        final service = _service(factory, store: store);
        service.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));
        service.getWirelessSettings();
        async.elapse(const Duration(seconds: 1));
        expect(store.meshIds, isEmpty);
      });
    });

    test('telemetry waits for slow but valid router replies', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory();
        final service = _service(factory);
        service.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));
        Map<String, dynamic>? reply;
        service.getSystemConnectionInfo().then((r) => reply = r);
        async.elapse(const Duration(milliseconds: 4800));
        factory.last.deliver(
          '$_appId/GetSysConnectInfo',
          '{"ErrorCode":0,"Data":{"Internet":1}}',
        );
        async.flushMicrotasks();
        expect(reply?['ErrorCode'], 0);
      });
    });

    test('two app instances keep separate client identities and replies', () {
      fakeAsync((async) {
        final foldFactory = FakeTransportFactory();
        final onePlusFactory = FakeTransportFactory();
        final fold = _service(foldFactory, appId: 'fold4id');
        final onePlus = _service(onePlusFactory, appId: 'oneplusid');
        fold.connect('mesh1', '10.0.0.1');
        onePlus.connect('mesh1', '10.0.0.1');
        async.elapse(const Duration(milliseconds: 1));

        final a = foldFactory.last, b = onePlusFactory.last;
        expect(a.clientId, 'fold4id');
        expect(b.clientId, 'oneplusid');
        expect(a.username, b.username); // same router credentials
        expect(a.subscriptions, ['fold4id/+']);
        expect(b.subscriptions, ['oneplusid/+']);

        Map<String, dynamic>? foldReply, onePlusReply;
        fold.getSystemConnectionInfo().then((r) => foldReply = r);
        onePlus.getSystemConnectionInfo().then((r) => onePlusReply = r);
        async.elapse(const Duration(milliseconds: 10));
        expect(a.published.single.topic, 'mesh1/fold4id/GetSysConnectInfo');
        expect(b.published.single.topic, 'mesh1/oneplusid/GetSysConnectInfo');

        // A reply for one phone never completes the other phone's request.
        a.deliver('fold4id/GetSysConnectInfo', '{"ErrorCode":0,"Data":{}}');
        async.flushMicrotasks();
        expect(foldReply, isNotNull);
        expect(onePlusReply, isNull);
        b.deliver('oneplusid/GetSysConnectInfo', '{"ErrorCode":0,"Data":{}}');
        async.flushMicrotasks();
        expect(onePlusReply, isNotNull);
        expect(fold.isConnected && onePlus.isConnected, isTrue);
      });
    });

    test(
      'requests while disconnected return null without publishing',
      () async {
        final factory = FakeTransportFactory();
        final service = _service(factory);
        expect(await service.getSystemStatus(), isNull);
        expect(factory.created, isEmpty);
      },
    );
  });
}
