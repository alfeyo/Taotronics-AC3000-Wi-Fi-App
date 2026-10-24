import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_info.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../providers/router_provider.dart';
import '../providers/pi_provider.dart';
import '../widgets/home_widgets.dart';
import 'discovery_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  Timer? _navigationTimer;
  Timer? _textTimer;
  late final AnimationController _logoController;
  late final AnimationController _textController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _textController.forward();
    });

    _navigationTimer = Timer(const Duration(milliseconds: 1700), _goNext);
  }

  bool _connecting = false;

  /// Pi-first start: opens Home as soon as Argon answers (or after a short
  /// wait, showing its honest offline state). The router is never contacted
  /// here. Only a phone that knows neither Argon nor a router sees setup.
  Future<void> _goNext() async {
    if (!mounted) return;
    final router = context.read<RouterProvider>();
    final pi = maybePiProvider(context, listen: false);
    await router.ready;
    if (pi != null) await pi.ready;
    if (!mounted) return;
    final knowsArgon = pi?.trustedId != null;
    if (pi != null && !pi.connected) {
      setState(() => _connecting = true);
      final done = Completer<void>();
      void check() {
        if ((pi.connected || pi.state == PiLinkState.unreachable) &&
            !done.isCompleted) {
          done.complete();
        }
      }

      pi.addListener(check);
      check();
      await done.future
          .timeout(const Duration(seconds: 8), onTimeout: () {})
          .whenComplete(() => pi.removeListener(check));
    }
    if (!mounted) return;
    final home =
        (pi?.connected ?? false) || knowsArgon || router.hasSavedPairing;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) =>
            home ? const HomeScreen() : const DiscoveryScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _textTimer?.cancel();
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Palette.background,
        child: Stack(
          children: [
            // Soft spotlight behind the router, as on the Home hero.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.12),
                    radius: 0.7,
                    colors: [
                      Palette.icy.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      final scale = Curves.elasticOut.transform(
                        _logoController.value,
                      );
                      return Transform.scale(
                        scale: 0.6 + 0.4 * scale,
                        child: Opacity(
                          opacity: _logoController.value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 104,
                      height: 138,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0xff767b86),
                          BlendMode.modulate,
                        ),
                        child: Image.asset(
                          'assets/original_setup/ic_guide_need.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _textController.value,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - _textController.value)),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      children: const [
                        Text(
                          'TT Router',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Palette.softWhite,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Household network · Argon',
                          style: TextStyle(
                            fontSize: 14,
                            color: Palette.muted,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: Column(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Palette.icy.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _connecting
                        ? 'Connecting to Argon…'
                        : 'v${AppInfo.version}',
                    style: TextStyle(
                      color: Palette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
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
