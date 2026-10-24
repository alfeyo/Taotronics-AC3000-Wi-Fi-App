import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/hub_widgets.dart';
import '../widgets/speed_gauge.dart';
import 'argon_devices_view.dart';

/// Statistics in Argon mode, built from Argon's collectors only:
///   * household rates and totals: eth1 nftables on Argon (the one link all
///     household traffic crosses; counted once),
///   * VPN: the tun0 subset of those totals (never added on top),
///   * history: Argon's SQLite daily rows (Pi local days) with coverage,
///   * per-device: estimates from the router observer's sampled rates.
/// Live speeds are bits per second; transferred totals bytes (KiB/MiB/GiB).
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
                      'Live speed',
                      trailing: DataStateChip(
                        state: pi.liveState,
                        at: pi.liveAt,
                      ),
                    ),
                    _LiveSpeed(pi: pi),
                    SectionLabel(
                      'Usage',
                      trailing: DataStateChip(
                        state: pi.hubState,
                        at: pi.gatewayAt,
                      ),
                    ),
                    _DayTotals(pi: pi),
                    const SizedBox(height: Space.md),
                    _MoreHistory(pi: pi),
                    const SectionLabel('Device activity · last 7 days'),
                    _WeeklyDevices(pi: pi),
                    const SectionLabel('Monitoring coverage'),
                    _MonitoringCoverage(pi: pi),
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

class _LiveSpeed extends StatelessWidget {
  const _LiveSpeed({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final peakBytes = pi.liveSamples.fold<int>(
      0,
      (m, s) => math.max(m, math.max(s.down, s.up)),
    );
    final aggregate = (pi.live?['traffic'] as Map?)?['aggregate'];
    final avg = aggregate is Map ? aggregate['avg1m'] : null;
    final fresh = pi.liveFresh;
    Widget readout(IconData icon, Color color, String label, num? bits) =>
        Expanded(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                ],
              ),
              Text(
                fresh && bits != null ? formatBitRate(bits) : '—',
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
        );
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpeedGauge(
            downBits: pi.householdDownBitsPerSec,
            upBits: pi.householdUpBitsPerSec,
            peakBits: peakBytes * 8,
            state: pi.liveState,
            at: pi.liveAt,
          ),
          Row(
            children: [
              readout(
                Icons.south_rounded,
                context.tone(Tone.brand).foreground,
                'Download',
                pi.householdDownBitsPerSec,
              ),
              readout(
                Icons.north_rounded,
                Palette.amber,
                'Upload',
                pi.householdUpBitsPerSec,
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          SizedBox(
            height: 130,
            child: DualRateChart(
              down: [for (final s in pi.liveSamples) s.down],
              up: [for (final s in pi.liveSamples) s.up],
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            [
              'Last ${PiProvider.sampleWindow.inMinutes} min while the app is open',
              if (avg is Map && avg['downloadBps'] is num)
                '1-min avg ↓ ${formatBitRate(avg['downloadBps'] as num)}',
              'dial scale follows the recent peak, not your plan speed',
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
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

/// Today and yesterday (Pi local days): downloaded, uploaded, total.
class _DayTotals extends StatelessWidget {
  const _DayTotals({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget day(String title, UsagePeriod? p) {
      String b(int? v) => v == null
          ? (p == null ? hubValue(pi.hubState, null) : 'Not measured')
          : formatBytes(v);
      final partial = p?.measured == false && p?.total != null;
      return Expanded(
        child: PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge),
              const SizedBox(height: Space.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${partial ? '≥ ' : ''}${b(p?.total)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'total',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
              const SizedBox(height: Space.sm),
              _Line(
                icon: Icons.south_rounded,
                color: context.tone(Tone.brand).foreground,
                label: 'Downloaded',
                value: b(p?.downloadBytes),
              ),
              _Line(
                icon: Icons.north_rounded,
                color: Palette.amber,
                label: 'Uploaded',
                value: b(p?.uploadBytes),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        day('Today', pi.todayUsage),
        const SizedBox(width: Space.md),
        day('Yesterday', pi.usage?.yesterday),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Longer periods, daily history and VPN share, collapsed by default.
class _MoreHistory extends StatelessWidget {
  const _MoreHistory({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = pi.usage;
    final rows = <(String, UsagePeriod?)>[
      ('Last 7 days', u?.last7),
      ('Previous 7 days', u?.previous7),
      ('This month', u?.thisMonth),
      ('Last month', u?.lastMonth),
      ('Last 30 days', u?.last30),
    ];
    final days = u?.days ?? const <UsageDay>[];
    return PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: Space.sm),
          childrenPadding: const EdgeInsets.fromLTRB(
            Space.sm,
            0,
            Space.sm,
            Space.md,
          ),
          title: Text('More history', style: theme.textTheme.titleSmall),
          subtitle: Text(
            [
              'Last 7 days ${periodFigure(u?.last7, pi.hubState)}',
              'this month ${periodFigure(u?.thisMonth, pi.hubState)}',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            for (final (label, p) in rows)
              KvRow(
                label,
                [
                  periodFigure(p, pi.hubState),
                  if (p?.downloadBytes != null && p?.uploadBytes != null)
                    '↓ ${formatBytes(p!.downloadBytes!)} ↑ ${formatBytes(p.uploadBytes!)}',
                ].join('\n'),
              ),
            if (days.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              DailyUsageChart(days: days),
              const SizedBox(height: Space.sm),
              for (final d in days.reversed.take(7))
                KvRow(
                  d.day,
                  d.total != null
                      ? '${d.measured ? '' : '≥ '}↓ ${formatBytes(d.downloadBytes!)} · ↑ ${formatBytes(d.uploadBytes!)} · ${coverageShort(d.coverage)}'
                      : 'Not measured',
                ),
            ],
            const SizedBox(height: Space.sm),
            for (final (label, p) in [
              ('VPN share today', pi.todayUsage),
              ('VPN share, last 7 days', u?.last7),
              ('VPN share, this month', u?.thisMonth),
            ])
              ShareBar(
                label: label,
                share: p?.vpnShare,
                state: pi.hubState,
                unmeasured: p != null && p.measured == false,
              ),
            Text(
              '"≥" marks a period Argon measured only partly. VPN traffic '
              'is part of the totals, never added to them.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top devices by estimated transfer over the last seven days, each with a
/// seven-day strip; tap for the per-day breakdown.
class _WeeklyDevices extends StatelessWidget {
  const _WeeklyDevices({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final view = pi.routerView;
    // Align every device to the same Argon-local week, including devices
    // whose newest observation is older than the current reporting day.
    final dates = [
      for (final d in pi.usage?.days ?? const <UsageDay>[]) d.day,
      for (final c in view?.clients ?? const <ArgonClient>[]) ?c.today?.day,
    ]..sort();
    final reportingDay = dates.lastOrNull;
    final ranked =
        [
            for (final c in view?.clients ?? const <ArgonClient>[])
              (c, WeeklyUsage.of(c.usageDays, today: reportingDay)),
          ].where((e) => (e.$2.totalBytes ?? 0) > 0).toList()
          ..sort((a, b) => b.$2.totalBytes!.compareTo(a.$2.totalBytes!));
    if (ranked.isEmpty) {
      return PanelCard(
        child: Text(
          hubValue(pi.hubState, 'No per-device activity recorded this week.'),
        ),
      );
    }
    final top = ranked.take(8).toList();
    final estimated = view?.usageMethod == 'estimated';
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (c, w) in top)
            InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () =>
                  showArgonClientDetails(context, c, estimated: estimated),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${estimated ? '≈ ' : ''}${formatBytes(w.totalBytes!)}'
                            ' · ${coverageShort(w.coverage)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    WeekStrip(week: w),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Space.xs),
          Text(
            estimated
                ? 'Estimated from the router observer\'s sampled rates, only '
                      'for the time it was observing; empty bars are days '
                      'without observations. Not metered.'
                : 'Per-device usage as reported by Argon.',
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// "92% observed" for a coverage fraction.
String coverageShort(double? c) =>
    c == null ? 'coverage unknown' : '${(c * 100).round()}% observed';

/// Seven bars, oldest first; a day without data draws an empty slot.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.week});
  final WeeklyUsage week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.tone(Tone.brand).foreground;
    final dayMax = week.days
        .map((d) => d?.totalBytes ?? 0)
        .fold<int>(1, math.max);
    return SizedBox(
      width: 98,
      height: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in week.days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: d == null
                    ? Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : Container(
                        height: math.max(3, 28 * (d.totalBytes ?? 0) / dayMax),
                        decoration: BoxDecoration(
                          color: color.withValues(
                            alpha: 0.35 + 0.65 * (d.coverage ?? 0.5),
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What "coverage" means for a period: [UsagePeriod.coverage] is the share
/// of that period for which Argon's household traffic collector has usable
/// measurements (measured seconds / period seconds).
const monitoringCoverageExplanation =
    'How much of each period Argon has usable network measurements for. '
    'Gaps mean some activity may not have been recorded, so totals are a '
    'lower bound. It is not Wi-Fi signal, data used or device availability.';

String coverageLabel100(double? c) => c == null
    ? 'Not reported'
    : c >= 0.995
    ? '100%'
    : '${(c * 100).toStringAsFixed(c >= 0.1 ? 0 : 1)}%';

class _MonitoringCoverage extends StatelessWidget {
  const _MonitoringCoverage({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final u = pi.usage;
    final rows = <(String, UsagePeriod?)>[
      ('Today so far', pi.usage?.today),
      ('Yesterday', u?.yesterday),
      ('Last 7 days', u?.last7),
      ('This month', u?.thisMonth),
    ];
    final history = pi.gateway?['history'];
    final since = history is Map && history['dataSince'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (history['dataSince'] as num).toInt() * 1000,
          )
        : null;
    final view = pi.routerView;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Household measurements',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'What is monitoring coverage?',
                icon: const Icon(Icons.info_outline_rounded, size: 20),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Monitoring coverage'),
                    content: const Text(monitoringCoverageExplanation),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Text(
            monitoringCoverageExplanation,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: Space.sm),
          for (final (i, (label, p)) in rows.indexed)
            KvRow(
              label,
              p == null
                  ? hubValue(pi.hubState, null)
                  : coverageLabel100(p.coverage),
              tone: p?.coverage != null && p!.coverage! < 0.95
                  ? Tone.warning
                  : null,
              last: i == rows.length - 1,
            ),
          const SizedBox(height: Space.sm),
          Text(
            [
              if (since != null)
                'Stored since ${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}',
              if (pi.liveAt != null) 'live sample ${formatAge(pi.liveAt)}',
              if (view?.observedAt != null)
                'devices ${formatAge(view!.observedAt)} (${view.sourceLabel})',
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
