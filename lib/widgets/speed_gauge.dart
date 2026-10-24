import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/pi_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Upper end of the dial for the rates seen recently, in bits per second:
/// the next 1-2-5 step above the peak, never below 1 Mbit/s. It adapts to
/// what was measured; it is not the internet plan's capacity.
num gaugeScaleBits(num peakBitsPerSecond) {
  final v = math.max(peakBitsPerSecond.toDouble(), 1e6);
  var base = 1.0;
  while (base * 10 <= v) {
    base *= 10;
  }
  for (final m in const [1, 2, 5, 10]) {
    if (base * m >= v) return base * m;
  }
  return base * 10;
}

/// Short dial label: 2000000 -> "2M", 500000 -> "500k".
String gaugeTickLabel(num bits) {
  if (bits >= 1e9) return '${_trim(bits / 1e9)}G';
  if (bits >= 1e6) return '${_trim(bits / 1e6)}M';
  if (bits >= 1e3) return '${_trim(bits / 1e3)}k';
  return '${bits.round()}';
}

String _trim(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// Animated semi-circular speedometer for Argon's live household rates:
/// download on the needle and main arc, upload on the inner arc. The scale
/// adapts to the peak of the recent samples (see [gaugeScaleBits]).
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({
    super.key,
    required this.downBits,
    required this.upBits,
    required this.peakBits,
    required this.state,
    this.at,
  });

  /// Current rates in bits per second; null when not fresh.
  final num? downBits;
  final num? upBits;

  /// Highest rate in the recent samples (bits per second).
  final num peakBits;
  final HubDataState state;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = state == HubDataState.connected && downBits != null;
    final scale = gaugeScaleBits(
      math.max(peakBits, math.max(downBits ?? 0, upBits ?? 0)),
    );
    final down = live ? (downBits! / scale).clamp(0.0, 1.0) : 0.0;
    final up = live ? ((upBits ?? 0) / scale).clamp(0.0, 1.0) : 0.0;
    final idle = live && (downBits! + (upBits ?? 0)) < 8000; // < 1 kB/s
    final (headline, caption) = switch (state) {
      HubDataState.loading => ('—', 'Loading…'),
      HubDataState.unreachable => ('—', 'Argon unreachable'),
      HubDataState.stale => ('—', 'Stale · ${formatAge(at)}'),
      HubDataState.connected =>
        live
            ? (formatBitRate(downBits!), idle ? 'Idle · download' : 'Download')
            : ('—', 'No sample yet'),
    };
    return Semantics(
      container: true,
      label: live
          ? 'Download ${formatBitRate(downBits!)}, upload '
                '${formatBitRate(upBits ?? 0)}, dial scale up to '
                '${formatBitRate(scale)}'
          : 'Speed gauge: $caption',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 200,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(end: Offset(down, up)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => CustomPaint(
              painter: _GaugePainter(
                down: v.dx,
                up: v.dy,
                scale: scale,
                live: live,
                track: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                tick: theme.colorScheme.onSurfaceVariant,
                downColor: context.tone(Tone.brand).foreground,
                upColor: Palette.amber,
                label: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              child: Align(
                alignment: const Alignment(0, 0.62),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        headline,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      caption,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: state == HubDataState.connected
                            ? theme.colorScheme.onSurfaceVariant
                            : context.tone(Tone.warning).foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.down,
    required this.up,
    required this.scale,
    required this.live,
    required this.track,
    required this.tick,
    required this.downColor,
    required this.upColor,
    required this.label,
  });

  final double down;
  final double up;
  final num scale;
  final bool live;
  final Color track;
  final Color tick;
  final Color downColor;
  final Color upColor;
  final TextStyle label;

  static const _start = math.pi * 0.8;
  static const _sweep = math.pi * 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2, size.height * 0.6) * 0.9;
    final center = Offset(size.width / 2, size.height * 0.6);
    Offset at(double a, double r) =>
        center + Offset(math.cos(a), math.sin(a)) * r;
    for (var i = 0; i <= 30; i++) {
      final a = _start + _sweep * i / 30;
      final major = i % 6 == 0;
      canvas.drawLine(
        at(a, radius - (major ? 13 : 7)),
        at(a, radius),
        Paint()
          ..color = (live && i / 30 <= down ? downColor : tick).withValues(
            alpha: major ? 0.9 : 0.45,
          )
          ..strokeWidth = major ? 2.4 : 1.3
          ..strokeCap = StrokeCap.round,
      );
      if (major) {
        final tp = TextPainter(
          text: TextSpan(text: gaugeTickLabel(scale * i / 30), style: label),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          at(a, radius - 27) - Offset(tp.width / 2, tp.height / 2),
        );
      }
    }
    void arc(double r, double fraction, Color color, double width) {
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawArc(
        rect,
        _start,
        _sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = track,
      );
      if (fraction > 0.002) {
        canvas.drawArc(
          rect,
          _start,
          _sweep * fraction,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..color = color,
        );
      }
    }

    arc(radius - 42, down, downColor, 7);
    arc(radius - 54, up, upColor, 4);
    if (live) {
      final a = _start + _sweep * down;
      canvas.drawLine(
        center,
        at(a, radius - 34),
        Paint()
          ..color = downColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(center, 6, Paint()..color = downColor);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.down != down ||
      old.up != up ||
      old.scale != scale ||
      old.live != live ||
      old.downColor != downColor ||
      old.upColor != upColor ||
      old.track != track ||
      old.tick != tick ||
      old.label != label;
}
