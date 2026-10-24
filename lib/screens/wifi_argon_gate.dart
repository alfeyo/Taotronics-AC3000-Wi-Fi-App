import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/managed_router.dart';

/// Where a router setting can be read or changed in the default Argon mode.
enum RouterSettingAccess {
  /// Through an authenticated Argon command with read-back confirmation.
  argonCommand('Argon command', Tone.success),

  /// Argon reports it; it cannot be changed through Argon.
  viewOnly('View-only via Argon', Tone.info),

  /// Neither read nor written by Argon: needs Direct Router Control.
  direct('Requires Direct Router Control', Tone.warning);

  const RouterSettingAccess(this.label, this.tone);
  final String label;
  final Tone tone;
}

/// The verified capability matrix. Argon has no router write handler
/// (`POST /api/v1/router/control` answers 409 by design) and its observer
/// never relays Wi-Fi settings, so no row is an Argon command today.
const routerSettingAccess = <(String, String, RouterSettingAccess)>[
  (
    'Connected clients',
    'Names, IPs, online state and rates',
    RouterSettingAccess.viewOnly,
  ),
  ('Router status', 'Model and WAN rate', RouterSettingAccess.viewOnly),
  (
    'Wi-Fi names and passwords',
    'SSIDs, bands, WPA2 security',
    RouterSettingAccess.direct,
  ),
  ('Guest Wi-Fi', 'Guest network on/off and name', RouterSettingAccess.direct),
  ('Mesh nodes and LEDs', 'Node list and lights', RouterSettingAccess.direct),
  (
    'Internet and LAN',
    'WAN mode, DHCP, LAN address',
    RouterSettingAccess.direct,
  ),
  ('USB storage', 'Shared disks', RouterSettingAccess.direct),
];

/// Wi-Fi tab in Argon mode. The advanced Wi-Fi Settings screen (with its
/// WPA2 safeguards) opens unchanged once Direct Router Control is active;
/// until then nothing stale is shown as editable.
class WifiArgonGate extends StatelessWidget {
  const WifiArgonGate({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final ssids = pi.routerView?.ssids ?? const <String>[];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 120),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Wi-Fi', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Router Wi-Fi settings live on the TaoTronics router.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: Space.md),
                  const DirectControlPanel(),
                  InfoBanner(
                    tone: Tone.info,
                    icon: Icons.lock_outline_rounded,
                    title: 'Wi-Fi changes need Direct Router Control',
                    message: ssids.isEmpty
                        ? 'Argon\'s observer does not read Wi-Fi settings, so '
                              'passwords never leave the router. Take direct '
                              'control to view and change them; every change is '
                              'confirmed by reading the router back.'
                        : 'Argon reports: ${ssids.join(', ')}. Take direct '
                              'control to change them.',
                  ),
                  const SizedBox(height: Space.md),
                  FilledButton.icon(
                    onPressed: pi.directInProgress
                        ? null
                        : () => showTakeDirectControl(context),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Take Direct Router Control'),
                  ),
                  const SectionLabel('Router settings in Argon mode'),
                  PanelCard(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Column(
                      children: [
                        for (final (title, detail, access)
                            in routerSettingAccess)
                          ListTile(
                            title: Text(title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(detail),
                                const SizedBox(height: Space.xs),
                                StatusPill(
                                  label: access.label,
                                  tone: access.tone,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    'WPA3 is not offered: the router\'s WPA3 behaviour is '
                    'unverified, so the Wi-Fi screen keeps WPA2 safeguards.',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
