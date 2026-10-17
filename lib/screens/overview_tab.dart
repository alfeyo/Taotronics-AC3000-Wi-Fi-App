import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/save_result.dart';
import '../providers/router_provider.dart';
import '../services/router_certificate_verifier.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';
import '../widgets/feedback.dart';
import 'diagnostics_screen.dart';
import 'discovery_screen.dart';
import 'home_screen.dart';
import 'nodes_screen.dart';
import 'router_settings_screens.dart';
import 'settings_screen.dart';
import 'setup_wizard_screen.dart';

/// Home dashboard: router status, live activity, Wi-Fi networks, health
/// and quick controls. Every value comes from the router; missing or old
/// values are labelled as such.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final connected = provider.isConnected;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;

    final primary = <Widget>[
      _RouterHero(provider: provider),
      const SectionLabel('Network activity'),
      _ActivityRow(provider: provider),
      const SectionLabel('Wi-Fi networks'),
      _WifiSummary(provider: provider),
    ];
    final secondary = <Widget>[
      const SectionLabel('Quick controls'),
      _QuickControls(provider: provider),
      const SizedBox(height: Space.md),
      _MoreActions(provider: provider),
      const SectionLabel('Network health'),
      _HealthPanel(provider: provider),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: provider.refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 120),
            children: [
              ContentWidth(
                maxWidth: wide ? 1100 : Breakpoints.contentMaxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(provider: provider),
                    const SizedBox(height: Space.lg),
                    ConnectionStatusBanners(
                      onOpenSetup: () => _openSetup(context),
                    ),
                    if (!connected) ...[
                      _SetupCard(provider: provider),
                      const SizedBox(height: Space.md),
                    ],
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: primary)),
                          const SizedBox(width: Space.xl),
                          Expanded(child: Column(children: secondary)),
                        ],
                      )
                    else ...[
                      ...primary,
                      ...secondary,
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

void _openDiagnostics(BuildContext context, RouterProvider provider) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DiagnosticsScreen(
        routerReachable: provider.isNetworkReachable,
        mqttPortOpen: provider.isMqttPortOpen,
      ),
    ),
  );
}

void _push(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

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

Future<void> _restart(BuildContext context, RouterProvider provider) async {
  if (!provider.isConnected) {
    _whenConnected(context, provider, () {});
    return;
  }
  final confirmed = await confirmAction(
    context,
    title: 'Restart all mesh nodes?',
    message:
        'Every device loses its connection for a few minutes while the '
        'router restarts. The app reconnects automatically.',
    confirmLabel: 'Restart',
    destructive: true,
    icon: Icons.restart_alt_rounded,
  );
  if (!confirmed || !context.mounted) return;
  final result = await provider.rebootRouter();
  if (context.mounted) showSaveResult(context, result);
}

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Good evening.';
  if (h < 12) return 'Good morning.';
  if (h < 18) return 'Good afternoon.';
  return 'Good evening.';
}

class _Header extends StatelessWidget {
  const _Header({required this.provider});

  final RouterProvider provider;

  Future<void> _logout(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Log out of this router?',
      message:
          'The app disconnects and returns to discovery. Your pairing stays '
          'saved, so you can reconnect later.',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await provider.logout();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final (label, tone) = connected
        ? ('Connected', Tone.success)
        : provider.isReconnecting
        ? ('Reconnecting', Tone.warning)
        : ('Not connected', Tone.danger);
    final internet = !connected || !provider.hasInternetStatus
        ? null
        : provider.internetConnected
        ? ('Internet online', Tone.success)
        : ('No internet', Tone.danger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Network control',
          title: _greeting(DateTime.now()),
          subtitle: 'Your home network, clearly in control',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: connected
                    ? provider.refreshAll
                    : provider.reconnectNow,
              ),
              const SizedBox(width: Space.sm),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) => switch (value) {
                  'diagnostics' => _openDiagnostics(context, provider),
                  'restart' => _restart(context, provider),
                  'logout' => _logout(context),
                  _ => null,
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'diagnostics',
                    child: ListTile(
                      leading: Icon(Icons.monitor_heart_outlined),
                      title: Text('Diagnostics'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restart',
                    child: ListTile(
                      leading: Icon(Icons.restart_alt_rounded),
                      title: Text('Restart router'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout_rounded),
                      title: Text('Log out'),
                    ),
                  ),
                ],
                child: const _RoundIconButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'More',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            StatusPill(label: label, tone: tone),
            if (internet != null)
              StatusPill(label: internet.$1, tone: internet.$2),
            if (connected && provider.certificateVerdict?.trusted == true)
              const StatusPill(
                label: 'Verified router',
                tone: Tone.info,
                icon: Icons.verified_user_rounded,
              ),
          ],
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final circle = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
      child: Icon(icon, color: scheme.onSurface, size: 22),
    );
    if (onPressed == null) return Tooltip(message: tooltip, child: circle);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: circle,
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Router found', provider.isRouterFound),
      ('Gateway reachable', provider.isNetworkReachable),
      ('Control port open', provider.isMqttPortOpen),
      ('Signed in', provider.isConnected),
    ];
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Finish setting up',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Provision the router, join its Wi-Fi, then pair this phone.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final (label, done) in steps)
                StatusPill(
                  label: label,
                  tone: done ? Tone.success : Tone.neutral,
                  icon: done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  primary: true,
                  label: 'Set up router',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => _openSetup(context),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: PillButton(
                  label: 'Diagnose',
                  icon: Icons.monitor_heart_outlined,
                  onPressed: () => _openDiagnostics(context, provider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Router card with a devices-online gauge.
class _RouterHero extends StatelessWidget {
  const _RouterHero({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final connected = provider.isConnected;
    final online = provider.reportedOnlineDeviceCount;
    final known = provider.devices.length;
    final networks = provider.wirelessNetworksParsed;
    final wifiOn = networks.where((n) => n.isEnabled).length;
    final nodesOnline = provider.reportedOnlineNodeCount;
    final nodesTotal = provider.reportedTotalNodeCount;
    final meshId = provider.currentRouter?.meshId;

    return PanelCard(
      onTap: () => _whenConnected(
        context,
        provider,
        () => HomeNavigation.maybeOf(context)?.select(HomeTab.devices),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TaoTronics mesh router',
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            connected && networks.isNotEmpty
                ? 'Main Wi-Fi: ${provider.currentWifiName}'
                : meshId == null
                ? 'No router selected'
                : 'Mesh $meshId',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: Space.lg),
          Center(
            child: _DeviceGauge(
              value: connected ? online : null,
              fraction: !connected || known == 0
                  ? 0
                  : (online / math.max(known, online)).clamp(0.0, 1.0),
              caption: known > online && connected
                  ? 'devices online of $known'
                  : 'devices online',
            ),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  !connected || networks.isEmpty
                      ? 'Wi-Fi: —'
                      : '$wifiOn Wi-Fi network${wifiOn == 1 ? '' : 's'} on',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                !connected
                    ? 'Mesh: —'
                    : nodesTotal > nodesOnline
                    ? '$nodesOnline of $nodesTotal nodes online'
                    : '$nodesOnline mesh node${nodesOnline == 1 ? '' : 's'}',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceGauge extends StatelessWidget {
  const _DeviceGauge({
    required this.value,
    required this.fraction,
    required this.caption,
  });

  final int? value;
  final double fraction;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: value == null
          ? 'Devices online: not available'
          : '$value $caption',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 190,
          height: 170,
          child: CustomPaint(
            painter: _GaugePainter(
              fraction: fraction,
              track: scheme.surfaceContainerHighest,
              fill: scheme.primary,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                // Scale the centre to the ring so large text never overflows.
                child: SizedBox(
                  width: 136,
                  height: 116,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          child: Text(
                            value == null ? '—' : '$value',
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.5,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          caption,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
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
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final Color track;
  final Color fill;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height * 1.15) / 2 - 8;
    final center = Offset(size.width / 2, size.height / 2 + 8);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * fraction,
        false,
        paint..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = provider.isConnected;
    final stale = connected && provider.liveDataStale;
    final source = provider.hasLiveWanRates
        ? 'Router internet (WAN) rate'
        : 'Sum of connected device rates';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _RateCard(
                label: 'Download',
                icon: Icons.south_rounded,
                tone: Tone.brand,
                value: connected ? formatRate(provider.liveDownRate) : null,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: _RateCard(
                label: 'Upload',
                icon: Icons.north_rounded,
                tone: Tone.accent,
                value: connected ? formatRate(provider.liveUpRate) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            StatusPill(
              label: !connected
                  ? 'Offline'
                  : stale
                  ? 'Stale'
                  : 'Live',
              tone: !connected
                  ? Tone.neutral
                  : stale
                  ? Tone.warning
                  : Tone.success,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                connected
                    ? '$source · updated ${formatAge(provider.liveDataUpdatedAt)}'
                    : 'Live rates appear once the router is connected.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({
    required this.label,
    required this.icon,
    required this.tone,
    required this.value,
  });

  final String label;
  final IconData icon;
  final Tone tone;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label ${value ?? 'not available'}',
      child: ExcludeSemantics(
        child: PanelCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon, tone: tone, size: 36, round: true),
              const SizedBox(height: Space.lg),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value ?? '—', style: theme.textTheme.headlineSmall),
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
      ),
    );
  }
}

class _WifiSummary extends StatelessWidget {
  const _WifiSummary({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final networks = provider.wirelessNetworksParsed;
    void openWifi() => _whenConnected(
      context,
      provider,
      () => HomeNavigation.maybeOf(context)?.select(HomeTab.wifi),
    );

    return PanelCard(
      onTap: openWifi,
      child: networks.isEmpty
          ? Row(
              children: [
                const IconBadge(
                  Icons.wifi_rounded,
                  tone: Tone.neutral,
                  size: 40,
                  round: true,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    !provider.isConnected
                        ? 'Wi-Fi networks appear once the router is connected.'
                        : provider.wirelessLoaded
                        ? 'The router did not report its Wi-Fi networks.'
                        : 'Reading Wi-Fi networks…',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (var i = 0; i < networks.length; i++) ...[
                  if (i > 0) const Divider(height: Space.lg),
                  Row(
                    children: [
                      IconBadge(
                        networks[i].isEnabled
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        tone: networks[i].isEnabled ? Tone.brand : Tone.neutral,
                        size: 36,
                        round: true,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              networks[i].ssid.isEmpty
                                  ? 'No name set'
                                  : networks[i].ssid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              networks[i].bandLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: networks[i].isEnabled ? 'On' : 'Off',
                        tone: networks[i].isEnabled
                            ? Tone.success
                            : Tone.neutral,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: PillButton(
                    label: 'Manage Wi-Fi',
                    icon: Icons.tune_rounded,
                    onPressed: openWifi,
                  ),
                ),
              ],
            ),
    );
  }
}

class _QuickControls extends StatelessWidget {
  const _QuickControls({required this.provider});

  final RouterProvider provider;

  Future<void> _setLed(BuildContext context, String sn, bool on) async {
    final result = await provider.updateNodeLed(nodeSn: sn, led: on ? 1 : 0);
    if (!context.mounted) return;
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
    final connected = provider.isConnected;
    final networks = provider.wirelessNetworksParsed;
    final wifiOn = networks.where((n) => n.isEnabled).length;
    final led = provider.mainRouterLed;
    final ledOn = led == null ? null : RouterProvider.isLedOn(led);
    final nodesOnline = provider.reportedOnlineNodeCount;

    return ResponsiveGrid(
      minTileWidth: 260,
      maxColumns: 2,
      children: [
        ActionTile(
          icon: Icons.wifi_rounded,
          tone: Tone.brand,
          title: 'Wi-Fi networks',
          subtitle: !connected || networks.isEmpty
              ? 'Bands, names and passwords'
              : '$wifiOn of ${networks.length} on',
          onTap: () => _whenConnected(
            context,
            provider,
            () => HomeNavigation.maybeOf(context)?.select(HomeTab.wifi),
          ),
        ),
        ActionTile(
          icon: Icons.lightbulb_outline_rounded,
          tone: ledOn == true ? Tone.accent : Tone.neutral,
          title: 'Router lights',
          subtitle: !connected
              ? 'LED controls'
              : ledOn == null
              ? 'LED state not reported yet'
              : 'Main router LED ${ledOn ? 'on' : 'off'}',
          onTap: () => _push(context, const NodeLedSettingsScreen()),
          trailing: Semantics(
            label: 'Main router LED',
            toggled: ledOn ?? false,
            child: Switch(
              value: ledOn ?? false,
              onChanged: !connected || led == null
                  ? null
                  : (on) => _setLed(context, '${led['NodeSn']}', on),
            ),
          ),
        ),
        ActionTile(
          icon: Icons.devices_other_rounded,
          tone: Tone.info,
          title: 'Devices',
          subtitle: connected
              ? '${provider.reportedOnlineDeviceCount} connected'
              : 'Manage connected',
          onTap: () => _whenConnected(
            context,
            provider,
            () => HomeNavigation.maybeOf(context)?.select(HomeTab.devices),
          ),
        ),
        ActionTile(
          icon: Icons.hub_rounded,
          tone: Tone.success,
          title: 'Mesh',
          subtitle: connected
              ? '$nodesOnline node${nodesOnline == 1 ? '' : 's'} online'
              : 'Nodes & health',
          onTap: () => _whenConnected(
            context,
            provider,
            () => _push(context, const NodesScreen()),
          ),
        ),
        ActionTile(
          icon: Icons.settings_rounded,
          tone: Tone.neutral,
          title: 'Settings',
          subtitle: 'Internet, LAN, security and more',
          onTap: () =>
              HomeNavigation.maybeOf(context)?.select(HomeTab.settings),
        ),
      ],
    );
  }
}

/// Secondary shortcuts that used to be dashboard quick actions.
class _MoreActions extends StatelessWidget {
  const _MoreActions({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        PillButton(
          label: 'Guest Wi-Fi',
          icon: Icons.wifi_tethering_rounded,
          onPressed: () => _whenConnected(
            context,
            provider,
            () => _push(context, const GuestWifiSettingsScreen()),
          ),
        ),
        PillButton(
          label: 'USB storage',
          icon: Icons.usb_rounded,
          onPressed: () => _whenConnected(
            context,
            provider,
            () => _push(context, const UsbStorageScreen()),
          ),
        ),
        PillButton(
          label: 'Diagnostics',
          icon: Icons.monitor_heart_outlined,
          onPressed: () => _openDiagnostics(context, provider),
        ),
        PillButton(
          label: 'Restart',
          icon: Icons.restart_alt_rounded,
          onPressed: () => _restart(context, provider),
        ),
      ],
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel({required this.provider});

  final RouterProvider provider;

  @override
  Widget build(BuildContext context) {
    final connected = provider.isConnected;
    final router = provider.currentRouter;
    final verdict = provider.certificateVerdict;
    final meshId = router?.meshId;
    final master = provider.nodes.where((n) => n.isMaster).firstOrNull;
    String na(String? v) => connected && v != null ? v : 'Not available';

    final rows = <(String, String, Tone)>[
      (
        'Internet',
        !connected || !provider.hasInternetStatus
            ? 'Not reported'
            : provider.internetConnected
            ? 'Online'
            : 'Offline',
        !connected || !provider.hasInternetStatus
            ? Tone.neutral
            : provider.internetConnected
            ? Tone.success
            : Tone.danger,
      ),
      (
        'Connection quality',
        !connected || !provider.internetConnected
            ? 'Not reported'
            : provider.networkQualityLabel,
        provider.networkQuality == 2 ? Tone.warning : Tone.success,
      ),
      (
        'Router uptime',
        na(
          master != null && master.uptimeSeconds > 0
              ? formatUptime(master.uptimeSeconds)
              : null,
        ),
        Tone.neutral,
      ),
      (
        'Guest devices',
        connected ? '${provider.reportedGuestDeviceCount}' : 'Not available',
        Tone.neutral,
      ),
      (
        'USB storage',
        !connected
            ? 'Not available'
            : provider.usbDisks.isEmpty
            ? 'No disk'
            : '${formatBytes(provider.usbAvailableBytes)} free',
        Tone.neutral,
      ),
      (
        'Live statistics',
        !connected
            ? 'Offline'
            : provider.liveTelemetrySupported
            ? 'Answering'
            : 'Slow; using device totals',
        provider.liveTelemetrySupported ? Tone.success : Tone.warning,
      ),
      (
        'Router address',
        router?.ipAddress ?? 'Unknown',
        router?.ipAddress == null ? Tone.neutral : Tone.success,
      ),
      (
        'Router certificate',
        verdict == null
            ? 'Not checked'
            : verdict.trusted
            ? 'Verified'
            : 'Rejected',
        verdict == null
            ? Tone.neutral
            : verdict.trusted
            ? Tone.success
            : Tone.danger,
      ),
      if (meshId != null && provider.authService.isPaired(meshId))
        (
          'Saved password',
          provider.authService.isPasswordStoredSecurely(meshId)
              ? 'Android Keystore'
              : 'App storage',
          provider.authService.isPasswordStoredSecurely(meshId)
              ? Tone.success
              : Tone.warning,
        ),
    ];

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Health details'),
        subtitle: Text(
          meshId == null ? 'No router selected' : 'Mesh $meshId',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
          for (final (label, value, tone) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  const SizedBox(width: Space.md),
                  Flexible(
                    child: StatusPill(label: value, tone: tone),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
