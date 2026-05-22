import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/router_provider.dart';
import 'home_screen.dart';
import 'setup_wizard_screen.dart';
import 'diagnostics_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final NetworkInfo _networkInfo = NetworkInfo();

  String? _wifiName;
  String? _wifiIP;
  String? _gatewayIP;
  bool _isScanning = true;
  bool _routerReachable = false;
  bool _mqttPortOpen = false;
  String? _errorMessage;

  static const String _defaultGateway = '192.168.10.1';
  static const int _mqttPort = 25678;

  Future<void> _confirmExit() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave app?'),
        content: const Text('Do you want to leave TT Router now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (shouldLeave == true) {
      SystemNavigator.pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _routerReachable = false;
      _mqttPortOpen = false;
    });

    await _requestPermissions();
    await _getNetworkInfo();
    await _checkRouterReachability();
    await _checkMqttPort();

    if (!mounted) return;
    context.read<RouterProvider>().updateNetworkState(
      gatewayReachable: _routerReachable,
      mqttPortOpen: _mqttPortOpen,
    );
    setState(() => _isScanning = false);
  }

  Future<void> _requestPermissions() async {
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      setState(
        () => _errorMessage = 'Location permission required for WiFi info',
      );
    }
  }

  Future<void> _getNetworkInfo() async {
    try {
      _wifiName = await _networkInfo.getWifiName();
      _wifiIP = await _networkInfo.getWifiIP();
      _gatewayIP = await _networkInfo.getWifiGatewayIP() ?? _defaultGateway;
      setState(() {});
    } catch (e) {
      setState(() {
        _gatewayIP = _defaultGateway;
      });
    }
  }

  Future<void> _checkRouterReachability() async {
    if (_gatewayIP == null) return;

    try {
      final socket = await Socket.connect(
        _gatewayIP!,
        80,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      setState(() => _routerReachable = true);
    } catch (_) {
      try {
        final result = await InternetAddress.lookup(_gatewayIP!);
        setState(() => _routerReachable = result.isNotEmpty);
      } catch (_) {
        setState(() => _routerReachable = false);
      }
    }
  }

  Future<void> _checkMqttPort() async {
    if (_gatewayIP == null) return;

    try {
      final socket = await Socket.connect(
        _gatewayIP!,
        _mqttPort,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      setState(() => _mqttPortOpen = true);
    } catch (_) {
      setState(() => _mqttPortOpen = false);
    }
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _navigateToPairing() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
    );
  }

  void _navigateToDiagnostics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiagnosticsScreen(
          wifiName: _wifiName,
          wifiIP: _wifiIP,
          gatewayIP: _gatewayIP,
          routerReachable: _routerReachable,
          mqttPortOpen: _mqttPortOpen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Consumer<RouterProvider>(
          builder: (context, provider, child) {
            return RefreshIndicator(
              onRefresh: _startDiscovery,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildHeroHeader(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildStatusCard(),
                          const SizedBox(height: 14),
                          _buildNetworkCard(),
                          const SizedBox(height: 14),
                          _buildConnectionCard(provider),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            _buildErrorCard(),
                          ],
                          const SizedBox(height: 18),
                          _buildActionButtons(provider),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: const Color(0xffc14524),
      foregroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: const Text(
        'Router Discovery',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bug_report_outlined),
          tooltip: 'Diagnostics',
          onPressed: _navigateToDiagnostics,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xfff37a4d),
                    Color(0xffe85d2f),
                    Color(0xffc14524),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -50,
              top: -30,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              right: 80,
              top: 70,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              left: 20,
              bottom: 50,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _heroTitle(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _heroSubtitle(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _heroTitle() {
    if (_isScanning) return 'Looking for your router…';
    if (_routerReachable && _mqttPortOpen) return 'Router ready';
    if (_routerReachable) return 'Pairing required';
    return 'Router not reachable';
  }

  String _heroSubtitle() {
    if (_isScanning) return 'Checking gateway and MQTT port';
    if (_routerReachable && _mqttPortOpen) return 'Tap continue to open the dashboard';
    if (_routerReachable) return 'Router found, but needs authentication';
    return "Connect to the router's Wi-Fi and try again";
  }

  Widget _statusBadge() {
    Color color;
    String label;
    IconData icon;
    if (_isScanning) {
      color = Colors.blueAccent;
      label = 'Scanning';
      icon = Icons.radar_rounded;
    } else if (_routerReachable && _mqttPortOpen) {
      color = const Color(0xff10b981);
      label = 'Online';
      icon = Icons.check_circle_rounded;
    } else if (_routerReachable) {
      color = const Color(0xfff59e0b);
      label = 'Locked';
      icon = Icons.lock_outline_rounded;
    } else {
      color = const Color(0xffef4444);
      label = 'Offline';
      icon = Icons.wifi_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    Color color;
    IconData icon;
    String title;
    String body;

    if (_isScanning) {
      color = Colors.blueAccent;
      icon = Icons.radar_rounded;
      title = 'Scanning network';
      body = 'Checking gateway reachability and MQTT broker availability.';
    } else if (_routerReachable && _mqttPortOpen) {
      color = const Color(0xff10b981);
      icon = Icons.check_circle_rounded;
      title = 'Router found';
      body = 'Gateway is reachable and the MQTT broker is accepting connections.';
    } else if (_routerReachable) {
      color = const Color(0xfff59e0b);
      icon = Icons.warning_amber_rounded;
      title = 'Authentication required';
      body = 'Router responded, but the MQTT broker is locked. Pair the router to continue.';
    } else {
      color = const Color(0xffef4444);
      icon = Icons.error_outline_rounded;
      title = 'Router not reachable';
      body = "We can't reach the gateway. Make sure you're on the router's Wi-Fi.";
    }

    return _cleanCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _isScanning
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )
                : Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _statusBadge(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard() {
    return _cleanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.wifi_rounded, 'Your network'),
          const SizedBox(height: 14),
          _kvRow(Icons.network_wifi_rounded, 'Wi-Fi', _cleanSsid(_wifiName)),
          const Divider(height: 22),
          _kvRow(Icons.smartphone_rounded, 'Device IP', _wifiIP ?? '—'),
          const Divider(height: 22),
          _kvRow(Icons.router_rounded, 'Gateway', _gatewayIP ?? '—'),
        ],
      ),
    );
  }

  String _cleanSsid(String? name) {
    if (name == null || name.isEmpty) return '—';
    return name.replaceAll('"', '');
  }

  Widget _buildConnectionCard(RouterProvider provider) {
    return _cleanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.health_and_safety_rounded, 'Connection checks'),
          const SizedBox(height: 14),
          _checkRow('Gateway reachable', _routerReachable),
          const SizedBox(height: 10),
          _checkRow('MQTT port 25678', _mqttPortOpen),
          const SizedBox(height: 10),
          _checkRow(
            'Authentication',
            provider.isConnected,
            pendingLabel: 'Required',
          ),
        ],
      ),
    );
  }

  Widget _cardHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.deepOrange),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }

  Widget _kvRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _checkRow(String label, bool status, {String? pendingLabel}) {
    final color =
        status ? const Color(0xff10b981) : const Color(0xffef4444);
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            status ? Icons.check_rounded : Icons.close_rounded,
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        Text(
          status ? 'OK' : (pendingLabel ?? 'Failed'),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _cleanCard({required Widget child, Color? bg, Color? border}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildErrorCard() {
    return _cleanCard(
      bg: const Color(0xfffff1f0),
      border: const Color(0xffffd6d3),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xffd32f2f), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xff8a1f1f),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(RouterProvider provider) {
    if (_isScanning) {
      return _cleanCard(
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Scanning…',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_routerReachable && _mqttPortOpen) ...[
          _primaryButton(
            label: 'Continue to Dashboard',
            icon: Icons.arrow_forward_rounded,
            onTap: _navigateToDashboard,
          ),
        ] else if (_routerReachable) ...[
          _primaryButton(
            label: 'Pair Router',
            icon: Icons.link_rounded,
            onTap: _navigateToPairing,
          ),
          const SizedBox(height: 10),
          _secondaryButton(
            label: 'Continue in Read-Only Mode',
            icon: Icons.visibility_outlined,
            onTap: _navigateToDashboard,
          ),
        ] else ...[
          _primaryButton(
            label: 'Retry Scan',
            icon: Icons.refresh_rounded,
            onTap: _startDiscovery,
          ),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _navigateToDiagnostics,
          icon: const Icon(Icons.bug_report_outlined, size: 18),
          label: const Text('View diagnostics'),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label, style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
