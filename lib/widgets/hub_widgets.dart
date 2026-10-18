import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/pi_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_widgets.dart';

/// What to show instead of a value that is not available, by data state:
/// nothing has arrived yet ("Loading…"), Argon cannot be reached
/// ("Unreachable"), or Argon answered without this field ("Not reported").
/// A real value is never replaced by 0.
String hubValue(HubDataState state, String? value) {
  if (value != null) return value;
  return switch (state) {
    HubDataState.loading => 'Loading…',
    HubDataState.unreachable => 'Unreachable',
    _ => 'Not reported',
  };
}

/// "Loading", "Live", "Stale · 2 min ago" or "Unreachable".
class DataStateChip extends StatelessWidget {
  const DataStateChip({super.key, required this.state, this.at});

  final HubDataState state;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      HubDataState.loading => const StatusPill(label: 'Loading…'),
      HubDataState.connected => const StatusPill(
        label: 'Live',
        tone: Tone.success,
      ),
      HubDataState.stale => StatusPill(
        label: 'Stale · ${formatAge(at)}',
        tone: Tone.warning,
        icon: Icons.history_rounded,
      ),
      HubDataState.unreachable => const StatusPill(
        label: 'Unreachable',
        tone: Tone.warning,
      ),
    };
  }
}

/// Label/value row with a hairline divider.
class KvRow extends StatelessWidget {
  const KvRow(
    this.label,
    this.value, {
    super.key,
    this.last = false,
    this.tone,
  });

  final String label;
  final String value;
  final bool last;
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
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
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge?.copyWith(
                color: tone == null ? null : context.tone(tone!).foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A prominent live rate: "84.2 Mbps", or why there is no current value.
class BigRate extends StatelessWidget {
  const BigRate({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
    required this.bitsPerSecond,
    required this.state,
    this.at,
  });

  final String label;
  final IconData icon;
  final Tone tone;
  final num? bitsPerSecond;
  final HubDataState state;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = bitsPerSecond == null
        ? switch (state) {
            HubDataState.stale => 'Stale',
            _ => hubValue(state, null),
          }
        : formatBitRate(bitsPerSecond!);
    final live = bitsPerSecond != null;
    return Semantics(
      container: true,
      label: '$label $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: context.tone(tone).foreground),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style:
                    (live
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.titleLarge)
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: live
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
              ),
            ),
            if (!live && state == HubDataState.stale && at != null)
              Text(
                'Last update ${formatAge(at)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.tone(Tone.warning).foreground,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Download and upload over time (values are bytes/s; axis shows bit rates).
class DualRateChart extends StatelessWidget {
  const DualRateChart({super.key, required this.down, required this.up});

  final List<int> down;
  final List<int> up;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (down.length < 2) {
      return Center(
        child: Text(
          'Collecting samples… the chart fills in every few seconds.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final peak = math.max(1, [...down, ...up].reduce(math.max));
    return Semantics(
      label:
          'Download and upload over the last ${down.length} samples, '
          'peak ${formatBitRate(peak * 8)}',
      child: CustomPaint(
        size: Size.infinite,
        painter: _DualPainter(
          down: down,
          up: up,
          downColor: context.tone(Tone.brand).foreground,
          upColor: Palette.amber,
          grid: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          label: theme.textTheme.labelSmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          peakLabel: formatBitRate(peak * 8),
        ),
      ),
    );
  }
}

class _DualPainter extends CustomPainter {
  _DualPainter({
    required this.down,
    required this.up,
    required this.downColor,
    required this.upColor,
    required this.grid,
    required this.label,
    required this.peakLabel,
  });

  final List<int> down;
  final List<int> up;
  final Color downColor;
  final Color upColor;
  final Color grid;
  final TextStyle label;
  final String peakLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = math.max(1, [...down, ...up].reduce(math.max)).toDouble();
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = 14 + (size.height - 18) * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final tp = TextPainter(
      text: TextSpan(text: peakLabel, style: label),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    tp.paint(canvas, Offset(size.width - tp.width, 0));

    void series(List<int> values, Color color, {bool fill = false}) {
      if (values.length < 2) return;
      final dx = size.width / (values.length - 1);
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = i * dx;
        final y = size.height - 4 - (values[i] / maxV) * (size.height - 18);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      if (fill) {
        final area = Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.26),
                color.withValues(alpha: 0),
              ],
            ).createShader(Offset.zero & size),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    series(down, downColor, fill: true);
    series(up, upColor);
  }

  @override
  bool shouldRepaint(_DualPainter old) =>
      old.down != down || old.up != up || old.peakLabel != peakLabel;
}

/// Small coloured legend entry.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Daily household totals; the VPN part of each day is drawn inside its bar
/// (it is a subset of the total, never added on top).
class DailyUsageChart extends StatelessWidget {
  const DailyUsageChart({super.key, required this.days});

  final List<UsageDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = days
        .map((d) => d.measured ? (d.total ?? 0) : 0)
        .fold<int>(1, math.max);
    final vpnColor = context.tone(Tone.success).foreground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Tooltip(
                    message: d.measured && d.total != null
                        ? '${d.day}: ${formatBytes(d.total!)}'
                              '${d.vpnBytes == null ? '' : ' · VPN ${formatBytes(d.vpnBytes!)}'}'
                        : '${d.day}: not measured',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _Bar(
                        fraction: d.measured && d.total != null
                            ? (d.total! / max).clamp(0.02, 1.0).toDouble()
                            : 0.02,
                        vpnFraction:
                            d.measured &&
                                d.vpnBytes != null &&
                                (d.total ?? 0) > 0
                            ? (d.vpnBytes! / d.total!).clamp(0.0, 1.0)
                            : 0,
                        color: d.measured
                            ? Palette.amber.withValues(alpha: 0.85)
                            : theme.colorScheme.outlineVariant,
                        vpnColor: vpnColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              days.first.day.length >= 10
                  ? days.first.day.substring(5)
                  : days.first.day,
              style: theme.textTheme.labelSmall,
            ),
            Text('Today', style: theme.textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.lg,
          runSpacing: Space.xs,
          children: [
            const ChartLegend(color: Palette.amber, label: 'Household total'),
            ChartLegend(color: vpnColor, label: 'Part via VPN'),
            ChartLegend(
              color: theme.colorScheme.outlineVariant,
              label: 'Not measured',
            ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.vpnFraction,
    required this.color,
    required this.vpnColor,
  });

  final double fraction;
  final double vpnFraction;
  final Color color;
  final Color vpnColor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: fraction,
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: color),
            if (vpnFraction > 0)
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: vpnFraction,
                  widthFactor: 1,
                  child: ColoredBox(color: vpnColor.withValues(alpha: 0.8)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A share (0..1) as a labelled bar.
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.label,
    required this.share,
    required this.state,
  });

  final String label;
  final double? share;
  final HubDataState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                share == null ? hubValue(state, null) : formatShare(share!),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: share ?? 0,
              color: context.tone(Tone.success).foreground,
              backgroundColor: theme.colorScheme.outlineVariant.withValues(
                alpha: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
