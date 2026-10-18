import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../services/argon_status.dart';
import '../services/pi_api.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/home_widgets.dart';
import '../widgets/hub_widgets.dart';
import '../widgets/pi_board.dart';
import '../widgets/vpn_card.dart';
import '../services/hub_links.dart';
import 'nokia_mesh_screen.dart';
import 'diagnostics_screen.dart';

/// Network Hub: Argon, the Raspberry Pi between the internet and the
/// TaoTronics router. Connection is automatic (PiProvider); this screen shows
/// what Argon measures (household traffic, usage, VPN, uplink, health) and
/// hosts the operator-authorized VPN control. Pairing and manual endpoints
/// live in secondary sheets, never in place of the dashboard.
class NetworkHubScreen extends StatelessWidget {
  const NetworkHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final router = context.watch<RouterProvider>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: pi.reconnect,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              120,
            ),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(pi: pi, router: router),
                    const SizedBox(height: Space.md),
                    _Hero(pi: pi),
                    const SizedBox(height: Space.lg),
                    _QuickActions(pi: pi, router: router),
                    const SizedBox(height: Space.md),
                    _SyncCard(pi: pi, router: router),
                    SectionLabel(
                      'Live traffic',
                      trailing: DataStateChip(
                        state: pi.liveState,
                        at: pi.liveAt,
                      ),
                    ),
                    _LiveTraffic(pi: pi),
                    SectionLabel(
                      'Usage',
                      trailing: pi.usage?.timeZone == null
                          ? null
                          : Text(
                              pi.usage!.timeZone!,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                    ),
                    _Usage(pi: pi),
                    _ClientUsage(pi: pi),
                    const SectionLabel('VPN'),
                    VpnCard(pi: pi),
                    const SectionLabel('Health'),
                    _Health(pi: pi, router: router),
                    if (pi.gatewayInfo?['storage'] is Map &&
                        pi.gatewayInfo!['storage']['usedPercent'] is num &&
                        (pi.gatewayInfo!['storage']['usedPercent'] as num)
                            .isFinite)
                      Padding(
                        padding: const EdgeInsets.all(Space.md),
                        child: Text(
                          'Storage: ${pi.gatewayInfo!['storage']['usedPercent']}% used · filesystem capacity; SD-card health not measured',
                        ),
                      ),
                    const SectionLabel('Internet uplink'),
                    _Uplink(pi: pi),
                    const SectionLabel('Recent events'),
                    _Events(pi: pi),
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

String _linkLine(PiProvider pi) {
  return switch (pi.state) {
    PiLinkState.connected => 'Connected · ${pi.transportKind!.label}',
    PiLinkState.unreachable => 'Unreachable · retrying automatically',
    _ => 'Looking for Argon…',
  };
}

/// "Raspberry Pi 4 Model B" from "Raspberry Pi 4 Model B Rev 1.2".
String hubModel(PiProvider pi) {
  final model = pi.gatewayInfo?['model'];
  return model is String && model.trim().isNotEmpty
      ? model.replaceAll(RegExp(r'\s+Rev\s+[\d.]+$'), '')
      : 'Raspberry Pi';
}

class _Header extends StatelessWidget {
  const _Header({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = pi.connected
        ? Tone.success
        : pi.state == PiLinkState.unreachable
        ? Tone.warning
        : Tone.neutral;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Network Hub',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.tone(tone).foreground,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _linkLine(pi),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
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
          tooltip: 'Manage connection',
          onPressed: () => showManageConnection(context),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = pi.gatewayInfo;
    final fresh = pi.gatewayFresh;
    final online =
        pi.uplink?.online ??
        ((g?['upstream'] is Map) ? (g!['upstream'] as Map)['online'] : null);
    final vpn = pi.vpn;
    return Column(
      children: [
        SizedBox(
          height: 200,
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
                            .withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Semantics(
                image: true,
                label:
                    'Raspberry Pi Network Hub, ${pi.connected ? 'connected' : 'not connected'}',
                child: PiBoard(
                  active: pi.connected,
                  dim: !pi.connected,
                  size: 240,
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
        const SizedBox(height: 2),
        Text(
          'Network Hub between your internet and the router',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            StatusPill(
              label: pi.connected
                  ? pi.transportKind!.label
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
                _ => Icons.lan_rounded,
              },
            ),
            if (pi.hubState != HubDataState.connected &&
                pi.hubState != HubDataState.unreachable)
              DataStateChip(state: pi.hubState, at: pi.gatewayAt),
            if (fresh && online is bool)
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
                'Uptime',
                hubValue(
                  pi.hubState,
                  g?['uptimeSeconds'] is num
                      ? formatUptime((g!['uptimeSeconds'] as num).round())
                      : null,
                ),
              ),
              KvRow(
                'Last contact',
                pi.lastContact == null ? 'Not yet' : formatAge(pi.lastContact),
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
              if (pi.hubState == HubDataState.stale)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    'Showing the last report received ${formatAge(pi.gatewayAt)}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.tone(Tone.warning).foreground,
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

/// Device synchronization; pairing happens in a sheet, never inline.
class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (pi.paired) {
      final status = !pi.syncEnabled
          ? 'Synchronization is off'
          : pi.sharedAt != null &&
                DateTime.now().difference(pi.sharedAt!).inSeconds < 60
          ? 'Shared ${pi.sharedCount ?? 0} router device${pi.sharedCount == 1 ? '' : 's'} ${formatAge(pi.sharedAt)}'
          : pi.syncError ?? 'Waiting to share router devices';
      return PanelCard(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.sm,
          Space.md,
        ),
        child: Row(
          children: [
            IconBadge(
              Icons.sync_rounded,
              tone: pi.syncActive && pi.syncError == null
                  ? Tone.success
                  : Tone.neutral,
              size: 40,
              round: true,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device synchronization',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Switch(value: pi.syncEnabled, onChanged: pi.setSyncEnabled),
          ],
        ),
      );
    }
    return ActionTile(
      icon: Icons.devices_rounded,
      tone: Tone.accent,
      title: pi.credentialRejected
          ? 'Pair again to resume sharing'
          : 'Enable device synchronization',
      subtitle:
          'Share your router\'s connected devices with Argon while the app is open.',
      trailing: PillButton(
        label: 'Set up',
        onPressed: pi.connected
            ? () => _showPairingSheet(context, pi, router)
            : null,
      ),
    );
  }
}

Future<void> _showPairingSheet(
  BuildContext context,
  PiProvider pi,
  RouterProvider router,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PairingSheet(pi: pi, router: router),
  );
}

class _PairingSheet extends StatefulWidget {
  const _PairingSheet({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;

  @override
  State<_PairingSheet> createState() => _PairingSheetState();
}

class _PairingSheetState extends State<_PairingSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pi.pair(
        _code.text,
        deviceName:
            'TT Router · ${widget.router.currentRouter?.displayName ?? 'phone'}',
      );
      if (mounted) Navigator.pop(context);
    } on PiApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pair with Argon', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            'On Argon open Devices → Pair TT Router app, then enter the 6-digit code.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Pairing code',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _pair(),
                ),
              ),
              const SizedBox(width: Space.sm),
              PillButton(
                label: _busy ? 'Pairing…' : 'Pair',
                primary: true,
                onPressed: _busy ? null : _pair,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.tone(Tone.danger).foreground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveTraffic extends StatelessWidget {
  const _LiveTraffic({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = pi.liveSamples;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BigRate(
                  label: 'Download',
                  icon: Icons.south_rounded,
                  tone: Tone.brand,
                  bitsPerSecond: pi.householdDownBitsPerSec,
                  state: pi.liveState,
                  at: pi.liveAt,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: BigRate(
                  label: 'Upload',
                  icon: Icons.north_rounded,
                  tone: Tone.accent,
                  bitsPerSecond: pi.householdUpBitsPerSec,
                  state: pi.liveState,
                  at: pi.liveAt,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            height: 140,
            child: DualRateChart(
              down: [for (final s in samples) s.down],
              up: [for (final s in samples) s.up],
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChartLegend(
                color: context.tone(Tone.brand).foreground,
                label: 'Download',
              ),
              const ChartLegend(color: Palette.amber, label: 'Upload'),
              Text(
                'Last 10 min · ${samples.length} samples',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Measured by Argon where household traffic enters your router (eth1).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({
    required this.label,
    required this.period,
    required this.state,
    this.previous,
    this.compareLabel,
  });

  final String label;
  final UsagePeriod? period;
  final UsagePeriod? previous;
  final String? compareLabel;
  final HubDataState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final p = period;
    final value = p == null
        ? hubValue(state, null)
        : p.measured == false
        ? 'Not measured'
        : p.total == null
        ? 'Not reported'
        : formatBytes(p.total!);
    final comparable =
        p != null &&
        p.hasTotal &&
        previous != null &&
        previous!.hasTotal &&
        compareLabel != null;
    final details = <String>[
      if (p != null &&
          p.measured != false &&
          p.downloadBytes != null &&
          p.uploadBytes != null)
        '↓ ${formatBytes(p.downloadBytes!)} · ↑ ${formatBytes(p.uploadBytes!)}',
      if (p?.coverage != null && p!.coverage! < 0.995 && p.measured != false)
        'Measured ${(p.coverage!.clamp(0, 1) * 100).round()}% of the time',
    ];
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: PanelCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p?.hasTotal == true ? null : muted,
                  ),
                ),
              ),
              for (final d in details)
                Text(
                  d,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              if (comparable)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${formatChange(p.total!, previous!.total!)} $compareLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.tone(Tone.info).foreground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Usage extends StatelessWidget {
  const _Usage({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final state = pi.hubState;
    final usage = pi.usage;
    final today = pi.todayUsage;
    final days = usage?.days ?? const <UsageDay>[];
    final usageState = state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minTileWidth: 150,
          maxColumns: 3,
          spacing: Space.md,
          children: [
            _PeriodTile(
              label: 'Today',
              period: today,
              state: today == null && pi.live != null
                  ? HubDataState.connected
                  : usageState,
            ),
            _PeriodTile(
              label: 'Last 7 days',
              period: usage?.last7,
              previous: usage?.previous7,
              compareLabel: 'vs previous 7 days',
              state: usageState,
            ),
            _PeriodTile(
              label: 'This month',
              period: usage?.thisMonth,
              // A partial month is never compared with a complete one.
              previous: null,
              state: usageState,
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'VPN share of household traffic',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: Space.xs),
              ShareBar(
                label: 'Today',
                share: today?.measured == false ? null : today?.vpnShare,
                unmeasured: today?.measured == false,
                state: usageState,
              ),
              ShareBar(
                label: 'Last 7 days',
                share: usage?.last7?.measured == false
                    ? null
                    : usage?.last7?.vpnShare,
                unmeasured: usage?.last7?.measured == false,
                state: usageState,
              ),
              ShareBar(
                label: 'This month',
                share: usage?.thisMonth?.measured == false
                    ? null
                    : usage?.thisMonth?.vpnShare,
                unmeasured: usage?.thisMonth?.measured == false,
                state: usageState,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'VPN traffic is part of the household totals above, not added to them.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Daily usage', style: theme.textTheme.titleSmall),
              const SizedBox(height: Space.md),
              if (days.isEmpty)
                Text(
                  state == HubDataState.connected || state == HubDataState.stale
                      ? 'No daily history reported yet.'
                      : hubValue(state, null),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                )
              else
                DailyUsageChart(days: days),
            ],
          ),
        ),
      ],
    );
  }
}

class _Health extends StatelessWidget {
  const _Health({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = pi.hubState;
    final g = pi.gatewayInfo;
    final cpu = g?['cpuPercent'];
    final temp = g?['temperatureC'];
    final mem = (g?['memory'] is Map)
        ? (g!['memory'] as Map)['usedPercent']
        : null;
    final throttled = g?['activeThrottling'];
    final rv = pi.routerView;
    final connected = router.isConnected;
    final devicesAt = router.devicesUpdatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(
                    Icons.router_rounded,
                    tone: connected ? Tone.brand : Tone.neutral,
                    size: 36,
                    round: true,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      'TaoTronics router',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              KvRow(
                'App connection (MQTT)',
                connected
                    ? 'Connected'
                    : router.isReconnecting
                    ? 'Reconnecting'
                    : 'Not connected',
                tone: connected ? Tone.success : Tone.warning,
              ),
              KvRow(
                'Router internet report',
                connected && router.hasInternetStatus
                    ? (router.internetConnected ? 'Online' : 'Offline')
                    : 'Not reported',
              ),
              KvRow(
                'Devices online',
                connected && devicesAt != null
                    ? '${router.reportedOnlineDeviceCount} · router, ${formatAge(devicesAt)}'
                    : 'Not reported',
              ),
              KvRow(
                'Devices seen by Argon',
                hubValue(
                  state,
                  rv?.devicesOnline == null
                      ? null
                      : '${rv!.devicesOnline} · Argon snapshot'
                            '${rv.observedAt == null ? '' : ', ${formatAge(rv.observedAt)}'}',
                ),
              ),
              KvRow(
                'Mesh nodes',
                connected && router.reportedTotalNodeCount > 0
                    ? '${router.reportedOnlineNodeCount}/${router.reportedTotalNodeCount} online · router'
                    : 'Not reported',
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        ResponsiveGrid(
          minTileWidth: 140,
          maxColumns: 4,
          spacing: Space.md,
          children: [
            StatTile(
              icon: Icons.memory_rounded,
              value: hubValue(state, cpu is num ? '${cpu.round()}%' : null),
              label: 'Pi CPU',
            ),
            StatTile(
              icon: Icons.thermostat_rounded,
              value: hubValue(
                state,
                temp is num ? '${temp.toStringAsFixed(0)}°C' : null,
              ),
              label: 'Pi temperature',
              tone: temp is num && temp >= 75
                  ? Tone.danger
                  : temp is num && temp >= 65
                  ? Tone.warning
                  : Tone.brand,
            ),
            StatTile(
              icon: Icons.sd_storage_rounded,
              value: hubValue(state, mem is num ? '${mem.round()}%' : null),
              label: 'Pi memory',
            ),
            StatTile(
              icon: Icons.bolt_rounded,
              value: hubValue(
                state,
                throttled is bool ? (throttled ? 'Active' : 'None') : null,
              ),
              label: 'Throttling',
              tone: throttled == true ? Tone.danger : Tone.success,
            ),
          ],
        ),
      ],
    );
  }
}

class _Uplink extends StatelessWidget {
  const _Uplink({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final state = pi.hubState;
    final u = pi.uplink;
    final legacy = pi.gatewayInfo?['upstream'] is Map
        ? (pi.gatewayInfo!['upstream'] as Map).cast<String, dynamic>()
        : null;
    final online =
        u?.online ??
        (legacy?['online'] is bool ? legacy!['online'] as bool : null);
    final active =
        u?.active ??
        [
          if (legacy?['ssid'] is String) legacy!['ssid'] as String,
          if (legacy?['interface'] is String) legacy!['interface'] as String,
        ].join(' · ');
    final profiles = u?.profiles;
    final radios = u?.radios;
    String v(String? value) => hubValue(state, value);
    return PanelCard(
      child: Column(
        children: [
          KvRow(
            'Internet via Argon',
            v(online == null ? null : (online ? 'Online' : 'Offline')),
            tone: online == null
                ? null
                : online
                ? Tone.success
                : Tone.danger,
          ),
          KvRow('Connection type', v(u?.type)),
          KvRow('Active link', v(active.isEmpty ? null : active)),
          KvRow('Upstream gateway', v(u?.gatewayIp)),
          KvRow('Since', v(u?.since == null ? null : formatAge(u!.since))),
          KvRow(
            'Fallback',
            v(
              u?.fallbackReady == null
                  ? null
                  : (u!.fallbackReady! ? 'Configured' : 'Not ready'),
            ),
            tone: u?.fallbackReady == null
                ? null
                : u!.fallbackReady!
                ? Tone.success
                : Tone.warning,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.sm),
            child: Text(
              'Backup readiness reflects the saved profile and radio. Hotspot reachability is verified only when it connects.',
            ),
          ),
          KvRow(
            'Fallback networks',
            v(
              profiles == null
                  ? null
                  : profiles.isEmpty
                  ? 'None configured'
                  : profiles
                        .map(
                          (p) => [
                            p.ssid ?? p.name ?? 'Unnamed',
                            if (p.priority != null) 'priority ${p.priority}',
                          ].join(' · '),
                        )
                        .join('\n'),
            ),
          ),
          KvRow(
            'Fallback radios',
            v(
              radios == null
                  ? null
                  : radios.isEmpty
                  ? 'None available'
                  : radios.join(', '),
            ),
            last: true,
          ),
        ],
      ),
    );
  }
}

class _Events extends StatelessWidget {
  const _Events({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = pi.events.take(5).toList();
    return PanelCard(
      child: events.isEmpty
          ? Text(
              'No VPN, uplink or monitoring changes observed.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final e in events)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      switch (e.severity) {
                        'warning' || 'error' => Icons.warning_amber_rounded,
                        'success' => Icons.check_circle_rounded,
                        _ => Icons.info_outline_rounded,
                      },
                      color: context.tone(switch (e.severity) {
                        'error' => Tone.danger,
                        'warning' => Tone.warning,
                        'success' => Tone.success,
                        _ => Tone.info,
                      }).foreground,
                    ),
                    title: Text(e.title),
                    subtitle: Text('${e.message} · ${formatAge(e.at)}'),
                  ),
              ],
            ),
    );
  }
}

/// Advanced connection details and settings, out of the main flow.
Future<void> showManageConnection(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => const _ManageSheet(),
  );
}

class _ManageSheet extends StatefulWidget {
  const _ManageSheet();

  @override
  State<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends State<_ManageSheet> {
  final _manual = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _manual.text = context.read<PiProvider>().manualEndpoint?.toString() ?? '';
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _toggleBluetooth(PiProvider pi, bool value) async {
    if (value) {
      final status = await Permission.bluetoothConnect.request();
      if (!status.isGranted) {
        setState(
          () => _error =
              'Bluetooth permission was not granted; the fallback stays off.',
        );
        return;
      }
    }
    await pi.setBluetoothFallback(value);
  }

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          Space.lg,
          0,
          Space.lg,
          Space.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Text('Network Hub connection', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.md),
          PanelCard(
            child: Column(
              children: [
                KvRow('Status', _linkLine(pi)),
                KvRow(
                  'Route',
                  pi.connected
                      ? '${pi.transportKind!.label} · ${pi.transport!.describe}'
                      : '—',
                ),
                KvRow(
                  'Trusted Argon',
                  pi.trustedId == null
                      ? 'Not yet'
                      : '${pi.trustedId!.substring(0, 8)}…',
                ),
                KvRow(
                  'Order tried',
                  'Local 192.168.50.1 → Tailscale 100.94.137.17${pi.manualEndpoint != null ? ' → ${pi.manualEndpoint!.host}' : ''}${pi.bluetoothFallback ? ' → Bluetooth' : ''}',
                ),
                KvRow(
                  'Synchronization',
                  pi.paired
                      ? (pi.pairedName ?? 'Paired')
                      : pi.credentialRejected
                      ? 'Pairing revoked'
                      : 'Not paired',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bluetooth fallback'),
            subtitle: Text(
              pi.bluetoothAddress == null
                  ? 'Available after Argon has been reached once over the network.'
                  : 'Read-only monitoring over Bluetooth when no network route works. Requires pairing.',
            ),
            value: pi.bluetoothFallback,
            onChanged: pi.bluetoothAddress == null
                ? null
                : (v) => _toggleBluetooth(pi, v),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _manual,
            decoration: const InputDecoration(
              labelText: 'Additional address (optional)',
              hintText: 'https://… or http://<private IP>',
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              PillButton(
                label: 'Save address',
                onPressed: () async {
                  try {
                    await pi.setManualEndpoint(_manual.text);
                    setState(() => _error = null);
                  } on FormatException catch (e) {
                    setState(() => _error = e.message);
                  }
                },
              ),
              const SizedBox(width: Space.sm),
              PillButton(
                label: 'Retry now',
                icon: Icons.refresh_rounded,
                onPressed: pi.reconnect,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.tone(Tone.danger).foreground,
                ),
              ),
            ),
          const SizedBox(height: Space.lg),
          if (pi.trustedId != null || pi.paired)
            PillButton(
              label: 'Forget this Argon',
              icon: Icons.link_off_rounded,
              onPressed: () async {
                await pi.forget();
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh statistics'),
        onPressed: pi.reconnect,
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.devices),
        label: const Text('Refresh devices'),
        onPressed: !router.isConnected || router.isLivePaused
            ? null
            : router.refreshDevices,
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.router),
        label: const Text('Nokia Mesh'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NokiaMeshScreen()),
        ),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.monitor_heart_outlined),
        label: const Text('Diagnostics'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
        ),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.open_in_new),
        label: const Text('Argon dashboard'),
        onPressed: () async {
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
      OutlinedButton.icon(
        icon: const Icon(Icons.notifications_none),
        label: Text('Network alerts (${pi.unreadEvents})'),
        onPressed: () {
          pi.markEventsRead();
          showModalBottomSheet<void>(
            context: context,
            builder: (_) => SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(Space.lg),
                children: [
                  const Text(
                    'Recent network alerts',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (pi.events.isEmpty)
                    const Text('No observed network events.'),
                  for (final e in pi.events.take(30))
                    ListTile(
                      title: Text(e.title),
                      subtitle: Text('${e.message} · ${e.at.toLocal()}'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
}

String _estimate(Map c) {
  final usage = c['usage'];
  final today = usage is Map ? usage['today'] : null;
  final total = today is Map ? today['totalBytes'] : null;
  final coverage = today is Map ? today['coverage'] : null;
  return total is num && total.isFinite && total >= 0
      ? '≈ ${formatBytes(total.toInt())}${coverage is num && coverage.isFinite ? '\n${(coverage.clamp(0, 1) * 100).toStringAsFixed(1)}% observed' : ''}'
      : 'Not observed today';
}

class _ClientUsage extends StatelessWidget {
  const _ClientUsage({required this.pi});
  final PiProvider pi;
  @override
  Widget build(BuildContext context) {
    final router = pi.gateway?['router'];
    final rawClients = router is Map ? router['clients'] : null;
    final clients = rawClients is List
        ? rawClients.whereType<Map>().toList()
        : const <Map>[];
    return ExpansionTile(
      title: const Text('Device usage & coverage'),
      subtitle: Text('${clients.length} known identities · observed estimates'),
      children: [
        const Padding(
          padding: EdgeInsets.all(Space.md),
          child: Text(
            'Estimates integrate short observed router-rate intervals only. Gaps over 45 seconds are excluded. MAC changes remain separate identities; VPN attribution is unavailable behind NAT.',
          ),
        ),
        if (clients.isEmpty)
          const ListTile(
            title: Text(
              'Waiting for a paired phone to share router observations.',
            ),
          ),
        for (final c in clients)
          ListTile(
            title: Text(
              c['name']?.toString() ?? c['mac']?.toString() ?? 'Unknown device',
            ),
            subtitle: Text(
              '${c['ip'] ?? 'IP unknown'} · ${c['mac'] ?? 'MAC unknown'}',
            ),
            trailing: SizedBox(
              width: 130,
              child: Text(_estimate(c), textAlign: TextAlign.right),
            ),
          ),
      ],
    );
  }
}
