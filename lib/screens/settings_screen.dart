import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/usb_storage.dart';
import '../providers/router_provider.dart';
import 'router_settings_screens.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Consumer<RouterProvider>(
        builder: (context, provider, child) {
          return ListView(
            children: [
              _buildSectionHeader('Network'),
              _buildSettingsTile(
                icon: Icons.wifi,
                title: 'WiFi Settings',
                subtitle: provider.currentWifiName,
                onTap: () => _navigateToWifiSettings(context),
              ),
              _buildSettingsTile(
                icon: Icons.usb_rounded,
                title: 'USB Storage',
                subtitle: provider.usbDisks.isEmpty
                    ? 'Private storage and SMB shares'
                    : '${provider.usbDisks.length} disk${provider.usbDisks.length == 1 ? '' : 's'} connected',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UsbStorageScreen()),
                ),
              ),
              _buildSettingsTile(
                icon: Icons.wifi_tethering,
                title: 'Guest Wi-Fi',
                subtitle: 'Visitor network access',
                onTap: () => _push(context, const GuestWifiSettingsScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.public,
                title: 'WAN Settings',
                subtitle: 'Internet connection settings',
                onTap: () => _push(context, const WanSettingsScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.lan,
                title: 'LAN Settings',
                subtitle: 'Local network configuration',
                onTap: () => _push(context, const LanSettingsScreen()),
              ),

              _buildSectionHeader('Advanced'),
              _buildSettingsTile(
                icon: Icons.security,
                title: 'Security & NAT',
                subtitle: 'Firewall, UPnP, DMZ and Fast NAT',
                onTap: () => _push(context, const SecuritySettingsScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.speed,
                title: 'QoS',
                subtitle: 'Quality of Service settings',
                onTap: () => _push(context, const QosSettingsScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.vpn_key,
                title: 'VPN',
                subtitle: 'VPN client configuration',
                onTap: () => _push(context, const VpnSettingsScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.router,
                title: 'Port Forwarding',
                subtitle: 'Virtual server settings',
                onTap: () => _push(context, const PortForwardingScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.dns,
                title: 'DNS Settings',
                subtitle: 'Custom DNS is part of WAN settings',
                onTap: () => _push(context, const WanSettingsScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.public_outlined,
                title: 'DDNS',
                subtitle: 'Dynamic DNS provider',
                onTap: () => _push(context, const DdnsSettingsScreen()),
              ),

              _buildSectionHeader('System'),
              _buildSettingsTile(
                icon: Icons.system_update,
                title: 'Firmware Update',
                subtitle: 'Mesh node firmware status',
                onTap: () => _push(context, const FirmwareStatusScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.lightbulb_outline,
                title: 'Router LEDs',
                subtitle: 'Control LED state per mesh node',
                onTap: () => _push(context, const NodeLedSettingsScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.schedule,
                title: 'Restart Schedule',
                subtitle: 'Weekly restart and restart now',
                onTap: () => _push(context, const RestartScheduleScreen()),
              ),
              _buildSettingsTile(
                icon: Icons.backup,
                title: 'Backup & Restore',
                subtitle: 'Export or import settings',
                onTap: () => _showBackupNote(context),
              ),
              _buildSettingsTile(
                icon: Icons.restart_alt,
                title: 'Reboot',
                subtitle: 'Restart mesh routers',
                onTap: () => _showRebootDialog(context, provider),
              ),
              _buildSettingsTile(
                icon: Icons.settings_backup_restore,
                title: 'Factory Reset',
                subtitle: 'Reset to default settings',
                onTap: () => _showFactoryResetDialog(context),
              ),

              _buildSectionHeader('About'),
              _buildSettingsTile(
                icon: Icons.info,
                title: 'About',
                subtitle: 'App version 1.0.0',
                onTap: () => _showAboutDialog(context),
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.deepOrange.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.deepOrange, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _navigateToWifiSettings(BuildContext context) {
    _push(context, const WifiSettingsDetailScreen());
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _showBackupNote(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Backup & Restore',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'The original local router command set reviewed so far does not '
              'show a safe configuration backup or restore command. '
              'Diagnostics export stays available for debugging state.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRebootDialog(BuildContext context, RouterProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reboot Router'),
        content: const Text(
          'Are you sure you want to reboot all mesh nodes? '
          'This will temporarily disconnect all devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await provider.rebootRouter();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rebooting router...')),
                );
              }
            },
            child: const Text('Reboot', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showFactoryResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Factory Reset'),
        content: const Text(
          'Use the router reset button for a factory reset. '
          'A local MQTT reset command has not been confirmed from the '
          'original app yet, so the Flutter app will not send one here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'TT Router',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.deepOrange,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.router, color: Colors.white),
      ),
      children: [
        const Text(
          'Local control app for TaoTronics Mesh Routers. '
          'No cloud login required.',
        ),
      ],
    );
  }
}

class WifiSettingsDetailScreen extends StatefulWidget {
  const WifiSettingsDetailScreen({super.key});

  @override
  State<WifiSettingsDetailScreen> createState() =>
      _WifiSettingsDetailScreenState();
}

class _WifiSettingsDetailScreenState extends State<WifiSettingsDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ssid2gController = TextEditingController();
  final _password2gController = TextEditingController();
  final _ssid5gController = TextEditingController();
  final _password5gController = TextEditingController();
  bool _enable2g = true;
  bool _enable5g = true;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  Future<void> _loadSettings() async {
    final provider = context.read<RouterProvider>();
    await provider.refreshWirelessSettings();
    if (!mounted) return;

    final networks = provider.wirelessNetworksParsed;
    final network2g = networks
        .where((network) => network.index == 0)
        .firstOrNull;
    final network5g = networks
        .where((network) => network.index == 1)
        .firstOrNull;

    _ssid2gController.text = network2g?.ssid ?? '';
    _password2gController.text = network2g?.password ?? '';
    _ssid5gController.text = network5g?.ssid ?? '';
    _password5gController.text = network5g?.password ?? '';
    setState(() {
      _enable2g = network2g?.isEnabled ?? false;
      _enable5g = network5g?.isEnabled ?? false;
    });
  }

  @override
  void dispose() {
    _ssid2gController.dispose();
    _password2gController.dispose();
    _ssid5gController.dispose();
    _password5gController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton(onPressed: _saveSettings, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildWifiSection(
              title: '2.4GHz Network',
              enabled: _enable2g,
              onEnabledChanged: (v) => setState(() => _enable2g = v),
              ssidController: _ssid2gController,
              passwordController: _password2gController,
            ),
            const SizedBox(height: 24),
            _buildWifiSection(
              title: '5GHz Network',
              enabled: _enable5g,
              onEnabledChanged: (v) => setState(() => _enable5g = v),
              ssidController: _ssid5gController,
              passwordController: _password5gController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiSection({
    required String title,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required TextEditingController ssidController,
    required TextEditingController passwordController,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: onEnabledChanged,
                  activeTrackColor: Colors.deepOrange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: ssidController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Network Name (SSID)',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(),
              ),
              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: passwordController,
              enabled: enabled,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password',
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
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v.length < 8) return 'At least 8 characters';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<RouterProvider>();
    final currentNetworks = provider.wirelessNetworksParsed;
    final patchedNetworks = currentNetworks.map((network) {
      if (network.index == 0) {
        return network.copyWith(
          ssid: _ssid2gController.text.trim(),
          password: _password2gController.text,
          create: _enable2g ? 1 : 0,
          disable: _enable2g ? 0 : 1,
        );
      }
      if (network.index == 1) {
        return network.copyWith(
          ssid: _ssid5gController.text.trim(),
          password: _password5gController.text,
          create: _enable5g ? 1 : 0,
          disable: _enable5g ? 0 : 1,
        );
      }
      return network;
    }).toList();
    final hasRouterNetworks = patchedNetworks.any(
      (network) => network.index == 0 || network.index == 1,
    );
    final success = hasRouterNetworks
        ? await provider.setWirelessSettings(
            patchedNetworks
                .map((network) => network.toRouterPayload())
                .toList(),
          )
        : false;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Settings saved!' : 'Failed to save settings',
          ),
        ),
      );
      if (success) Navigator.pop(context);
    }
  }
}

class UsbStorageScreen extends StatefulWidget {
  const UsbStorageScreen({super.key});

  @override
  State<UsbStorageScreen> createState() => _UsbStorageScreenState();
}

class _UsbStorageScreenState extends State<UsbStorageScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RouterProvider>().refreshUsbStorage();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('USB Storage'),
        actions: [
          Consumer<RouterProvider>(
            builder: (_, provider, _) => IconButton(
              tooltip: 'Refresh',
              onPressed: provider.usbStorageLoading
                  ? null
                  : provider.refreshUsbStorage,
              icon: provider.usbStorageLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      body: Consumer<RouterProvider>(
        builder: (context, provider, child) {
          if (!provider.isConnected) {
            return const Center(
              child: Text('Pair the router to manage storage.'),
            );
          }

          final settings =
              provider.usbStorageSettings ??
              const UsbStorageSettings(
                usb3Enabled: false,
                sambaEnabled: false,
                anonymousAccess: false,
              );

          return RefreshIndicator(
            onRefresh: provider.refreshUsbStorage,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _storageSummary(provider),
                const SizedBox(height: 12),
                _storageSwitches(context, provider, settings),
                const SizedBox(height: 12),
                _shareAddress(provider),
                const SizedBox(height: 12),
                Text(
                  'Connected disks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (provider.usbDisks.isEmpty)
                  _emptyDisks()
                else
                  ...provider.usbDisks.map(
                    (disk) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _diskCard(disk),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _storageSummary(RouterProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.usb_rounded, color: Colors.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${provider.usbDisks.length} disk${provider.usbDisks.length == 1 ? '' : 's'}, '
                    '${provider.usbPartitionCount} partition${provider.usbPartitionCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatBytes(provider.usbAvailableBytes)} free of ${_formatBytes(provider.usbTotalBytes)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _storageSwitches(
    BuildContext context,
    RouterProvider provider,
    UsbStorageSettings settings,
  ) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('USB 3.0 mode'),
            subtitle: const Text('Use the router USB 3.0 storage mode'),
            value: settings.usb3Enabled,
            onChanged: provider.usbStorageSaving
                ? null
                : (value) => _save(
                    context,
                    provider,
                    settings.copyWith(usb3Enabled: value),
                  ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('SMB file sharing'),
            subtitle: const Text('Expose connected disks on the local network'),
            value: settings.sambaEnabled,
            onChanged: provider.usbStorageSaving
                ? null
                : (value) => _save(
                    context,
                    provider,
                    settings.copyWith(sambaEnabled: value),
                  ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Anonymous access'),
            subtitle: const Text('Allow share access without a private user'),
            value: settings.anonymousAccess,
            onChanged: !settings.sambaEnabled || provider.usbStorageSaving
                ? null
                : (value) => _save(
                    context,
                    provider,
                    settings.copyWith(anonymousAccess: value),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _shareAddress(RouterProvider provider) {
    final address = provider.usbVisitAddress;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_shared_rounded, color: Colors.indigo),
        title: const Text('Share address'),
        subtitle: address == null
            ? const Text('The router has not reported an SMB address yet.')
            : Text('Windows: \\\\$address\nMac: smb://$address'),
      ),
    );
  }

  Widget _emptyDisks() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.sd_storage_outlined, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No USB disk reported. Connect storage to the router and refresh.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diskCard(UsbDisk disk) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage_rounded, color: Colors.deepOrange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    disk.brand,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  disk.devNode,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...disk.partitions.map(
              (partition) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('Partition ${partition.id}')),
                      Text(
                        '${_formatBytes(partition.availableBytes)} free / '
                        '${_formatBytes(partition.totalBytes)}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    RouterProvider provider,
    UsbStorageSettings updated,
  ) async {
    final success = await provider.updateUsbStorageSettings(updated);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'USB storage settings updated.' : 'Storage update failed.',
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final formatted = value >= 100
        ? value.toStringAsFixed(0)
        : value >= 10
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2);
    return '$formatted ${units[unit]}';
  }
}
