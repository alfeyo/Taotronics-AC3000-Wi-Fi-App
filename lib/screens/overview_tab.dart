import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/home_sheets.dart';
import '../services/argon_status.dart';
import '../widgets/home_widgets.dart';
import '../widgets/hub_widgets.dart';
import '../widgets/managed_router.dart';
import 'diagnostics_screen.dart';
import 'home_screen.dart';
import 'nodes_screen.dart';
import 'router_settings_screens.dart';
import 'setup_wizard_screen.dart';

/// Router details (the TaoTronics dashboard that used to be Home): router
/// hero with live LED, live activity, network summary and quick controls.
/// Opened from Home's Managed Router card. In Argon mode the router is shown
/// as Argon observes it and router-specific controls need Direct Router
/// Control; every value says where it comes from.
class RouterDetailsScreen extends StatelessWidget {
  const RouterDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    void select(HomeTab tab) => HomeNavigation.maybeOf(context)?.select(tab);

    final hero = RouterHero(
      provider: provider,
      onOpenDevices: () => select(HomeTab.devices),
    );
    final details = <Widget>[
      SectionLabel(
        'Live activity',
        trailing: TextButton(
          onPressed: () => select(HomeTab.statistics),
          child: const Text('Statistics'),
        ),
      ),
      _LiveRow(provider: provider),
      const SizedBox(height: Space.md),
      _HubStrip(select: select),
      const SectionLabel('Network'),
      _NetworkTiles(provider: provider, select: select),
      _RecentNotices(provider: provider),
      const SectionLabel('Quick controls'),
      _QuickControls(provider: provider, select: select),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: provider.refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              120,
            ),
            children: [
              ContentWidth(
                maxWidth: wide ? 1040 : Breakpoints.contentMaxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(provider: provider),
                    const SizedBox(height: Space.md),
                    const DirectControlPanel(),
                    if (provider.isArgonMode) ...[
                      const ArgonRouterSummary(),
                      const SizedBox(height: Space.md),
                    ] else
                      ConnectionStatusBanners(
                        onOpenSetup: () => _openSetup(context),
                      ),
                    if (!provider.isConnected && provider.isDirectMode) ...[
                      _SetupCard(provider: provider),
                      const SizedBox(height: Space.md),
                    ],
                    if (provider.isArgonMode) ...[
                      const SectionLabel('Router screens'),
                      _QuickControls(provider: provider, select: select),
                    ] else if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: hero),
                          const SizedBox(width: Space.xl),
                          Expanded(child: Column(children: details)),
                        ],
                      )
                    else ...[
                      hero,
                      ...details,
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

class _Header extends StatelessWidget {
  const _Header({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = provider.isConnected;
    final (text, tone) = provider.isArgonMode
        ? ('Observed by Argon · direct control off', Tone.info)
        : connected
        ? (
            !provider.hasInternetStatus
                ? 'Connected'
                : provider.internetConnected
                ? 'Online'
                : 'No internet',
            provider.hasInternetStatus && !provider.internetConnected
                ? Tone.danger
                : Tone.success,
          )
        : provider.isReconnecting
        ? ('Reconnecting…', Tone.warning)
        : ('Not connected', Tone.danger);

    return Row(
      children: [
        if (Navigator.canPop(context)) ...[
          HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: Space.md),
        ],
        Expanded(
          child: Semantics(
            container: true,
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Router', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: context.tone(tone).foreground,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
        ),
        if (provider.isDirectMode) ...[
          HeaderIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Search devices',
            onPressed: () => showDeviceSearch(context, provider),
          ),
          const SizedBox(width: Space.sm),
        ],
        EventsButton(provider: provider),
        const SizedBox(width: Space.sm),
        HeaderIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Router & preferences',
          onPressed: () => showRouterPreferences(context, provider),
        ),
      ],
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            provider.isReconnecting
                ? 'Reconnecting to your router'
                : 'Router not connected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Join the router Wi-Fi, or set up and pair a router.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              PillButton(
                primary: true,
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: provider.reconnectNow,
              ),
              PillButton(
                label: 'Set up',
                icon: Icons.add_rounded,
                onPressed: () => _openSetup(context),
              ),
              PillButton(
                label: 'Diagnose',
                icon: Icons.monitor_heart_outlined,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DiagnosticsScreen(
                      routerReachable: provider.isNetworkReachable,
                      mqttPortOpen: provider.isMqttPortOpen,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Household throughput. Argon's eth1 measurement is preferred while fresh
/// (it is what actually crossed into the household); the router's own
/// telemetry is the fallback. The source line always says which is shown.
class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final pi = maybePiProvider(context);
    final usePi = pi != null && pi.liveFresh;
    final connected = provider.isConnected;
    final stale = !usePi && connected && provider.liveDataStale;
    final theme = Theme.of(context);
    final String source;
    if (usePi) {
      source = 'Measured by Argon · household traffic · live';
    } else if (connected) {
      source =
          '${stale ? 'Stale · ' : ''}'
          '${provider.hasLiveWanRates ? 'Router internet (WAN) rate' : 'Sum of connected device rates'}'
          ' · updated ${formatAge(provider.liveDataUpdatedAt)}'
          '${pi != null && pi.gateway != null ? ' · Argon data not current' : ''}';
    } else {
      source = 'Live rates appear once the router or Argon is reachable.';
    }
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
                value: usePi
                    ? formatBitRate(pi.householdDownBitsPerSec ?? 0)
                    : connected
                    ? formatBitRate(provider.liveDownRate * 8)
                    : null,
                samples: usePi
                    ? [for (final r in pi.liveSamples) r.down]
                    : [for (final r in provider.rateSamples) r.down],
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: SparkCard(
                label: 'Upload',
                icon: Icons.north_rounded,
                tone: Tone.accent,
                value: usePi
                    ? formatBitRate(pi.householdUpBitsPerSec ?? 0)
                    : connected
                    ? formatBitRate(provider.liveUpRate * 8)
                    : null,
                samples: usePi
                    ? [for (final r in pi.liveSamples) r.up]
                    : [for (final r in provider.rateSamples) r.up],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(
          source,
          style: theme.textTheme.bodySmall?.copyWith(
            color: stale
                ? context.tone(Tone.warning).foreground
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (pi != null) ...[
          const SizedBox(height: Space.md),
          _UsageStrip(pi: pi),
        ],
      ],
    );
  }
}

/// Data used today / last 7 days / this month, measured by Argon.
class _UsageStrip extends StatelessWidget {
  const _UsageStrip({required this.pi});

  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final usage = pi.usage;
    final today = pi.todayUsage;
    final state = pi.hubState;
    String figure(UsagePeriod? p, HubDataState s) => p == null
        ? hubValue(s, null)
        : p.measured == false
        ? 'Not measured'
        : p.total == null
        ? 'Not reported'
        : formatBytes(p.total!);
    Widget cell(String label, String value) => Expanded(
      child: Semantics(
        container: true,
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
    final share = today?.measured == false ? null : today?.vpnShare;
    final vpn = pi.gatewayFresh ? pi.vpn : null;
    return PanelCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              cell(
                'Today',
                figure(
                  today,
                  today == null && pi.live != null
                      ? HubDataState.connected
                      : state,
                ),
              ),
              cell('Last 7 days', figure(usage?.last7, state)),
              cell('This month', figure(usage?.thisMonth, state)),
            ],
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              if (share != null)
                StatusPill(
                  label: '${formatShare(share)} of today via VPN',
                  tone: Tone.success,
                  icon: Icons.shield_rounded,
                ),
              if (vpn?.mode != null)
                StatusPill(
                  label: vpn!.isOff
                      ? 'VPN off'
                      : vpn.connected
                      ? 'VPN on'
                      : 'VPN ${vpn.state ?? 'on'}',
                  tone: vpn.isOff
                      ? Tone.neutral
                      : vpn.connected
                      ? Tone.success
                      : Tone.warning,
                  dot: true,
                ),
              if (state == HubDataState.stale)
                DataStateChip(state: state, at: pi.gatewayAt),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Household data measured by Argon',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// Network Hub at a glance on Home; opens the Network Hub tab.
class _HubStrip extends StatelessWidget {
  const _HubStrip({required this.select});

  final ValueChanged<HomeTab> select;

  @override
  Widget build(BuildContext context) {
    final pi = maybePiProvider(context);
    if (pi == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final fresh = pi.gatewayFresh;
    final vpn = fresh ? pi.vpn : null;
    final upstream = pi.gatewayInfo?['upstream'];
    final online = fresh
        ? pi.uplink?.online ??
              (upstream is Map && upstream['online'] is bool
                  ? upstream['online'] as bool
                  : null)
        : null;
    final link = switch (pi.state) {
      PiLinkState.connected => 'Available via ${pi.transportKind!.label}',
      PiLinkState.unreachable => 'Unreachable · retrying automatically',
      _ => 'Looking for Argon…',
    };
    final details = [
      if (pi.hubState == HubDataState.stale)
        'data from ${formatAge(pi.gatewayAt)}'
      else if (pi.hubState == HubDataState.loading && pi.connected)
        'loading…',
      if (online == true)
        'internet online'
      else if (online == false)
        'no internet',
      if (vpn?.mode == 'off')
        'VPN off'
      else if (vpn?.mode == 'on')
        vpn!.connected ? 'VPN on' : 'VPN ${vpn.state ?? 'on'}',
    ];
    return PanelCard(
      onTap: () => select(HomeTab.hub),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.md,
        Space.md,
      ),
      child: Row(
        children: [
          IconBadge(
            Icons.developer_board_rounded,
            tone: pi.connected
                ? Tone.success
                : pi.state == PiLinkState.unreachable
                ? Tone.warning
                : Tone.neutral,
            size: 40,
            round: true,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Network Hub', style: theme.textTheme.titleSmall),
                Text(
                  [link, ...details].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// The latest few router and Network Hub notifications.
class _RecentNotices extends StatelessWidget {
  const _RecentNotices({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final pi = maybePiProvider(context);
    final notices = EventsButton.merged(
      provider,
      pi,
    ).where((n) => n.tone != 'info' || n.source != 'Router').take(3).toList();
    if (notices.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Recent notifications'),
        PanelCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm,
          ),
          child: Column(
            children: [
              for (final n in notices)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    switch (n.tone) {
                      'success' => Icons.check_circle_rounded,
                      'error' => Icons.error_rounded,
                      'warning' => Icons.warning_amber_rounded,
                      _ => Icons.info_outline_rounded,
                    },
                    color: context.tone(switch (n.tone) {
                      'success' => Tone.success,
                      'error' => Tone.danger,
                      'warning' => Tone.warning,
                      _ => Tone.info,
                    }).foreground,
                  ),
                  title: Text(
                    n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${n.source} · ${formatAge(n.time)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NetworkTiles extends StatelessWidget {
  const _NetworkTiles({required this.provider, required this.select});

  final RouterProvider provider;
  final ValueChanged<HomeTab> select;

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final networks = provider.wirelessNetworksParsed;
    final wifiOn = networks.where((n) => n.isEnabled).length;
    final master = provider.nodes.where((n) => n.isMaster).firstOrNull;
    final online = provider.reportedOnlineNodeCount;
    final total = provider.reportedTotalNodeCount;
    return ResponsiveGrid(
      minTileWidth: 140,
      maxColumns: 4,
      spacing: Space.md,
      children: [
        StatTile(
          icon: Icons.devices_other_rounded,
          tone: Tone.brand,
          value: connected && provider.knownOnlineDeviceCount != null
              ? '${provider.knownOnlineDeviceCount}'
              : null,
          label: !connected || provider.devicesUpdatedAt == null
              ? (provider.managedElsewhere
                    ? 'Devices online · waiting for router access'
                    : 'Devices online · router')
              : provider.managedElsewhere
              ? 'Devices online · last read ${formatAge(provider.devicesUpdatedAt)}'
              : 'Devices online · router, ${formatAge(provider.devicesUpdatedAt)}',
          onTap: () => select(HomeTab.devices),
        ),
        StatTile(
          icon: Icons.wifi_rounded,
          tone: Tone.info,
          value: connected && networks.isNotEmpty
              ? '$wifiOn/${networks.length}'
              : null,
          label: 'Wi-Fi networks on',
          onTap: () => select(HomeTab.wifi),
        ),
        StatTile(
          icon: Icons.hub_rounded,
          tone: total > online ? Tone.warning : Tone.success,
          value: connected
              ? (total > online ? '$online/$total' : '$online')
              : null,
          label: 'Mesh nodes online',
          onTap: () => _whenConnected(
            context,
            provider,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NodesScreen()),
            ),
          ),
        ),
        StatTile(
          icon: Icons.timer_outlined,
          tone: Tone.neutral,
          value: connected && master != null && master.uptimeSeconds > 0
              ? formatUptime(master.uptimeSeconds)
              : null,
          label: 'Router uptime',
        ),
      ],
    );
  }
}

class _QuickControls extends StatelessWidget {
  const _QuickControls({required this.provider, required this.select});

  final RouterProvider provider;
  final ValueChanged<HomeTab> select;

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final led = provider.mainRouterLed;
    final ledOn = led == null ? null : RouterProvider.isLedOn(led);
    return ResponsiveGrid(
      minTileWidth: 260,
      maxColumns: 2,
      spacing: Space.sm,
      children: [
        ActionTile(
          icon: Icons.wifi_rounded,
          tone: Tone.brand,
          title: 'Wi-Fi networks',
          subtitle: 'Bands, names, passwords, guest',
          onTap: () => select(HomeTab.wifi),
        ),
        ActionTile(
          icon: Icons.lightbulb_outline_rounded,
          tone: ledOn == true ? Tone.accent : Tone.neutral,
          title: 'Router lights',
          subtitle: !connected || ledOn == null
              ? 'LED controls'
              : 'Main router LED ${ledOn ? 'on' : 'off'}',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NodeLedSettingsScreen()),
          ),
        ),
        ActionTile(
          icon: Icons.hub_outlined,
          tone: Tone.success,
          title: 'Mesh',
          subtitle: 'Nodes, uptime and LEDs',
          onTap: () => _whenConnected(
            context,
            provider,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NodesScreen()),
            ),
          ),
        ),
        ActionTile(
          icon: Icons.settings_outlined,
          tone: Tone.neutral,
          title: 'Settings',
          subtitle: 'Internet, LAN, security and more',
          onTap: () => select(HomeTab.settings),
        ),
      ],
    );
  }
}
