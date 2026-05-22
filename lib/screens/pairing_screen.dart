import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../services/ble_provisioning_service.dart';
import 'home_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _meshIdController = TextEditingController();
  final _ipController = TextEditingController(text: '192.168.10.1');
  final _passwordController = TextEditingController();
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _bleProvisioningService = BleProvisioningService();
  bool _isPairing = false;
  bool _isBleProvisioning = false;
  bool _showPassword = false;
  String? _errorMessage;
  String? _successMessage;
  PairingMethod _selectedMethod = PairingMethod.automatic;

  @override
  void initState() {
    super.initState();
    _loadDiscoveredRouter();
  }

  void _loadDiscoveredRouter() {
    final provider = context.read<RouterProvider>();
    if (provider.routers.isNotEmpty) {
      final router = provider.routers.first;
      _meshIdController.text = router.meshId;
      if (router.ipAddress != null) {
        _ipController.text = router.ipAddress!;
      }
    }
  }

  @override
  void dispose() {
    _meshIdController.dispose();
    _ipController.dispose();
    _passwordController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    super.dispose();
  }

  Future<void> _provisionOverBluetooth() async {
    final ssid = _wifiSsidController.text.trim();
    final password = _wifiPasswordController.text;
    if (ssid.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage =
            'Enter the WiFi name and password to set up the router.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isBleProvisioning = true;
      _errorMessage = null;
      _successMessage = null;
    });

    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    try {
      final result = await _bleProvisioningService.provision(
        ssid: ssid,
        password: password,
      );
      if (!mounted) return;

      _meshIdController.text = result.meshId;
      setState(() {
        _successMessage =
            'Router ${result.meshId} received WiFi setup over Bluetooth. '
            'Connect this phone to "$ssid" when it appears, then test the '
            'local router connection below.';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message ?? 'Bluetooth setup failed.';
      });
    } finally {
      if (mounted) {
        setState(() => _isBleProvisioning = false);
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isPairing = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final provider = context.read<RouterProvider>();
    String meshId = _meshIdController.text.trim();
    String ipAddress = _ipController.text.trim();

    if (_selectedMethod == PairingMethod.automatic) {
      if (provider.routers.isEmpty) {
        setState(() {
          _errorMessage =
              'No routers discovered. Make sure the router is powered on.';
          _isPairing = false;
        });
        return;
      }
      final router = provider.routers.first;
      meshId = router.meshId;
      ipAddress = router.ipAddress ?? '192.168.10.1';
    }

    if (meshId.isEmpty || ipAddress.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter Mesh ID and IP address';
        _isPairing = false;
      });
      return;
    }

    final success = await provider.attemptAuthentication(
      meshId,
      ipAddress,
      password: _passwordController.text.isNotEmpty
          ? _passwordController.text
          : null,
    );

    if (success) {
      setState(() {
        _successMessage = 'Connection successful! Router paired.';
        _isPairing = false;
      });

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } else {
      setState(() {
        _errorMessage =
            provider.errorMessage ??
            'Authentication failed. The router may require:\n'
                '• Factory reset to enter pairing mode\n'
                '• WPS button press for pairing\n'
                '• Manual credentials from the original TT Router app';
        _isPairing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Router')),
      body: Consumer<RouterProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(provider),
                const SizedBox(height: 24),
                _buildBluetoothSetup(),
                const SizedBox(height: 24),
                _buildInstructions(),
                const SizedBox(height: 24),
                _buildMethodSelector(),
                const SizedBox(height: 24),
                if (_selectedMethod == PairingMethod.manual) _buildManualForm(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(),
                ],
                if (_successMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildSuccessCard(),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isPairing ? null : _testConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isPairing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Connecting...'),
                          ],
                        )
                      : const Text('Test Connection & Pair'),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(RouterProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Status',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              'Router Discovered',
              provider.isRouterFound,
              provider.isRouterFound
                  ? '${provider.routers.length} found'
                  : 'Scanning...',
            ),
            _buildStatusRow(
              'Network Reachable',
              provider.isNetworkReachable,
              null,
            ),
            _buildStatusRow(
              'MQTT Port Open',
              provider.isMqttPortOpen,
              'Port 25678',
            ),
            _buildStatusRow(
              'Authenticated',
              provider.isConnected,
              provider.isConnected ? 'Connected' : 'Required',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool status, String? detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            status ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: status ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          if (detail != null)
            Text(
              detail,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Pairing Instructions',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '1. Ensure the router is powered on\n'
              '2. Connect your phone to the router\'s WiFi\n'
              '3. If previously configured, you may need to factory reset\n'
              '4. Some routers require WPS button for pairing\n'
              '5. Tap "Test Connection & Pair" below',
              style: TextStyle(color: Colors.blue.shade800, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothSetup() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.bluetooth_searching, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text(
                  'Bluetooth Setup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Use this for a new or reset TT Router in setup mode. '
              'The app searches nearby TTBT routers and sends the WiFi '
              'network the router should create.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _wifiSsidController,
              decoration: const InputDecoration(
                labelText: 'Router WiFi Name',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wifiPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Router WiFi Password',
                prefixIcon: Icon(Icons.password),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isBleProvisioning ? null : _provisionOverBluetooth,
              icon: _isBleProvisioning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.bluetooth_connected),
              label: Text(
                _isBleProvisioning
                    ? 'Setting up nearby router...'
                    : 'Set Up Router over Bluetooth',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pairing Method',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            RadioGroup<PairingMethod>(
              groupValue: _selectedMethod,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedMethod = value);
                }
              },
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Radio<PairingMethod>(
                      value: PairingMethod.automatic,
                      activeColor: Colors.deepOrange,
                    ),
                    title: const Text('Automatic'),
                    subtitle: const Text(
                      'Use discovered router with default credentials',
                    ),
                    onTap: () => setState(
                      () => _selectedMethod = PairingMethod.automatic,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Radio<PairingMethod>(
                      value: PairingMethod.manual,
                      activeColor: Colors.deepOrange,
                    ),
                    title: const Text('Manual'),
                    subtitle: const Text('Enter router credentials manually'),
                    onTap: () =>
                        setState(() => _selectedMethod = PairingMethod.manual),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Router Credentials',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _meshIdController,
              decoration: const InputDecoration(
                labelText: 'Mesh ID',
                hintText: 'e.g., 100D7F5A6B8C',
                prefixIcon: Icon(Icons.router),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Router IP Address',
                hintText: '192.168.10.1',
                prefixIcon: Icon(Icons.lan),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password (optional)',
                hintText: 'Leave blank for auto-generated',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The Mesh ID is usually printed on the router label. '
              'If you leave the password blank, the app will use the default TaoTronics credentials.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _successMessage!,
                style: TextStyle(color: Colors.green.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum PairingMethod { automatic, manual }
