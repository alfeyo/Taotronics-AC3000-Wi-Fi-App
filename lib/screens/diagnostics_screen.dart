import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/router_provider.dart';
import '../widgets/ui_components.dart';

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
  final List<DiagnosticEntry> _diagnosticLog = [];
  final NetworkInfo _networkInfo = NetworkInfo();
  bool _isRunning = false;
  bool _isExporting = false;

  String? _wifiName;
  String? _wifiIP;
  String? _gatewayIP;
  bool _routerReachable = false;
  bool _mqttPortOpen = false;
  bool _mqttAuthenticated = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _wifiName = widget.wifiName;
    _wifiIP = widget.wifiIP;
    _gatewayIP = widget.gatewayIP;
    _routerReachable = widget.routerReachable;
    _mqttPortOpen = widget.mqttPortOpen;
    _addInitialEntries();
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

    if (provider.errorMessage != null) {
      _addEntry(DiagnosticType.error, 'Last error: ${provider.errorMessage}');
      _lastError = provider.errorMessage;
    }
  }

  void _addEntry(DiagnosticType type, String message) {
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
    setState(() => _isRunning = true);
    _diagnosticLog.clear();
    _lastError = null;

    _addEntry(DiagnosticType.info, 'Starting full diagnostics...');

    await _getNetworkInfo();
    await _checkNetworkInterfaces();
    await _checkGatewayConnectivity();
    await _checkMqttPort();
    await _checkDiscoveryPort();
    _checkRouterProvider();

    _addEntry(DiagnosticType.info, 'Diagnostics complete');
    setState(() => _isRunning = false);
  }

  Future<void> _getNetworkInfo() async {
    _addEntry(DiagnosticType.info, 'Getting network info...');
    try {
      _wifiName = await _networkInfo.getWifiName();
      _wifiIP = await _networkInfo.getWifiIP();
      _gatewayIP = await _networkInfo.getWifiGatewayIP() ?? '192.168.10.1';

      _addEntry(DiagnosticType.network, 'WiFi SSID: ${_wifiName ?? "Unknown"}');
      _addEntry(DiagnosticType.network, 'Device IP: ${_wifiIP ?? "Unknown"}');
      _addEntry(
        DiagnosticType.network,
        'Gateway IP: ${_gatewayIP ?? "Unknown"}',
      );
    } catch (e) {
      _addEntry(DiagnosticType.warning, 'Network info error: $e');
      _gatewayIP = '192.168.10.1';
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
    final gateway = _gatewayIP ?? '192.168.10.1';
    _addEntry(
      DiagnosticType.info,
      'Testing gateway connectivity ($gateway)...',
    );

    try {
      final socket = await Socket.connect(
        gateway,
        80,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      _addEntry(DiagnosticType.success, 'HTTP port (80): Open');
      _routerReachable = true;
    } catch (e) {
      _addEntry(DiagnosticType.warning, 'HTTP port (80): Closed/Timeout');
    }

    try {
      final socket = await Socket.connect(
        gateway,
        443,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      _addEntry(DiagnosticType.success, 'HTTPS port (443): Open');
      _routerReachable = true;
    } catch (e) {
      _addEntry(DiagnosticType.warning, 'HTTPS port (443): Closed/Timeout');
    }
  }

  Future<void> _checkMqttPort() async {
    final gateway = _gatewayIP ?? '192.168.10.1';
    _addEntry(DiagnosticType.info, 'Testing MQTT port (25678)...');

    try {
      final socket = await Socket.connect(
        gateway,
        25678,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      _addEntry(DiagnosticType.success, 'MQTT port (25678): Open');
      _mqttPortOpen = true;
    } catch (e) {
      _addEntry(DiagnosticType.error, 'MQTT port (25678): $e');
      _mqttPortOpen = false;
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

  void _checkRouterProvider() {
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
      _addEntry(
        DiagnosticType.info,
        'Current router: ${provider.currentRouter!.meshId}',
      );
    }

    if (provider.errorMessage != null) {
      _addEntry(
        DiagnosticType.error,
        'Provider error: ${provider.errorMessage}',
      );
      _lastError = provider.errorMessage;
    }

    provider.updateNetworkState(
      gatewayReachable: _routerReachable,
      mqttPortOpen: _mqttPortOpen,
    );
  }

  Future<void> _exportDiagnostics() async {
    setState(() => _isExporting = true);

    try {
      final provider = context.read<RouterProvider>();
      final prefs = await SharedPreferences.getInstance();

      final exportData = {
        'exportedAt': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0',
        'network': {
          'wifiName': _wifiName,
          'wifiIP': _wifiIP,
          'gatewayIP': _gatewayIP,
          'gatewayReachable': _routerReachable,
          'mqttPort': 25678,
          'mqttPortOpen': _mqttPortOpen,
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
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('Diagnostics copied to clipboard'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () => _showExportPreview(jsonString),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }

    setState(() => _isExporting = false);
  }

  void _showExportPreview(String json) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.code_rounded,
                        color: AppColors.brand,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Exported JSON',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xfff8f9fa),
                      borderRadius: BorderRadius.circular(10),
                    ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final successCount = _diagnosticLog
        .where((e) => e.type == DiagnosticType.success)
        .length;
    final warningCount = _diagnosticLog
        .where((e) => e.type == DiagnosticType.warning)
        .length;
    final errorCount = _diagnosticLog
        .where((e) => e.type == DiagnosticType.error)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xfff7f7fa),
      appBar: AppBar(
        title: const Text('Diagnostics'),
        backgroundColor: const Color(0xffc14524),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy to clipboard',
            onPressed: _isExporting ? null : _exportDiagnostics,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Run diagnostics',
            onPressed: _isRunning ? null : _runFullDiagnostics,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusOverview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _buildCountChip(
                  Icons.check_circle_rounded,
                  successCount,
                  AppColors.success,
                ),
                const SizedBox(width: 8),
                _buildCountChip(
                  Icons.warning_rounded,
                  warningCount,
                  AppColors.warning,
                ),
                const SizedBox(width: 8),
                _buildCountChip(
                  Icons.error_rounded,
                  errorCount,
                  AppColors.error,
                ),
                const Spacer(),
                Text(
                  '${_diagnosticLog.length} entries',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorCard(
                title: 'Last Error',
                message: _lastError,
                onDismiss: () => setState(() => _lastError = null),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _diagnosticLog.length,
              itemBuilder: (context, index) {
                final entry = _diagnosticLog[index];
                return _buildLogEntry(entry);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isRunning ? null : _runFullDiagnostics,
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: _isRunning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.play_arrow_rounded),
        label: Text(_isRunning ? 'Running...' : 'Run Diagnostics'),
      ),
    );
  }

  Widget _buildStatusOverview() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.network_check_rounded,
                  color: AppColors.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Network Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatusTile(
                  'Wi-Fi',
                  _wifiName ?? 'Unknown',
                  Icons.wifi_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatusTile(
                  'Device IP',
                  _wifiIP ?? 'Unknown',
                  Icons.phone_android_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatusTile(
                  'Gateway',
                  _gatewayIP ?? 'Unknown',
                  Icons.router_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatusIndicator(
                  'Gateway Reachable',
                  _routerReachable,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatusIndicator('MQTT Port', _mqttPortOpen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatusIndicator('MQTT Auth', _mqttAuthenticated),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRouterWifiSection(),
        ],
      ),
    );
  }

  Widget _buildRouterWifiSection() {
    final provider = context.read<RouterProvider>();
    final routerSsid = provider.currentWifiName;
    final allSsids = provider.allSsids;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfff0f7ff),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffdbeafe)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.router_rounded,
                size: 16,
                color: Color(0xff3b82f6),
              ),
              const SizedBox(width: 8),
              const Text(
                'Router Wi-Fi',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff3b82f6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Primary SSID',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      routerSsid,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (allSsids.length > 1) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All SSIDs',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        allSsids.join(', '),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfff7f7fa),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool ok) {
    final color = ok ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  ok ? 'OK' : 'Failed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountChip(IconData icon, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(DiagnosticEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: entry.type.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(entry.type.icon, color: entry.type.color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(entry.timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
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
