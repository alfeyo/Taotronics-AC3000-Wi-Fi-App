import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/router_provider.dart';
import '../widgets/home_widgets.dart';
import 'diagnostics_screen.dart';
import 'network_hub_screen.dart';
import 'nokia_mesh_screen.dart';
import 'wifi_argon_gate.dart';
import 'wifi_screen.dart';

/// Secondary destinations opened from Home, Router and Settings. None of them
/// starts a router session by itself; router access stays behind Direct
/// Router Control.
abstract final class AppRoutes {
  /// Tab-style screens have no app bar of their own; a slim transparent bar
  /// adds the back button when they are pushed.
  static Future<void> _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            ),
            body: screen,
          ),
        ),
      );

  /// Detailed Argon diagnostics (WAN, CPU/memory, observer health, VPN
  /// details, backup readiness, Bluetooth/Tailscale, event history).
  static Future<void> networkHub(BuildContext context) =>
      _push(context, const NetworkHubScreen());

  /// Advanced Wi-Fi settings in Direct Control; the capability explanation
  /// (and the way into Direct Control) in Argon mode.
  static Future<void> wifi(BuildContext context) {
    return _push(context, const _WifiDestination());
  }

  static Future<void> _pushOwnAppBar(BuildContext context, Widget screen) =>
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen));

  static Future<void> nokiaMesh(BuildContext context) =>
      _pushOwnAppBar(context, const NokiaMeshScreen());

  /// Router-network diagnostics; probes only when direct access is allowed.
  static Future<void> routerDiagnostics(BuildContext context) =>
      _pushOwnAppBar(context, const DiagnosticsScreen());
}

/// Re-evaluate the destination when takeover or background release changes mode.
class _WifiDestination extends StatelessWidget {
  const _WifiDestination();
  @override
  Widget build(BuildContext context) {
    final argon =
        context.watch<RouterProvider>().isArgonMode &&
        maybePiProvider(context) != null;
    return argon ? const WifiArgonGate() : const WifiSettingsScreen();
  }
}
