import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/home_sheets.dart';
import '../widgets/home_widgets.dart';
import 'diagnostics_screen.dart';
import 'home_screen.dart';
import 'nodes_screen.dart';
import 'router_settings_screens.dart';
import 'setup_wizard_screen.dart';

/// Home: router hero with live LED, live activity, network summary and
/// quick controls. Every value comes from the router or from this
/// session's measurements; missing values are shown as such.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

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
      _GatewayStrip(select: select),
      const SectionLabel('Network'),
      _NetworkTiles(provider: provider, select: select),
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
                    ConnectionStatusBanners(
                      onOpenSetup: () => _openSetup(context),
                    ),
                    if (!provider.isConnected) ...[
                      _SetupCard(provider: provider),
                      const SizedBox(height: Space.md),
                    ],
                    if (wide)
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
    final (text, tone) = connected
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
        HeaderIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Search devices',
          onPressed: () => showDeviceSearch(context, provider),
        ),
        const SizedBox(width: Space.sm),
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
    final today = usePi ? pi.today : null;
    final todayDown = (today?['downloadBytes'] as num?)?.toInt();
    final todayUp = (today?['uploadBytes'] as num?)?.toInt();
    final todayVpn =
        ((today?['vpnDownloadBytes'] as num?) ?? 0) +
        ((today?['vpnUploadBytes'] as num?) ?? 0);
    final todayTotal = todayDown == null || todayUp == null
        ? null
        : todayDown + todayUp;
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
                    ? formatRate(pi.householdDownBytesPerSec!)
                    : connected
                    ? formatRate(provider.liveDownRate)
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
                    ? formatRate(pi.householdUpBytesPerSec!)
                    : connected
                    ? formatRate(provider.liveUpRate)
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
        if (todayTotal != null) ...[
          const SizedBox(height: Space.md),
          PanelCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                const IconBadge(
                  Icons.data_usage_rounded,
                  tone: Tone.brand,
                  size: 36,
                  round: true,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today ${formatBytes(todayTotal)}',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        '↓ ${formatBytes(todayDown!)} · ↑ ${formatBytes(todayUp!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (todayTotal > 0)
                  StatusPill(
                    label: '${(todayVpn / todayTotal * 100).round()}% via VPN',
                    tone: Tone.success,
                    icon: Icons.shield_rounded,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Argon at a glance on Home; opens the Gateway tab.
class _GatewayStrip extends StatelessWidget {
  const _GatewayStrip({required this.select});

  final ValueChanged<HomeTab> select;

  @override
  Widget build(BuildContext context) {
    final pi = maybePiProvider(context);
    if (pi == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final g = pi.gatewayFresh ? pi.gatewayInfo : null;
    final vpn = (g?['vpn'] as Map?)?['state'];
    final online = (g?['upstream'] as Map?)?['online'];
    final status = switch (pi.state) {
      PiLinkState.connected => [
        'Online via ${pi.transportKind!.label}',
        if (online == true)
          'internet up'
        else if (online == false)
          'no internet',
        if (vpn == 'connected')
          'VPN protected'
        else if (vpn != null)
          'VPN $vpn',
      ].join(' · '),
      PiLinkState.unreachable => 'Unreachable · retrying automatically',
      _ => 'Looking for Argon…',
    };
    return PanelCard(
      onTap: () => select(HomeTab.gateway),
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
                Text('Argon gateway', style: theme.textTheme.titleSmall),
                Text(
                  status,
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
          value: connected ? '${provider.reportedOnlineDeviceCount}' : null,
          label: 'Devices online',
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
