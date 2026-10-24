import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/hub_widgets.dart';
import 'argon_devices_view.dart';

/// Statistics in Argon mode, built from Argon's collectors only:
///   * household rates and totals: eth1 nftables on Argon (the one link all
///     household traffic crosses; counted once),
///   * VPN: the tun0 subset of those totals (never added on top),
///   * history: Argon's SQLite daily rows with measured coverage,
///   * per-device: estimates from the router observer's sampled rates.
/// Bytes use 1024-based units (KiB, MiB, GiB), rates bits per second.
class ArgonStatisticsView extends StatelessWidget {
  const ArgonStatisticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final theme = Theme.of(context);
    final usage = pi.usage;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Statistics', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Household network measured by Argon'
                      '${usage?.timeZone == null ? '' : ' · days in ${usage!.timeZone}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SectionLabel(
                      'Real-time',
                      trailing: DataStateChip(
                        state: pi.liveState,
                        at: pi.liveAt,
                      ),
                    ),
                    _RealTime(pi: pi),
                    SectionLabel(
                      'Totals',
                      trailing: DataStateChip(
                        state: pi.hubState,
                        at: pi.gatewayAt,
                      ),
                    ),
                    _Totals(pi: pi),
                    const SectionLabel('Download / upload history'),
                    _History(pi: pi),
                    const SectionLabel('VPN share of household traffic'),
                    _VpnShare(pi: pi),
                    const SectionLabel('Device activity today'),
                    _DeviceActivity(pi: pi),
                    const SectionLabel('Collection'),
                    _Collection(pi: pi),
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

class _RealTime extends StatelessWidget {
  const _RealTime({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aggregate = (pi.live?['traffic'] as Map?)?['aggregate'];
    final avg = aggregate is Map ? aggregate['avg1m'] : null;
    final vpnDown = aggregate is Map ? aggregate['vpnDownloadBps'] : null;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          const SizedBox(height: Space.md),
          SizedBox(
            height: 140,
            child: DualRateChart(
              down: [for (final s in pi.liveSamples) s.down],
              up: [for (final s in pi.liveSamples) s.up],
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.xs,
            children: [
              ChartLegend(
                color: context.tone(Tone.brand).foreground,
                label: 'Download',
              ),
              const ChartLegend(color: Palette.amber, label: 'Upload'),
              if (avg is Map && avg['downloadBps'] is num)
                Text(
                  '1-min average ↓ ${formatBitRate(avg['downloadBps'] as num)}'
                  ' ↑ ${formatBitRate((avg['uploadBps'] as num?) ?? 0)}',
                  style: theme.textTheme.labelSmall,
                ),
              if (vpnDown is num && pi.liveFresh)
                Text(
                  'VPN now ↓ ${formatBitRate(vpnDown)}',
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Last ${PiProvider.sampleWindow.inMinutes} minutes sampled while '
            'the app is open · Argon eth1',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String periodFigure(UsagePeriod? p, HubDataState state) {
  if (p == null) return hubValue(state, null);
  final t = p.total;
  if (t == null) return 'Not measured';
  return p.measured == false ? '≥ ${formatBytes(t)}' : formatBytes(t);
}

class _Totals extends StatelessWidget {
  const _Totals({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = pi.usage;
    final rows = <(String, UsagePeriod?)>[
      ('Today', pi.todayUsage),
      ('Yesterday', u?.yesterday),
      ('Last 7 days', u?.last7),
      ('Previous 7 days', u?.previous7),
      ('This month', u?.thisMonth),
      ('Last month', u?.lastMonth),
      ('Last 30 days', u?.last30),
    ];
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (label, p)) in rows.indexed)
            KvRow(
              label,
              [
                periodFigure(p, pi.hubState),
                if (p?.downloadBytes != null && p?.uploadBytes != null)
                  '↓ ${formatBytes(p!.downloadBytes!)} ↑ ${formatBytes(p.uploadBytes!)}',
                if (p?.coverage != null && p!.coverage! < 0.995)
                  '${(p.coverage! * 100).toStringAsFixed(0)}% covered',
              ].join('\n'),
              last: i == rows.length - 1,
            ),
          const SizedBox(height: Space.sm),
          Text(
            '"≥" marks a period Argon measured only partly (a lower bound).',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = pi.usage?.days ?? const <UsageDay>[];
    if (days.isEmpty) {
      return PanelCard(
        child: Text(hubValue(pi.hubState, 'No daily history reported yet.')),
      );
    }
    final muted = theme.colorScheme.onSurfaceVariant;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DailyUsageChart(days: days),
          const SizedBox(height: Space.md),
          for (final d in days.reversed.take(7))
            KvRow(
              d.day,
              d.measured || d.total != null
                  ? '↓ ${formatBytes(d.downloadBytes ?? 0)} · ↑ ${formatBytes(d.uploadBytes ?? 0)}'
                        '${d.coverage != null && d.coverage! < 0.995 ? ' · ${(d.coverage! * 100).toStringAsFixed(0)}%' : ''}'
                  : 'Not measured',
            ),
          Text(
            'Bars: daily total; green: VPN subset.',
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _VpnShare extends StatelessWidget {
  const _VpnShare({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final u = pi.usage;
    final rows = <(String, UsagePeriod?)>[
      ('Today', pi.todayUsage),
      ('Last 7 days', u?.last7),
      ('This month', u?.thisMonth),
    ];
    return PanelCard(
      child: Column(
        children: [
          for (final (label, p) in rows)
            ShareBar(
              label: label,
              share: p?.vpnShare,
              state: pi.hubState,
              unmeasured: p != null && p.measured == false,
            ),
          Text(
            'VPN traffic is the part of household traffic that crossed tun0; '
            'it is included in the totals above, never added to them.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceActivity extends StatelessWidget {
  const _DeviceActivity({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = pi.routerView;
    final top = arrangeArgonClients(
      view?.clients ?? const [],
      sort: ArgonDeviceSort.usage,
    ).where((c) => (c.today?.totalBytes ?? 0) > 0).take(8).toList();
    if (top.isEmpty) {
      return PanelCard(
        child: Text(
          hubValue(pi.hubState, 'No per-device usage recorded today.'),
        ),
      );
    }
    final max = top.first.today!.totalBytes!;
    final estimated = view?.usageMethod == 'estimated';
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in top)
            InkWell(
              onTap: () =>
                  showArgonClientDetails(context, c, estimated: estimated),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${estimated ? '≈ ' : ''}${formatBytes(c.today!.totalBytes!)}',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: c.today!.totalBytes! / (max <= 0 ? 1 : max),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Space.sm),
          Text(
            estimated
                ? 'Estimated usage from the router observer\'s sampled rates '
                      '(not metered). Per-device estimates do not add up to the '
                      'household total, which Argon measures directly.'
                : 'Per-device usage as reported by Argon.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Collection extends StatelessWidget {
  const _Collection({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final history = pi.gateway?['history'];
    final since = history is Map && history['dataSince'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (history['dataSince'] as num).toInt() * 1000,
          )
        : null;
    final lastFlush = history is Map && history['lastFlush'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (history['lastFlush'] as num).toInt() * 1000,
          )
        : null;
    final traffic = pi.live?['traffic'];
    final view = pi.routerView;
    return PanelCard(
      child: Column(
        children: [
          KvRow(
            'Household traffic',
            traffic is Map && traffic['source'] is String
                ? traffic['source'] as String
                : hubValue(pi.liveState, null),
          ),
          KvRow(
            'Live sample',
            pi.liveAt == null ? 'Not yet' : formatAge(pi.liveAt),
          ),
          KvRow(
            'History stored since',
            since == null
                ? hubValue(pi.hubState, null)
                : '${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}',
          ),
          KvRow(
            'Last history write',
            lastFlush == null
                ? hubValue(pi.hubState, null)
                : formatAge(lastFlush),
          ),
          KvRow(
            'Device inventory',
            view == null
                ? hubValue(pi.hubState, null)
                : '${view.sourceLabel} · ${view.observedAt == null ? 'no observation' : formatAge(view.observedAt)}',
          ),
          KvRow(
            'Per-device usage',
            view?.usageMethod == null
                ? 'Not reported'
                : '${view!.usageMethod}${view.usageStale == true ? ' · stale' : ''}'
                      '${view.usageObservedAt == null ? '' : ' · ${formatAge(view.usageObservedAt)}'}',
            last: true,
          ),
        ],
      ),
    );
  }
}
