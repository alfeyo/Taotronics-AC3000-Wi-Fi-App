import 'network_hub_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/router_provider.dart';
import '../services/network_probe.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
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
  final NetworkProbe _probe = NetworkProbe();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _connectivityDebounce;
  Future<void>? _scan;

  String? _wifiName;
  String? _wifiIP;
  String? _gatewayIP;
  bool _isScanning = true;
  bool _routerReachable = false;
  bool _mqttPortOpen = false;
  String? _errorMessage;
  bool _permissionBlocked = false;

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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      // Re-check after Wi-Fi changes, once the new network has settled.
      _connectivityDebounce?.cancel();
      _connectivityDebounce = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _startDiscovery();
        context.read<RouterProvider>().reconnectNow();
      });
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityDebounce?.cancel();
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  /// Runs one scan at a time; overlapping requests share the running scan.
  Future<void> _startDiscovery({bool askPermission = false}) =>
      _scan ??= _runScan(askPermission: askPermission).whenComplete(() {
        _scan = null;
      });

  Future<void> _retryDiscovery() => _startDiscovery(askPermission: true);

  Future<void> _runScan({bool askPermission = false}) async {
    _update(() {
      _isScanning = true;
      _errorMessage = null;
      _routerReachable = false;
      _mqttPortOpen = false;
    });

    await _requestPermissions(ask: askPermission);
    await _getNetworkInfo();
    await _checkRouterReachability();
    await _checkMqttPort();

    if (!mounted) return;
    context.read<RouterProvider>().updateNetworkState(
      gatewayReachable: _routerReachable,
      mqttPortOpen: _mqttPortOpen,
    );
    _update(() => _isScanning = false);
  }

  bool _permissionAsked = false;

  /// Prompts at most once per visit: scans re-run on every connectivity change,
  /// and re-requesting would keep raising the system dialog over this screen.
  /// Later scans only read the current status; Retry asks again.
  Future<void> _requestPermissions({bool ask = false}) async {
    final shouldAsk = ask || !_permissionAsked;
    _permissionAsked = true;
    final locationStatus = shouldAsk
        ? await Permission.locationWhenInUse.request()
        : await Permission.locationWhenInUse.status;
    _update(() => _permissionBlocked = locationStatus.isPermanentlyDenied);
    if (!locationStatus.isGranted) {
      _update(
        () => _errorMessage = locationStatus.isPermanentlyDenied
            ? 'Location permission is off for TT Router. The Wi-Fi name is '
                  'hidden, but router checks still run. Enable it in app settings.'
            : 'Location permission lets Android show the Wi-Fi name. Router '
                  'checks still run without it.',
      );
    }
  }

  Future<void> _getNetworkInfo() async {
    try {
      final wifiName = await _networkInfo.getWifiName();
      final wifiIP = await _networkInfo.getWifiIP();
      final gateway = await _networkInfo.getWifiGatewayIP();
      _update(() {
        _wifiName = wifiName;
        _wifiIP = wifiIP;
        _gatewayIP = gateway ?? _defaultGateway;
      });
    } catch (e) {
      _update(() => _gatewayIP = _defaultGateway);
    }
  }

  Future<void> _checkRouterReachability() async {
    final gateway = _gatewayIP;
    if (gateway == null) return;
    final reachable = await _probe.isHostReachable(
      gateway,
      ports: const [80, 443, _mqttPort],
    );
    _update(() => _routerReachable = reachable);
  }

  Future<void> _checkMqttPort() async {
    final gateway = _gatewayIP;
    if (gateway == null) return;
    final outcome = await _probe.probe(gateway, _mqttPort);
    _update(() => _mqttPortOpen = outcome == ProbeOutcome.open);
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
        appBar: AppBar(
          title: const Text('Find your router'),
          actions: [
            IconButton(
              tooltip: 'Network Hub',
              icon: const Icon(Icons.hub_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NetworkHubScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.monitor_heart_outlined),
              tooltip: 'Diagnostics',
              onPressed: _navigateToDiagnostics,
            ),
          ],
        ),
        body: Consumer<RouterProvider>(
          builder: (context, provider, child) {
            return RefreshIndicator(
              onRefresh: _retryDiscovery,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  Space.xxl,
                ),
                children: [
                  ContentWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatusCard(),
                        const SizedBox(height: Space.md),
                        _buildNetworkCard(),
                        const SizedBox(height: Space.md),
                        _buildConnectionCard(provider),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: Space.md),
                          InfoBanner(
                            tone: Tone.warning,
                            icon: Icons.location_off_outlined,
                            title: 'Location permission',
                            message: _errorMessage,
                            action: _permissionBlocked
                                ? TextButton(
                                    onPressed: openAppSettings,
                                    child: const Text('Open app settings'),
                                  )
                                : null,
                          ),
                        ],
                        const SizedBox(height: Space.xl),
                        _buildActionButtons(provider),
                      ],
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

  (String, String, Tone, IconData) get _state {
    if (_isScanning) {
      return (
        'Looking for your router…',
        'Checking the gateway and the router control port.',
        Tone.info,
        Icons.radar_rounded,
      );
    }
    if (_routerReachable && _mqttPortOpen) {
      return (
        'Router found',
        'The router is reachable and accepting local control.',
        Tone.success,
        Icons.check_circle_rounded,
      );
    }
    if (_routerReachable) {
      return (
        'Router found, control port closed',
        'The router answered but is not accepting local control yet. Pair it '
            'or wait for it to finish starting.',
        Tone.warning,
        Icons.lock_outline_rounded,
      );
    }
    return (
      'Router not reachable',
      "Connect this phone to the router's Wi-Fi and try again.",
      Tone.danger,
      Icons.wifi_off_rounded,
    );
  }

  Widget _buildStatusCard() {
    final (title, body, tone, icon) = _state;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            _isScanning
                ? SizedBox(
                    width: 52,
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: context.tone(tone).foreground,
                      ),
                    ),
                  )
                : IconBadge(icon, tone: tone, size: 52),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Space.xs),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkCard() {
    return SectionCard(
      title: 'Your network',
      icon: Icons.wifi_rounded,
      child: Column(
        children: [
          _kvRow(Icons.network_wifi_rounded, 'Wi-Fi', _cleanSsid(_wifiName)),
          const Divider(height: Space.xl),
          _kvRow(Icons.smartphone_rounded, 'Phone IP', _wifiIP ?? '—'),
          const Divider(height: Space.xl),
          _kvRow(Icons.router_rounded, 'Gateway', _gatewayIP ?? '—'),
        ],
      ),
    );
  }

  String _cleanSsid(String? name) {
    if (name == null || name.isEmpty || name == '<unknown ssid>') return '—';
    return name.replaceAll('"', '');
  }

  Widget _buildConnectionCard(RouterProvider provider) {
    return SectionCard(
      title: 'Connection checks',
      icon: Icons.health_and_safety_outlined,
      child: Column(
        children: [
          _checkRow('Router discovered', provider.isRouterFound),
          const SizedBox(height: Space.sm),
          _checkRow('Gateway reachable', _routerReachable),
          const SizedBox(height: Space.sm),
          _checkRow('Control port $_mqttPort open', _mqttPortOpen),
          const SizedBox(height: Space.sm),
          _checkRow(
            'Signed in',
            provider.isConnected,
            pendingLabel: provider.isReconnecting ? 'Connecting' : 'Required',
          ),
        ],
      ),
    );
  }

  Widget _kvRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: Space.md),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
  }

  Widget _checkRow(String label, bool status, {String? pendingLabel}) {
    final waiting = _isScanning && pendingLabel == null;
    return Row(
      children: [
        Expanded(child: Text(label)),
        StatusPill(
          label: waiting
              ? 'Checking'
              : status
              ? 'OK'
              : (pendingLabel ?? 'Failed'),
          tone: waiting
              ? Tone.neutral
              : status
              ? Tone.success
              : pendingLabel != null
              ? Tone.warning
              : Tone.danger,
          icon: waiting
              ? Icons.more_horiz_rounded
              : status
              ? Icons.check_rounded
              : Icons.close_rounded,
        ),
      ],
    );
  }

  Widget _buildActionButtons(RouterProvider provider) {
    final children = <Widget>[];
    if (_isScanning) {
      children.add(
        const FilledButton(onPressed: null, child: Text('Scanning…')),
      );
    } else if (_routerReachable && _mqttPortOpen || provider.isConnected) {
      children.add(
        FilledButton.icon(
          onPressed: _navigateToDashboard,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Continue to dashboard'),
        ),
      );
    } else if (_routerReachable) {
      children.addAll([
        FilledButton.icon(
          onPressed: _navigateToPairing,
          icon: const Icon(Icons.link_rounded),
          label: const Text('Pair router'),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: _navigateToDashboard,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Continue in read-only mode'),
        ),
      ]);
    } else {
      children.addAll([
        FilledButton.icon(
          onPressed: _retryDiscovery,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry scan'),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: _navigateToPairing,
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: const Text('Set up a new router'),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        const SizedBox(height: Space.sm),
        TextButton.icon(
          onPressed: _navigateToDiagnostics,
          icon: const Icon(Icons.monitor_heart_outlined, size: 18),
          label: const Text('View diagnostics'),
        ),
      ],
    );
  }
}
