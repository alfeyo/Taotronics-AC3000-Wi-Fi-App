import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_widgets.dart';
import 'home_widgets.dart';
import 'hub_widgets.dart';

/// Short label for Argon's router monitoring state.
String routerMonitoringLabel(ArgonRouterView? view) =>
    switch (view?.monitoring) {
      'connected' => 'Monitored by Argon',
      'stale' => 'Router data stale',
      'unreachable' => 'Router not responding',
      'direct-control' => 'Under direct phone control',
      'not-connected' => 'Not monitored',
      _ => 'Not reported',
    };

Tone routerMonitoringTone(ArgonRouterView? view) => switch (view?.monitoring) {
  'connected' => Tone.success,
  'direct-control' => Tone.info,
  'stale' || 'unreachable' => Tone.warning,
  _ => Tone.neutral,
};

/// Opens the router details screen (registered by the app shell).
typedef OpenRouterDetails = void Function(BuildContext context);

/// Home's secondary card: the TaoTronics router as Argon observes it.
class ManagedRouterCard extends StatelessWidget {
  const ManagedRouterCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final router = context.watch<RouterProvider>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final view = pi.routerView;
    final direct = router.isDirectMode;
    final live = view?.live == true;
    final ssid = direct && router.wirelessNetworksParsed.isNotEmpty
        ? router.currentWifiName
        : view?.ssids.firstOrNull;
    final nodes = direct
        ? '${router.reportedOnlineNodeCount}/${router.reportedTotalNodeCount}'
        : view?.nodesTotal != null
        ? '${view!.nodesOnline ?? '?'}/${view.nodesTotal}'
        : null;
    final clients = direct && router.devicesKnown
        ? '${router.knownOnlineDeviceCount ?? '—'}'
        : view?.onlineCount != null
        ? '${view!.onlineCount}'
        : null;
    final line = [
      if (direct) 'Direct control' else routerMonitoringLabel(view),
      if (!direct && view?.observedAt != null)
        'updated ${formatAge(view!.observedAt)}',
      if (!direct && view?.source != null) view!.sourceLabel,
    ].join(' · ');
    return PanelCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                Icons.router_rounded,
                tone: direct ? Tone.accent : routerMonitoringTone(view),
                size: 40,
                round: true,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Managed router · TaoTronics ${view?.model ?? 'ND001'}',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              _MiniStat(
                label: 'Clients online',
                value: clients ?? (live || direct ? '—' : 'Unknown'),
              ),
              _MiniStat(label: 'Mesh nodes', value: nodes ?? 'Not reported'),
              _MiniStat(label: 'Wi-Fi', value: ssid ?? 'Not relayed'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        container: true,
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
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

/// The router as Argon observes it, for Router details in Argon mode.
class ArgonRouterSummary extends StatelessWidget {
  const ArgonRouterSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final theme = Theme.of(context);
    final view = pi.routerView;
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Observed by Argon',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              StatusPill(
                label: routerMonitoringLabel(view),
                tone: routerMonitoringTone(view),
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          KvRow('Source', hubValue(pi.hubState, view?.sourceLabel)),
          KvRow(
            'Last observation',
            view?.observedAt == null
                ? hubValue(pi.hubState, null)
                : formatAge(view!.observedAt),
          ),
          KvRow(
            'Clients',
            view?.knownCount == null
                ? hubValue(pi.hubState, null)
                : '${view!.onlineCount ?? '—'} online · ${view.knownCount} known'
                      '${view.wifiCount == null ? '' : ' · ${view.wifiCount} Wi-Fi, ${view.wiredCount ?? 0} wired'}',
          ),
          KvRow(
            'Router WAN rate',
            view?.wanDownBitsPerSec == null
                ? 'Not reported'
                : '↓ ${formatBitRate(view!.wanDownBitsPerSec!)} · ↑ ${formatBitRate(view.wanUpBitsPerSec ?? 0)}',
          ),
          KvRow(
            'Mesh nodes',
            view?.nodesTotal == null
                ? 'Not relayed by the observer'
                : '${view!.nodesOnline ?? '?'} of ${view.nodesTotal} online',
          ),
          KvRow(
            'Wi-Fi settings',
            view?.ssids.isNotEmpty == true
                ? view!.ssids.join(', ')
                : 'Not relayed (passwords never leave the router)',
            last: true,
          ),
          if (view?.monitoringDetail != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              view!.monitoringDetail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
              label: 'Take Direct Router Control',
              icon: Icons.admin_panel_settings_outlined,
              onPressed: pi.directInProgress
                  ? null
                  : () => showTakeDirectControl(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visible indicator and controls while Direct Router Control is in
/// progress, active or failed. Renders nothing in plain Argon mode.
class DirectControlPanel extends StatelessWidget {
  const DirectControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = maybePiProvider(context);
    if (pi == null || pi.directPhase == DirectControlPhase.off) {
      return const SizedBox.shrink();
    }
    final busy = switch (pi.directPhase) {
      DirectControlPhase.requesting ||
      DirectControlPhase.waitingForObserver ||
      DirectControlPhase.connecting ||
      DirectControlPhase.waitingForRouter ||
      DirectControlPhase.returning => true,
      _ => false,
    };
    final (title, tone) = switch (pi.directPhase) {
      DirectControlPhase.requesting => ('Requesting router control', Tone.info),
      DirectControlPhase.waitingForObserver => (
        'Argon is releasing the router',
        Tone.info,
      ),
      DirectControlPhase.connecting => ('Connecting to the router', Tone.info),
      DirectControlPhase.waitingForRouter => (
        'Waiting for the router handover',
        Tone.warning,
      ),
      DirectControlPhase.active => ('Direct router control', Tone.accent),
      DirectControlPhase.returning => ('Returning to Argon', Tone.info),
      _ => ('Direct control unavailable', Tone.danger),
    };
    final message = pi.directPhase == DirectControlPhase.active
        ? [
            'Controlled by ${pi.controllerName} (this phone). Argon keeps '
                'internet, VPN and accounting running.',
            if (pi.directWithoutHandover) 'Taken without an Argon handover.',
            if (pi.leaseAtRisk)
              'Argon has not confirmed the lease for a minute; its observer '
                  'may resume when it lapses.',
          ].join(' ')
        : pi.directMessage;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: InfoBanner(
        tone: tone,
        busy: busy,
        icon: pi.directPhase == DirectControlPhase.failed
            ? Icons.block_rounded
            : Icons.admin_panel_settings_rounded,
        title: title,
        message: message,
        action: switch (pi.directPhase) {
          DirectControlPhase.failed => TextButton(
            onPressed: pi.dismissDirectResult,
            child: const Text('Dismiss'),
          ),
          DirectControlPhase.returning => null,
          _ => TextButton(
            onPressed: () => pi.returnToArgon(),
            child: const Text('Return to Argon'),
          ),
        },
      ),
    );
  }
}

/// Settings: the router control mode with its one deliberate switch.
class RouterControlCard extends StatelessWidget {
  const RouterControlCard({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = maybePiProvider(context);
    final router = context.watch<RouterProvider>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (pi == null) return const SizedBox.shrink();
    final direct = router.isDirectMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DirectControlPanel(),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(
                    direct
                        ? Icons.admin_panel_settings_rounded
                        : Icons.developer_board_rounded,
                    tone: direct ? Tone.accent : Tone.success,
                    size: 40,
                    round: true,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          direct ? 'Direct router control' : 'Argon mode',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          direct
                              ? 'This phone manages the TaoTronics router. '
                                    'Router settings below are live.'
                              : 'Argon monitors the router; this phone holds no '
                                    'router session. Router settings below need '
                                    'direct control.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: direct
                    ? PillButton(
                        primary: true,
                        label: 'Return to Argon mode',
                        icon: Icons.developer_board_rounded,
                        onPressed:
                            pi.directPhase == DirectControlPhase.returning
                            ? null
                            : () => pi.returnToArgon(),
                      )
                    : PillButton(
                        label: 'Take Direct Router Control',
                        icon: Icons.admin_panel_settings_outlined,
                        onPressed: pi.directInProgress
                            ? null
                            : () => showTakeDirectControl(context),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Explains Direct Router Control and starts it on confirmation.
Future<void> showTakeDirectControl(BuildContext context) async {
  final pi = context.read<PiProvider>();
  final router = context.read<RouterProvider>();
  if (!router.hasSavedPairing) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded),
        title: const Text('No router pairing on this phone'),
        content: const Text(
          'Direct control uses this phone\'s existing TaoTronics pairing. '
          'Pair the router from Settings first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }
  final blocker = pi.handoverBlocker;
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.admin_panel_settings_outlined),
      title: const Text('Take Direct Router Control?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The app will connect straight to the TaoTronics router with '
              'this phone\'s saved pairing to change router settings.',
            ),
            const SizedBox(height: Space.sm),
            const Text(
              'The router serves one manager at a time, so Argon\'s observer '
              'pauses router monitoring until you return. Household internet, '
              'VPN, DHCP, Tailscale and traffic accounting on Argon keep '
              'running. Control ends automatically about two minutes after '
              'the app stops renewing it.',
            ),
            if (blocker != null) ...[
              const SizedBox(height: Space.md),
              InfoBanner(
                tone: Tone.warning,
                title: 'Argon cannot coordinate the handover',
                message:
                    '$blocker Connecting anyway may compete with the observer '
                    'until it backs off.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(c, blocker == null ? 'handover' : 'override'),
          child: Text(blocker == null ? 'Take control' : 'Connect anyway'),
        ),
      ],
    ),
  );
  if (choice == null) return;
  await pi.takeDirectControl(withoutHandover: choice == 'override');
}
