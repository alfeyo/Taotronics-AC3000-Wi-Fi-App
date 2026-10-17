import 'package:flutter/material.dart';

import '../app_info.dart';
import '../providers/router_provider.dart';
import '../screens/devices_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/discovery_screen.dart';
import '../services/router_certificate_verifier.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_widgets.dart';
import 'feedback.dart';

/// Global device search from the Home header. Results open the same device
/// details sheet as the Devices tab.
Future<void> showDeviceSearch(BuildContext context, RouterProvider provider) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DeviceSearchSheet(provider: provider),
  );
}

class _DeviceSearchSheet extends StatefulWidget {
  const _DeviceSearchSheet({required this.provider});

  final RouterProvider provider;

  @override
  State<_DeviceSearchSheet> createState() => _DeviceSearchSheetState();
}

class _DeviceSearchSheetState extends State<_DeviceSearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.text.trim().toLowerCase();
    final results = sortDevices(
      widget.provider.devices
          .where((d) => q.isEmpty || d.searchText.contains(q))
          .toList(),
      DeviceSort.activity,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchBar(
              controller: _query,
              autoFocus: true,
              hintText: 'Search devices by name, IP or MAC',
              leading: const Icon(Icons.search_rounded),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.md),
            Expanded(
              child: results.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: widget.provider.devices.isEmpty
                          ? 'No devices reported yet'
                          : 'No devices match',
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = results[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: IconBadge(
                            Icons.devices_other_rounded,
                            tone: d.isOnline ? Tone.brand : Tone.neutral,
                            size: 40,
                            round: true,
                          ),
                          title: Text(d.displayName),
                          subtitle: Text(
                            '${d.ipAddress ?? d.mac} · '
                            '${d.isOnline ? (d.isActive ? 'active' : 'online') : 'offline'}',
                            style: theme.textTheme.bodySmall,
                          ),
                          onTap: () => showDeviceDetails(context, d),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local router and app preferences (no cloud account).
Future<void> showRouterPreferences(
  BuildContext context,
  RouterProvider provider,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final router = provider.currentRouter;
      final meshId = router?.meshId;
      final verdict = provider.certificateVerdict;
      final paired = provider.authService.pairedRouters;
      final secure =
          meshId != null &&
          provider.authService.isPasswordStoredSecurely(meshId);

      Future<void> logout() async {
        final ok = await confirmAction(
          sheetContext,
          title: 'Log out of this router?',
          message:
              'The app disconnects and returns to discovery. Your pairing '
              'stays saved, so you can reconnect later.',
          confirmLabel: 'Log out',
          icon: Icons.logout_rounded,
        );
        if (!ok || !sheetContext.mounted) return;
        await provider.logout();
        if (!sheetContext.mounted) return;
        Navigator.of(sheetContext).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
          (_) => false,
        );
      }

      Future<void> restart() async {
        final ok = await confirmAction(
          sheetContext,
          title: 'Restart all mesh nodes?',
          message:
              'Every device loses its connection for a few minutes while the '
              'router restarts. The app reconnects automatically.',
          confirmLabel: 'Restart',
          destructive: true,
          icon: Icons.restart_alt_rounded,
        );
        if (!ok || !sheetContext.mounted) return;
        final result = await provider.rebootRouter();
        if (sheetContext.mounted) showSaveResult(sheetContext, result);
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          children: [
            Text('Router & preferences', style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.md),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connected router', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Space.sm),
                  for (final (label, value) in [
                    ('Mesh ID', meshId ?? 'None'),
                    ('Address', router?.ipAddress ?? 'Unknown'),
                    (
                      'Certificate',
                      verdict == null
                          ? 'Not checked'
                          : verdict.trusted
                          ? 'Verified TaoTronics'
                          : 'Rejected',
                    ),
                    (
                      'Saved password',
                      meshId == null || !provider.authService.isPaired(meshId)
                          ? 'Not paired'
                          : secure
                          ? 'Android Keystore'
                          : 'App storage',
                    ),
                    ('Paired routers', '${paired.length}'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
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
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (paired.isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      'Paired ${formatAge(paired.first.pairedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            ActionTile(
              icon: Icons.monitor_heart_outlined,
              tone: Tone.info,
              title: 'Diagnostics',
              subtitle: 'Connection checks and exportable report',
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  sheetContext,
                  MaterialPageRoute(
                    builder: (_) => DiagnosticsScreen(
                      routerReachable: provider.isNetworkReachable,
                      mqttPortOpen: provider.isMqttPortOpen,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: Space.sm),
            ActionTile(
              icon: Icons.restart_alt_rounded,
              tone: Tone.danger,
              title: 'Restart router',
              subtitle: 'Reboot all mesh nodes',
              enabled: provider.isConnected,
              onTap: restart,
            ),
            const SizedBox(height: Space.sm),
            ActionTile(
              icon: Icons.logout_rounded,
              tone: Tone.neutral,
              title: 'Log out',
              subtitle: 'Return to discovery; pairing stays saved',
              onTap: logout,
            ),
            const SizedBox(height: Space.lg),
            Center(
              child: Text(
                '${AppInfo.name} ${AppInfo.version} (${AppInfo.build}) · local control only',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
