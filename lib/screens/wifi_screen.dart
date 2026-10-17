import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/save_result.dart';
import '../models/wireless_network.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/feedback.dart';
import 'router_settings_screens.dart';
import 'settings_screen.dart';
import 'setup_wizard_screen.dart';

/// Every wireless network the router reports, each with its own switch,
/// editor and password controls.
class WifiSettingsScreen extends StatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  State<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends State<WifiSettingsScreen> {
  /// Router index of the network currently being saved.
  int? _savingIndex;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RouterProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !provider.isConnected) return;
      provider.refreshWirelessSettings();
      provider.loadGuestWifiSettings();
    });
  }

  Future<void> _apply(
    RouterProvider provider,
    WirelessNetwork network,
    Future<SaveResult> Function() save,
  ) async {
    setState(() => _savingIndex = network.index);
    final pause = provider.pauseLiveUpdates('Wi-Fi save');
    try {
      final result = await save();
      if (mounted) showSaveResult(context, result);
    } finally {
      pause.release();
      if (mounted) setState(() => _savingIndex = null);
    }
  }

  Future<void> _toggle(
    RouterProvider provider,
    WirelessNetwork network,
    bool enable,
  ) async {
    final name = network.ssid.isEmpty ? network.bandLabel : '"${network.ssid}"';
    final confirmed = await confirmAction(
      context,
      title: enable
          ? 'Turn on ${network.bandLabel} Wi-Fi?'
          : 'Turn off ${network.bandLabel} Wi-Fi?',
      message: enable
          ? 'The router starts broadcasting $name with its saved name and '
                'password. Other networks restart briefly while it applies.'
          : 'Devices on $name (${network.bandLabel}) disconnect. Its name, '
                'password and settings are kept so you can turn it back on. '
                'If this phone uses this network it will lose its connection.',
      confirmLabel: enable ? 'Turn on' : 'Turn off',
      destructive: !enable,
      icon: enable ? Icons.wifi_rounded : Icons.wifi_off_rounded,
    );
    if (!confirmed || !mounted) return;
    await _apply(
      provider,
      network,
      () => provider.setWirelessNetworkEnabled(network.index, enable),
    );
  }

  Future<void> _edit(RouterProvider provider, WirelessNetwork network) async {
    final updated = await showModalBottomSheet<WirelessNetwork>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WifiEditSheet(network: network),
    );
    if (updated == null || !mounted) return;

    final renamed = updated.ssid != network.ssid;
    final newPassword =
        updated.toRouterPayload()['Password'] != null &&
        updated.toRouterPayload()['Password'] !=
            network.toRouterPayload()['Password'];
    final confirmed = await confirmAction(
      context,
      title: 'Apply Wi-Fi changes?',
      message: network.isEnabled
          ? 'The router restarts ${network.bandLabel} Wi-Fi to apply this. '
                'Devices on "${network.ssid}", possibly including this phone, '
                'disconnect and must rejoin'
                '${renamed ? ' "${updated.ssid}"' : ''}'
                '${newPassword ? ' with the new password' : ''}.'
          : 'This network is off. The new settings are saved and used when '
                'you turn it on.',
      confirmLabel: 'Apply',
      icon: Icons.wifi_rounded,
    );
    if (!confirmed || !mounted) return;
    await _apply(
      provider,
      network,
      () => provider.updateWirelessNetwork(updated),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final networks = provider.wirelessNetworksParsed;
    final connected = provider.isConnected;
    final editable = connected && _savingIndex == null;

    final enabled = networks.where((n) => n.isEnabled).toList();
    final names = enabled.map((n) => n.ssid).where((s) => s.isNotEmpty).toSet();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await provider.refreshWirelessSettings();
            if (provider.isConnected) await provider.loadGuestWifiSettings();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 120),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      kicker: 'Wireless management',
                      title: 'Wi-Fi networks',
                      subtitle: 'Edit each band, its password and availability',
                      trailing: IconButton(
                        tooltip: 'Refresh',
                        onPressed: provider.wirelessLoading || !connected
                            ? null
                            : provider.refreshWirelessSettings,
                        icon: provider.wirelessLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                      ),
                    ),
                    if (networks.isNotEmpty) ...[
                      const SizedBox(height: Space.md),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          StatusPill(
                            label:
                                '${networks.length} network${networks.length == 1 ? '' : 's'} reported',
                            tone: Tone.neutral,
                            dot: false,
                          ),
                          StatusPill(
                            label: '${enabled.length} on',
                            tone: enabled.isEmpty ? Tone.danger : Tone.success,
                          ),
                          StatusPill(
                            label:
                                '${names.length} name${names.length == 1 ? '' : 's'} broadcasting',
                            tone: Tone.info,
                            dot: false,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    ConnectionStatusBanners(
                      onOpenSetup: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SetupWizardScreen(),
                        ),
                      ),
                    ),
                    if (networks.isEmpty)
                      _emptyState(provider)
                    else ...[
                      if (provider.wirelessUpdatedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: Text(
                            'Read from the router ${formatAge(provider.wirelessUpdatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      for (final network in networks)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: WifiNetworkCard(
                            network: network,
                            saving: _savingIndex == network.index,
                            editable: editable,
                            onToggle: (on) => _toggle(provider, network, on),
                            onEdit: () => _edit(provider, network),
                          ),
                        ),
                    ],
                    _GuestCard(provider: provider),
                    const SizedBox(height: Space.md),
                    ActionTile(
                      icon: Icons.edit_note_rounded,
                      tone: Tone.info,
                      title: 'Edit both bands together',
                      subtitle: '2.4 GHz and 5 GHz names, passwords and on/off',
                      enabled: connected,
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
      ),
    );
  }

  Widget _emptyState(RouterProvider provider) {
    if (!provider.isConnected) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Router access required',
          message: 'Connect to the router to see and change Wi-Fi settings.',
        ),
      );
    }
    if (provider.wirelessLoading || !provider.wirelessLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'No Wi-Fi networks reported',
        message:
            'The router did not return its wireless list, so nothing can be '
            'changed yet.',
        action: FilledButton.icon(
          onPressed: provider.refreshWirelessSettings,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
    );
  }
}

/// Card for one router-reported wireless network.
class WifiNetworkCard extends StatefulWidget {
  const WifiNetworkCard({
    super.key,
    required this.network,
    required this.editable,
    required this.saving,
    required this.onToggle,
    required this.onEdit,
  });

  final WirelessNetwork network;
  final bool editable;
  final bool saving;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  State<WifiNetworkCard> createState() => _WifiNetworkCardState();
}

class _WifiNetworkCardState extends State<WifiNetworkCard> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.network;
    final secured = n.encrypt > 0;
    final muted = theme.colorScheme.onSurfaceVariant;
    final passwordShown = secured && n.passwordKnown && n.password.isNotEmpty;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                n.isEnabled ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                tone: n.isEnabled ? Tone.brand : Tone.neutral,
                size: 44,
                round: true,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${n.bandLabel} · network ${n.index + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.ssid.isEmpty ? 'No name set' : n.ssid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              if (widget.saving)
                const Padding(
                  padding: EdgeInsets.all(Space.md),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              else
                Semantics(
                  label: '${n.bandLabel} ${n.ssid} Wi-Fi',
                  toggled: n.isEnabled,
                  child: Switch(
                    value: n.isEnabled,
                    onChanged: widget.editable ? widget.onToggle : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: n.isEnabled ? 'Broadcasting' : 'Off · settings kept',
              tone: n.isEnabled ? Tone.success : Tone.neutral,
            ),
          ),
          const Divider(height: Space.xl),
          _detailRow(
            context,
            secured ? Icons.lock_rounded : Icons.lock_open_rounded,
            secured ? n.encryptionLabel : 'Open network (no password)',
            color: secured ? muted : context.tone(Tone.warning).foreground,
          ),
          if (secured) ...[
            const SizedBox(height: Space.sm),
            _detailRow(
              context,
              Icons.key_rounded,
              !n.passwordKnown
                  ? 'Password not reported by the router'
                  : n.password.isEmpty
                  ? 'No password set'
                  : _reveal
                  ? n.password
                  : '•' * 12,
              monospace: _reveal && passwordShown,
              trailing: passwordShown
                  ? IconButton(
                      tooltip: 'Copy password',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: n.password));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password copied')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 20),
                    )
                  : null,
            ),
          ],
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'Edit',
                  icon: Icons.edit_rounded,
                  onPressed: widget.editable ? widget.onEdit : null,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: PillButton(
                  label: _reveal ? 'Hide' : 'Show',
                  icon: _reveal
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  onPressed: passwordShown
                      ? () => setState(() => _reveal = !_reveal)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
    bool monospace = false,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: monospace ? 'monospace' : null,
              letterSpacing: monospace ? 0.5 : null,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final guest = provider.guestWifi;
    final theme = Theme.of(context);
    final on = guest != null && '${guest['Enable']}' == '1';
    final ssid = '${guest?['Ssid'] ?? ''}'.trim();
    return PanelCard(
      child: Row(
        children: [
          IconBadge(
            Icons.wifi_tethering_rounded,
            tone: on ? Tone.accent : Tone.neutral,
            size: 44,
            round: true,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Guest Wi-Fi', style: theme.textTheme.titleMedium),
                Text(
                  guest == null
                      ? 'Separate access for visitors'
                      : on
                      ? (ssid.isEmpty ? 'On' : 'On · $ssid')
                      : 'Off',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PillButton(
            label: 'Manage',
            onPressed: provider.isConnected
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const GuestWifiSettingsScreen(),
                    ),
                  )
                : null,
          ),
        ],
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
  late final _password = TextEditingController(
    text: widget.network.passwordKnown ? widget.network.password : '',
  );
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
    final updated = n.copyWith(
      ssid: _ssid.text.trim(),
      password: _password.text,
    );
    Navigator.pop(context, updated.hasEdits ? updated : null);
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
                'Edit ${n.bandLabel} network',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Security: ${n.encryptionLabel} · '
                '${n.isEnabled ? 'currently on' : 'currently off'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _ssid,
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
                  helperText: !secured
                      ? 'Change the security type on the router to add a password'
                      : n.passwordKnown
                      ? '8–63 characters, or a 64-digit hex key'
                      : 'The router did not report the current password; '
                            'enter a new one to save this network',
                  helperMaxLines: 2,
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
              InfoBanner(
                tone: Tone.warning,
                icon: Icons.info_outline_rounded,
                title: n.isEnabled
                    ? 'Devices will reconnect'
                    : 'Saved for when it is turned on',
                message: n.isEnabled
                    ? 'Applying restarts this Wi-Fi network. The app confirms '
                          'the new settings once it is connected again.'
                    : 'This network stays off; on/off is changed with the '
                          'switch on its card.',
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
