import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/router_provider.dart';
import 'providers/pi_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const TTRouterApp());
    },
    (error, stackTrace) {
      if (error is SocketException && error.osError?.errorCode == 103) {
        debugPrint('TT Router: local socket closed during reconnect - $error');
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'tt_router_flutter',
        ),
      );
    },
  );
}

class TTRouterApp extends StatelessWidget {
  const TTRouterApp({super.key, this.home = const SplashScreen()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RouterProvider()),
        // Created eagerly: Argon discovery starts with the app, not with a tab.
        ChangeNotifierProvider(
          lazy: false,
          create: (context) =>
              PiProvider(router: context.read<RouterProvider>()),
        ),
      ],
      child: MaterialApp(
        title: 'TT Router',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: home,
      ),
    );
  }
}
