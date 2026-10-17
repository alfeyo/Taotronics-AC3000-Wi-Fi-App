import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final stale = connected && provider.liveDataStale;
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
        Text(
          !connected
              ? 'Live rates appear once the router is connected.'
              : '${stale ? 'Stale · ' : ''}'
                    '${provider.hasLiveWanRates ? 'Router internet (WAN) rate' : 'Sum of connected device rates'}'
                    ' · updated ${formatAge(provider.liveDataUpdatedAt)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: stale
                ? context.tone(Tone.warning).foreground
                : Theme.of(context).colorScheme.onSurfaceVariant,
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
