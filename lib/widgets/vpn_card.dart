import 'package:flutter/material.dart';

import '../providers/pi_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_widgets.dart';
import 'hub_widgets.dart';

/// Household VPN status and the operator-authorized on/off control.
class VpnCard extends StatelessWidget {
  const VpnCard({super.key, required this.pi});

  final PiProvider pi;

  static String stateLabel(ArgonVpn? vpn) {
    if (vpn == null) return 'Not reported';
    final mode = switch (vpn.mode) {
      'on' => 'On',
      'off' => 'Off',
      _ => null,
    };
    final state = switch (vpn.state) {
      null => null,
      'connected' => 'Connected',
      'disconnected' => 'Disconnected',
      final s => s[0].toUpperCase() + s.substring(1),
    };
    return [?mode, ?state].join(' · ').ifEmpty('Not reported');
  }

  Future<void> _request(BuildContext context, bool on) async {
    if (pi.vpnInFlight) return;
    if (!pi.vpnControlRoute) {
      // Explains Bluetooth / unreachable without asking for anything.
      await pi.setVpnMode(on);
      return;
    }
    if (!pi.paired || !pi.vpnDeviceAllowed) {
      await pi.refreshVpnPermission();
      if (!context.mounted) return;
      if (!pi.vpnDeviceAllowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The Argon owner can allow VPN control for this phone in Devices.',
            ),
          ),
        );
        return;
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmVpnDialog(on: on, vpn: pi.vpn),
    );
    if (confirmed != true) return;
    await pi.setVpnMode(on);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final state = pi.hubState;
    final vpn = pi.vpn;
    final busy = pi.vpnInFlight;
    final known = vpn?.mode != null;
    final switchValue = busy ? pi.vpnTarget == 'on' : vpn?.isOn ?? false;
    final healthy = vpn?.healthOk;
    final tone = vpn == null
        ? Tone.neutral
        : vpn.isOn && vpn.connected && healthy != false
        ? Tone.success
        : vpn.isOff
        ? Tone.neutral
        : Tone.warning;
    String v(String? value) => hubValue(state, value);
    String? flag(bool? b, String yes, String no) =>
        b == null ? null : (b ? yes : no);

    final rows = <(String, String, Tone?)>[
      ('Mode', v(vpn?.mode == null ? null : (vpn!.isOn ? 'On' : 'Off')), null),
      (
        'Connection',
        v(vpn?.state == null ? null : stateLabel(ArgonVpn(state: vpn!.state))),
        vpn?.state == null
            ? null
            : vpn!.connected
            ? Tone.success
            : vpn.isOn
            ? Tone.warning
            : null,
      ),
      ('Exit location', v(vpn?.location), null),
      (
        'Tunnel interface',
        v(
          vpn?.interface == null && vpn?.interfaceUp == null
              ? null
              : [
                  vpn?.interface ?? 'interface not reported',
                  ?flag(vpn?.interfaceUp, 'up', 'down'),
                ].join(' · '),
        ),
        null,
      ),
      ('Tunnel address', v(vpn?.tunnelIp), null),
      (
        'Last change',
        v(
          vpn?.lastChangeAt == null
              ? null
              : formatAge(vpn!.lastChangeAt, now: DateTime.now()),
        ),
        null,
      ),
      (
        'Kill switch',
        v(
          vpn?.killSwitchEnforced == null
              ? null
              : [
                  vpn!.killSwitchEnforced! ? 'Enforced' : 'Not enforced',
                  if (vpn.rejectedPackets != null)
                    '${vpn.rejectedPackets} packets blocked',
                ].join(' · '),
        ),
        vpn?.killSwitchEnforced == true
            ? Tone.success
            : vpn?.killSwitchEnforced == false && vpn!.isOn
            ? Tone.warning
            : null,
      ),
      (
        'Health',
        v(
          vpn?.healthOk == null && vpn?.healthDetail == null
              ? null
              : [
                  ?flag(vpn?.healthOk, 'Healthy', 'Problem'),
                  ?vpn?.healthDetail,
                ].join(' · '),
        ),
        vpn?.healthOk == true
            ? Tone.success
            : vpn?.healthOk == false
            ? Tone.danger
            : null,
      ),
    ];

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                vpn?.isOff == true
                    ? Icons.shield_outlined
                    : Icons.shield_rounded,
                tone: tone,
                size: 44,
                round: true,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Household VPN', style: theme.textTheme.titleMedium),
                    Text(
                      busy
                          ? (pi.vpnMessage ?? 'Changing…')
                          : vpn == null
                          ? v(null)
                          : [stateLabel(vpn), ?vpn.location].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(Space.sm),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              Semantics(
                label: 'VPN',
                toggled: switchValue,
                child: Switch(
                  key: const ValueKey('vpn-toggle'),
                  value: switchValue,
                  onChanged: busy || !known || vpn?.busy == true
                      ? null
                      : (value) => _request(context, value),
                ),
              ),
            ],
          ),
          if (vpn?.busy == true && !busy) ...[
            const SizedBox(height: Space.md),
            const InfoBanner(
              tone: Tone.info,
              busy: true,
              title: 'A VPN change is already in progress on Argon.',
            ),
          ],
          if (pi.vpnPhase != VpnCommandPhase.idle) ...[
            const SizedBox(height: Space.md),
            _Result(pi: pi),
          ],
          const SizedBox(height: Space.sm),
          for (final (i, (label, value, rowTone)) in rows.indexed)
            KvRow(label, value, tone: rowTone, last: i == rows.length - 1),
          const SizedBox(height: Space.sm),
          Text(
            vpn?.isOff == true
                ? 'VPN off: household traffic goes directly via your ISP.'
                : 'VPN on: household traffic routes through Surfshark; the '
                      'kill switch keeps it off the direct ISP path if the '
                      'tunnel drops.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Icon(
                pi.vpnDeviceAllowed ? Icons.key_rounded : Icons.key_off_rounded,
                size: 18,
                color: muted,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  pi.vpnDeviceAllowed
                      ? 'VPN permission granted to this phone'
                      : 'Owner approval needed for this phone',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
          if (pi.vpnKeyFingerprint != null)
            Text(
              'Phone key: ${pi.vpnKeyFingerprint!.substring(0, pi.vpnKeyFingerprint!.length.clamp(0, 16))}…',
              style: theme.textTheme.bodySmall,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: pi.refreshVpnPermission,
              child: const Text('Refresh permission'),
            ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _Result extends StatelessWidget {
  const _Result({required this.pi});

  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final message = pi.vpnMessage ?? '';
    switch (pi.vpnPhase) {
      case VpnCommandPhase.idle:
        return const SizedBox.shrink();
      case VpnCommandPhase.sending:
      case VpnCommandPhase.verifying:
        return InfoBanner(
          tone: Tone.info,
          busy: true,
          title: pi.vpnPhase == VpnCommandPhase.sending
              ? 'Sending to Argon…'
              : 'Waiting for confirmation…',
          message: message,
        );
      case VpnCommandPhase.confirmed:
        return InfoBanner(
          tone: Tone.success,
          icon: Icons.check_circle_rounded,
          title: message,
          onDismiss: pi.dismissVpnResult,
        );
      case VpnCommandPhase.failed:
        final issue = pi.vpnIssue;
        return InfoBanner(
          tone:
              issue == VpnCommandIssue.busy ||
                  issue == VpnCommandIssue.unconfirmed ||
                  issue == VpnCommandIssue.bluetooth
              ? Tone.warning
              : Tone.danger,
          icon: Icons.error_outline_rounded,
          title: message,
          message: pi.vpnRecovery,
          onDismiss: pi.dismissVpnResult,
          action:
              issue == VpnCommandIssue.tokenInvalid ||
                  issue == VpnCommandIssue.needsToken
              ? TextButton(
                  onPressed: pi.refreshVpnPermission,
                  child: const Text('Refresh permission'),
                )
              : null,
        );
    }
  }
}

class _ConfirmVpnDialog extends StatelessWidget {
  const _ConfirmVpnDialog({required this.on, required this.vpn});

  final bool on;
  final ArgonVpn? vpn;

  @override
  Widget build(BuildContext context) {
    final where = vpn?.location == null ? '' : ' (exit ${vpn!.location})';
    return AlertDialog(
      icon: Icon(on ? Icons.shield_rounded : Icons.shield_outlined),
      title: Text(on ? 'Turn VPN on?' : 'Turn VPN off?'),
      content: Text(
        on
            ? 'All household traffic will route through Surfshark$where. '
                  'Connections may pause briefly while the tunnel comes up. '
                  'While the VPN is on, the kill switch keeps traffic off the '
                  'direct ISP path if the tunnel drops.'
            : 'All household traffic will go directly to the internet via '
                  'your ISP, without Surfshark. Connections may pause briefly '
                  'while Argon switches routes.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(on ? 'Turn on' : 'Turn off'),
        ),
      ],
    );
  }
}
