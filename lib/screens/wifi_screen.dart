import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/wireless_network.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/feedback.dart';
import 'router_settings_screens.dart';
import 'settings_screen.dart';
import 'setup_wizard_screen.dart';

class WifiSettingsScreen extends StatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  State<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends State<WifiSettingsScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<RouterProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && provider.isConnected) provider.refreshWirelessSettings();
    });
  }

  Future<void> _edit(RouterProvider provider, WirelessNetwork network) async {
    final updated = await showModalBottomSheet<WirelessNetwork>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WifiEditSheet(network: network),
    );
    if (updated == null || !mounted) return;

    final confirmed = await confirmAction(
      context,
      title: 'Apply Wi-Fi changes?',
      message:
          'The router restarts ${network.bandLabel} Wi-Fi to apply this. '
          'Devices on "${network.ssid}", possibly including this phone, '
          'disconnect and must rejoin${updated.ssid != network.ssid ? ' "${updated.ssid}"' : ''}'
          '${updated.password != network.password ? ' with the new password' : ''}.',
      confirmLabel: 'Apply',
      icon: Icons.wifi_rounded,
    );
    if (!confirmed || !mounted) return;

    final pause = provider.pauseLiveUpdates('Wi-Fi save');
    try {
      final result = await provider.updateWirelessNetwork(updated);
      if (mounted) showSaveResult(context, result);
    } finally {
      pause.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final networks = provider.wirelessNetworksParsed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.wirelessLoading || !provider.isConnected
                ? null
                : provider.refreshWirelessSettings,
            icon: provider.wirelessLoading
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
        onRefresh: provider.refreshWirelessSettings,
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
                  ConnectionStatusBanners(
                    onOpenSetup: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SetupWizardScreen(),
                      ),
                    ),
                  ),
                  if (!provider.isConnected && networks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: EmptyState(
                        icon: Icons.lock_outline_rounded,
                        title: 'Router access required',
                        message:
                            'Connect to the router to see and change Wi-Fi settings.',
                      ),
                    )
                  else if (networks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child:
                          provider.wirelessLoading || !provider.wirelessLoaded
                          ? const Center(child: CircularProgressIndicator())
                          : EmptyState(
                              icon: Icons.wifi_off_rounded,
                              title: 'No Wi-Fi networks reported',
                              message:
                                  'The router did not return its wireless list.',
                              action: FilledButton.icon(
                                onPressed: provider.refreshWirelessSettings,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try again'),
                              ),
                            ),
                    )
                  else ...[
                    const SectionLabel('Wireless networks'),
                    for (final network in networks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: _WifiNetworkCard(
                          network: network,
                          editable: provider.isConnected,
                          onEdit: () => _edit(provider, network),
                        ),
                      ),
                  ],
                  const SectionLabel('More Wi-Fi settings'),
                  Card(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.wifi_tethering_rounded,
                          tone: Tone.success,
                          title: 'Guest Wi-Fi',
                          subtitle: 'Separate network for visitors',
                          enabled: provider.isConnected,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GuestWifiSettingsScreen(),
                            ),
                          ),
                        ),
                        const Divider(indent: 72),
                        SettingsTile(
                          icon: Icons.edit_note_rounded,
                          tone: Tone.info,
                          title: 'Edit both bands together',
                          subtitle: 'Names, passwords and on/off per band',
                          enabled: provider.isConnected,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WifiSettingsDetailScreen(),
                            ),
                          ),
                        ),
                      ],
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
}

class _WifiNetworkCard extends StatefulWidget {
  const _WifiNetworkCard({
    required this.network,
    required this.editable,
    required this.onEdit,
  });

  final WirelessNetwork network;
  final bool editable;
  final VoidCallback onEdit;

  @override
  State<_WifiNetworkCard> createState() => _WifiNetworkCardState();
}

class _WifiNetworkCardState extends State<_WifiNetworkCard> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.network;
    final secured = n.encrypt > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  n.isEnabled ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  tone: n.isEnabled ? Tone.info : Tone.neutral,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.ssid.isEmpty ? 'Not configured' : n.ssid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        n.bandLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: n.isEnabled ? 'On' : 'Off',
                  tone: n.isEnabled ? Tone.success : Tone.neutral,
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Icon(
                  secured ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 18,
                  color: secured
                      ? theme.colorScheme.onSurfaceVariant
                      : context.tone(Tone.warning).foreground,
                ),
                const SizedBox(width: Space.sm),
                Text(
                  secured ? n.encryptionLabel : 'Open network (no password)',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            if (secured && n.password.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  Icon(
                    Icons.key_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      _reveal ? n.password : '•' * 10,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: _reveal ? 'monospace' : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _reveal ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _reveal = !_reveal),
                    icon: Icon(
                      _reveal
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy password',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: n.password));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: widget.editable ? widget.onEdit : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits one wireless network. Pops the updated network, or null.
class WifiEditSheet extends StatefulWidget {
  const WifiEditSheet({super.key, required this.network});

  final WirelessNetwork network;

  @override
  State<WifiEditSheet> createState() => _WifiEditSheetState();
}

class _WifiEditSheetState extends State<WifiEditSheet> {
  final _form = GlobalKey<FormState>();
  late final _ssid = TextEditingController(text: widget.network.ssid);
  late final _password = TextEditingController(text: widget.network.password);
  bool _showPassword = false;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final n = widget.network;
    final ssid = _ssid.text.trim();
    final password = _password.text;
    if (ssid == n.ssid && password == n.password) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      n.copyWith(ssid: ssid, password: password, create: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.network;
    final secured = n.encrypt > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit ${n.bandLabel} Wi-Fi',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Security: ${n.encryptionLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _ssid,
                autofocus: false,
                textInputAction: TextInputAction.next,
                maxLength: 32,
                decoration: const InputDecoration(
                  labelText: 'Network name (SSID)',
                  prefixIcon: Icon(Icons.wifi_rounded),
                ),
                validator: Validators.ssid,
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                enabled: secured,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: secured ? 'Password' : 'Password (open network)',
                  helperText: secured
                      ? '8–63 characters, or a 64-digit hex key'
                      : 'Change the security type on the router to add a password',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
                validator: (v) => Validators.wifiPassword(v, secured: secured),
              ),
              const SizedBox(height: Space.lg),
              const InfoBanner(
                tone: Tone.warning,
                icon: Icons.info_outline_rounded,
                title: 'Devices will reconnect',
                message:
                    'Applying restarts this Wi-Fi network. The app confirms '
                    'the new settings once it is connected again.',
              ),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
