import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/router_provider.dart';
import '../services/router_certificate_verifier.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/feedback.dart';
import 'diagnostics_screen.dart';
import 'discovery_screen.dart';
import 'home_screen.dart';
import 'nodes_screen.dart';
import 'router_settings_screens.dart';
import 'settings_screen.dart';
import 'setup_wizard_screen.dart';

/// Network overview: internet state, live throughput, mesh and device
/// summaries and the most used actions.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final connected = provider.isConnected;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: provider.refreshAll,
        edgeOffset: 120,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _OverviewAppBar(provider: provider),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.xxl,
              ),
              sliver: SliverToBoxAdapter(
                child: ContentWidth(
                  maxWidth: 960,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConnectionStatusBanners(
                        onOpenSetup: () => _openSetup(context),
                      ),
                      if (!connected) ...[
                        _SetupCard(provider: provider),
                        const SizedBox(height: Space.md),
                      ],
                      _InternetCard(provider: provider),
                      const SectionLabel('Your network'),
                      _NetworkMetrics(provider: provider),
                      const SectionLabel('Quick actions'),
                      _QuickActions(provider: provider),
                      const SizedBox(height: Space.md),
                      _ConnectionDetails(provider: provider),
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

class _OverviewAppBar extends StatelessWidget {
  const _OverviewAppBar({required this.provider});

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
    final theme = Theme.of(context);
    final connected = provider.isConnected;
    final (label, tone) = connected
        ? ('Connected', Tone.success)
        : provider.isReconnecting
        ? ('Reconnecting', Tone.warning)
        : ('Not connected', Tone.danger);

    return SliverAppBar(
      pinned: true,
      toolbarHeight: 72,
      titleSpacing: Space.lg,
      title: Row(
        children: [
          const IconBadge(Icons.router_rounded, size: 40),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected && provider.wirelessNetworksParsed.isNotEmpty
                      ? provider.currentWifiName
                      : 'TT Router',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(label: label, tone: tone),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: connected ? provider.refreshAll : provider.reconnectNow,
          icon: const Icon(Icons.refresh_rounded),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (value) => switch (value) {
            'diagnostics' => _openDiagnostics(context, provider),
            'logout' => _logout(context),
            _ => null,
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'diagnostics',
              child: ListTile(
                leading: Icon(Icons.monitor_heart_outlined),
                title: Text('Diagnostics'),
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
        ),
        const SizedBox(width: Space.xs),
      ],
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
    return SectionCard(
      title: 'Finish setting up',
      subtitle: 'Provision the router, join its Wi-Fi, then pair this phone.',
      icon: Icons.rocket_launch_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                child: FilledButton.icon(
                  onPressed: () => _openSetup(context),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Set up router'),
                ),
              ),
              const SizedBox(width: Space.sm),
              OutlinedButton.icon(
                onPressed: () => _openDiagnostics(context, provider),
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('Diagnose'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InternetCard extends StatelessWidget {
  const _InternetCard({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = provider.isConnected;
    final known = connected && provider.hasInternetStatus;
    final online = known && provider.internetConnected;

    final (title, tone, icon) = !connected
        ? ('Router not connected', Tone.neutral, Icons.link_off_rounded)
        : !known
        ? ('Checking internet', Tone.neutral, Icons.public_rounded)
        : online
        ? ('Internet online', Tone.success, Icons.public_rounded)
        : ('No internet', Tone.danger, Icons.public_off_rounded);

    final quality = !online
        ? null
        : provider.networkQuality == 2
        ? ('Check connection quality', Tone.warning)
        : ('Good connection', Tone.success);

    final wan = provider.hasLiveWanRates;
    final stale = connected && provider.liveDataStale;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(icon, tone: tone, size: 52),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: Space.xs),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        children: [
                          if (quality != null)
                            StatusPill(label: quality.$1, tone: quality.$2),
                          if (connected &&
                              provider.certificateVerdict?.trusted == true)
                            const StatusPill(
                              label: 'Verified router',
                              tone: Tone.info,
                              icon: Icons.verified_user_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: _RateBlock(
                    label: 'Download',
                    icon: Icons.south_rounded,
                    value: connected ? formatRate(provider.liveDownRate) : null,
                    tone: Tone.info,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _RateBlock(
                    label: 'Upload',
                    icon: Icons.north_rounded,
                    value: connected ? formatRate(provider.liveUpRate) : null,
                    tone: Tone.brand,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Icon(
                  stale ? Icons.history_rounded : Icons.sensors_rounded,
                  size: 16,
                  color: stale
                      ? context.tone(Tone.warning).foreground
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    !connected
                        ? 'Live rates appear once the router is connected.'
                        : '${wan ? 'Router internet (WAN) rate' : 'Sum of connected device rates'}'
                              ' · updated ${formatAge(provider.liveDataUpdatedAt)}'
                              '${stale ? ' · may be stale' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

class _RateBlock extends StatelessWidget {
  const _RateBlock({
    required this.label,
    required this.icon,
    required this.value,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final String? value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.tone(tone);
    return Semantics(
      label: '$label ${value ?? 'not available'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.container.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: colors.foreground),
                  const SizedBox(width: Space.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value ?? '—', style: theme.textTheme.headlineSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkMetrics extends StatelessWidget {
  const _NetworkMetrics({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final master = provider.nodes.where((n) => n.isMaster).firstOrNull;
    final active = provider.devices.where((d) => d.isActive).length;
    final guests = provider.reportedGuestDeviceCount;
    final online = provider.reportedOnlineNodeCount;
    final total = provider.reportedTotalNodeCount;

    return ResponsiveGrid(
      minTileWidth: 150,
      children: [
        MetricTile(
          icon: Icons.devices_rounded,
          label: 'Devices online',
          value: connected ? '${provider.reportedOnlineDeviceCount}' : null,
          caption: !connected
              ? null
              : [
                  '$active active now',
                  if (guests > 0) '$guests guest',
                ].join(' · '),
          tone: Tone.info,
          onTap: () => _whenConnected(
            context,
            provider,
            () => HomeNavigation.maybeOf(context)?.select(HomeTab.devices),
          ),
        ),
        MetricTile(
          icon: Icons.hub_rounded,
          label: 'Mesh nodes',
          value: connected
              ? (total > online ? '$online / $total' : '$online')
              : null,
          caption: connected
              ? (total > online
                    ? '${total - online} offline'
                    : 'All nodes online')
              : null,
          tone: total > online ? Tone.warning : Tone.success,
          onTap: () => _whenConnected(
            context,
            provider,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NodesScreen()),
            ),
          ),
        ),
        MetricTile(
          icon: Icons.timer_outlined,
          label: 'Router uptime',
          value: connected && master != null && master.uptimeSeconds > 0
              ? formatUptime(master.uptimeSeconds)
              : null,
          caption: connected && master?.model != null
              ? 'Main node ${master!.model}'
              : null,
          tone: Tone.brand,
        ),
        MetricTile(
          icon: Icons.usb_rounded,
          label: 'USB storage',
          value: !connected
              ? null
              : provider.usbDisks.isEmpty
              ? 'No disk'
              : formatBytes(provider.usbAvailableBytes),
          caption: !connected
              ? null
              : provider.usbDisks.isEmpty
              ? (provider.usbStorageSettings?.sambaEnabled == true
                    ? 'File sharing on'
                    : 'Connect a USB drive')
              : 'free of ${formatBytes(provider.usbTotalBytes)}',
          tone: Tone.neutral,
          onTap: () => _whenConnected(
            context,
            provider,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UsbStorageScreen()),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.provider});

  final RouterProvider provider;

  Future<void> _restart(BuildContext context) async {
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

  void _push(BuildContext context, Widget screen) => _whenConnected(
    context,
    provider,
    () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
  );

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final actions = [
      (
        Icons.wifi_rounded,
        'Wi-Fi',
        'Names and passwords',
        Tone.info,
        () => _whenConnected(
          context,
          provider,
          () => HomeNavigation.maybeOf(context)?.select(HomeTab.wifi),
        ),
      ),
      (
        Icons.wifi_tethering_rounded,
        'Guest Wi-Fi',
        'Visitor network',
        Tone.success,
        () => _push(context, const GuestWifiSettingsScreen()),
      ),
      (
        Icons.hub_outlined,
        'Mesh nodes',
        'Status and uptime',
        Tone.brand,
        () => _push(context, const NodesScreen()),
      ),
      (
        Icons.tune_rounded,
        'Advanced',
        'WAN, LAN, security',
        Tone.neutral,
        () => HomeNavigation.maybeOf(context)?.select(HomeTab.settings),
      ),
      (
        Icons.monitor_heart_outlined,
        'Diagnostics',
        'Check the connection',
        Tone.warning,
        () => _openDiagnostics(context, provider),
      ),
      (
        Icons.restart_alt_rounded,
        'Restart',
        'Reboot all nodes',
        Tone.danger,
        () => _whenConnected(context, provider, () => _restart(context)),
      ),
    ];

    return ResponsiveGrid(
      minTileWidth: 140,
      maxColumns: 6,
      children: [
        for (final (icon, title, subtitle, tone, onTap) in actions)
          _ActionTile(
            icon: icon,
            title: title,
            subtitle: subtitle,
            tone: tone,
            locked: !connected && title != 'Diagnostics' && title != 'Advanced',
            onTap: onTap,
          ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.locked,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Tone tone;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title. $subtitle${locked ? '. Requires router access' : ''}',
      child: ExcludeSemantics(
        child: Card(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(
                        icon,
                        tone: locked ? Tone.neutral : tone,
                        size: 40,
                      ),
                      const Spacer(),
                      if (locked)
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionDetails extends StatelessWidget {
  const _ConnectionDetails({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final router = provider.currentRouter;
    final verdict = provider.certificateVerdict;
    final meshId = router?.meshId;
    final rows = <(String, String, Tone)>[
      (
        'Router address',
        router?.ipAddress ?? 'Unknown',
        router?.ipAddress == null ? Tone.neutral : Tone.success,
      ),
      (
        'Gateway reachable',
        provider.networkState == NetworkState.unknown
            ? 'Not checked'
            : provider.isNetworkReachable
            ? 'Yes'
            : 'No',
        provider.isNetworkReachable ? Tone.success : Tone.warning,
      ),
      (
        'Control port (25678)',
        provider.mqttPortState == MqttPortState.unknown
            ? 'Not checked'
            : provider.isMqttPortOpen
            ? 'Open'
            : 'Closed',
        provider.isMqttPortOpen ? Tone.success : Tone.warning,
      ),
      (
        'Signed in',
        provider.isConnected ? 'Yes' : provider.statusSummary,
        provider.isConnected ? Tone.success : Tone.warning,
      ),
      (
        'Router certificate',
        verdict == null
            ? 'Not checked'
            : verdict.trusted
            ? 'Verified'
            : 'Rejected: ${verdict.name}',
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
              : 'App storage (Keystore unavailable)',
          provider.authService.isPasswordStoredSecurely(meshId)
              ? Tone.success
              : Tone.warning,
        ),
    ];

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.info_outline_rounded),
        title: const Text('Connection details'),
        subtitle: Text(meshId == null ? 'No router selected' : 'Mesh $meshId'),
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
                    child: StatusPill(label: value, tone: tone, dot: true),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
