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
  overview('Home', Icons.space_dashboard_outlined, Icons.space_dashboard),
  devices('Devices', Icons.devices_outlined, Icons.devices),
  wifi('Wi-Fi', Icons.wifi_outlined, Icons.wifi),
  settings('Settings', Icons.settings_outlined, Icons.settings);

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
              body: body,
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab.index,
                onDestinationSelected: (i) => _select(HomeTab.values[i]),
                destinations: [
                  for (final tab in HomeTab.values)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: tab.label,
                    ),
                ],
              ),
            ),
    );
  }
}
