import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/save_result.dart';
import '../models/wifi_inventory.dart';
import '../models/wireless_network.dart';
import '../providers/router_provider.dart';
import '../services/wifi_scan.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/feedback.dart';
import '../widgets/hub_widgets.dart' show KvRow;
import 'router_settings_screens.dart';
import 'settings_screen.dart';
import 'setup_wizard_screen.dart';

/// The Wi-Fi network manager: the household network as one logical network,
/// every network the router or this phone can see, and the per-entry router
/// controls under "Advanced".
class WifiSettingsScreen extends StatefulWidget {
  const WifiSettingsScreen({
    super.key,
    this.scanner = const PlatformWifiScanner(),
  });

  /// Reads the phone's own Wi-Fi scan (observed networks).
  final WifiScanner scanner;

  @override
  State<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends State<WifiSettingsScreen> {
  /// Router index of the network currently being saved.
  int? _savingIndex;
  bool _advancedOpen = false;

  /// Entry turned off by "Consolidate", offered for re-enabling.
  int? _rollbackIndex;
  WifiScanSnapshot? _scan;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RouterProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runScan();
      if (!provider.isConnected) return;
      provider.refreshWirelessSettings();
      provider.loadGuestWifiSettings();
    });
  }

  /// Never prompts for permission unless [request] (a user tap).
  Future<void> _runScan({bool request = false}) async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final snapshot = await widget.scanner.scan(requestPermission: request);
    if (!mounted) return;
    setState(() {
      _scan = snapshot;
      _scanning = false;
    });
  }

  Future<SaveResult?> _apply(
    RouterProvider provider,
    WirelessNetwork network,
    Future<SaveResult> Function() save,
  ) async {
    setState(() => _savingIndex = network.index);
    final pause = provider.pauseLiveUpdates('Wi-Fi save');
    try {
      final result = await save();
      if (mounted) showSaveResult(context, result);
      return result;
    } finally {
      pause.release();
      if (mounted) setState(() => _savingIndex = null);
    }
  }

  static String _name(WirelessNetwork n) =>
      n.ssid.isEmpty ? n.entryLabel : '"${n.ssid}" (entry ${n.index + 1})';

  /// Explains why an open network cannot be turned on and offers the editor.
  Future<void> _explainUnsecured(
    RouterProvider provider,
    WirelessNetwork network,
  ) async {
    final edit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.lock_open_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Secure this network first'),
        content: const Text(unsecuredEnableMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set WPA2 & password'),
          ),
        ],
      ),
    );
    if (edit == true && mounted) await _edit(provider, network);
  }

  Future<SaveResult?> _toggle(
    RouterProvider provider,
    WirelessNetwork network,
    bool enable,
  ) async {
    if (enable && network.isUnsecured) {
      await _explainUnsecured(provider, network);
      return null;
    }
    final name = _name(network);
    final confirmed = await confirmAction(
      context,
      title: enable ? 'Turn on $name?' : 'Turn off $name?',
      message: enable
          ? 'The router starts broadcasting $name with its saved name and '
                'password on 2.4 GHz and 5 GHz. Other networks restart '
                'briefly while it applies.'
          : 'Devices on $name disconnect. Its name, password and settings '
                'are kept so you can turn it back on. If this phone uses this '
                'network it will lose its connection.',
      confirmLabel: enable ? 'Turn on' : 'Turn off',
      destructive: !enable,
      icon: enable ? Icons.wifi_rounded : Icons.wifi_off_rounded,
    );
    if (!confirmed || !mounted) return null;
    return _apply(
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
          ? 'The router restarts ${network.entryLabel} to apply this. '
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

  /// Guided: review → confirm what stays → approve → write with read-back
  /// → offer rollback. Never runs on its own.
  Future<void> _consolidate(
    RouterProvider provider,
    DuplicateGroup group,
  ) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ConsolidateSheet(group: group),
    );
    if (proceed != true || !mounted) return;
    final retire = group.retire;
    final keep = group.keep;
    final approved = await confirmAction(
      context,
      title: 'Turn off ${retire.entryLabel.toLowerCase()}?',
      message:
          'Devices currently connected through entry ${retire.index + 1} will '
          'briefly disconnect and reconnect to entry ${keep.index + 1} '
          '("${keep.ssid}", ${keep.securityLabel}, same password). This phone '
          'may reconnect too. Entry ${retire.index + 1} keeps its settings, '
          'so you can turn it back on afterwards.',
      confirmLabel: 'Turn off entry ${retire.index + 1}',
      destructive: true,
      icon: Icons.merge_type_rounded,
    );
    if (!approved || !mounted) return;
    final result = await _apply(
      provider,
      retire,
      () => provider.setWirelessNetworkEnabled(retire.index, false),
    );
    if (mounted && result != null && result.accepted) {
      setState(() => _rollbackIndex = retire.index);
    }
  }

  Future<void> _rollback(RouterProvider provider) async {
    final network = provider.wirelessNetworksParsed
        .where((n) => n.index == _rollbackIndex)
        .firstOrNull;
    if (network == null) {
      setState(() => _rollbackIndex = null);
      return;
    }
    final result = await _toggle(provider, network, true);
    if (mounted && result != null && result.accepted) {
      setState(() => _rollbackIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final networks = provider.wirelessNetworksParsed;
    final connected = provider.isConnected;
    final editable = connected && _savingIndex == null;
    final theme = Theme.of(context);

    final enabled = networks.where((n) => n.isEnabled).toList();
    final names = enabled.map((n) => n.ssid).where((s) => s.isNotEmpty).toSet();
    final primary = WifiInventory.primary(networks);
    final duplicates = WifiInventory.duplicates(networks);
    final inventory = WifiInventory.build(
      networks: networks,
      guest: provider.guestWifi,
      scan: _scan,
    );
    final openOn = enabled.where((n) => n.isUnsecured).toList();
    final rollback = networks
        .where((n) => n.index == _rollbackIndex && !n.isEnabled)
        .firstOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await provider.refreshWirelessSettings();
            if (provider.isConnected) await provider.loadGuestWifiSettings();
            await _runScan();
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
                      subtitle: 'Your household network and everything on air',
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
                                '${networks.length} network${networks.length == 1 ? '' : 's'}',
                            tone: Tone.neutral,
                            dot: false,
                          ),
                          StatusPill(
                            label: '${enabled.length} on',
                            tone: enabled.isEmpty ? Tone.danger : Tone.success,
                          ),
                          StatusPill(
                            label:
                                '${names.length} name${names.length == 1 ? '' : 's'} live',
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
                      if (primary != null)
                        PrimaryNetworkCard(
                          primary: primary,
                          provider: provider,
                          duplicates: duplicates,
                          radios: {
                            for (final row in inventory)
                              if (row.network != null &&
                                  primary.entries.contains(row.network))
                                for (final r in row.radios) r.bssid: r,
                          }.values.toList(),
                        )
                      else
                        const InfoBanner(
                          tone: Tone.danger,
                          icon: Icons.wifi_off_rounded,
                          title: 'No household network is on',
                          message:
                              'The router reports every Wi-Fi entry as off. '
                              'Turn one on under Advanced.',
                        ),
                      for (final n in openOn) ...[
                        const SizedBox(height: Space.md),
                        InfoBanner(
                          tone: Tone.danger,
                          icon: Icons.lock_open_rounded,
                          title: '${_name(n)} is on without a password',
                          message:
                              'Anyone nearby can join it. Set WPA2 (AES) and '
                              'a password.',
                          action: TextButton(
                            onPressed: editable
                                ? () => _edit(provider, n)
                                : null,
                            child: const Text('Secure it'),
                          ),
                        ),
                      ],
                      for (final group in duplicates) ...[
                        const SizedBox(height: Space.md),
                        InfoBanner(
                          key: ValueKey('wifi-duplicate-${group.ssid}'),
                          tone: Tone.warning,
                          icon: Icons.copy_all_rounded,
                          title: 'Duplicate configuration',
                          message:
                              'Router entries ${group.entriesLabel} both '
                              'broadcast "${group.ssid}" with '
                              '${group.securityLabel}. Both are active and '
                              'real clients may use either one; together '
                              'they add radio overhead without adding '
                              'coverage.',
                          action: TextButton.icon(
                            key: const ValueKey('wifi-consolidate'),
                            onPressed: editable
                                ? () => _consolidate(provider, group)
                                : null,
                            icon: const Icon(Icons.merge_type_rounded),
                            label: const Text('Consolidate…'),
                          ),
                        ),
                      ],
                      if (rollback != null) ...[
                        const SizedBox(height: Space.md),
                        InfoBanner(
                          tone: Tone.info,
                          icon: Icons.undo_rounded,
                          title: '${rollback.entryLabel} is off',
                          message:
                              'Consolidated "${rollback.ssid}". If devices '
                              'have trouble reconnecting, turn it back on.',
                          onDismiss: () =>
                              setState(() => _rollbackIndex = null),
                          action: TextButton(
                            key: const ValueKey('wifi-rollback'),
                            onPressed: editable
                                ? () => _rollback(provider)
                                : null,
                            child: Text(
                              'Re-enable entry ${rollback.index + 1}',
                            ),
                          ),
                        ),
                      ],
                      SectionLabel(
                        'All networks',
                        trailing: IconButton(
                          key: const ValueKey('wifi-scan-refresh'),
                          tooltip: 'Scan nearby networks',
                          visualDensity: VisualDensity.compact,
                          onPressed: _scanning
                              ? null
                              : () => _runScan(
                                  request:
                                      _scan?.status ==
                                      WifiScanStatus.permissionDenied,
                                ),
                          icon: _scanning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.radar_rounded),
                        ),
                      ),
                      _ScanStatus(
                        scan: _scan,
                        scanning: _scanning,
                        observed: inventory.any(
                          (r) =>
                              r.kind == NetworkKind.observed ||
                              r.kind == NetworkKind.meshInternal ||
                              r.radios.isNotEmpty,
                        ),
                        onAllow: () => _runScan(request: true),
                      ),
                      PanelCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                          vertical: Space.sm,
                        ),
                        child: Column(
                          children: [
                            for (final (i, row) in inventory.indexed)
                              InventoryTile(
                                entry: row,
                                last: i == inventory.length - 1,
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.md),
                    _AdvancedHeader(
                      open: _advancedOpen,
                      onTap: () =>
                          setState(() => _advancedOpen = !_advancedOpen),
                    ),
                    if (_advancedOpen) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: Text(
                          'Each router entry is its own dual-band network '
                          '(2.4 GHz and 5 GHz). Changes here apply to one '
                          'entry at a time and are confirmed by reading the '
                          'router back.'
                          '${provider.wirelessUpdatedAt == null ? '' : ' Read from the router ${formatAge(provider.wirelessUpdatedAt)}.'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
                      _GuestCard(provider: provider),
                      const SizedBox(height: Space.md),
                      ActionTile(
                        icon: Icons.edit_note_rounded,
                        tone: Tone.info,
                        title: 'Edit primary profiles together',
                        subtitle:
                            'Separate router entries, names, passwords and on/off',
                        enabled: connected,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WifiSettingsDetailScreen(),
                          ),
                        ),
                      ),
                    ],
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

class _AdvancedHeader extends StatelessWidget {
  const _AdvancedHeader({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: const ValueKey('wifi-advanced-toggle'),
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xs,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            Icon(
              Icons.tune_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Advanced (per-configuration)',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              semanticLabel: open ? 'Hide advanced' : 'Show advanced',
            ),
          ],
        ),
      ),
    );
  }
}

/// The household network as one logical network.
class PrimaryNetworkCard extends StatefulWidget {
  const PrimaryNetworkCard({
    super.key,
    required this.primary,
    required this.provider,
    required this.duplicates,
    this.radios = const [],
  });

  final PrimaryNetwork primary;
  final RouterProvider provider;
  final List<DuplicateGroup> duplicates;

  /// Router radios this phone heard broadcasting the primary SSID.
  final List<WifiScanResult> radios;

  @override
  State<PrimaryNetworkCard> createState() => _PrimaryNetworkCardState();
}

class _PrimaryNetworkCardState extends State<PrimaryNetworkCard> {
  bool _reveal = false;
  PrimaryNetwork get primary => widget.primary;
  RouterProvider get provider => widget.provider;
  List<DuplicateGroup> get duplicates => widget.duplicates;
  List<WifiScanResult> get radios => widget.radios;

  (String, Tone) get _health {
    if (!provider.isConnected) return ('Router not connected', Tone.warning);
    if (primary.anyUnsecured) return ('Unsecured — set WPA2', Tone.danger);
    if (provider.hasInternetStatus && !provider.internetConnected) {
      return ('No internet reported by the router', Tone.danger);
    }
    if (duplicates.any((g) => g.ssid == primary.ssid)) {
      return ('Check duplicate entries', Tone.warning);
    }
    if (provider.liveDataStale) {
      return ('Router data is not live', Tone.warning);
    }
    return ('No reported fault', Tone.success);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (health, healthTone) = _health;
    final devices = provider.knownOnlineDeviceCount;
    final devicesAt = provider.devicesUpdatedAt ?? provider.telemetryUpdatedAt;
    final guests = provider.reportedGuestDeviceCount;
    final nodesKnown =
        provider.nodes.isNotEmpty || provider.connectionInfo != null;
    final bandsHeard = {for (final r in radios) r.band}.toList()..sort();

    final rows = <(String, String, Tone?)>[
      (
        'Status',
        'On · ${primary.entriesLabel.replaceFirst('Router entries', 'entries').replaceFirst('Router entry', 'entry')}',
        Tone.success,
      ),
      (
        'Security',
        primary.securityLabel,
        primary.anyUnsecured ? Tone.danger : null,
      ),
      (
        'Bands',
        bandsHeard.isEmpty
            ? '2.4 GHz · 5 GHz'
            : '2.4 GHz · 5 GHz · heard here on ${bandsHeard.join(', ')} '
                  '(${radios.length} BSSIDs; profiles may share a radio)',
        null,
      ),
      (
        'Devices online',
        devices == null
            ? 'Not reported yet'
            : [
                '$devices',
                if (guests > 0) '$guests on guest',
                'all router clients; per-SSID count unavailable',
                if (devicesAt != null) formatAge(devicesAt),
              ].join(' · '),
        null,
      ),
      (
        'TaoTronics access points',
        !nodesKnown
            ? 'Not reported yet'
            : [
                '${provider.reportedOnlineNodeCount} of '
                    '${provider.reportedTotalNodeCount} online',
                if (provider.nodesUpdatedAt != null)
                  formatAge(provider.nodesUpdatedAt),
              ].join(' · '),
        null,
      ),
      ('Health', health, healthTone),
    ];

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                Icons.wifi_rounded,
                tone: healthTone == Tone.success ? Tone.brand : healthTone,
                size: 48,
                round: true,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primary.ssid,
                      key: const ValueKey('wifi-primary-ssid'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      'Main Household Network',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Flexible(
                child: StatusPill(label: health, tone: healthTone),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          for (final (i, (label, value, tone)) in rows.indexed)
            KvRow(label, value, tone: tone, last: i == rows.length - 1),
          const SizedBox(height: Space.sm),
          if (!primary.anyUnsecured &&
              primary.entries.every((e) => e.passwordKnown) &&
              primary.entries.map((e) => e.password).toSet().length == 1)
            Row(
              children: [
                const Icon(Icons.key_outlined, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _reveal ? primary.entries.first.password : '••••••••••••',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _reveal = !_reveal),
                  child: Text(_reveal ? 'Hide' : 'Show'),
                ),
              ],
            )
          else
            Text(
              primary.anyUnsecured
                  ? 'Unsecured network — no password protection.'
                  : 'Passwords differ or are not reported. Inspect each profile in Advanced.',
            ),
          const SizedBox(height: Space.sm),
          Text(
            'Built from what the router reports; nothing is changed to show '
            'it. Device counts cover every client of the router.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// Scan state for observed networks: permission, Wi-Fi off, unsupported.
class _ScanStatus extends StatelessWidget {
  const _ScanStatus({
    required this.scan,
    required this.scanning,
    required this.observed,
    required this.onAllow,
  });

  final WifiScanSnapshot? scan;
  final bool scanning;
  final bool observed;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final s = scan;
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    if (s == null) {
      return scanning ? note('Scanning nearby networks…') : const SizedBox();
    }
    switch (s.status) {
      case WifiScanStatus.permissionDenied:
      case WifiScanStatus.permissionBlocked:
        final blocked = s.status == WifiScanStatus.permissionBlocked;
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: InfoBanner(
            key: const ValueKey('wifi-scan-permission'),
            tone: Tone.info,
            icon: Icons.location_off_rounded,
            title: 'Location permission needed for nearby networks',
            message: blocked
                ? s.message ??
                      'Android shares Wi-Fi scan results only with location '
                          'access. Allow it for TT Router in system settings to '
                          'list networks the router API does not expose. '
                          'Router-configured networks below are unaffected.'
                : 'Android shares Wi-Fi scan results only with location '
                      'access. Without it, networks the router API does not '
                      'expose are not listed. Router-configured networks '
                      'below are unaffected.',
            action: blocked
                ? null
                : TextButton(
                    key: const ValueKey('wifi-scan-allow'),
                    onPressed: scanning ? null : onAllow,
                    child: const Text('Allow and scan'),
                  ),
          ),
        );
      case WifiScanStatus.wifiOff:
        return note(
          'Wi-Fi is off on this phone, so nearby networks are not listed.',
        );
      case WifiScanStatus.unsupported:
      case WifiScanStatus.failed:
        return note(s.message ?? 'Nearby networks could not be scanned.');
      case WifiScanStatus.ok:
        return note(
          observed
              ? 'Nearby networks heard by this phone ${formatAge(s.at)}, '
                    'limited to the router\'s own radios.'
              : 'This phone is not joined to the router, so nearby networks '
                    'cannot be matched to it. Join the household network '
                    'and scan again.',
        );
    }
  }
}

/// One row of the "All networks" list.
class InventoryTile extends StatelessWidget {
  const InventoryTile({super.key, required this.entry, this.last = false});

  final InventoryEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (icon, tone) = switch (entry.kind) {
      NetworkKind.configured => (Icons.wifi_rounded, Tone.success),
      NetworkKind.disabled => (Icons.wifi_off_rounded, Tone.neutral),
      NetworkKind.guest => (Icons.wifi_tethering_rounded, Tone.accent),
      NetworkKind.observed => (Icons.visibility_rounded, Tone.info),
      NetworkKind.meshInternal => (Icons.hub_rounded, Tone.neutral),
      NetworkKind.unknown => (Icons.help_outline_rounded, Tone.warning),
    };
    final heard = entry.radios.isEmpty
        ? null
        : 'Heard on ${entry.bandsSeen.join(', ')} · '
              '${entry.radios.length} radio${entry.radios.length == 1 ? '' : 's'}'
              ' · strongest ${entry.radios.map((r) => r.level).reduce((a, b) => a > b ? a : b)} dBm';
    return Container(
      key: ValueKey('wifi-inventory-${entry.kind.name}-${entry.name}'),
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, tone: tone, size: 36, round: true),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(label: entry.kind.label, tone: tone, dot: false),
                    if (entry.unsecured)
                      const StatusPill(
                        label: 'Unsecured',
                        tone: Tone.danger,
                        icon: Icons.lock_open_rounded,
                      ),
                  ],
                ),
                if (entry.note != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    entry.note!,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                if (heard != null)
                  Text(
                    heard,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Steps 1–2 of consolidation: what turns off, and confirming what stays.
class _ConsolidateSheet extends StatefulWidget {
  const _ConsolidateSheet({required this.group});

  final DuplicateGroup group;

  @override
  State<_ConsolidateSheet> createState() => _ConsolidateSheetState();
}

class _ConsolidateSheetState extends State<_ConsolidateSheet> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final g = widget.group;
    Widget step(
      String number,
      String title,
      WirelessNetwork n,
      String state,
      Tone tone,
    ) => Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.tone(tone).container,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: context.tone(tone).foreground,
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.surface,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: context.tone(tone).onContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${n.entryLabel} · "${n.ssid}" · ${n.securityLabel} · $state',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.tone(tone).onContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Consolidate "${g.ssid}"', style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              'Router entries ${g.entriesLabel} broadcast the same network. '
              'Keeping one removes the duplicate; nothing changes until you '
              'approve it.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.lg),
            step(
              '1',
              'Will be turned off',
              g.retire,
              'currently on → off (settings kept)',
              Tone.warning,
            ),
            const SizedBox(height: Space.sm),
            step('2', 'Stays on', g.keep, 'on', Tone.success),
            const SizedBox(height: Space.sm),
            CheckboxListTile(
              key: const ValueKey('consolidate-confirm-remaining'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              title: Text(
                '${g.keep.entryLabel} keeps the name "${g.keep.ssid}" and '
                '${g.keep.securityLabel}',
              ),
              subtitle: const Text(
                'Devices that used the other entry rejoin this one with the '
                'same password.',
              ),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('consolidate-continue'),
                    onPressed: _checked
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],
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
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.network;
    final secured = !n.isUnsecured;
    final muted = theme.colorScheme.onSurfaceVariant;
    final passwordShown = secured && n.passwordKnown && n.password.isNotEmpty;

    return PanelCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                Space.lg,
                Space.md,
                Space.lg,
              ),
              child: Row(
                children: [
                  IconBadge(
                    n.isEnabled ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    tone: n.isEnabled ? Tone.brand : Tone.neutral,
                    size: 42,
                    round: true,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.ssid.isEmpty ? 'No name set' : n.ssid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            StatusPill(
                              label: n.entryLabel,
                              tone: Tone.neutral,
                              dot: false,
                            ),
                            StatusPill(
                              label: n.isEnabled ? 'On' : 'Off',
                              tone: n.isEnabled ? Tone.success : Tone.neutral,
                            ),
                            if (n.isUnsecured)
                              const StatusPill(
                                label: 'Unsecured',
                                tone: Tone.danger,
                                icon: Icons.lock_open_rounded,
                              ),
                          ],
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
                      label: '${n.entryLabel} ${n.ssid} Wi-Fi',
                      toggled: n.isEnabled,
                      child: Switch(
                        value: n.isEnabled,
                        onChanged: widget.editable ? widget.onToggle : null,
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: muted,
                    semanticLabel: _expanded ? 'Hide details' : 'Show details',
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: Space.md),
                        _detailRow(
                          context,
                          secured
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          secured
                              ? n.encryptionLabel
                              : 'Unsecured: open network (no password)',
                          color: secured
                              ? muted
                              : context.tone(Tone.warning).foreground,
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
                                      Clipboard.setData(
                                        ClipboardData(text: n.password),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Password copied'),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 20,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                        const SizedBox(height: Space.sm),
                        Text(
                          '${n.entryLabel} · broadcasts on 2.4 GHz and 5 GHz',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                label: 'Edit',
                                icon: Icons.edit_rounded,
                                onPressed: widget.editable
                                    ? widget.onEdit
                                    : null,
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
                  ),
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
  late bool _clientIsolation = widget.network.staIsolate == 1;
  late bool _networkIsolation = widget.network.ssidIsolate == 1;

  /// Router `Encrypt` modes offered for a secured network. Weaker modes
  /// (none, WEP, WPA-only) are never offered. The router's `Encrypt=5`
  /// ("WPA3") is deliberately absent: tested 2026-10-18 on the TT-ND001, the
  /// router stored it as an unsecured network (read-back: no password,
  /// secured=false), so offering it would create open Wi-Fi.
  static const securityModes = <int, String>{
    3: 'WPA2 (AES)',
    4: 'WPA/WPA2 mixed',
  };
  late int _encrypt = widget.network.encrypt;

  /// The network will carry a password after saving.
  bool get _securing => _encrypt != 0 && _encrypt != 5;

  /// Restoring WPA2 on a network the router currently stores as open.
  bool get _restoring => widget.network.isUnsecured && _securing;

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
      encrypt: securityModes.containsKey(_encrypt) ? _encrypt : null,
      staIsolate: n.rawData.containsKey('StaIsolate')
          ? (_clientIsolation ? 1 : 0)
          : null,
      ssidIsolate: n.rawData.containsKey('SsidIsolate')
          ? (_networkIsolation ? 1 : 0)
          : null,
    );
    Navigator.pop(context, updated.hasEdits ? updated : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.network;
    final secured = _securing;
    final showSelector = n.isUnsecured || securityModes.containsKey(n.encrypt);

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
                'Edit ${n.entryLabel.toLowerCase()}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Security: ${n.securityLabel} · '
                '${n.isEnabled ? 'currently on' : 'currently off'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (n.isUnsecured) ...[
                const SizedBox(height: Space.md),
                const InfoBanner(
                  tone: Tone.danger,
                  icon: Icons.lock_open_rounded,
                  title: 'This network has no password',
                  message:
                      'Choose WPA2 (AES) below and enter a new password to '
                      'secure it before it is ever turned on.',
                ),
              ],
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
                  labelText: secured
                      ? (_restoring ? 'New password' : 'Password')
                      : 'Password (open network)',
                  helperText: !secured
                      ? 'Choose WPA2 (AES) under Security to add a password'
                      : _restoring
                      ? 'Required: 8–63 characters, or a 64-digit hex key'
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
              if (showSelector) ...[
                const SizedBox(height: Space.sm),
                DropdownButtonFormField<int>(
                  key: const ValueKey('wifi-security-select'),
                  isExpanded: true,
                  initialValue: _encrypt,
                  decoration: const InputDecoration(
                    labelText: 'Security',
                    prefixIcon: Icon(Icons.shield_outlined),
                  ),
                  items: [
                    // The current open state is shown, never offered as a
                    // new choice: picking it changes nothing.
                    if (n.isUnsecured)
                      DropdownMenuItem(
                        value: n.encrypt,
                        child: const Text('Open — no password (current)'),
                      ),
                    for (final e in securityModes.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _encrypt = v ?? _encrypt),
                ),
                if (_encrypt == 4 && n.encrypt != 4)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      'Mixed mode also accepts WPA1 clients. Keep WPA2 unless '
                      'an old device needs it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: Space.lg),
              if (n.rawData.containsKey('StaIsolate'))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Client isolation'),
                  subtitle: const Text(
                    'Router-reported StaIsolate; restrict communication between wireless clients.',
                  ),
                  value: _clientIsolation,
                  onChanged: (v) => setState(() => _clientIsolation = v),
                ),
              if (n.rawData.containsKey('SsidIsolate'))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Network isolation'),
                  subtitle: const Text(
                    'Router-reported SsidIsolate; kept independent for each profile.',
                  ),
                  value: _networkIsolation,
                  onChanged: (v) => setState(() => _networkIsolation = v),
                ),
              const Text(
                'Channels, channel width and SSID hiding are not exposed by the verified local API. No speculative writes are offered.',
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
