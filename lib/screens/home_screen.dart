import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/home_widgets.dart';
import 'argon_devices_view.dart';
import 'argon_statistics_view.dart';
import 'router_tab.dart';
import '../widgets/app_widgets.dart';
import 'devices_screen.dart';
import 'home_tab.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';

/// Top-level destinations of the signed-in app.
enum HomeTab {
  overview('Home', Icons.home_outlined, Icons.home_rounded),
  router('Router', Icons.router_outlined, Icons.router_rounded),
  devices('Devices', Icons.devices_other_outlined, Icons.devices_other_rounded),
  statistics('Statistics', Icons.insights_outlined, Icons.insights_rounded),
  settings('Settings', Icons.settings_outlined, Icons.settings_rounded);

  const HomeTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Lets tabs switch to another destination (e.g. the dashboard's device
/// summary opens the Devices tab).
class HomeNavigation extends InheritedWidget {
  const HomeNavigation({super.key, required this.select, required super.child});

  final ValueChanged<HomeTab> select;

  static HomeNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeNavigation>();

  @override
  bool updateShouldNotify(HomeNavigation oldWidget) => false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialTab = HomeTab.overview});

  final HomeTab initialTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late HomeTab _tab = widget.initialTab;

  void _select(HomeTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  Future<void> _onBack() async {
    if (_tab != HomeTab.overview) {
      _select(HomeTab.overview);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave TT Router?'),
        content: const Text(
          'Argon keeps monitoring your network. Your pairings stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true) SystemNavigator.pop();
  }

  // Only the visible tab is built, so per-screen work (polling pauses,
  // refreshes) stops when the user switches away. In Argon mode (default)
  // Devices and Statistics come from Argon and router settings wait for
  // Direct Router Control; in Direct Control the router-backed screens return.
  Widget _buildTab() {
    final argon =
        context.select<RouterProvider, bool>((r) => r.isArgonMode) &&
        maybePiProvider(context, listen: false) != null;
    return KeyedSubtree(
      key: ValueKey((_tab, argon)),
      child: switch (_tab) {
        HomeTab.overview => const OverviewTab(),
        HomeTab.router => const RouterTab(),
        HomeTab.devices =>
          argon ? const ArgonDevicesView() : const DevicesScreen(),
        HomeTab.statistics =>
          argon ? const ArgonStatisticsView() : const StatisticsScreen(),
        HomeTab.settings => const SettingsScreen(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    final body = HomeNavigation(select: _select, child: _buildTab());

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: wide
          ? Scaffold(
              body: Row(
                children: [
                  SafeArea(
                    right: false,
                    // A phone in landscape is wide but short: the rail must
                    // scroll instead of overflowing its six destinations.
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final short = constraints.maxHeight < 560;
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: IntrinsicHeight(
                              child: NavigationRail(
                                selectedIndex: _tab.index,
                                onDestinationSelected: (i) =>
                                    _select(HomeTab.values[i]),
                                groupAlignment: short ? -1 : -0.85,
                                labelType: short
                                    ? NavigationRailLabelType.selected
                                    : null,
                                leading: short
                                    ? null
                                    : const Padding(
                                        padding: EdgeInsets.only(
                                          bottom: Space.lg,
                                        ),
                                        child: IconBadge(
                                          Icons.developer_board_rounded,
                                        ),
                                      ),
                                destinations: [
                                  for (final tab in HomeTab.values)
                                    NavigationRailDestination(
                                      icon: Icon(tab.icon),
                                      selectedIcon: Icon(tab.selectedIcon),
                                      label: Text(tab.label),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              ),
            )
          : Scaffold(
              extendBody: true,
              body: body,
              bottomNavigationBar: FloatingNavBar(
                selected: _tab,
                onSelected: _select,
              ),
            ),
    );
  }
}

/// Rounded navigation bar that floats above the content.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final HomeTab selected;
  final ValueChanged<HomeTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final theme = Theme.of(context);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
      child: Material(
        color: colors.navBar,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              for (final tab in HomeTab.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: tab == selected,
                    label: tab.label,
                    child: ExcludeSemantics(
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => onSelected(tab),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          height: 54,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: ShapeDecoration(
                            shape: const StadiumBorder(),
                            color: tab == selected
                                ? colors.navIndicator
                                : Colors.transparent,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                tab == selected ? tab.selectedIcon : tab.icon,
                                size: 21,
                                color: tab == selected
                                    ? colors.onNavIndicator
                                    : colors.onNavBar,
                              ),
                              const SizedBox(height: 2),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    tab.label,
                                    maxLines: 1,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 10.5,
                                      color: tab == selected
                                          ? colors.onNavIndicator
                                          : colors.onNavBar,
                                      fontWeight: tab == selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
