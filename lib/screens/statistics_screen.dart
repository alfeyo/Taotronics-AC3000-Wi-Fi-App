import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/router_provider.dart';
import '../services/router_certificate_verifier.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import 'devices_screen.dart';

/// Live network statistics built only from real measurements: router
/// telemetry and rate samples collected while the app is open.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

enum _Window {
  oneMinute('1 min', Duration(minutes: 1)),
  fiveMinutes('5 min', Duration(minutes: 5)),
  session('Session', null);

  const _Window(this.label, this.span);
  final String label;
  final Duration? span;
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  _Window _window = _Window.oneMinute;
  bool _measuring = false;

  Future<void> _measure(RouterProvider provider) async {
    setState(() => _measuring = true);
    await provider.measureRouterResponse();
    if (mounted) setState(() => _measuring = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final theme = Theme.of(context);
    final connected = provider.isConnected;
    final samples = provider.rateSamples;
    final span = samples.length < 2
        ? Duration.zero
        : samples.last.time.difference(samples.first.time);
    final ssid = provider.wirelessNetworksParsed
        .where((n) => n.isEnabled && n.ssid.isNotEmpty)
        .firstOrNull
        ?.ssid;

    final windowed = _window.span == null
        ? samples
        : samples
              .where(
                (s) => samples.isEmpty
                    ? false
                    : samples.last.time.difference(s.time) <= _window.span!,
              )
              .toList();

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      kicker: 'Wi-Fi statistics',
                      title: 'Statistics',
                      subtitle: ssid == null
                          ? 'Live measurements from your router'
                          : '$ssid · live measurements',
                    ),
                    const SizedBox(height: Space.lg),
                    const ConnectionStatusBanners(),
                    _GaugeCard(provider: provider),
                    const SectionLabel('Throughput'),
                    PanelCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 0,
                            runSpacing: Space.sm,
                            children: [
                              for (final w in _Window.values) ...[
                                ChoiceChip(
                                  label: Text(w.label),
                                  selected: _window == w,
                                  onSelected:
                                      w.span == null ||
                                          span >= w.span! * 0.5 ||
                                          w == _Window.oneMinute
                                      ? (_) => setState(() => _window = w)
                                      : null,
                                ),
                                const SizedBox(width: Space.sm),
                              ],
                            ],
                          ),
                          const SizedBox(height: Space.md),
                          SizedBox(
                            height: 180,
                            child: windowed.length < 2
                                ? Center(
                                    child: Text(
                                      connected
                                          ? 'Collecting samples… the chart '
                                                'fills in every few seconds.'
                                          : 'No live samples while '
                                                'disconnected.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  )
                                : ThroughputChart(samples: windowed),
                          ),
                          const SizedBox(height: Space.sm),
                          Wrap(
                            spacing: Space.lg,
                            runSpacing: Space.xs,
                            children: [
                              _Legend(
                                color: theme.colorScheme.primary,
                                label: 'Download',
                              ),
                              const _Legend(
                                color: Palette.amber,
                                label: 'Upload',
                              ),
                              Text(
                                '${windowed.length} samples',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SectionLabel('Session transfer'),
                    _TransferCard(provider: provider),
                    const SectionLabel('Devices'),
                    _DevicesCard(provider: provider),
                    const SectionLabel('Wi-Fi availability'),
                    _WifiAvailability(provider: provider),
                    const SectionLabel('Internet'),
                    _InternetCard(
                      provider: provider,
                      measuring: _measuring,
                      onMeasure: connected ? () => _measure(provider) : null,
                    ),
                    const SizedBox(height: Space.md),
                    _TechnicalDetails(provider: provider),
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

String _mbps(int bytesPerSecond) {
  final mbps = bytesPerSecond * 8 / 1e6;
  return mbps >= 10
      ? '${mbps.toStringAsFixed(0)} Mbps'
      : mbps >= 1
      ? '${mbps.toStringAsFixed(1)} Mbps'
      : '${(mbps * 1000).toStringAsFixed(0)} kbps';
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Speed dial for the current download rate. The scale adapts to this
/// session's peak so the needle stays readable.
class _GaugeCard extends StatelessWidget {
  const _GaugeCard({required this.provider});

  final RouterProvider provider;

  static int _niceMax(int value) {
    // 1, 2, 5 × 10^n bytes per second, at least 64 KB/s.
    final v = math.max(value, 64 * 1024);
    var base = 1;
    while (base * 10 <= v) {
      base *= 10;
    }
    for (final m in [1, 2, 5, 10]) {
      if (base * m >= v) return base * m;
    }
    return base * 10;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = provider.isConnected;
    final down = provider.liveDownRate;
    final up = provider.liveUpRate;
    final peak = provider.rateSamples.fold<int>(
      0,
      (m, s) => math.max(m, math.max(s.down, s.up)),
    );
    final max = _niceMax(math.max(peak, math.max(down, up)));
    return Semantics(
      container: true,
      label: connected
          ? 'Download ${formatRate(down)}, upload ${formatRate(up)}'
          : 'Speeds not available while disconnected',
      child: ExcludeSemantics(
        child: PanelCard(
          child: Column(
            children: [
              SizedBox(
                height: 190,
                child: CustomPaint(
                  painter: _DialPainter(
                    fraction: connected ? (down / max).clamp(0.0, 1.0) : 0,
                    max: max,
                    track: theme.colorScheme.outlineVariant,
                    tick: theme.colorScheme.onSurfaceVariant,
                    fill: theme.colorScheme.primary,
                    label: theme.textTheme.labelSmall!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  child: Align(
                    alignment: const Alignment(0, 0.45),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              connected ? formatRate(down) : '—',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.surface,
                              ),
                            ),
                          ),
                          Text(
                            connected ? _mbps(down) : 'download',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: Space.xl,
                runSpacing: Space.xs,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.south_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      Text(
                        ' ${connected ? formatRate(down) : '—'}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.north_rounded,
                        size: 16,
                        color: Palette.amber,
                      ),
                      Text(
                        ' ${connected ? formatRate(up) : '—'}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                provider.hasLiveWanRates
                    ? 'Router internet (WAN) rate · scale 0–${formatRate(max)}'
                    : 'Sum of connected device rates · scale 0–${formatRate(max)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.fraction,
    required this.max,
    required this.track,
    required this.tick,
    required this.fill,
    required this.label,
  });

  final double fraction;
  final int max;
  final Color track;
  final Color tick;
  final Color fill;
  final TextStyle label;

  static const _start = math.pi * 0.8;
  static const _sweep = math.pi * 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2, size.height) * 0.86;
    final center = Offset(size.width / 2, size.height * 0.62);
    // Ticks.
    for (var i = 0; i <= 30; i++) {
      final a = _start + _sweep * i / 30;
      final major = i % 6 == 0;
      final r1 = radius - (major ? 14 : 8);
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * r1,
        center + Offset(math.cos(a), math.sin(a)) * radius,
        Paint()
          ..color = (i / 30 <= fraction ? fill : tick).withValues(
            alpha: major ? 0.9 : 0.5,
          )
          ..strokeWidth = major ? 2.4 : 1.4
          ..strokeCap = StrokeCap.round,
      );
      if (major) {
        final value = max * i ~/ 30;
        final tp = TextPainter(
          text: TextSpan(text: _short(value), style: label),
          textDirection: TextDirection.ltr,
        )..layout();
        final p = center + Offset(math.cos(a), math.sin(a)) * (radius - 30);
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }
    // Progress arc.
    final rect = Rect.fromCircle(center: center, radius: radius - 44);
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = track,
    );
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * fraction,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = fill,
      );
    }
  }

  static String _short(int bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(bytesPerSecond % (1024 * 1024) == 0 ? 0 : 1)}M';
    }
    if (bytesPerSecond >= 1024) return '${bytesPerSecond ~/ 1024}K';
    return '$bytesPerSecond';
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.fraction != fraction || old.max != max || old.fill != fill;
}

/// Line chart of download/upload samples with a labelled rate axis.
class ThroughputChart extends StatelessWidget {
  const ThroughputChart({super.key, required this.samples});

  final List<RateSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label:
          'Throughput chart, ${samples.length} samples over '
          '${formatUptime(samples.last.time.difference(samples.first.time).inSeconds)}',
      child: CustomPaint(
        size: Size.infinite,
        painter: _ChartPainter(
          samples: samples,
          down: theme.colorScheme.primary,
          up: Palette.amber,
          grid: theme.colorScheme.outlineVariant,
          label: theme.textTheme.labelSmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.samples,
    required this.down,
    required this.up,
    required this.grid,
    required this.label,
  });

  final List<RateSample> samples;
  final Color down;
  final Color up;
  final Color grid;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 52.0;
    const bottomPad = 20.0;
    final plot = Rect.fromLTRB(leftPad, 6, size.width, size.height - bottomPad);
    final maxV = math.max(
      1,
      samples.fold<int>(0, (m, s) => math.max(m, math.max(s.down, s.up))),
    );
    final t0 = samples.first.time;
    final total = math.max(1, samples.last.time.difference(t0).inMilliseconds);

    void text(String s, Offset at, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(right ? tp.width : 0, tp.height / 2));
    }

    // Grid + rate axis.
    for (var i = 0; i <= 3; i++) {
      final y = plot.bottom - plot.height * i / 3;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = grid.withValues(alpha: i == 0 ? 0.9 : 0.4)
          ..strokeWidth = 1,
      );
      text(
        formatRate((maxV * i / 3).round()),
        Offset(leftPad - 6, y),
        right: true,
      );
    }
    // Time axis.
    final seconds = samples.last.time.difference(t0).inSeconds;
    text('-${formatUptime(seconds)}', Offset(plot.left, size.height - 8));
    text('now', Offset(plot.right, size.height - 8), right: true);

    Path line(int Function(RateSample) pick) {
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        final x =
            plot.left +
            plot.width * s.time.difference(t0).inMilliseconds / total;
        final y = plot.bottom - plot.height * pick(s) / maxV;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      return path;
    }

    for (final (pick, color) in [
      ((RateSample s) => s.down, down),
      ((RateSample s) => s.up, up),
    ]) {
      final path = line(pick);
      final area = Path.from(path)
        ..lineTo(plot.right, plot.bottom)
        ..lineTo(plot.left, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(plot),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.samples != samples;
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final est = provider.sessionTransferEstimate;
    final has = est.covered > const Duration(seconds: 10);
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Downloaded (est.)',
                  value: has ? formatBytes(est.down) : null,
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Uploaded (est.)',
                  value: has ? formatBytes(est.up) : null,
                  color: Palette.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            has
                ? 'Estimated from live rates over '
                      '${formatUptime(est.covered.inSeconds)} of sampling while '
                      'the app was open. Not a meter: the router reports no '
                      'daily or monthly totals.'
                : 'Not enough samples yet. Totals are estimated from live '
                      'rates while the app is open; the router reports no '
                      'usage history.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value ?? '—',
          style: theme.textTheme.headlineSmall?.copyWith(color: color),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DevicesCard extends StatelessWidget {
  const _DevicesCard({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = provider.devices;
    final online = devices.where((d) => d.isOnline).length;
    final active = devices.where((d) => d.isActive).toList()
      ..sort(
        (a, b) => (b.downloadSpeed + b.uploadSpeed).compareTo(
          a.downloadSpeed + a.uploadSpeed,
        ),
      );
    final top = active.take(5).toList();
    final maxRate = top.isEmpty
        ? 1
        : math.max(1, top.first.downloadSpeed + top.first.uploadSpeed);
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Online',
                  value: provider.isConnected ? '$online' : null,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Active now',
                  value: provider.isConnected ? '${active.length}' : null,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Known',
                  value: provider.isConnected ? '${devices.length}' : null,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          if (top.isNotEmpty) ...[
            const Divider(height: Space.xl),
            Text('Most active right now', style: theme.textTheme.titleSmall),
            const SizedBox(height: Space.sm),
            for (final d in top)
              InkWell(
                onTap: () => showDeviceDetails(context, d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            formatRate(d.downloadSpeed + d.uploadSpeed),
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: (d.downloadSpeed + d.uploadSpeed) / maxRate,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _WifiAvailability extends StatelessWidget {
  const _WifiAvailability({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final networks = provider.wirelessNetworksParsed;
    return PanelCard(
      child: networks.isEmpty
          ? Text(
              provider.isConnected
                  ? 'The router has not reported its Wi-Fi networks yet.'
                  : 'Not available while disconnected.',
            )
          : Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final n in networks)
                  StatusPill(
                    label:
                        '${n.bandLabel} · ${n.ssid.isEmpty ? 'unnamed' : n.ssid} · '
                        '${n.isEnabled ? 'on' : 'off'}',
                    tone: n.isEnabled ? Tone.success : Tone.neutral,
                  ),
                if (provider.guestWifi != null)
                  StatusPill(
                    label:
                        'Guest · ${'${provider.guestWifi!['Enable']}' == '1' ? 'on' : 'off'}',
                    tone: '${provider.guestWifi!['Enable']}' == '1'
                        ? Tone.success
                        : Tone.neutral,
                  ),
              ],
            ),
    );
  }
}

class _InternetCard extends StatelessWidget {
  const _InternetCard({
    required this.provider,
    required this.measuring,
    required this.onMeasure,
  });

  final RouterProvider provider;
  final bool measuring;
  final VoidCallback? onMeasure;

  static String _wanType(dynamic proto) => switch ('$proto') {
    '0' => 'DHCP (automatic)',
    '1' => 'Static IP',
    '2' => 'PPPoE',
    '3' => 'Bridge',
    _ => 'Not reported',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wan = provider.wanInfo;
    String text(dynamic v) {
      final t = '${v ?? ''}'.trim();
      return t.isEmpty ? 'Not reported' : t;
    }

    final response = provider.lastResponseTime;
    final rows = <(String, String)>[
      (
        'Status',
        !provider.isConnected || !provider.hasInternetStatus
            ? 'Not reported'
            : provider.internetConnected
            ? 'Online · ${provider.networkQualityLabel.toLowerCase()}'
            : 'Offline',
      ),
      ('Connection type', _wanType(wan?['WanProto'])),
      ('WAN IP', text(wan?['WanIp'])),
      ('Gateway', text(wan?['WanGateway'])),
      if ('${wan?['ManualDns']}' == '1') ('DNS', text(wan?['WanDns'])),
      (
        'Router response',
        response == null
            ? 'Not measured'
            : '${response.inMilliseconds} ms · ${formatAge(provider.lastResponseAt)}',
      ),
    ];
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: Alignment.centerRight,
            child: PillButton(
              label: measuring ? 'Measuring…' : 'Measure response',
              icon: Icons.speed_rounded,
              onPressed: measuring ? null : onMeasure,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final samples = provider.rateSamples;
    final verdict = provider.certificateVerdict;
    final rows = <(String, String)>[
      (
        'Rate source',
        provider.hasLiveWanRates
            ? 'GetWanRateInfo (router WAN)'
            : 'GetDevListInfo (sum of device rates)',
      ),
      (
        'Live statistics',
        provider.liveTelemetrySupported ? 'Answering' : 'Delayed',
      ),
      (
        'Guest devices online',
        provider.isConnected
            ? '${provider.reportedGuestDeviceCount}'
            : 'Not available',
      ),
      (
        'USB storage',
        !provider.isConnected
            ? 'Not available'
            : provider.usbDisks.isEmpty
            ? 'No disk'
            : '${formatBytes(provider.usbAvailableBytes)} free',
      ),
      ('Samples kept', '${samples.length} of ${RouterProvider.maxRateSamples}'),
      ('Polling interval', 'about 3 s while open'),
      ('Last update', formatAge(provider.liveDataUpdatedAt)),
      ('Router address', provider.currentRouter?.ipAddress ?? 'Unknown'),
      (
        'Certificate',
        verdict == null
            ? 'Not checked'
            : verdict.trusted
            ? 'Verified TaoTronics'
            : 'Rejected',
      ),
      for (final n in provider.nodeRateInfo)
        (
          'Node ${n['Sn'] ?? n['MeshNodeName'] ?? ''} rate (raw)',
          '${n['Rate'] ?? '—'}',
        ),
    ];
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.data_object_rounded),
        title: const Text('Technical details'),
        subtitle: const Text('Sources, sampling and raw values'),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(
          Space.lg,
          0,
          Space.lg,
          Space.lg,
        ),
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
