import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/save_result.dart';
import '../providers/router_provider.dart';
import '../services/router_certificate_verifier.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/feedback.dart';
import '../widgets/home_widgets.dart';
import 'diagnostics_screen.dart';
import 'discovery_screen.dart';
import 'home_screen.dart';
import 'nodes_screen.dart';
import 'router_settings_screens.dart';
import 'settings_screen.dart';
import 'setup_wizard_screen.dart';

/// Home dashboard: router status, live activity, Wi-Fi networks, health
/// and quick controls. Every value comes from the router; missing or old
/// values are labelled as such.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final connected = provider.isConnected;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;

    final primary = <Widget>[
      RouterCard(
        provider: provider,
        onOpenDevices: () =>
            HomeNavigation.maybeOf(context)?.select(HomeTab.devices),
      ),
      const SectionLabel('Network activity'),
      _ActivityRow(provider: provider),
      const SectionLabel('Wi-Fi networks'),
      _WifiSummary(provider: provider),
    ];
    final secondary = <Widget>[
      const SectionLabel('Quick controls'),
      _QuickControls(provider: provider),
      const SizedBox(height: Space.md),
      _MoreActions(provider: provider),
      const SectionLabel('Insights & health'),
      InsightsPanel(provider: provider),
      const SizedBox(height: Space.md),
      _HealthPanel(provider: provider),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: provider.refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 120),
            children: [
              ContentWidth(
                maxWidth: wide ? 1100 : Breakpoints.contentMaxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(provider: provider),
                    const SizedBox(height: Space.lg),
                    ConnectionStatusBanners(
                      onOpenSetup: () => _openSetup(context),
                    ),
                    if (!connected) ...[
                      _SetupCard(provider: provider),
                      const SizedBox(height: Space.md),
                    ],
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: primary)),
                          const SizedBox(width: Space.xl),
                          Expanded(child: Column(children: secondary)),
                        ],
                      )
                    else ...[
                      ...primary,
                      ...secondary,
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
}

void _openSetup(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
  );
}

void _openDiagnostics(BuildContext context, RouterProvider provider) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DiagnosticsScreen(
        routerReachable: provider.isNetworkReachable,
        mqttPortOpen: provider.isMqttPortOpen,
      ),
    ),
  );
}

void _push(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

/// Runs [action] when connected; otherwise explains that pairing is needed.
void _whenConnected(
  BuildContext context,
  RouterProvider provider,
  VoidCallback action,
) {
  if (provider.isConnected) {
    action();
    return;
  }
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: const Text('Router access required'),
      content: Text(
        provider.isReconnecting
            ? 'The app is reconnecting to your router. Try again in a moment.'
            : 'Join the router Wi-Fi and pair this phone to use this feature.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
        if (!provider.isReconnecting)
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openSetup(context);
            },
            child: const Text('Set up or pair'),
          ),
      ],
    ),
  );
}

Future<void> _restart(BuildContext context, RouterProvider provider) async {
  if (!provider.isConnected) {
    _whenConnected(context, provider, () {});
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

class _Header extends StatelessWidget {
  const _Header({required this.provider});

  final RouterProvider provider;

  Future<void> _logout(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Log out of this router?',
      message:
          'The app disconnects and returns to discovery. Your pairing stays '
          'saved, so you can reconnect later.',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await provider.logout();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final (label, tone) = connected
        ? ('Connected', Tone.success)
        : provider.isReconnecting
        ? ('Reconnecting', Tone.warning)
        : ('Not connected', Tone.danger);
    final internet = !connected || !provider.hasInternetStatus
        ? null
        : provider.internetConnected
        ? ('Internet online', Tone.success)
        : ('No internet', Tone.danger);

    return PageHeader(
      title: 'My Router',
      subtitle: connected
          ? [
              'Connected',
              if (internet != null) internet.$1.toLowerCase(),
            ].join(' · ')
          : label,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EventsButton(provider: provider),
          const SizedBox(width: Space.sm),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) => switch (value) {
              'refresh' =>
                connected ? provider.refreshAll() : provider.reconnectNow(),
              'diagnostics' => _openDiagnostics(context, provider),
              'restart' => _restart(context, provider),
              'logout' => _logout(context),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('Refresh'),
                ),
              ),
              PopupMenuItem(
                value: 'diagnostics',
                child: ListTile(
                  leading: Icon(Icons.monitor_heart_outlined),
                  title: Text('Diagnostics'),
                ),
              ),
              PopupMenuItem(
                value: 'restart',
                child: ListTile(
                  leading: Icon(Icons.restart_alt_rounded),
                  title: Text('Restart router'),
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Log out'),
                ),
              ),
            ],
            child: const _RoundIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'More',
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: scheme.onSurface, size: 22),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Router found', provider.isRouterFound),
      ('Gateway reachable', provider.isNetworkReachable),
      ('Control port open', provider.isMqttPortOpen),
      ('Signed in', provider.isConnected),
    ];
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Finish setting up',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Provision the router, join its Wi-Fi, then pair this phone.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final (label, done) in steps)
                StatusPill(
                  label: label,
                  tone: done ? Tone.success : Tone.neutral,
                  icon: done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  primary: true,
                  label: 'Set up router',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => _openSetup(context),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: PillButton(
                  label: 'Diagnose',
                  icon: Icons.monitor_heart_outlined,
                  onPressed: () => _openDiagnostics(context, provider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = provider.isConnected;
    final stale = connected && provider.liveDataStale;
    final source = provider.hasLiveWanRates
        ? 'Router internet (WAN) rate'
        : 'Sum of connected device rates';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SparkCard(
                label: 'Download',
                icon: Icons.south_rounded,
                tone: Tone.brand,
                value: connected ? formatRate(provider.liveDownRate) : null,
                samples: [for (final r in provider.rateSamples) r.down],
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: SparkCard(
                label: 'Upload',
                icon: Icons.north_rounded,
                tone: Tone.accent,
                value: connected ? formatRate(provider.liveUpRate) : null,
                samples: [for (final r in provider.rateSamples) r.up],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        MergeSemantics(
          child: Row(
            children: [
              StatusPill(
                label: !connected
                    ? 'Offline'
                    : stale
                    ? 'Stale'
                    : 'Live',
                tone: !connected
                    ? Tone.neutral
                    : stale
                    ? Tone.warning
                    : Tone.success,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  connected
                      ? '$source · updated ${formatAge(provider.liveDataUpdatedAt)}'
                      : 'Live rates appear once the router is connected.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WifiSummary extends StatelessWidget {
  const _WifiSummary({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final networks = provider.wirelessNetworksParsed;
    void openWifi() => _whenConnected(
      context,
      provider,
      () => HomeNavigation.maybeOf(context)?.select(HomeTab.wifi),
    );

    return PanelCard(
      onTap: openWifi,
      child: networks.isEmpty
          ? Row(
              children: [
                const IconBadge(
                  Icons.wifi_rounded,
                  tone: Tone.neutral,
                  size: 40,
                  round: true,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    !provider.isConnected
                        ? 'Wi-Fi networks appear once the router is connected.'
                        : provider.wirelessLoaded
                        ? 'The router did not report its Wi-Fi networks.'
                        : 'Reading Wi-Fi networks…',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (var i = 0; i < networks.length; i++) ...[
                  if (i > 0) const Divider(height: Space.lg),
                  Row(
                    children: [
                      IconBadge(
                        networks[i].isEnabled
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        tone: networks[i].isEnabled ? Tone.brand : Tone.neutral,
                        size: 36,
                        round: true,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              networks[i].ssid.isEmpty
                                  ? 'No name set'
                                  : networks[i].ssid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              networks[i].bandLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: networks[i].isEnabled ? 'On' : 'Off',
                        tone: networks[i].isEnabled
                            ? Tone.success
                            : Tone.neutral,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: PillButton(
                    label: 'Manage Wi-Fi',
                    icon: Icons.tune_rounded,
                    onPressed: openWifi,
                  ),
                ),
              ],
            ),
    );
  }
}

class _QuickControls extends StatelessWidget {
  const _QuickControls({required this.provider});

  final RouterProvider provider;

  Future<void> _setLed(BuildContext context, String sn, bool on) async {
    final result = await provider.updateNodeLed(nodeSn: sn, led: on ? 1 : 0);
    if (!context.mounted) return;
    showSaveResult(
      context,
      result.isConfirmed
          ? SaveResult.confirmed(
              on ? 'Router LED turned on.' : 'Router LED turned off.',
            )
          : result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final networks = provider.wirelessNetworksParsed;
    final wifiOn = networks.where((n) => n.isEnabled).length;
    final led = provider.mainRouterLed;
    final ledOn = led == null ? null : RouterProvider.isLedOn(led);
    final nodesOnline = provider.reportedOnlineNodeCount;

    return ResponsiveGrid(
      minTileWidth: 260,
      maxColumns: 2,
      children: [
        ActionTile(
          icon: Icons.wifi_rounded,
          tone: Tone.brand,
          title: 'Wi-Fi networks',
          subtitle: !connected || networks.isEmpty
              ? 'Bands, names and passwords'
              : '$wifiOn of ${networks.length} on',
          onTap: () => _whenConnected(
            context,
            provider,
            () => HomeNavigation.maybeOf(context)?.select(HomeTab.wifi),
          ),
        ),
        ActionTile(
          icon: Icons.lightbulb_outline_rounded,
          tone: ledOn == true ? Tone.accent : Tone.neutral,
          title: 'Router lights',
          subtitle: !connected
              ? 'LED controls'
              : ledOn == null
              ? 'LED state not reported yet'
              : 'Main router LED ${ledOn ? 'on' : 'off'}',
          onTap: () => _push(context, const NodeLedSettingsScreen()),
          trailing: Semantics(
            label: 'Main router LED',
            toggled: ledOn ?? false,
            child: Switch(
              value: ledOn ?? false,
              onChanged: !connected || led == null
                  ? null
                  : (on) => _setLed(context, '${led['NodeSn']}', on),
            ),
          ),
        ),
        ActionTile(
          icon: Icons.devices_other_rounded,
          tone: Tone.info,
          title: 'Devices',
          subtitle: connected
              ? '${provider.reportedOnlineDeviceCount} connected'
              : 'Manage connected',
          onTap: () => _whenConnected(
            context,
            provider,
            () => HomeNavigation.maybeOf(context)?.select(HomeTab.devices),
          ),
        ),
        ActionTile(
          icon: Icons.hub_rounded,
          tone: Tone.success,
          title: 'Mesh',
          subtitle: connected
              ? '$nodesOnline node${nodesOnline == 1 ? '' : 's'} online'
              : 'Nodes & health',
          onTap: () => _whenConnected(
            context,
            provider,
            () => _push(context, const NodesScreen()),
          ),
        ),
        ActionTile(
          icon: Icons.settings_rounded,
          tone: Tone.neutral,
          title: 'Settings',
          subtitle: 'Internet, LAN, security and more',
          onTap: () =>
              HomeNavigation.maybeOf(context)?.select(HomeTab.settings),
        ),
      ],
    );
  }
}

/// Secondary shortcuts that used to be dashboard quick actions.
class _MoreActions extends StatelessWidget {
  const _MoreActions({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        PillButton(
          label: 'Guest Wi-Fi',
          icon: Icons.wifi_tethering_rounded,
          onPressed: () => _whenConnected(
            context,
            provider,
            () => _push(context, const GuestWifiSettingsScreen()),
          ),
        ),
        PillButton(
          label: 'USB storage',
          icon: Icons.usb_rounded,
          onPressed: () => _whenConnected(
            context,
            provider,
            () => _push(context, const UsbStorageScreen()),
          ),
        ),
        PillButton(
          label: 'Diagnostics',
          icon: Icons.monitor_heart_outlined,
          onPressed: () => _openDiagnostics(context, provider),
        ),
        PillButton(
          label: 'Restart',
          icon: Icons.restart_alt_rounded,
          onPressed: () => _restart(context, provider),
        ),
      ],
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final router = provider.currentRouter;
    final verdict = provider.certificateVerdict;
    final meshId = router?.meshId;
    final master = provider.nodes.where((n) => n.isMaster).firstOrNull;
    String na(String? v) => connected && v != null ? v : 'Not available';

    final rows = <(String, String, Tone)>[
      (
        'Internet',
        !connected || !provider.hasInternetStatus
            ? 'Not reported'
            : provider.internetConnected
            ? 'Online'
            : 'Offline',
        !connected || !provider.hasInternetStatus
            ? Tone.neutral
            : provider.internetConnected
            ? Tone.success
            : Tone.danger,
      ),
      (
        'Connection quality',
        !connected || !provider.internetConnected
            ? 'Not reported'
            : provider.networkQualityLabel,
        provider.networkQuality == 2 ? Tone.warning : Tone.success,
      ),
      (
        'Router uptime',
        na(
          master != null && master.uptimeSeconds > 0
              ? formatUptime(master.uptimeSeconds)
              : null,
        ),
        Tone.neutral,
      ),
      (
        'Guest devices',
        connected ? '${provider.reportedGuestDeviceCount}' : 'Not available',
        Tone.neutral,
      ),
      (
        'USB storage',
        !connected
            ? 'Not available'
            : provider.usbDisks.isEmpty
            ? 'No disk'
            : '${formatBytes(provider.usbAvailableBytes)} free',
        Tone.neutral,
      ),
      (
        'Live statistics',
        !connected
            ? 'Offline'
            : provider.liveTelemetrySupported
            ? 'Answering'
            : 'Slow; using device totals',
        provider.liveTelemetrySupported ? Tone.success : Tone.warning,
      ),
      (
        'Router address',
        router?.ipAddress ?? 'Unknown',
        router?.ipAddress == null ? Tone.neutral : Tone.success,
      ),
      (
        'Router certificate',
        verdict == null
            ? 'Not checked'
            : verdict.trusted
            ? 'Verified'
            : 'Rejected',
        verdict == null
            ? Tone.neutral
            : verdict.trusted
            ? Tone.success
            : Tone.danger,
      ),
      if (meshId != null && provider.authService.isPaired(meshId))
        (
          'Saved password',
          provider.authService.isPasswordStoredSecurely(meshId)
              ? 'Android Keystore'
              : 'App storage',
          provider.authService.isPasswordStoredSecurely(meshId)
              ? Tone.success
              : Tone.warning,
        ),
    ];

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Health details'),
        subtitle: Text(
          meshId == null ? 'No router selected' : 'Mesh $meshId',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(
          Space.lg,
          0,
          Space.lg,
          Space.lg,
        ),
        children: [
          for (final (label, value, tone) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  const SizedBox(width: Space.md),
                  Flexible(
                    child: StatusPill(label: value, tone: tone),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
