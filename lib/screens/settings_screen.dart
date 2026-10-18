import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/save_result.dart';
import '../models/usb_storage.dart';
import '../models/wireless_network.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/feedback.dart';
import '../widgets/led_card.dart';
import 'diagnostics_screen.dart';
import 'nodes_screen.dart';
import 'router_settings_screens.dart';
import 'setup_wizard_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 120),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PageHeader(kicker: 'Control centre', title: 'Settings'),
                  const SizedBox(height: Space.lg),
                  const ConnectionStatusBanners(),
                  const RouterLedCard(),
                  const SizedBox(height: Space.md),
                  SettingsGroup(
                    title: 'Wi-Fi & wireless',
                    icon: Icons.wifi_rounded,
                    summary: 'Networks and guest access',
                    initiallyExpanded: true,
                    tiles: [
                      SettingsTile(
                        icon: Icons.wifi_rounded,
                        tone: Tone.info,
                        title: 'Wi-Fi settings',
                        subtitle: provider.isConnected
                            ? provider.currentWifiName
                            : 'Names, passwords, bands',
                        onTap: () =>
                            _push(context, const WifiSettingsDetailScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.wifi_tethering_rounded,
                        tone: Tone.success,
                        title: 'Guest Wi-Fi',
                        subtitle: 'Visitor network access',
                        onTap: () =>
                            _push(context, const GuestWifiSettingsScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  SettingsGroup(
                    title: 'Internet & local network',
                    icon: Icons.public_rounded,
                    summary: 'WAN, LAN, DNS and DDNS',
                    tiles: [
                      SettingsTile(
                        icon: Icons.public_rounded,
                        title: 'Internet (WAN & DNS)',
                        subtitle: 'DHCP, static IP, PPPoE, DNS, VLAN',
                        onTap: () => _push(context, const WanSettingsScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.lan_rounded,
                        title: 'Local network (LAN & DHCP)',
                        subtitle: 'Router address and DHCP range',
                        onTap: () => _push(context, const LanSettingsScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.dns_outlined,
                        title: 'DNS servers',
                        subtitle: 'Set in Internet (WAN & DNS)',
                        onTap: () => _push(context, const WanSettingsScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.travel_explore_rounded,
                        title: 'Dynamic DNS',
                        subtitle: 'DDNS provider',
                        onTap: () => _push(context, const DdnsSettingsScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  SettingsGroup(
                    title: 'Devices & mesh',
                    icon: Icons.hub_outlined,
                    summary: 'Mesh nodes, setup and USB storage',
                    tiles: [
                      SettingsTile(
                        icon: Icons.hub_outlined,
                        title: 'Mesh nodes',
                        subtitle: 'Status, clients and uptime',
                        onTap: () => _push(context, const NodesScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.add_circle_outline_rounded,
                        title: 'Set up a router',
                        subtitle:
                            'Provision a new or reset router over Bluetooth',
                        onTap: () => _push(context, const SetupWizardScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.usb_rounded,
                        tone: Tone.neutral,
                        title: 'USB storage',
                        subtitle: provider.usbDisks.isEmpty
                            ? 'Private storage and SMB shares'
                            : '${provider.usbDisks.length} disk${provider.usbDisks.length == 1 ? '' : 's'} connected',
                        onTap: () => _push(context, const UsbStorageScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  SettingsGroup(
                    title: 'Router LEDs & system',
                    icon: Icons.settings_suggest_outlined,
                    summary: 'LEDs, firmware and restarts',
                    tiles: [
                      SettingsTile(
                        icon: Icons.lightbulb_outline_rounded,
                        title: 'Router LEDs',
                        subtitle: 'LED on/off per mesh node',
                        onTap: () =>
                            _push(context, const NodeLedSettingsScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.system_update_alt_rounded,
                        title: 'Firmware',
                        subtitle: 'Mesh node firmware status',
                        onTap: () =>
                            _push(context, const FirmwareStatusScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.schedule_rounded,
                        title: 'Restart schedule',
                        subtitle: 'Weekly restart and restart now',
                        onTap: () =>
                            _push(context, const RestartScheduleScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.restart_alt_rounded,
                        tone: Tone.danger,
                        title: 'Restart router',
                        subtitle: 'Reboot all mesh nodes',
                        onTap: () => _confirmReboot(context, provider),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  SettingsGroup(
                    title: 'Security & advanced',
                    icon: Icons.shield_outlined,
                    summary: 'Firewall, ports, QoS, VPN',
                    tiles: [
                      SettingsTile(
                        icon: Icons.shield_outlined,
                        title: 'Security & NAT',
                        subtitle: 'Firewall, UPnP, DMZ and Fast NAT',
                        onTap: () =>
                            _push(context, const SecuritySettingsScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.call_split_rounded,
                        title: 'Port forwarding',
                        subtitle: 'Virtual servers',
                        onTap: () =>
                            _push(context, const PortForwardingScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.speed_rounded,
                        title: 'QoS',
                        subtitle: 'Bandwidth limits',
                        onTap: () => _push(context, const QosSettingsScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.vpn_key_outlined,
                        title: 'VPN client',
                        subtitle: 'PPTP or L2TP/IPsec',
                        onTap: () => _push(context, const VpnSettingsScreen()),
                      ),
                      SettingsTile(
                        icon: Icons.backup_outlined,
                        tone: Tone.neutral,
                        title: 'Backup & restore',
                        subtitle: 'No local backup command',
                        trailing: const Icon(Icons.info_outline_rounded),
                        onTap: () => _showUnavailable(
                          context,
                          'Backup & restore',
                          'The local router command set reviewed so far has no '
                              'safe configuration backup or restore command. '
                              'Diagnostics export stays available for debugging state.',
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.settings_backup_restore_rounded,
                        tone: Tone.neutral,
                        title: 'Factory reset',
                        subtitle: 'Use the reset button on the router',
                        trailing: const Icon(Icons.info_outline_rounded),
                        onTap: () => _showUnavailable(
                          context,
                          'Factory reset',
                          'Use the router reset button for a factory reset. A '
                              'local reset command has not been confirmed from '
                              'the original app, so this app will not send one.',
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.family_restroom_rounded,
                        tone: Tone.neutral,
                        title: 'Parental controls',
                        subtitle: 'Not supported by the local API',
                        trailing: const Icon(Icons.info_outline_rounded),
                        onTap: () => _showUnavailable(
                          context,
                          'Parental controls',
                          'No local router command for schedules or content '
                              'filtering has been verified, so this app does not '
                              'offer parental controls.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  SettingsGroup(
                    title: 'Diagnostics & app',
                    icon: Icons.monitor_heart_outlined,
                    summary: 'Checks, report and version',
                    tiles: [
                      SettingsTile(
                        icon: Icons.monitor_heart_outlined,
                        tone: Tone.warning,
                        title: 'Diagnostics',
                        subtitle: 'Connection checks and exportable report',
                        onTap: () => _push(
                          context,
                          DiagnosticsScreen(
                            routerReachable: provider.isNetworkReachable,
                            mqttPortOpen: provider.isMqttPortOpen,
                          ),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.info_outline_rounded,
                        title: 'About ${AppInfo.name}',
                        subtitle: 'Version ${AppInfo.version}',
                        onTap: () => showAboutDialog(
                          context: context,
                          applicationName: AppInfo.name,
                          applicationVersion:
                              '${AppInfo.version} (${AppInfo.build})',
                          applicationIcon: const IconBadge(
                            Icons.router_rounded,
                          ),
                          children: const [
                            Text(
                              'Local control for TaoTronics mesh routers. No cloud '
                              'account required; the app talks to the router over '
                              'your Wi-Fi with a verified TLS connection.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReboot(
    BuildContext context,
    RouterProvider provider,
  ) async {
    if (!provider.isConnected) {
      showSaveResult(
        context,
        const SaveResult.failed('Connect to the router first.'),
      );
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Restart all mesh nodes?',
      message:
          'Every device loses its connection for a few minutes while the '
          'router restarts. The app reconnects automatically.',
      confirmLabel: 'Restart',
      destructive: true,
      icon: Icons.restart_alt_rounded,
    );
    if (!confirmed || !context.mounted) return;
    final result = await provider.rebootRouter();
    if (context.mounted) showSaveResult(context, result);
  }

  void _showUnavailable(BuildContext context, String title, String message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.md),
              Text(message),
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edits router profiles 0 and 1 independently; indices are not bands.
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
  bool _loading = true;
  bool _saving = false;
  WirelessNetwork? _network2g;
  WirelessNetwork? _network5g;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final provider = context.read<RouterProvider>();
    setState(() => _loading = true);
    if (provider.isConnected) await provider.refreshWirelessSettings();
    if (!mounted) return;

    final networks = provider.wirelessNetworksParsed;
    _network2g = networks.where((network) => network.index == 0).firstOrNull;
    _network5g = networks.where((network) => network.index == 1).firstOrNull;

    _ssid2gController.text = _network2g?.ssid ?? '';
    _password2gController.text = _network2g?.password ?? '';
    _ssid5gController.text = _network5g?.ssid ?? '';
    _password5gController.text = _network5g?.password ?? '';
    setState(() {
      _enable2g = _network2g?.isEnabled ?? false;
      _enable5g = _network5g?.isEnabled ?? false;
      _loading = false;
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

  bool get _loaded => _network2g != null || _network5g != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi settings'),
        actions: [
          if (_loaded)
            TextButton(
              onPressed: _saving ? null : _saveSettings,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_loaded
          ? EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Could not read the Wi-Fi settings',
              message:
                  'Editing is disabled so blank values cannot be sent to the router.',
              action: FilledButton.icon(
                onPressed: _loadSettings,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(Space.lg),
                children: [
                  ContentWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_network2g != null)
                          _buildWifiSection(
                            title: _network2g!.bandLabel,
                            network: _network2g!,
                            enabled: _enable2g,
                            onEnabledChanged: (v) =>
                                setState(() => _enable2g = v),
                            ssidController: _ssid2gController,
                            passwordController: _password2gController,
                          ),
                        const SizedBox(height: Space.lg),
                        if (_network5g != null)
                          _buildWifiSection(
                            title: _network5g!.bandLabel,
                            network: _network5g!,
                            enabled: _enable5g,
                            onEnabledChanged: (v) =>
                                setState(() => _enable5g = v),
                            ssidController: _ssid5gController,
                            passwordController: _password5gController,
                          ),
                        const SizedBox(height: Space.lg),
                        const InfoBanner(
                          tone: Tone.warning,
                          title: 'Saving restarts Wi-Fi',
                          message:
                              'Devices disconnect briefly and must rejoin with '
                              'the new name or password.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWifiSection({
    required String title,
    required WirelessNetwork network,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required TextEditingController ssidController,
    required TextEditingController passwordController,
  }) {
    final secured = network.encrypt > 0;
    return SectionCard(
      title: title,
      subtitle: network.encryptionLabel,
      icon: Icons.wifi_rounded,
      trailing: Switch(
        value: enabled,
        onChanged: _saving ? null : onEnabledChanged,
      ),
      child: Column(
        children: [
          TextFormField(
            controller: ssidController,
            enabled: enabled && !_saving,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Network name (SSID)',
              prefixIcon: Icon(Icons.wifi_rounded),
            ),
            validator: enabled ? Validators.ssid : null,
          ),
          const SizedBox(height: Space.sm),
          TextFormField(
            controller: passwordController,
            enabled: enabled && secured && !_saving,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide passwords' : 'Show passwords',
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: enabled
                ? (v) => Validators.wifiPassword(v, secured: secured)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    final confirmed = await confirmAction(
      context,
      title: 'Apply Wi-Fi changes?',
      message:
          'The router restarts Wi-Fi to apply this. Connected devices, '
          'possibly including this phone, disconnect and must rejoin.',
      confirmLabel: 'Apply',
      icon: Icons.wifi_rounded,
    );
    if (!confirmed || !mounted) return;

    final provider = context.read<RouterProvider>();
    final currentNetworks = provider.wirelessNetworksParsed;
    final patchedNetworks = currentNetworks.map((network) {
      if (network.index == 0) {
        return network
            .copyWith(
              ssid: _ssid2gController.text.trim(),
              password: _password2gController.text,
            )
            .withEnabled(_enable2g);
      }
      if (network.index == 1) {
        return network
            .copyWith(
              ssid: _ssid5gController.text.trim(),
              password: _password5gController.text,
            )
            .withEnabled(_enable5g);
      }
      return network;
    }).toList();

    setState(() => _saving = true);
    final pause = provider.pauseLiveUpdates('Wi-Fi save');
    final SaveResult result;
    try {
      result = await provider.saveWirelessNetworks(patchedNetworks);
    } finally {
      pause.release();
    }

    if (!mounted) return;
    setState(() => _saving = false);
    showSaveResult(context, result);
    if (result.accepted) Navigator.pop(context);
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
      if (mounted) context.read<RouterProvider>().refreshUsbStorage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final settings = provider.usbStorageSettings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('USB storage'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.usbStorageLoading || !provider.isConnected
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refreshUsbStorage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.lg),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConnectionStatusBanners(),
                  _storageSummary(context, provider),
                  const SizedBox(height: Space.md),
                  if (settings == null)
                    SectionCard(
                      title: 'Sharing settings',
                      icon: Icons.folder_shared_outlined,
                      child: Text(
                        provider.usbStorageLoading
                            ? 'Loading…'
                            : 'The router has not reported its storage '
                                  'settings, so they cannot be changed yet.',
                      ),
                    )
                  else
                    _storageSwitches(context, provider, settings),
                  const SizedBox(height: Space.md),
                  _shareAddress(provider),
                  const SectionLabel('Connected disks'),
                  if (provider.usbDisks.isEmpty)
                    const SectionCard(
                      child: Text(
                        'No USB disk reported. Connect storage to the router '
                        'and refresh.',
                      ),
                    )
                  else
                    ...provider.usbDisks.map(
                      (disk) => Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: _diskCard(context, disk),
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

  Widget _storageSummary(BuildContext context, RouterProvider provider) {
    final total = provider.usbTotalBytes;
    final free = provider.usbAvailableBytes;
    return SectionCard(
      child: Row(
        children: [
          const IconBadge(Icons.usb_rounded, tone: Tone.neutral, size: 48),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${provider.usbDisks.length} disk${provider.usbDisks.length == 1 ? '' : 's'}, '
                  '${provider.usbPartitionCount} partition${provider.usbPartitionCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  total == 0
                      ? 'No capacity reported'
                      : '${formatBytes(free)} free of ${formatBytes(total)}',
                ),
                if (total > 0) ...[
                  const SizedBox(height: Space.sm),
                  LinearProgressIndicator(
                    value: (total - free) / total,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageSwitches(
    BuildContext context,
    RouterProvider provider,
    UsbStorageSettings settings,
  ) {
    final busy = provider.usbStorageSaving || !provider.isConnected;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('USB 3.0 mode'),
            subtitle: const Text('Use the router USB 3.0 storage mode'),
            value: settings.usb3Enabled,
            onChanged: busy
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
            onChanged: busy
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
            subtitle: const Text(
              'Anyone on your network can open the shares without a password',
            ),
            value: settings.anonymousAccess,
            onChanged: !settings.sambaEnabled || busy
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
        leading: const Icon(Icons.folder_shared_rounded),
        title: const Text('Share address'),
        subtitle: address == null
            ? const Text('The router has not reported an SMB address yet.')
            : Text('Windows: \\\\$address\nMac: smb://$address'),
      ),
    );
  }

  Widget _diskCard(BuildContext context, UsbDisk disk) {
    return SectionCard(
      title: disk.brand,
      subtitle: disk.devNode,
      icon: Icons.storage_rounded,
      child: Column(
        children: [
          for (final partition in disk.partitions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Partition ${partition.id}'),
              subtitle: partition.totalBytes == 0
                  ? null
                  : LinearProgressIndicator(
                      value: partition.usedBytes / partition.totalBytes,
                      borderRadius: BorderRadius.circular(4),
                    ),
              trailing: Text(
                '${formatBytes(partition.availableBytes)} free / '
                '${formatBytes(partition.totalBytes)}',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    RouterProvider provider,
    UsbStorageSettings updated,
  ) async {
    if (updated.anonymousAccess &&
        !(provider.usbStorageSettings?.anonymousAccess ?? false)) {
      final confirmed = await confirmAction(
        context,
        title: 'Allow anonymous access?',
        message:
            'Anyone connected to your network can read the USB shares '
            'without a password.',
        confirmLabel: 'Allow',
        icon: Icons.warning_amber_rounded,
      );
      if (!confirmed || !context.mounted) return;
    }
    final result = await provider.updateUsbStorageSettings(updated);
    if (!context.mounted) return;
    showSaveResult(context, result);
  }
}

/// Collapsible settings section: a header row with a summary, expanding to
/// its entries inside one card.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    required this.tiles,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final String summary;
  final List<SettingsTile> tiles;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanelCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.xs,
          Space.md,
          Space.xs,
        ),
        childrenPadding: const EdgeInsets.only(bottom: Space.sm),
        leading: IconBadge(icon, tone: Tone.brand, size: 40, round: true),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(
          summary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          const Divider(height: 1, indent: Space.lg, endIndent: Space.lg),
          ...tiles,
        ],
      ),
    );
  }
}
