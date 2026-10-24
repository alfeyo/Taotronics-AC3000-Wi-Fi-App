import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_info.dart';
import '../providers/router_provider.dart';
import '../services/network_probe.dart';
import '../services/router_certificate_verifier.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

class DiagnosticsScreen extends StatefulWidget {
  final String? wifiName;
  final String? wifiIP;
  final String? gatewayIP;
  final bool routerReachable;
  final bool mqttPortOpen;

  const DiagnosticsScreen({
    super.key,
    this.wifiName,
    this.wifiIP,
    this.gatewayIP,
    this.routerReachable = false,
    this.mqttPortOpen = false,
  });

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _mqttPort = 25678;
  static const _defaultGateway = '192.168.10.1';

  final List<DiagnosticEntry> _diagnosticLog = [];
  final NetworkInfo _networkInfo = NetworkInfo();
  final NetworkProbe _probe = NetworkProbe();
  bool _isRunning = false;
  bool _isExporting = false;

  String? _wifiName;
  String? _wifiIP;
  String? _gatewayIP;
  bool _routerReachable = false;
  bool _mqttPortOpen = false;
  bool _mqttAuthenticated = false;
  String? _lastError;
  Duration? _gatewayLatency;
  Duration? _routerResponse;
  DateTime? _lastRun;

  @override
  void initState() {
    super.initState();
    _wifiName = widget.wifiName;
    _wifiIP = widget.wifiIP;
    _gatewayIP = widget.gatewayIP;
    _routerReachable = widget.routerReachable;
    _mqttPortOpen = widget.mqttPortOpen;
    _addInitialEntries();
    // Fill the phone's Wi-Fi details right away when the caller had none.
    if (_wifiIP == null || _gatewayIP == null) _getNetworkInfo();
  }

  void _addInitialEntries() {
    _addEntry(DiagnosticType.info, 'Diagnostics initialized');
    _addProviderState();
  }

  void _addProviderState() {
    final provider = context.read<RouterProvider>();
    _mqttAuthenticated = provider.isConnected;
    _addEntry(
      DiagnosticType.info,
      'Provider status: ${provider.statusSummary}',
    );
    _addEntry(
      DiagnosticType.network,
      'Discovery: ${provider.discoveryState.name}',
    );
    _addEntry(DiagnosticType.network, 'Network: ${provider.networkState.name}');
    _addEntry(
      DiagnosticType.network,
      'MQTT Port: ${provider.mqttPortState.name}',
    );
    _addEntry(DiagnosticType.network, 'Auth: ${provider.authState.name}');
    _addTlsEntry(provider);

    if (provider.errorMessage != null) {
      _addEntry(DiagnosticType.error, 'Last error: ${provider.errorMessage}');
      _lastError = provider.errorMessage;
    }
  }

  void _addEntry(DiagnosticType type, String message) {
    if (!mounted) return;
    setState(() {
      _diagnosticLog.add(
        DiagnosticEntry(
          type: type,
          message: message,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  Future<void> _runFullDiagnostics() async {
    setState(() {
      _isRunning = true;
      _diagnosticLog.clear();
      _lastError = null;
    });

    _addEntry(DiagnosticType.info, 'Starting full diagnostics...');

    final policy = context.read<RouterProvider>().accessPolicy;
    await _getNetworkInfo();
    await _checkNetworkInterfaces();
    if (policy.mayProbe) {
      await _checkGatewayConnectivity();
      await _checkMqttPort();
      await _checkDiscoveryPort();
    } else {
      _addEntry(
        DiagnosticType.info,
        'Router reachability and port probes are handled by Network Hub; '
        'this phone did not touch the router.',
      );
    }
    await _measureRouterResponse();
    _checkRouterProvider();

    _addEntry(DiagnosticType.info, 'Diagnostics complete');
    if (mounted) {
      setState(() {
        _isRunning = false;
        _lastRun = DateTime.now();
      });
    }
  }

  Future<void> _getNetworkInfo() async {
    _addEntry(DiagnosticType.info, 'Getting network info...');
    try {
      final name = await _networkInfo.getWifiName();
      final ip = await _networkInfo.getWifiIP();
      final gateway = await _networkInfo.getWifiGatewayIP();
      if (!mounted) return;
      setState(() {
        _wifiName = name;
        _wifiIP = ip;
        _gatewayIP = gateway ?? _defaultGateway;
      });

      _addEntry(DiagnosticType.network, 'WiFi SSID: ${_wifiName ?? "Unknown"}');
      _addEntry(DiagnosticType.network, 'Device IP: ${_wifiIP ?? "Unknown"}');
      _addEntry(
        DiagnosticType.network,
        'Gateway IP: ${_gatewayIP ?? "Unknown"}',
      );
    } catch (e) {
      _addEntry(DiagnosticType.warning, 'Network info error: $e');
      _gatewayIP = _defaultGateway;
    }
  }

  Future<void> _checkNetworkInterfaces() async {
    _addEntry(DiagnosticType.info, 'Checking network interfaces...');

    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            _addEntry(
              DiagnosticType.network,
              '${interface.name}: ${addr.address}',
            );
          }
        }
      }
    } catch (e) {
      _addEntry(DiagnosticType.error, 'Failed to list interfaces: $e');
    }
  }

  Future<void> _checkGatewayConnectivity() async {
    final gateway = _gatewayIP ?? _defaultGateway;
    _addEntry(
      DiagnosticType.info,
      'Testing gateway connectivity ($gateway)...',
    );

    var reachable = false;
    for (final port in const [80, 443]) {
      final outcome = await _probe.probe(
        gateway,
        port,
        timeout: const Duration(seconds: 5),
      );
      final ok =
          outcome == ProbeOutcome.open || outcome == ProbeOutcome.refused;
      reachable |= ok;
      _addEntry(
        ok ? DiagnosticType.success : DiagnosticType.warning,
        'TCP $port: ${switch (outcome) {
          ProbeOutcome.open => 'open',
          ProbeOutcome.refused => 'closed (host answered)',
          ProbeOutcome.timeout => 'no answer (timeout)',
          ProbeOutcome.error => 'unreachable',
        }}',
      );
    }

    final latency = await _probe.handshakeTime(gateway, _mqttPort);
    if (!mounted) return;
    setState(() {
      _routerReachable = reachable || latency != null;
      _gatewayLatency = latency;
    });
    _addEntry(
      latency == null ? DiagnosticType.warning : DiagnosticType.success,
      latency == null
          ? 'Gateway latency: no answer'
          : 'Gateway latency (TCP handshake): ${latency.inMilliseconds} ms',
    );
  }

  Future<void> _checkMqttPort() async {
    final gateway = _gatewayIP ?? _defaultGateway;
    _addEntry(DiagnosticType.info, 'Testing MQTT port ($_mqttPort)...');

    final outcome = await _probe.probe(
      gateway,
      _mqttPort,
      timeout: const Duration(seconds: 5),
    );
    final open = outcome == ProbeOutcome.open;
    if (mounted) setState(() => _mqttPortOpen = open);
    if (open) {
      _addEntry(DiagnosticType.success, 'MQTT port ($_mqttPort): Open');
    } else {
      _addEntry(
        DiagnosticType.error,
        'MQTT port ($_mqttPort): ${outcome.name}',
      );
      _lastError = 'MQTT port closed or filtered';
    }
  }

  Future<void> _checkDiscoveryPort() async {
    _addEntry(DiagnosticType.info, 'Checking discovery port (52011)...');

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.close();
      _addEntry(DiagnosticType.success, 'UDP sockets: Available');
    } catch (e) {
      _addEntry(DiagnosticType.warning, 'UDP sockets: $e');
    }
  }

  Future<void> _measureRouterResponse() async {
    final provider = context.read<RouterProvider>();
    if (!provider.accessPolicy.mayRefresh) {
      _addEntry(
        DiagnosticType.info,
        'Router response time is not measured while Network Hub controls the '
        'router.',
      );
      return;
    }
    if (!provider.isConnected) {
      _addEntry(DiagnosticType.info, 'Router response time: not connected');
      return;
    }
    final elapsed = await provider.measureRouterResponse();
    if (!mounted) return;
    setState(() => _routerResponse = elapsed);
    _addEntry(
      elapsed == null ? DiagnosticType.warning : DiagnosticType.success,
      elapsed == null
          ? 'Router response time: no answer within 4 s'
          : 'Router response time (MQTT round trip): ${elapsed.inMilliseconds} ms',
    );
  }

  void _checkRouterProvider() {
    if (!mounted) return;
    _addEntry(DiagnosticType.info, 'Checking router provider state...');

    final provider = context.read<RouterProvider>();
    _mqttAuthenticated = provider.isConnected;
    _addEntry(
      DiagnosticType.network,
      'Discovered routers: ${provider.routers.length}',
    );

    for (final router in provider.routers) {
      _addEntry(
        DiagnosticType.info,
        'Router: ${router.meshId} @ ${router.ipAddress}',
      );
    }

    _addEntry(
      provider.isConnected ? DiagnosticType.success : DiagnosticType.warning,
      'MQTT connected: ${provider.isConnected}',
    );

    if (provider.currentRouter != null) {
      final meshId = provider.currentRouter!.meshId;
      _addEntry(DiagnosticType.info, 'Current router: $meshId');
      if (provider.authService.isPaired(meshId)) {
        final secure = provider.authService.isPasswordStoredSecurely(meshId);
        _addEntry(
          secure ? DiagnosticType.success : DiagnosticType.warning,
          secure
              ? 'Router password: Android Keystore storage'
              : 'Router password: secure storage unavailable, kept in app preferences',
        );
      }
    }
    _addTlsEntry(provider);

    if (provider.errorMessage != null) {
      _addEntry(
        DiagnosticType.error,
        'Provider error: ${provider.errorMessage}',
      );
      _lastError = provider.errorMessage;
    }

    provider.updateNetworkState(
      gatewayReachable: provider.accessPolicy.mayProbe
          ? _routerReachable
          : null,
      mqttPortOpen: provider.accessPolicy.mayProbe ? _mqttPortOpen : null,
    );
  }

  void _addTlsEntry(RouterProvider provider) {
    final verdict = provider.certificateVerdict;
    if (verdict == null) {
      _addEntry(DiagnosticType.info, 'Router TLS certificate: not checked yet');
      return;
    }
    _addEntry(
      verdict.trusted ? DiagnosticType.success : DiagnosticType.error,
      verdict.trusted
          ? 'Router TLS certificate: verified against the TaoTronics CA'
          : 'Router TLS certificate REJECTED (${verdict.name}). The device '
                'answering on the router address is not a TaoTronics router.',
    );
  }

  /// Plain-language findings derived from the measured state.
  List<_Finding> _findings(RouterProvider provider) {
    final findings = <_Finding>[];
    final gateway = _gatewayIP;
    final verdict = provider.certificateVerdict;

    if (verdict != null && !verdict.trusted) {
      findings.add(
        const _Finding(
          Tone.danger,
          'Router identity could not be verified',
          'The device at the router address presented a certificate that is '
              'not signed by TaoTronics. The app refuses to connect. Make sure '
              'you are on your own router\'s Wi-Fi.',
        ),
      );
    }
    if (gateway != null && !gateway.startsWith('192.168.10.')) {
      findings.add(
        _Finding(
          Tone.warning,
          'Phone may not be on the router\'s Wi-Fi',
          'The phone\'s gateway is $gateway; TaoTronics routers usually use '
              '192.168.10.1. Join the router Wi-Fi and run diagnostics again.',
        ),
      );
    }
    if (!_routerReachable && _lastRun != null) {
      findings.add(
        const _Finding(
          Tone.danger,
          'Router does not answer',
          'Check that the router is powered on and that the phone is '
              'connected to its Wi-Fi (not mobile data).',
        ),
      );
    } else if (_routerReachable && !_mqttPortOpen && _lastRun != null) {
      findings.add(
        const _Finding(
          Tone.warning,
          'Control port is closed',
          'The router answers but does not accept local control on port '
              '25678. It may still be starting up; wait a minute and retry.',
        ),
      );
    }
    if (provider.isConnected &&
        provider.hasInternetStatus &&
        !provider.internetConnected) {
      findings.add(
        const _Finding(
          Tone.danger,
          'Router reports no internet',
          'Check the cable between the modem and the router\'s WAN port, '
              'restart the modem, then review Internet (WAN & DNS) settings.',
        ),
      );
    }
    if (provider.isConnected && !provider.liveTelemetrySupported) {
      findings.add(
        const _Finding(
          Tone.info,
          'Live statistics are slow to answer',
          'The router missed several telemetry requests in a row, so live '
              'rates use connected-device totals until it answers again.',
        ),
      );
    }
    final slow = _routerResponse;
    if (slow != null && slow > const Duration(seconds: 2)) {
      findings.add(
        _Finding(
          Tone.info,
          'Router is responding slowly',
          'A status request took ${slow.inMilliseconds} ms. Heavy traffic '
              'or a busy router can cause this; settings may take longer to apply.',
        ),
      );
    }
    if (findings.isEmpty && _lastRun != null) {
      findings.add(
        const _Finding(
          Tone.success,
          'No problems found',
          'The router is reachable, verified and answering.',
        ),
      );
    }
    return findings;
  }

  Future<void> _exportDiagnostics() async {
    setState(() => _isExporting = true);

    try {
      final provider = context.read<RouterProvider>();
      final prefs = await SharedPreferences.getInstance();

      final exportData = {
        'exportedAt': DateTime.now().toIso8601String(),
        'appVersion': AppInfo.version,
        'network': {
          'wifiName': _wifiName,
          'wifiIP': _wifiIP,
          'gatewayIP': _gatewayIP,
          'gatewayReachable': _routerReachable,
          'mqttPort': _mqttPort,
          'mqttPortOpen': _mqttPortOpen,
          'gatewayLatencyMs': _gatewayLatency?.inMilliseconds,
          'routerResponseMs': _routerResponse?.inMilliseconds,
        },
        'routerProvider': {
          'discoveryState': provider.discoveryState.name,
          'networkState': provider.networkState.name,
          'mqttPortState': provider.mqttPortState.name,
          'authenticationState': provider.authState.name,
          'statusSummary': provider.statusSummary,
          'isConnected': provider.isConnected,
          'discoveredRouters': provider.routers.map((r) => r.toJson()).toList(),
          'currentRouter': provider.currentRouter?.toJson(),
          'deviceCount': provider.devices.length,
          'nodeCount': provider.nodes.length,
          'lastError': provider.errorMessage,
          'tlsCertificate': provider.certificateVerdict?.name,
          'liveTelemetrySupported': provider.liveTelemetrySupported,
          'pendingChanges': provider.pendingChanges
              .map((c) => {'label': c.label, 'status': c.status.name})
              .toList(),
        },
        'diagnosticSummary': {
          'successCount': _diagnosticLog
              .where((e) => e.type == DiagnosticType.success)
              .length,
          'warningCount': _diagnosticLog
              .where((e) => e.type == DiagnosticType.warning)
              .length,
          'errorCount': _diagnosticLog
              .where((e) => e.type == DiagnosticType.error)
              .length,
          'lastError': _lastError,
        },
        'diagnosticLog': _diagnosticLog
            .map(
              (e) => {
                'type': e.type.name,
                'message': e.message,
                'timestamp': e.timestamp.toIso8601String(),
              },
            )
            .toList(),
        'pairedRouters': provider.authService.pairedRouters
            .map((r) => r.toDiagnosticsJson())
            .toList(),
        'savedPreferences': prefs.getKeys().toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      await Clipboard.setData(ClipboardData(text: jsonString));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Diagnostics copied to clipboard (passwords excluded)',
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _showExportPreview(jsonString),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }

    if (mounted) setState(() => _isExporting = false);
  }

  void _showExportPreview(String json) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          children: [
            Text(
              'Exported JSON',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Space.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: SelectableText(
                  json,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final findings = _findings(provider);
    int count(DiagnosticType type) =>
        _diagnosticLog.where((e) => e.type == type).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy report to clipboard',
            onPressed: _isExporting ? null : _exportDiagnostics,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 96),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusOverview(provider),
                if (findings.isNotEmpty) ...[
                  const SectionLabel('What we found'),
                  for (final f in findings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: InfoBanner(
                        tone: f.tone,
                        icon: switch (f.tone) {
                          Tone.success => Icons.check_circle_rounded,
                          Tone.danger => Icons.error_rounded,
                          Tone.warning => Icons.warning_amber_rounded,
                          _ => Icons.info_outline_rounded,
                        },
                        title: f.title,
                        message: f.advice,
                      ),
                    ),
                ] else if (_lastRun == null)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.md),
                    child: InfoBanner(
                      tone: Tone.info,
                      title: 'Run diagnostics for a full check',
                      message:
                          'Measures gateway latency and router response time '
                          'and checks every connection step.',
                    ),
                  ),
                if (_lastError != null) ...[
                  const SizedBox(height: Space.sm),
                  InfoBanner(
                    tone: Tone.danger,
                    icon: Icons.error_outline_rounded,
                    title: 'Last error',
                    message: _lastError,
                    onDismiss: () => setState(() => _lastError = null),
                  ),
                ],
                SectionLabel(
                  'Log',
                  trailing: Wrap(
                    spacing: Space.xs,
                    children: [
                      StatusPill(
                        label: '${count(DiagnosticType.success)}',
                        tone: Tone.success,
                        icon: Icons.check_circle_rounded,
                      ),
                      StatusPill(
                        label: '${count(DiagnosticType.warning)}',
                        tone: Tone.warning,
                        icon: Icons.warning_rounded,
                      ),
                      StatusPill(
                        label: '${count(DiagnosticType.error)}',
                        tone: Tone.danger,
                        icon: Icons.error_rounded,
                      ),
                    ],
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      for (final entry in _diagnosticLog) _buildLogEntry(entry),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isRunning ? null : _runFullDiagnostics,
        icon: _isRunning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : const Icon(Icons.play_arrow_rounded),
        label: Text(_isRunning ? 'Running...' : 'Run diagnostics'),
      ),
    );
  }

  Widget _buildStatusOverview(RouterProvider provider) {
    final verdict = provider.certificateVerdict;
    final tiles = <(IconData, String, String, Tone)>[
      (
        Icons.wifi_rounded,
        'Phone Wi-Fi',
        (_wifiName ?? 'Unknown').replaceAll('"', ''),
        Tone.neutral,
      ),
      (
        Icons.phone_android_rounded,
        'Phone IP',
        _wifiIP ?? 'Unknown',
        Tone.neutral,
      ),
      (
        Icons.router_rounded,
        'Gateway',
        _gatewayIP ?? 'Unknown',
        _routerReachable ? Tone.success : Tone.warning,
      ),
      (
        Icons.timer_outlined,
        'Gateway latency',
        _gatewayLatency == null
            ? 'Not measured'
            : '${_gatewayLatency!.inMilliseconds} ms',
        Tone.info,
      ),
      (
        Icons.swap_horiz_rounded,
        'Control port',
        _mqttPortOpen ? 'Open' : 'Closed / unknown',
        _mqttPortOpen ? Tone.success : Tone.warning,
      ),
      (
        Icons.verified_user_outlined,
        'Signed in',
        _mqttAuthenticated || provider.isConnected ? 'Yes' : 'No',
        provider.isConnected ? Tone.success : Tone.warning,
      ),
      (
        Icons.shield_outlined,
        'Certificate',
        verdict == null
            ? 'Not checked'
            : verdict.trusted
            ? 'Verified'
            : 'Rejected',
        verdict == null
            ? Tone.neutral
            : verdict.trusted
            ? Tone.success
            : Tone.danger,
      ),
      (
        Icons.speed_rounded,
        'Router response',
        _routerResponse == null
            ? 'Not measured'
            : '${_routerResponse!.inMilliseconds} ms',
        Tone.info,
      ),
    ];

    final master = provider.nodes.where((n) => n.isMaster).firstOrNull;
    return SectionCard(
      title: 'Connection status',
      subtitle: _lastRun == null
          ? 'Quick view; run diagnostics to measure'
          : 'Measured ${formatAge(_lastRun)}',
      icon: Icons.network_check_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveGrid(
            minTileWidth: 124,
            spacing: Space.sm,
            children: [
              for (final (icon, label, value, tone) in tiles)
                _statusTile(icon, label, value, tone),
            ],
          ),
          if (provider.isConnected) ...[
            const SizedBox(height: Space.md),
            Text(
              [
                'Router Wi-Fi: ${provider.allSsids.isEmpty ? 'unknown' : provider.allSsids.toSet().join(', ')}',
                if (master != null && master.uptimeSeconds > 0)
                  'Main node up ${formatUptime(master.uptimeSeconds)}',
                'Live data ${formatAge(provider.liveDataUpdatedAt)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusTile(IconData icon, String label, String value, Tone tone) {
    final theme = Theme.of(context);
    final colors = context.tone(tone);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.container.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.foreground),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(DiagnosticEntry entry) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(entry.type.icon, color: entry.type.color, size: 20),
      title: Text(entry.message, style: theme.textTheme.bodyMedium),
      subtitle: Text(_formatTime(entry.timestamp)),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

class _Finding {
  const _Finding(this.tone, this.title, this.advice);

  final Tone tone;
  final String title;
  final String advice;
}

class DiagnosticEntry {
  final DiagnosticType type;
  final String message;
  final DateTime timestamp;

  DiagnosticEntry({
    required this.type,
    required this.message,
    required this.timestamp,
  });
}

enum DiagnosticType {
  info(Icons.info_outline_rounded, Color(0xff3b82f6)),
  success(Icons.check_circle_outline_rounded, Color(0xff10b981)),
  warning(Icons.warning_amber_rounded, Color(0xfff59e0b)),
  error(Icons.error_outline_rounded, Color(0xffef4444)),
  network(Icons.lan_rounded, Color(0xff6366f1));

  final IconData icon;
  final Color color;
  const DiagnosticType(this.icon, this.color);
}
