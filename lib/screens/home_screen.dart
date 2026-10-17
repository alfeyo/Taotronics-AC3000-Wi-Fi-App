import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'devices_screen.dart';
import 'overview_tab.dart';
import 'settings_screen.dart';
import 'wifi_screen.dart';

/// Top-level destinations of the signed-in app.
enum HomeTab {
  overview('Home', Icons.home_outlined, Icons.home_rounded),
  devices('Devices', Icons.devices_other_outlined, Icons.devices_other_rounded),
  wifi('Wi-Fi', Icons.wifi_rounded, Icons.wifi_rounded),
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
          'Your router session stays saved and reconnects when you return.',
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
  // refreshes) stops when the user switches away.
  Widget _buildTab() => KeyedSubtree(
    key: ValueKey(_tab),
    child: switch (_tab) {
      HomeTab.overview => const OverviewTab(),
      HomeTab.devices => const DevicesScreen(),
      HomeTab.wifi => const WifiSettingsScreen(),
      HomeTab.settings => const SettingsScreen(),
    },
  );

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
                    child: NavigationRail(
                      selectedIndex: _tab.index,
                      onDestinationSelected: (i) => _select(HomeTab.values[i]),
                      groupAlignment: -0.85,
                      leading: const Padding(
                        padding: EdgeInsets.only(bottom: Space.lg),
                        child: IconBadge(Icons.router_rounded),
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
      minimum: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      child: Material(
        color: colors.navBar,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: const StadiumBorder(),
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
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          height: 56,
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
                                size: 22,
                                color: tab == selected
                                    ? colors.onNavIndicator
                                    : colors.onNavBar,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tab.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: tab == selected
                                      ? colors.onNavIndicator
                                      : colors.onNavBar,
                                  fontWeight: tab == selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
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
