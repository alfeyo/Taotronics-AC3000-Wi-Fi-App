import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_widgets.dart';
import 'feedback.dart';

/// Router hero: the TaoTronics router on a soft spotlight with its LED ring
/// drawn in place, plus SSID, password and a conventional LED switch.
///
/// The LED glow only shows a state the router has confirmed by read-back.
/// While a change is pending the ring breathes at the requested state.
class RouterHero extends StatefulWidget {
  const RouterHero({super.key, required this.provider, this.onOpenDevices});

  final RouterProvider provider;
  final VoidCallback? onOpenDevices;

  @override
  State<RouterHero> createState() => _RouterHeroState();
}

class _RouterHeroState extends State<RouterHero>
    with SingleTickerProviderStateMixin {
  bool _reveal = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _setLed(String sn, bool on) async {
    _pulse.repeat(reverse: true);
    final result = await widget.provider.updateNodeLed(
      nodeSn: sn,
      led: on ? 1 : 0,
    );
    if (!mounted) return;
    _pulse
      ..stop()
      ..value = 0;
    showSaveResult(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final connected = p.isConnected;
    final primary = p.wirelessNetworksParsed
        .where((n) => n.isEnabled && n.ssid.isNotEmpty)
        .firstOrNull;
    final led = p.mainRouterLed;
    final sn = led == null ? null : '${led['NodeSn']}';
    final confirmedOn = led == null ? null : RouterProvider.isLedOn(led);
    final requested = sn == null ? null : p.ledRequested(sn);
    final pending = requested != null;
    final master = p.nodes.where((n) => n.isMaster).firstOrNull;
    final canToggle = connected && sn != null && !p.ledBusy;
    final showPassword =
        connected &&
        primary != null &&
        primary.encrypt > 0 &&
        primary.passwordKnown &&
        primary.password.isNotEmpty;
    final ledLabel = confirmedOn == null
        ? 'Router LED, state not reported'
        : pending
        ? 'Router LED, turning ${requested == 1 ? 'on' : 'off'}'
        : 'Router LED ${confirmedOn ? 'on' : 'off'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 268,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Spotlight behind the router.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.62,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Floor shadow.
              Positioned(
                bottom: 14,
                child: Container(
                  width: 170,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              Semantics(
                image: true,
                label: 'TaoTronics router. $ledLabel',
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: canToggle
                        ? () => _setLed(sn, !(confirmedOn ?? false))
                        : null,
                    child: SizedBox(
                      width: 186,
                      height: 246,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => CustomPaint(
                          foregroundPainter: _LedRingPainter(
                            intensity: pending
                                ? (requested == 1
                                      ? 0.35 + 0.45 * _pulse.value
                                      : 0.45 - 0.35 * _pulse.value)
                                : null,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColorFiltered(
                                colorFilter: const ColorFilter.mode(
                                  Color(0xff767b86),
                                  BlendMode.modulate,
                                ),
                                child: Image.asset(
                                  'assets/original_setup/ic_guide_need.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              AnimatedOpacity(
                                opacity: !pending && confirmedOn == true
                                    ? 1
                                    : 0,
                                duration: const Duration(milliseconds: 200),
                                child: CustomPaint(
                                  painter: _LedRingPainter(intensity: 1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 24,
                child: _LedButton(
                  on: confirmedOn,
                  pending: pending,
                  label: ledLabel,
                  onTap: canToggle
                      ? () => _setLed(sn, !(confirmedOn ?? false))
                      : null,
                ),
              ),
            ],
          ),
        ),
        Text(
          master?.model == null
              ? 'TaoTronics router'
              : 'TaoTronics ${master!.model}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            StatusPill(
              label: !connected
                  ? (p.isReconnecting ? 'Reconnecting' : 'Offline')
                  : !p.hasInternetStatus
                  ? 'Connected'
                  : p.internetConnected
                  ? 'Internet online'
                  : 'No internet',
              tone: !connected
                  ? (p.isReconnecting ? Tone.warning : Tone.danger)
                  : p.hasInternetStatus && !p.internetConnected
                  ? Tone.danger
                  : Tone.success,
            ),
            if (connected)
              Semantics(
                button: true,
                child: GestureDetector(
                  onTap: widget.onOpenDevices,
                  child: StatusPill(
                    label: p.knownOnlineDeviceCount == null
                        ? (p.managedElsewhere
                              ? 'Devices: waiting'
                              : 'Reading devices')
                        : p.managedElsewhere
                        ? '${p.knownOnlineDeviceCount} devices · '
                              '${formatAge(p.devicesUpdatedAt)}'
                        : '${p.knownOnlineDeviceCount} devices',
                    tone: Tone.info,
                    icon: Icons.devices_other_rounded,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        PanelCard(
          padding: const EdgeInsets.fromLTRB(20, Space.lg, Space.md, Space.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected && primary != null
                          ? primary.ssid
                          : connected
                          ? 'Reading Wi-Fi…'
                          : 'Not connected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.key_rounded, size: 15, color: muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            !showPassword
                                ? (primary != null && !primary.passwordKnown
                                      ? 'Password not reported'
                                      : primary?.encrypt == 0
                                      ? 'Open network'
                                      : 'Password unavailable')
                                : _reveal
                                ? primary.password
                                : 'Password  ••••••••',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontFamily: _reveal && showPassword
                                  ? 'monospace'
                                  : null,
                            ),
                          ),
                        ),
                        if (showPassword)
                          IconButton(
                            tooltip: _reveal
                                ? 'Hide password'
                                : 'Show password',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _reveal = !_reveal),
                            icon: Icon(
                              _reveal
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Router LED switch',
                    toggled: confirmedOn ?? false,
                    child: Switch(
                      activeTrackColor: Palette.amber,
                      value: pending ? requested == 1 : (confirmedOn ?? false),
                      onChanged: canToggle ? (on) => _setLed(sn, on) : null,
                    ),
                  ),
                  Text(
                    pending ? 'Applying…' : 'LED',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Glow over the router's top LED ring (geometry measured from the asset:
/// the rim sits at ~7% of the image height and spans ~52% of its width).
class _LedRingPainter extends CustomPainter {
  _LedRingPainter({required this.intensity});

  /// 0..1 ring brightness; null draws nothing.
  final double? intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final i = intensity;
    if (i == null || i <= 0) return;
    // Image is drawn BoxFit.contain: compute its rect.
    const aspect = 297 / 393;
    final w = math.min(size.width, size.height * aspect);
    final h = w / aspect;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final ring = Rect.fromCenter(
      center: Offset(left + w * 0.5, top + h * 0.088),
      width: w * 0.44,
      height: h * 0.03,
    );
    canvas.drawOval(
      ring.inflate(6),
      Paint()
        ..color = Palette.amber.withValues(alpha: 0.35 * i)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawOval(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Palette.amber.withValues(alpha: 0.95 * i),
    );
  }

  @override
  bool shouldRepaint(_LedRingPainter old) => old.intensity != intensity;
}

class _LedButton extends StatelessWidget {
  const _LedButton({
    required this.on,
    required this.pending,
    required this.label,
    this.onTap,
  });

  final bool? on;
  final bool pending;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lit = on == true && !pending;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$label. ${onTap == null ? '' : 'Double tap to toggle'}',
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: Material(
            color: lit
                ? Palette.amber.withValues(alpha: 0.18)
                : scheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: pending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            lit
                                ? Icons.lightbulb_rounded
                                : Icons.lightbulb_outline_rounded,
                            key: ValueKey(lit),
                            color: lit
                                ? Palette.amber
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live rate card with a sparkline of this session's samples.
class SparkCard extends StatelessWidget {
  const SparkCard({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
    required this.value,
    required this.samples,
  });

  final String label;
  final IconData icon;
  final Tone tone;
  final String? value;
  final List<int> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.tone(tone).foreground;
    return Semantics(
      container: true,
      label: '$label ${value ?? 'not available'}',
      child: ExcludeSemantics(
        child: PanelCard(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(icon, tone: tone, size: 34, round: true),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value ?? '—',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 56,
                child: samples.length < 2
                    ? Center(
                        child: Text(
                          'Collecting samples…',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : CustomPaint(
                        size: Size.infinite,
                        painter: _SparkPainter(samples, color),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = math.max(1, values.reduce(math.max)).toDouble();
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - 6 - (values[i] / maxV) * (size.height - 12);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
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

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}

/// Bell with unread count; opens the in-app event list.
/// Looks up the gateway provider when the app provides one (tests and the
/// discovery flow may not).
PiProvider? maybePiProvider(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<PiProvider>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

typedef Notice = ({
  String title,
  String message,
  DateTime time,
  String tone,
  String source,
});

/// One notifications panel for router events (this phone's MQTT session) and
/// Argon events (server-observed, plus link changes seen by this phone).
class EventsButton extends StatelessWidget {
  const EventsButton({super.key, required this.provider});

  final RouterProvider provider;

  static List<Notice> merged(RouterProvider provider, PiProvider? pi) {
    final items = <Notice>[
      for (final e in provider.events)
        (
          title: e.title,
          message: e.message,
          time: e.time,
          tone: e.tone,
          source: 'Router',
        ),
      for (final e in pi?.events ?? const <PiEvent>[])
        (
          title: e.title,
          message: e.message,
          time: e.at,
          tone: e.severity,
          source: e.source == 'argon' ? 'Network Hub' : 'Network Hub link',
        ),
    ];
    items.sort((a, b) => b.time.compareTo(a.time));
    return items;
  }

  void _open(BuildContext context) {
    final pi = maybePiProvider(context, listen: false);
    provider.markEventsRead();
    pi?.markEventsRead();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final events = merged(provider, pi);
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
            children: [
              Text('Notifications', style: theme.textTheme.titleLarge),
              const SizedBox(height: Space.xs),
              Text(
                'Router and Network Hub events observed while the app is open.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.md),
              if (events.isEmpty)
                const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No events yet',
                  message:
                      'Router and Network Hub disconnections, VPN and uplink '
                      'changes and settings results appear here.',
                )
              else
                for (final e in events)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      switch (e.tone) {
                        'success' => Icons.check_circle_rounded,
                        'error' => Icons.error_rounded,
                        'warning' => Icons.warning_amber_rounded,
                        _ => Icons.info_outline_rounded,
                      },
                      color: context.tone(switch (e.tone) {
                        'success' => Tone.success,
                        'error' => Tone.danger,
                        'warning' => Tone.warning,
                        _ => Tone.info,
                      }).foreground,
                    ),
                    title: Text(e.title),
                    subtitle: Text(
                      '${e.message}\n${e.source} · ${formatAge(e.time)}',
                    ),
                    isThreeLine: true,
                  ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pi = maybePiProvider(context);
    final unread = provider.unreadEvents + (pi?.unreadEvents ?? 0);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: unread == 0 ? 'Notifications' : 'Notifications, $unread new',
      child: ExcludeSemantics(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _open(context),
          child: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
