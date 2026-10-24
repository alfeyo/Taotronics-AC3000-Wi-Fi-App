import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../services/argon_status.dart';
import '../services/hub_links.dart';
import '../services/pi_api.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/home_widgets.dart';
import '../widgets/hub_widgets.dart';
import '../widgets/managed_router.dart';
import '../widgets/pi_board.dart';
import '../widgets/vpn_card.dart';
import 'home_screen.dart';
import 'network_hub_screen.dart';
import 'overview_tab.dart';

/// Home (Pi-first): Argon, the Raspberry Pi gateway, and the household
/// network it measures. The TaoTronics router appears as a secondary Managed
/// Router card. Every figure is Argon's own measurement or observation, and
/// says so; missing values are shown as missing, never as zero.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final router = context.watch<RouterProvider>();
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    void select(HomeTab tab) => HomeNavigation.maybeOf(context)?.select(tab);
    void openRouter() => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const RouterDetailsScreen()),
    );

    final hero = _PiHero(pi: pi);
    final details = <Widget>[
      SectionLabel(
        'Household traffic',
        trailing: DataStateChip(state: pi.liveState, at: pi.liveAt),
      ),
      _LiveRates(pi: pi),
      const SizedBox(height: Space.md),
      _Today(pi: pi),
      SectionLabel(
        'Activity · 14 days',
        trailing: TextButton(
          onPressed: () => select(HomeTab.statistics),
          child: const Text('Statistics'),
        ),
      ),
      _Activity(pi: pi),
      const SectionLabel('Network'),
      _NetworkStats(pi: pi, select: select),
      const SectionLabel('Managed router'),
      ManagedRouterCard(onOpen: openRouter),
      _RecentEvents(router: router, pi: pi),
      const SectionLabel('Controls'),
      _Controls(pi: pi, select: select),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: pi.refreshNow,
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
                    _Header(pi: pi, router: router),
                    const SizedBox(height: Space.md),
                    const DirectControlPanel(),
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

/// "Connected to Argon — monitoring household network", or the honest
/// alternative.
String argonStatusLine(PiProvider pi) {
  if (pi.connected) {
    return pi.hubState == HubDataState.stale
        ? 'Connected to Argon · data ${formatAge(pi.gatewayAt)}'
        : 'Connected to Argon — monitoring household network';
  }
  return switch (pi.state) {
    PiLinkState.unreachable =>
      pi.gateway == null
          ? 'Argon unreachable · retrying automatically'
          : 'Argon unreachable · showing data from ${formatAge(pi.gatewayAt)}',
    _ => 'Connecting to Argon…',
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = pi.connected
        ? (pi.hubState == HubDataState.stale ? Tone.warning : Tone.success)
        : pi.state == PiLinkState.unreachable
        ? Tone.danger
        : Tone.neutral;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Argon', style: theme.textTheme.headlineSmall),
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
                        argonStatusLine(pi),
                        maxLines: 2,
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
        EventsButton(provider: router),
        const SizedBox(width: Space.sm),
        HeaderIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Manage Argon connection',
          onPressed: () => showManageConnection(context),
        ),
      ],
    );
  }
}

class _PiHero extends StatelessWidget {
  const _PiHero({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = pi.gatewayInfo;
    final fresh = pi.gatewayFresh;
    final uplink = pi.uplink;
    final upstream = g?['upstream'] is Map ? g!['upstream'] as Map : null;
    final online = fresh
        ? uplink?.online ??
              (upstream?['online'] is bool ? upstream!['online'] as bool : null)
        : null;
    final source = [
      uplink?.type ?? (upstream?['interface'] as String?),
      if (upstream?['ssid'] is String) upstream!['ssid'] as String,
    ].whereType<String>().join(' · ');
    final vpn = pi.vpn;
    final uptime = g?['uptimeSeconds'];
    final lastUpdate = [pi.liveAt, pi.gatewayAt]
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.62,
                      colors: [
                        (pi.connected
                                ? Palette.amber
                                : theme.colorScheme.primary)
                            .withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Semantics(
                image: true,
                label:
                    'Argon Raspberry Pi, ${pi.connected ? 'connected' : 'not connected'}',
                child: PiBoard(
                  active: pi.connected,
                  dim: !pi.connected,
                  size: 270,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Argon · ${hubModel(pi)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            StatusPill(
              label: pi.connected
                  ? 'Connected · ${pi.transportKind!.label}'
                  : pi.state == PiLinkState.unreachable
                  ? 'Unreachable'
                  : 'Searching',
              tone: pi.connected
                  ? Tone.success
                  : pi.state == PiLinkState.unreachable
                  ? Tone.warning
                  : Tone.neutral,
              icon: switch (pi.transportKind) {
                PiTransportKind.bluetooth => Icons.bluetooth_rounded,
                PiTransportKind.tailscale => Icons.vpn_lock_rounded,
                PiTransportKind.https => Icons.lock_rounded,
                _ => Icons.lan_rounded,
              },
            ),
            if (online is bool)
              StatusPill(
                label: online ? 'Internet online' : 'No internet',
                tone: online ? Tone.success : Tone.danger,
                icon: Icons.public_rounded,
              ),
            if (fresh && vpn?.mode != null)
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
                icon: Icons.shield_rounded,
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        PanelCard(
          child: Column(
            children: [
              KvRow(
                'Internet source',
                hubValue(pi.hubState, source.isEmpty ? null : source),
              ),
              KvRow(
                'VPN',
                hubValue(
                  pi.hubState,
                  vpn == null
                      ? null
                      : vpn.isOff
                      ? 'Off · next location ${vpn.location ?? 'not set'}'
                      : '${VpnCard.stateLabel(vpn)} · ${vpn.location ?? 'location not reported'}',
                ),
              ),
              KvRow(
                'Gateway uptime',
                hubValue(
                  pi.hubState,
                  uptime is num ? formatUptime(uptime.round()) : null,
                ),
              ),
              KvRow(
                'Last monitoring update',
                lastUpdate == null ? 'Not yet' : formatAge(lastUpdate),
                last: true,
              ),
              if (!pi.connected && pi.lastError != null) ...[
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pi.lastError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    PillButton(
                      label: 'Retry',
                      icon: Icons.refresh_rounded,
                      onPressed: pi.reconnect,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveRates extends StatelessWidget {
  const _LiveRates({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fresh = pi.liveFresh;
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
                value: fresh
                    ? formatBitRate(pi.householdDownBitsPerSec ?? 0)
                    : null,
                samples: [for (final r in pi.liveSamples) r.down],
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: SparkCard(
                label: 'Upload',
                icon: Icons.north_rounded,
                tone: Tone.accent,
                value: fresh
                    ? formatBitRate(pi.householdUpBitsPerSec ?? 0)
                    : null,
                samples: [for (final r in pi.liveSamples) r.up],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(
          fresh
              ? 'Measured by Argon at the household link (eth1) · bits per second'
              : pi.live == null
              ? 'Live rates appear once Argon answers.'
              : 'Stale · last sample ${formatAge(pi.liveAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: fresh
                ? theme.colorScheme.onSurfaceVariant
                : context.tone(Tone.warning).foreground,
          ),
        ),
      ],
    );
  }
}

/// Today's household download, upload and total, with collection coverage.
class _Today extends StatelessWidget {
  const _Today({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final today = pi.todayUsage;
    final state = today == null ? pi.hubState : HubDataState.connected;
    String bytes(int? v) => v == null ? hubValue(state, null) : formatBytes(v);
    Widget cell(String label, String value, IconData icon, Tone tone) =>
        Expanded(
          child: Semantics(
            container: true,
            label: '$label today: $value',
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Icon(icon, size: 18, color: context.tone(tone).foreground),
                  const SizedBox(height: Space.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ),
        );
    final coverage = today?.coverage;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              cell(
                'Downloaded',
                bytes(today?.downloadBytes),
                Icons.south_rounded,
                Tone.brand,
              ),
              cell(
                'Uploaded',
                bytes(today?.uploadBytes),
                Icons.north_rounded,
                Tone.accent,
              ),
              cell(
                'Total today',
                bytes(today?.total),
                Icons.data_usage_rounded,
                Tone.success,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            [
              'Household data today, measured by Argon',
              if (coverage != null)
                '${(coverage * 100).toStringAsFixed(coverage >= 0.995 ? 0 : 1)}% of the day observed',
              if (today?.vpnShare != null)
                '${formatShare(today!.vpnShare!)} via VPN',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
          if (today?.measured == false)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Partial coverage: totals are a lower bound.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.tone(Tone.warning).foreground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final usage = pi.usage;
    final days = usage?.days ?? const <UsageDay>[];
    if (days.isEmpty) {
      return PanelCard(
        child: Text(
          hubValue(pi.hubState, 'No daily history reported yet.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final week = usage?.last7;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DailyUsageChart(days: days),
          if (week?.total != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              'Last 7 days ${formatBytes(week!.total!)}'
              '${week.measured == false ? ' (partly measured)' : ''}'
              '${usage?.thisMonth?.total == null ? '' : ' · this month ${formatBytes(usage!.thisMonth!.total!)}'}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NetworkStats extends StatelessWidget {
  const _NetworkStats({required this.pi, required this.select});
  final PiProvider pi;
  final ValueChanged<HomeTab> select;

  @override
  Widget build(BuildContext context) {
    final view = pi.routerView;
    final g = pi.gatewayInfo;
    final temp = g?['temperatureC'];
    final throttled = g?['activeThrottling'] == true;
    return ResponsiveGrid(
      minTileWidth: 140,
      maxColumns: 4,
      spacing: Space.md,
      children: [
        StatTile(
          icon: Icons.devices_other_rounded,
          tone: Tone.brand,
          value: view?.onlineCount == null ? null : '${view!.onlineCount}',
          label: view?.knownCount == null
              ? 'Devices online'
              : 'Devices online · ${view!.knownCount} known',
          onTap: () => select(HomeTab.devices),
        ),
        StatTile(
          icon: Icons.router_rounded,
          tone: routerMonitoringTone(view),
          value: view?.observedAt == null ? null : formatAge(view!.observedAt),
          label: 'Router observed',
        ),
        StatTile(
          icon: Icons.thermostat_rounded,
          tone: throttled
              ? Tone.warning
              : temp is num && temp >= 70
              ? Tone.warning
              : Tone.success,
          value: temp is num ? '${temp.toStringAsFixed(0)}°C' : null,
          label: throttled ? 'Pi temperature · throttling' : 'Pi temperature',
          onTap: () => select(HomeTab.hub),
        ),
        StatTile(
          icon: Icons.notifications_active_outlined,
          tone: Tone.info,
          value: '${pi.events.where((e) => e.source == 'argon').length}',
          label: 'Network events',
        ),
      ],
    );
  }
}

class _RecentEvents extends StatelessWidget {
  const _RecentEvents({required this.router, required this.pi});
  final RouterProvider router;
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final notices = EventsButton.merged(router, pi).take(3).toList();
    if (notices.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Recent events'),
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
                    [
                      if (n.message.isNotEmpty) n.message,
                      '${n.source} · ${formatAge(n.time)}',
                    ].join('\n'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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

/// Safe, allowlisted Argon actions. No router reboot, Wi-Fi or system
/// commands here: VPN changes go through the confirmed, signed VPN card.
class _Controls extends StatelessWidget {
  const _Controls({required this.pi, required this.select});
  final PiProvider pi;
  final ValueChanged<HomeTab> select;

  @override
  Widget build(BuildContext context) {
    final vpn = pi.vpn;
    return ResponsiveGrid(
      minTileWidth: 260,
      maxColumns: 2,
      spacing: Space.sm,
      children: [
        ActionTile(
          icon: Icons.shield_outlined,
          tone: vpn?.isOn == true ? Tone.success : Tone.neutral,
          title: 'VPN',
          subtitle: vpn == null
              ? 'On/off and exit location'
              : '${VpnCard.stateLabel(vpn)}${vpn.location == null ? '' : ' · ${vpn.location}'}',
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (c) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.xl,
              ),
              child: Consumer<PiProvider>(
                builder: (_, live, _) => VpnCard(pi: live),
              ),
            ),
          ),
        ),
        ActionTile(
          icon: Icons.refresh_rounded,
          tone: Tone.brand,
          title: 'Refresh',
          subtitle: 'Network statistics and device inventory',
          onTap: pi.refreshNow,
        ),
        ActionTile(
          icon: Icons.monitor_heart_outlined,
          tone: Tone.info,
          title: 'Diagnostics',
          subtitle: 'Collector, health, uplink and logs',
          onTap: () => select(HomeTab.hub),
        ),
        ActionTile(
          icon: Icons.open_in_new_rounded,
          tone: Tone.neutral,
          title: 'Argon dashboard',
          subtitle: 'Opens over Tailscale',
          onTap: () async {
            try {
              await HubLinks.open(PiProvider.tailscaleDefault.toString());
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open Argon. Enable Tailscale and retry.',
                    ),
                  ),
                );
              }
            }
          },
        ),
        if (!pi.connected)
          ActionTile(
            icon: Icons.sync_rounded,
            tone: Tone.warning,
            title: 'Retry Argon connection',
            subtitle: pi.lastError ?? 'Looks for Argon on LAN, then Tailscale',
            onTap: pi.reconnect,
          ),
      ],
    );
  }
}
