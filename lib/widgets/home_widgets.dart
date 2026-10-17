import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/save_result.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_widgets.dart';
import 'feedback.dart';

/// Hero card: TaoTronics router illustration with a live LED badge, router
/// name, primary SSID, status, device count and the reported password.
class RouterCard extends StatefulWidget {
  const RouterCard({super.key, required this.provider, this.onOpenDevices});

  final RouterProvider provider;
  final VoidCallback? onOpenDevices;

  @override
  State<RouterCard> createState() => _RouterCardState();
}

class _RouterCardState extends State<RouterCard> {
  bool _reveal = false;
  bool _ledBusy = false;

  Future<void> _toggleLed(String sn, bool on) async {
    setState(() => _ledBusy = true);
    final result = await widget.provider.updateNodeLed(
      nodeSn: sn,
      led: on ? 1 : 0,
    );
    if (!mounted) return;
    setState(() => _ledBusy = false);
    showSaveResult(
      context,
      result.isConfirmed
          ? SaveResult.confirmed(
              on ? 'Router LED turned on.' : 'Router LED turned off.',
            )
          : result,
    );
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
    final ledOn = led == null ? null : RouterProvider.isLedOn(led);
    final master = p.nodes.where((n) => n.isMaster).firstOrNull;
    final showPassword =
        connected &&
        primary != null &&
        primary.encrypt > 0 &&
        primary.passwordKnown &&
        primary.password.isNotEmpty;

    return PanelCard(
      child: Column(
        children: [
          SizedBox(
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  'assets/original_setup/ic_guide_need.png',
                  height: 160,
                  fit: BoxFit.contain,
                  semanticLabel: 'TaoTronics mesh router',
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: _LedBadge(
                    on: ledOn,
                    busy: _ledBusy,
                    onTap: !connected || led == null || _ledBusy
                        ? null
                        : () => _toggleLed('${led['NodeSn']}', !ledOn!),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          Text(
            master?.model == null
                ? 'TaoTronics router'
                : 'TaoTronics ${master!.model}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 2),
          Text(
            connected && primary != null
                ? primary.ssid
                : connected
                ? 'Reading Wi-Fi…'
                : 'Not connected',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              StatusPill(
                label: connected
                    ? 'Connected'
                    : p.isReconnecting
                    ? 'Reconnecting'
                    : 'Offline',
                tone: connected
                    ? Tone.success
                    : p.isReconnecting
                    ? Tone.warning
                    : Tone.danger,
              ),
              if (connected)
                GestureDetector(
                  onTap: widget.onOpenDevices,
                  child: StatusPill(
                    label: '${p.reportedOnlineDeviceCount} devices',
                    tone: Tone.info,
                    icon: Icons.devices_other_rounded,
                  ),
                ),
            ],
          ),
          if (showPassword) ...[
            const Divider(height: Space.xl),
            Row(
              children: [
                Icon(Icons.key_rounded, size: 18, color: muted),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    _reveal ? primary.password : '•' * 10,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: _reveal ? 'monospace' : null,
                    ),
                  ),
                ),
                PillButton(
                  label: _reveal ? 'Hide' : 'Show',
                  icon: _reveal
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  onPressed: () => setState(() => _reveal = !_reveal),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LedBadge extends StatelessWidget {
  const _LedBadge({required this.on, required this.busy, this.onTap});

  final bool? on;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tone(on == true ? Tone.accent : Tone.neutral);
    final label = on == null
        ? 'Router LED: state not reported'
        : 'Router LED ${on! ? 'on' : 'off'}. Tap to turn ${on! ? 'off' : 'on'}';
    return Semantics(
      button: onTap != null,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: colors.container,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onContainer,
                          ),
                        )
                      : Icon(
                          on == true
                              ? Icons.lightbulb_rounded
                              : Icons.lightbulb_outline_rounded,
                          size: 18,
                          color: colors.onContainer,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    on == null ? 'LED' : (on! ? 'LED on' : 'LED off'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onContainer,
                    ),
                  ),
                ],
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
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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

/// Expandable session insights and internet source details.
class InsightsPanel extends StatelessWidget {
  const InsightsPanel({super.key, required this.provider});

  final RouterProvider provider;

  static String _wanType(dynamic proto) => switch ('$proto') {
    '0' => 'DHCP (automatic)',
    '1' => 'Static IP',
    '2' => 'PPPoE',
    '3' => 'Bridge',
    _ => 'Not reported',
  };

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final samples = p.rateSamples;
    final wan = p.wanInfo;
    String text(dynamic v) {
      final t = '${v ?? ''}'.trim();
      return t.isEmpty ? 'Not reported' : t;
    }

    final peakDown = samples.isEmpty
        ? null
        : samples.map((s) => s.down).reduce(math.max);
    final peakUp = samples.isEmpty
        ? null
        : samples.map((s) => s.up).reduce(math.max);
    final span = samples.length < 2
        ? null
        : samples.last.time.difference(samples.first.time);
    final networks = p.wirelessNetworksParsed;

    final rows = <(String, String)>[
      (
        'Internet',
        !p.hasInternetStatus
            ? 'Not reported'
            : p.internetConnected
            ? 'Online'
            : 'Offline',
      ),
      ('Connection type', _wanType(wan?['WanProto'])),
      ('WAN IP', text(wan?['WanIp'])),
      ('Gateway', text(wan?['WanGateway'])),
      ('Devices online', '${p.reportedOnlineDeviceCount}'),
      (
        'Wi-Fi networks on',
        networks.isEmpty
            ? 'Not reported'
            : '${networks.where((n) => n.isEnabled).length} of ${networks.length}',
      ),
      (
        'Peak download (this session)',
        peakDown == null ? '—' : formatRate(peakDown),
      ),
      ('Peak upload (this session)', peakUp == null ? '—' : formatRate(peakUp)),
    ];

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.insights_rounded),
        title: const Text('Usage & insights'),
        subtitle: Text(
          span == null
              ? 'Live rates sampled by the app'
              : 'Live samples over the last ${formatUptime(span.inSeconds)}',
        ),
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
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Text(value, style: Theme.of(context).textTheme.labelLarge),
                ],
              ),
            ),
          const SizedBox(height: Space.sm),
          Text(
            'Graphs show live throughput collected while the app is open. '
            'The router does not report daily or monthly data totals.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bell with unread count; opens the in-app event list.
class EventsButton extends StatelessWidget {
  const EventsButton({super.key, required this.provider});

  final RouterProvider provider;

  void _open(BuildContext context) {
    provider.markEventsRead();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final events = provider.events;
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
            children: [
              Text('Notifications', style: theme.textTheme.titleLarge),
              const SizedBox(height: Space.md),
              if (events.isEmpty)
                const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No events yet',
                  message:
                      'Disconnections, reconnection problems and settings '
                      'results appear here while the app is open.',
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
                    subtitle: Text('${e.message}\n${formatAge(e.time)}'),
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
    final unread = provider.unreadEvents;
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
