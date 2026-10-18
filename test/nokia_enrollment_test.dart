import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tt_router_flutter/providers/nokia_provider.dart';
import 'package:tt_router_flutter/screens/nokia_mesh_screen.dart';
import 'package:tt_router_flutter/services/nokia_service.dart';
import 'nokia_service_test.dart' show Transport, Scanner;

class EnrollmentTransport extends Transport {
  int meshReads = 0;
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic>? meshResponse;
  bool loseWriteReply = false;
  @override
  Future<Map<String, dynamic>> request(
    Uri base,
    String path, {
    Map<String, String>? form,
    String? cookie,
    String? responseKey,
    String? responseIv,
  }) async {
    if (path == '/mesh_status_web_app.cgi') {
      meshReads++;
      if (pending != null) return pending!.future;
      if (meshResponse != null) return meshResponse!;
    }
    if (path == '/mesh_web_app.cgi?add' && loseWriteReply) {
      writes.add(path);
      throw const NokiaException('Reply lost');
    }
    return super.request(
      base,
      path,
      form: form,
      cookie: cookie,
      responseKey: responseKey,
      responseIv: responseIv,
    );
  }
}

Future<NokiaProvider> controller(EnrollmentTransport t) async {
  t.web = true;
  t.mode = 'AP_BRIDGE';
  final n = NokiaProvider(
    service: NokiaService(transport: t),
    scanner: Scanner(),
  );
  await n.service.select(Uri.parse('http://192.168.10.97'));
  await n.service.login('owner', 'fixture-only');
  n.mode = 'AP_BRIDGE';
  n.observedAt = DateTime.now();
  return n;
}

void main() {
  testWidgets(
    'observation preserves feedback and serializes a foreground operation',
    (tester) async {
      final t = EnrollmentTransport();
      final n = await controller(t);
      addTearDown(n.dispose);
      n.message = 'Previous request acknowledged';
      n.error = 'Previous diagnostic warning';
      t.pending = Completer();
      n.observeExtender('ALCL12345678');
      await tester.pump();
      expect(n.message, 'Previous request acknowledged');
      expect(n.error, 'Previous diagnostic warning');
      expect(n.busy, isFalse);
      var foregroundRan = false;
      final operation = n.run(() async {
        foregroundRan = true;
      });
      await tester.pump();
      expect(foregroundRan, isFalse);
      t.pending!.complete({'beacon_detail': []});
      await tester.pump();
      await operation;
      expect(foregroundRan, isTrue);
      expect(n.enrollmentReading, isFalse);
      n.stopEnrollmentObservation();
    },
  );
  testWidgets(
    'read-back progresses without inventing connectivity or repeating writes',
    (tester) async {
      final t = EnrollmentTransport();
      final n = await controller(t);
      addTearDown(n.dispose);
      final initialWrites = t.writes.length;
      n.observeExtender('ALCL12345678');
      await tester.pump();
      expect(n.enrollmentStatus, contains('Not listed'));
      t.nodes = [
        {
          'SerialNumber': 'ALCL12345678',
          'MACAddress': 'b4:63:6f:00:11:22',
          'OnboardStatus': 'fixture-state',
          'BackhaulStatus': 'fixture-link',
        },
      ];
      await tester.pump(const Duration(seconds: 5));
      expect(n.enrollmentStatus, contains('Listed'));
      expect(n.enrollmentStatus, contains('fixture-link'));
      expect(n.clientVerified, isFalse);
      expect(n.meshCurrent, isTrue);
      expect(t.writes.length, initialWrites);
      await tester.pump(const Duration(minutes: 3));
      expect(n.watchingEnrollment, isFalse);
      expect(
        n.enrollmentStatus,
        contains('not an enrollment failure or success'),
      );
      final reads = t.meshReads;
      await tester.pump(const Duration(minutes: 1));
      expect(t.meshReads, reads);
    },
  );

  testWidgets('stopping or disposing discards a delayed report', (
    tester,
  ) async {
    for (final dispose in [false, true]) {
      final t = EnrollmentTransport();
      final n = await controller(t);
      t.pending = Completer();
      n.observeExtender('ALCL12345678');
      await tester.pump();
      expect(n.enrollmentReading, isTrue);
      expect(n.busy, isFalse);
      n.observeExtender('ALCL87654321'); // Single-flight guard.
      expect(n.enrollmentSerial, 'ALCL12345678');
      if (dispose) {
        n.dispose();
      } else {
        n.stopEnrollmentObservation();
      }
      t.pending!.complete({
        'beacon_detail': [
          {'SerialNumber': 'ALCL12345678'},
        ],
      });
      await tester.pump();
      expect(n.extenders, isNull);
      expect(n.meshObservedAt, isNull);
      await tester.pump(const Duration(minutes: 4));
      expect(t.meshReads, 1);
      if (!dispose) n.dispose();
    }
  });

  testWidgets(
    'identity change and unavailable schema stop observation without guessed empty inventory',
    (tester) async {
      for (final changedRoot in [false, true]) {
        final t = EnrollmentTransport();
        final n = await controller(t);
        if (changedRoot) {
          t.serial = 'OTHER';
        } else {
          t.meshResponse = {'result': 0};
        }
        n.observeExtender('ALCL12345678');
        await tester.pump();
        expect(n.watchingEnrollment, isFalse);
        expect(n.enrollmentStatus, contains('read-back unavailable'));
        expect(n.meshCurrent, isFalse);
        expect(n.extenders, isNull);
        expect(t.meshReads, changedRoot ? 0 : 1);
        n.dispose();
      }
    },
  );

  testWidgets('lost write reply is not retried or marked successful', (
    tester,
  ) async {
    final t = EnrollmentTransport()..loseWriteReply = true;
    final n = await controller(t);
    addTearDown(n.dispose);
    n.clientVerifiedAt = DateTime.now();
    await n.changeExtender('ALCL12345678');
    expect(t.writes.where((p) => p == '/mesh_web_app.cgi?add').length, 1);
    expect(n.enrollmentStatus, contains('Request not confirmed'));
    expect(n.error, isNotNull);
    expect(n.watchingEnrollment, isFalse);
    await tester.pump(const Duration(minutes: 4));
    expect(t.writes.where((p) => p == '/mesh_web_app.cgi?add').length, 1);
  });

  testWidgets(
    'UI shows reported progress and pauses observation on backgrounding',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final t = EnrollmentTransport()
        ..nodes = [
          {
            'SerialNumber': 'ALCL12345678',
            'MACAddress': 'b4:63:6f:00:11:22',
            'IPAddress': '192.168.10.98',
          },
        ];
      final n = await controller(t);
      await tester.pumpWidget(
        MaterialApp(home: NokiaMeshScreen(controller: n)),
      );
      n.observeExtender('ALCL12345678');
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Not supplied by this WebGUI schema'), findsOneWidget);
      expect(find.text('Not verified by root inventory'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(n.watchingEnrollment, isFalse);
      expect(n.meshCurrent, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      n.dispose();
    },
  );
}
