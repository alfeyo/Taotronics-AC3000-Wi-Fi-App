import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/home_widgets.dart';
import '../widgets/hub_widgets.dart';
import '../widgets/managed_router.dart';
import 'app_routes.dart';
import 'home_screen.dart';
import 'overview_tab.dart';

/// Router tab. In Argon mode (default) it shows the TaoTronics router as
/// Argon's observer reports it: opening it never starts a router session.
/// Under Direct Router Control it becomes the original live My Router
/// dashboard (LEDs, Wi-Fi, mesh) with the way back to Argon monitoring.
class RouterTab extends StatelessWidget {
  const RouterTab({super.key});

  @override
  Widget build(BuildContext context) {
    final direct = context.select<RouterProvider, bool>((r) => r.isDirectMode);
    final pi = maybePiProvider(context);
    if (direct || pi == null) return const RouterDetailsScreen();
    return _ArgonRouterPage(pi: pi);
  }
}

class _ArgonRouterPage extends StatelessWidget {
  const _ArgonRouterPage({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final router = context.watch<RouterProvider>();
    final view = pi.routerView;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    void select(HomeTab tab) => HomeNavigation.maybeOf(context)?.select(tab);
    final hero = _RouterHero(view: view, state: pi.hubState, select: select);
    final details = <Widget>[
      _DirectControlCard(pi: pi, router: router, view: view),
      const SectionLabel('Router'),
      _RouterFacts(view: view, state: pi.hubState),
      const SectionLabel('Router tools'),
      ResponsiveGrid(
        minTileWidth: 260,
        maxColumns: 2,
        spacing: Space.sm,
        children: [
          ActionTile(
            icon: Icons.wifi_rounded,
            tone: Tone.info,
            title: 'Advanced Wi-Fi settings',
            subtitle: 'Names, passwords, bands · needs direct control',
            onTap: () => AppRoutes.wifi(context),
          ),
          ActionTile(
            icon: Icons.settings_input_antenna_rounded,
            tone: Tone.brand,
            title: 'Nokia Mesh',
            subtitle: 'Beacon status and setup',
            onTap: () => AppRoutes.nokiaMesh(context),
          ),
          ActionTile(
            icon: Icons.monitor_heart_outlined,
            tone: Tone.neutral,
            title: 'Router diagnostics',
            subtitle: 'Phone-side network checks',
            onTap: () => AppRoutes.routerDiagnostics(context),
          ),
          ActionTile(
            icon: Icons.devices_other_rounded,
            tone: Tone.success,
            title: 'Connected devices',
            subtitle: view?.onlineCount == null
                ? 'Client list from Argon'
                : '${view!.onlineCount} online · ${view.knownCount} known',
            onTap: () => select(HomeTab.devices),
          ),
        ],
      ),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: pi.refreshNow,
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
                maxWidth: wide ? 1040 : Breakpoints.contentMaxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Router',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                Text(
                                  [
                                    routerMonitoringLabel(view),
                                    if (view?.observedAt != null)
                                      formatAge(view!.observedAt),
                                  ].join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        EventsButton(provider: router),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    const DirectControlPanel(),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: hero),
                          const SizedBox(width: Space.xl),
                          Expanded(child: Column(children: details)),
                        ],
                      )
                    else ...[
                      hero,
                      const SizedBox(height: Space.lg),
                      ...details,
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

class _RouterHero extends StatelessWidget {
  const _RouterHero({
    required this.view,
    required this.state,
    required this.select,
  });
  final ArgonRouterView? view;
  final HubDataState state;
  final ValueChanged<HomeTab> select;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = view?.live == true;
    final internet = live ? view?.internet : null;
    return Column(
      children: [
        SizedBox(
          height: 268,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.62,
                      colors: [
                        (live ? Palette.amber : theme.colorScheme.primary)
                            .withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
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
                label:
                    'TaoTronics router, ${routerMonitoringLabel(view).toLowerCase()}',
                child: RouterImage(
                  ledOn: live ? view?.ledOn : null,
                  dim: !live,
                ),
              ),
            ],
          ),
        ),
        Text(
          'TaoTronics ${view?.model ?? 'router'}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            StatusPill(
              label: !live
                  ? routerMonitoringLabel(view)
                  : internet == null
                  ? 'Router online'
                  : internet
                  ? 'Internet online'
                  : 'No internet',
              tone: !live
                  ? routerMonitoringTone(view)
                  : internet == false
                  ? Tone.danger
                  : Tone.success,
              dot: true,
            ),
            if (view?.onlineCount != null)
              Semantics(
                button: true,
                child: GestureDetector(
                  onTap: () => select(HomeTab.devices),
                  child: StatusPill(
                    label: '${view!.onlineCount} devices',
                    tone: Tone.info,
                    icon: Icons.devices_other_rounded,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RouterFacts extends StatelessWidget {
  const _RouterFacts({required this.view, required this.state});
  final ArgonRouterView? view;
  final HubDataState state;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final live = v?.live == true;
    String val(String? s) => hubValue(state, s);
    return PanelCard(
      child: Column(
        children: [
          KvRow(
            'Household Wi-Fi',
            v?.ssids.isNotEmpty == true
                ? v!.ssids.join(', ')
                : 'Name shown under direct control',
          ),
          KvRow(
            'Wi-Fi availability',
            !live
                ? val(v == null ? null : 'Unknown · router not observed')
                : v!.wifiCount == null
                ? 'Router online'
                : 'Serving ${v.clients.where((c) => c.online == true && c.connectionType == 'wifi').length} Wi-Fi clients',
          ),
          KvRow(
            'Connected devices',
            val(
              v?.knownCount == null
                  ? null
                  : '${v!.onlineCount ?? '—'} online · ${v.knownCount} known',
            ),
          ),
          KvRow(
            'Mesh nodes',
            v?.nodesTotal == null
                ? 'Not reported'
                : '${v!.nodesOnline ?? '?'} of ${v.nodesTotal} online',
          ),
          KvRow(
            'Router uptime',
            v?.uptimeSeconds == null
                ? 'Not reported'
                : formatUptime(v!.uptimeSeconds!),
          ),
          KvRow(
            'Health',
            !live
                ? val(v == null ? null : routerMonitoringLabel(v))
                : [
                    if (v!.internet != null)
                      v.internet! ? 'internet ok' : 'no internet',
                    if (v.responseMs != null)
                      'answers in ${(v.responseMs! / 1000).toStringAsFixed(1)} s',
                  ].join(' · ').ifEmptyThen('Responding'),
          ),
          KvRow(
            'LED',
            live && v?.ledOn != null
                ? (v!.ledOn! ? 'On' : 'Off')
                : 'Not reported by the observer',
            last: true,
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmptyThen(String other) => isEmpty ? other : this;
}

/// Who holds the router's single management session, and the one deliberate
/// switch to take it (or give it back).
class _DirectControlCard extends StatelessWidget {
  const _DirectControlCard({
    required this.pi,
    required this.router,
    required this.view,
  });
  final PiProvider pi;
  final RouterProvider router;
  final ArgonRouterView? view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final lease = view?.lease;
    final holder = lease?.active == true
        ? '${lease!.holderName ?? 'A paired phone'} (direct control)'
        : view?.observedByArgon == true
        ? 'Argon · ${view!.sourceLabel}'
        : view?.controlHolder == 'phone-snapshot'
        ? 'No observer · last data from a phone'
        : 'Nobody reported';
    final busy = pi.directInProgress;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: Palette.amber.withValues(alpha: 0.45)),
        color: Palette.amber.withValues(alpha: 0.06),
      ),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                color: Palette.amber,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Direct Router Control',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Router controlled by: $holder',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Take control only to change router settings. Argon\'s observer '
            'pauses until you return; internet, VPN and accounting keep '
            'running.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                foregroundColor: Palette.background,
                backgroundColor: Palette.amber,
              ),
              onPressed: busy ? null : () => showTakeDirectControl(context),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: Text(busy ? 'Taking control…' : 'Take Direct Control'),
            ),
          ),
        ],
      ),
    );
  }
}
