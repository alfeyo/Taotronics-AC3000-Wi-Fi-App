import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_provisioning_service.dart';
import 'discovery_screen.dart';
import 'pairing_screen.dart';

class SetupWizardScreen extends StatefulWidget {
  final bool quickStart;

  const SetupWizardScreen({super.key, this.quickStart = true});

  const SetupWizardScreen.guide({super.key}) : quickStart = false;

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen>
    with WidgetsBindingObserver {
  static const _rooms = [
    'Living room',
    'Bedroom',
    'Dining room',
    'Washroom',
    'Bathroom',
    'Kitchen',
    "Children's room",
    'Activity room',
    'Leisure room',
    'Office',
    'Basement',
    'Attic',
  ];

  final _ble = BleProvisioningService();
  final _networkInfo = NetworkInfo();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  SetupStep _step = SetupStep.welcome;
  BleProvisioningResult? _foundRouter;
  String _room = _rooms.first;
  String? _error;
  bool _busy = false;
  bool _showWifiPassword = false;
  bool _checkingWifi = false;
  bool _wifiConnectionVerified = false;
  String? _connectedWifiName;
  String? _wifiCheckMessage;
  bool _quickSetup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _quickSetup = widget.quickStart;
    if (_quickSetup) {
      _step = SetupStep.searching;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchRouter(directSetup: true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == SetupStep.connectWifi) {
      _checkWifiConnection(autoAdvance: true);
    }
  }

  void _next(SetupStep step) {
    setState(() {
      _step = step;
      _error = null;
    });
  }

  void _back() {
    if (_quickSetup &&
        (_step == SetupStep.searching || _step == SetupStep.wifi)) {
      Navigator.pop(context);
      return;
    }

    final previous = switch (_step) {
      SetupStep.welcome => null,
      SetupStep.need => SetupStep.welcome,
      SetupStep.modem => SetupStep.need,
      SetupStep.led => SetupStep.modem,
      SetupStep.bluetooth => SetupStep.led,
      SetupStep.searching => SetupStep.bluetooth,
      SetupStep.found => SetupStep.bluetooth,
      SetupStep.room => SetupStep.found,
      SetupStep.wifi => SetupStep.room,
      SetupStep.creating => SetupStep.wifi,
      SetupStep.connectWifi => SetupStep.wifi,
      SetupStep.finish => SetupStep.connectWifi,
    };

    if (previous == null) {
      Navigator.pop(context);
    } else {
      _next(previous);
    }
  }

  Future<void> _requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _searchRouter({bool? directSetup}) async {
    final skipGuide = directSetup ?? _quickSetup;
    _next(SetupStep.searching);
    setState(() {
      _busy = true;
      _quickSetup = skipGuide;
    });
    await _requestBlePermissions();

    try {
      final router = await _ble.discover();
      if (!mounted) return;
      setState(() {
        _foundRouter = router;
        _busy = false;
        _step = skipGuide ? SetupStep.wifi : SetupStep.found;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message ?? 'Could not find a nearby TT Router.';
      });
    }
  }

  void _startGuide() {
    setState(() {
      _quickSetup = false;
      _busy = false;
      _error = null;
      _step = SetupStep.welcome;
    });
  }

  Future<void> _createWifi() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;
    if (ssid.isEmpty || password.length < 8) {
      setState(() {
        _error =
            'Enter a Wi-Fi name and a password with at least 8 characters.';
      });
      return;
    }

    _next(SetupStep.creating);
    setState(() => _busy = true);
    await _requestBlePermissions();

    try {
      final router = await _ble.provision(ssid: ssid, password: password);
      if (!mounted) return;
      setState(() {
        _foundRouter = router;
        _busy = false;
        _step = SetupStep.connectWifi;
        _wifiConnectionVerified = false;
        _connectedWifiName = null;
        _wifiCheckMessage =
            'Open Wi-Fi networks and join the SSID you just created.';
      });
      await _checkWifiConnection();
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = SetupStep.wifi;
        _error = e.message ?? 'Router setup failed over Bluetooth.';
      });
    }
  }

  Future<void> _openWifiPicker() async {
    await Permission.locationWhenInUse.request();
    try {
      await _ble.openWifiPicker();
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _wifiCheckMessage =
            e.message ?? 'Open Android Wi-Fi settings and join the new SSID.';
      });
    }
  }

  Future<void> _checkWifiConnection({bool autoAdvance = false}) async {
    if (_checkingWifi) return;

    final targetSsid = _ssidController.text.trim();
    if (targetSsid.isEmpty) return;

    setState(() {
      _checkingWifi = true;
      _wifiCheckMessage = 'Checking the phone Wi-Fi connection...';
    });

    await Permission.locationWhenInUse.request();

    try {
      final rawSsid = await _networkInfo.getWifiName();
      final connectedSsid = _normalizeSsid(rawSsid);
      final isTargetNetwork = _matchesRouterSsid(connectedSsid, targetSsid);

      if (!mounted) return;
      setState(() {
        _checkingWifi = false;
        _connectedWifiName = connectedSsid;
        _wifiConnectionVerified = isTargetNetwork;
        _wifiCheckMessage = isTargetNetwork
            ? 'Connected to $targetSsid. Setup can continue.'
            : connectedSsid == null
            ? 'The connected Wi-Fi name is not available yet.'
            : 'Connected to $connectedSsid instead of $targetSsid.';
      });

      if (isTargetNetwork && autoAdvance) {
        _next(SetupStep.finish);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingWifi = false;
        _wifiConnectionVerified = false;
        _wifiCheckMessage =
            'Could not read the current Wi-Fi network. Join $targetSsid and check again.';
      });
    }
  }

  String? _normalizeSsid(String? value) {
    final ssid = value?.trim();
    if (ssid == null ||
        ssid.isEmpty ||
        ssid.toLowerCase() == '<unknown ssid>') {
      return null;
    }
    if (ssid.length > 1 && ssid.startsWith('"') && ssid.endsWith('"')) {
      return ssid.substring(1, ssid.length - 1);
    }
    return ssid;
  }

  bool _matchesRouterSsid(String? connectedSsid, String targetSsid) {
    return connectedSsid == targetSsid ||
        connectedSsid?.startsWith('$targetSsid-') == true;
  }

  void _showLedGuide() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Meaning of LED Indicators',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              _ledRow(Colors.white, 'Solid white: Router starting up.'),
              _ledRow(Colors.white, 'Flashing white: Firmware upgrading.'),
              _ledRow(Colors.green, 'Flashing green: Ready for setup.'),
              _ledRow(Colors.green, 'Solid green: Setup over Bluetooth.'),
              _ledRow(Colors.blue, 'Blue: Internet connection status.'),
              _ledRow(Colors.amber, 'Yellow: Poor wireless network.'),
              _ledRow(Colors.red, 'Red: Failure or reset status.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ledRow(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == SetupStep.welcome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: const Color(0xfffbfcfd),
        body: SafeArea(
          child: Column(
            children: [
              _WizardHeader(
                step: _step,
                onBack: _back,
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _buildStep(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      SetupStep.welcome => _welcome(),
      SetupStep.need => _need(),
      SetupStep.modem => _modem(),
      SetupStep.led => _led(),
      SetupStep.bluetooth => _bluetooth(),
      SetupStep.searching => _searching(),
      SetupStep.found => _found(),
      SetupStep.room => _roomStep(),
      SetupStep.wifi => _wifi(),
      SetupStep.creating => _creating(),
      SetupStep.connectWifi => _connectWifi(),
      SetupStep.finish => _finish(),
    };
  }

  Widget _welcome() {
    return _GuidePage(
      title: 'Install TT Router',
      subtitle: 'A guided Bluetooth setup for a new or reset router.',
      art: _asset('ic_guide_need.png', height: 250),
      primaryLabel: 'Start',
      onPrimary: () => _next(SetupStep.need),
      secondaryLabel: 'Local pairing instead',
      onSecondary: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PairingScreen()),
      ),
    );
  }

  Widget _need() {
    return _GuidePage(
      title: "What you'll need",
      subtitle: 'All of these can be found in your packaging.',
      art: Column(
        children: [
          _asset('ic_guide_need.png', height: 176),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _labeledAsset('ic_guide_need_img.png', 'Ethernet Cable'),
              _labeledAsset('ic_guide_need_img1.png', 'Power Adapter'),
            ],
          ),
        ],
      ),
      primaryLabel: 'Next',
      onPrimary: () => _next(SetupStep.modem),
      stepLabel: '1/10',
    );
  }

  Widget _modem() {
    return _GuidePage(
      title: 'Power off your modem',
      subtitle:
          'Disconnect the old router and power off the modem before moving on.',
      art: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _asset('ic_guide_modem.png', height: 224),
          const SizedBox(width: 18),
          _asset('ic_guide_close_modem_img.png', height: 188),
        ],
      ),
      primaryLabel: 'Next',
      onPrimary: () => _next(SetupStep.led),
      secondaryLabel: 'I have no modem',
      onSecondary: () => _next(SetupStep.led),
      stepLabel: '3/10',
    );
  }

  Widget _led() {
    return _GuidePage(
      title: 'Check the LED status',
      subtitle:
          'Wait until TT Router wakes up with a green LED flash. It can take up to 2 minutes.',
      art: _asset('ic_guide_led_check.png', height: 286),
      primaryLabel: 'LED is Flash Green',
      onPrimary: () => _next(SetupStep.bluetooth),
      secondaryLabel: 'Why is my LED not flash green?',
      onSecondary: _showLedGuide,
      stepLabel: '6/10',
    );
  }

  Widget _bluetooth() {
    return _GuidePage(
      title: 'Enable Bluetooth',
      subtitle:
          'The original TT Router setup sends router setup data over Bluetooth.',
      art: _asset('ic_guide_bluetooth_hint.png', height: 264),
      primaryLabel: 'Search Router',
      onPrimary: () => _searchRouter(directSetup: false),
      stepLabel: '7/10',
    );
  }

  Widget _searching() {
    return _GuidePage(
      title: 'Searching for device',
      subtitle:
          _error ??
          'Keep this phone within 1 meter of the router while the TTBT signal is checked.',
      art: Stack(
        alignment: Alignment.center,
        children: [
          _asset('ic_guide_need.png', height: 250),
          Positioned(
            right: 8,
            bottom: 12,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Icon(Icons.bluetooth_searching, size: 36),
            ),
          ),
        ],
      ),
      primaryLabel: _busy ? null : 'Search again',
      onPrimary: _busy ? null : () => _searchRouter(),
      secondaryLabel: _quickSetup && !_busy ? 'Setup guide' : null,
      onSecondary: _quickSetup && !_busy ? _startGuide : null,
      stepLabel: _quickSetup ? null : '7/10',
    );
  }

  Widget _found() {
    return _GuidePage(
      title: 'Device detected',
      subtitle: 'SN: ${_foundRouter?.serialNumber ?? 'TT Router'}',
      art: Column(
        children: [
          _asset('success.png', height: 150),
          const SizedBox(height: 26),
          _asset('ic_guide_need.png', height: 164),
        ],
      ),
      primaryLabel: 'Next',
      onPrimary: () => _next(SetupStep.room),
      secondaryLabel: 'Search again',
      onSecondary: _searchRouter,
      stepLabel: '7/10',
    );
  }

  Widget _roomStep() {
    return _GuidePage(
      title: 'Select Room',
      subtitle: 'Location helps identify this mesh router later.',
      art: Column(
        children: [
          _asset('ic_guide_need.png', height: 156),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _rooms
                .map(
                  (room) => ChoiceChip(
                    label: Text(room),
                    selected: _room == room,
                    onSelected: (_) => setState(() => _room = room),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      primaryLabel: 'Next',
      onPrimary: () => _next(SetupStep.wifi),
      stepLabel: '8/10',
    );
  }

  Widget _wifi() {
    final detectedRouter = _foundRouter?.serialNumber;
    return _GuidePage(
      title: _quickSetup ? 'Set up TT Router' : 'Create Wi-Fi Network',
      subtitle:
          _error ??
          (detectedRouter == null || detectedRouter.isEmpty
              ? 'Choose the Wi-Fi name and password for TT Router.'
              : 'Pairing-mode router detected: $detectedRouter. Create its Wi-Fi network now.'),
      art: Column(
        children: [
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: !_showWifiPassword,
            decoration: InputDecoration(
              labelText: 'Wi-Fi Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _showWifiPassword = !_showWifiPassword),
                icon: Icon(
                  _showWifiPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _asset('ic_guide_need.png', height: 168),
        ],
      ),
      primaryLabel: 'Create Wi-Fi',
      onPrimary: _createWifi,
      secondaryLabel: _quickSetup ? 'Setup guide' : null,
      onSecondary: _quickSetup ? _startGuide : null,
      stepLabel: _quickSetup ? null : '10/10',
    );
  }

  Widget _creating() {
    return _GuidePage(
      title: 'Creating Wi-Fi network',
      subtitle:
          'Keep Bluetooth on and keep the app in front while the router is configured.',
      art: Column(
        children: [
          _busy
              ? const SizedBox(
                  width: 124,
                  height: 124,
                  child: CircularProgressIndicator(strokeWidth: 6),
                )
              : _asset('guide_wireless_creating.png', height: 150),
          const SizedBox(height: 36),
          _asset('guide_wireless_creating.png', height: 144),
        ],
      ),
      stepLabel: '10/10',
    );
  }

  Widget _connectWifi() {
    final ssid = _ssidController.text.trim();
    return _GuidePage(
      title: 'Connect to TT Router Wi-Fi',
      subtitle:
          'The router accepted the Bluetooth setup. Connect this phone to $ssid before local control.',
      art: Column(
        children: [
          _NetworkDetails(
            ssid: ssid,
            password: _passwordController.text,
            room: _room,
            meshId: _foundRouter?.meshId,
          ),
          const SizedBox(height: 16),
          _WifiConnectionStatus(
            targetSsid: ssid,
            connectedSsid: _connectedWifiName,
            message: _wifiCheckMessage,
            checking: _checkingWifi,
            verified: _wifiConnectionVerified,
          ),
          TextButton(
            onPressed: () => _next(SetupStep.wifi),
            child: const Text('Resend Wi-Fi setup'),
          ),
        ],
      ),
      primaryLabel: _wifiConnectionVerified
          ? 'Continue Setup'
          : 'Open Wi-Fi Networks',
      onPrimary: _wifiConnectionVerified
          ? () => _next(SetupStep.finish)
          : _openWifiPicker,
      secondaryLabel: _wifiConnectionVerified ? null : 'Check Connection',
      onSecondary: _wifiConnectionVerified
          ? null
          : () => _checkWifiConnection(),
      stepLabel: '10/10',
    );
  }

  Widget _finish() {
    return _GuidePage(
      title: 'Connection setup complete',
      subtitle: 'You can now discover the router on the local network.',
      art: Column(
        children: [
          _asset('success.png', height: 168),
          const SizedBox(height: 34),
          _NetworkDetails(
            ssid: _ssidController.text.trim(),
            password: _passwordController.text,
            room: _room,
            meshId: _foundRouter?.meshId,
          ),
        ],
      ),
      primaryLabel: 'Discover Router',
      onPrimary: () => Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
        (route) => false,
      ),
      stepLabel: '10/10',
    );
  }

  Widget _asset(String name, {required double height}) {
    return Image.asset(
      'assets/original_setup/$name',
      height: height,
      fit: BoxFit.contain,
    );
  }

  Widget _labeledAsset(String name, String label) {
    return SizedBox(
      width: 120,
      child: Column(
        children: [
          _asset(name, height: 86),
          const SizedBox(height: 10),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

enum SetupStep {
  welcome,
  need,
  modem,
  led,
  bluetooth,
  searching,
  found,
  room,
  wifi,
  creating,
  connectWifi,
  finish,
}

class _WizardHeader extends StatelessWidget {
  final SetupStep step;
  final VoidCallback onBack;
  final VoidCallback onClose;

  const _WizardHeader({
    required this.step,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(
              step == SetupStep.welcome ? Icons.close : Icons.arrow_back,
            ),
          ),
          const Spacer(),
          TextButton(onPressed: onClose, child: const Text('Exit')),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget art;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? stepLabel;

  const _GuidePage({
    required this.title,
    required this.subtitle,
    required this.art,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.stepLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height - 124,
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
            ),
            const SizedBox(height: 34),
            art,
            const SizedBox(height: 32),
            if (stepLabel != null)
              Text(stepLabel!, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 18),
            if (primaryLabel != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                  ),
                  child: Text(primaryLabel!),
                ),
              ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NetworkDetails extends StatelessWidget {
  final String ssid;
  final String password;
  final String room;
  final String? meshId;

  const _NetworkDetails({
    required this.ssid,
    required this.password,
    required this.room,
    this.meshId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _detail('Wi-Fi Name', ssid),
          const SizedBox(height: 10),
          _detail('Wi-Fi Password', password),
          const SizedBox(height: 10),
          _detail('Location', room),
          if (meshId != null && meshId!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detail('Mesh ID', meshId!),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _WifiConnectionStatus extends StatelessWidget {
  final String targetSsid;
  final String? connectedSsid;
  final String? message;
  final bool checking;
  final bool verified;

  const _WifiConnectionStatus({
    required this.targetSsid,
    required this.connectedSsid,
    required this.message,
    required this.checking,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final color = verified ? Colors.green : Colors.deepOrange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (checking)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              verified ? Icons.wifi_rounded : Icons.wifi_find_rounded,
              color: color,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verified ? 'Router Wi-Fi connected' : 'Router Wi-Fi needed',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  message ?? 'Join $targetSsid from Android Wi-Fi networks.',
                ),
                if (connectedSsid != null && !verified) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Current Wi-Fi: $connectedSsid',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
