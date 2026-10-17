import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tt_router_flutter/providers/router_provider.dart';
import 'package:tt_router_flutter/screens/pairing_screen.dart';
import 'package:tt_router_flutter/screens/setup_wizard_screen.dart';
import 'package:tt_router_flutter/services/auth_pairing_service.dart';
import 'package:tt_router_flutter/services/credential_store.dart';
import 'package:tt_router_flutter/theme/app_theme.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final (name, screen) in [
      ('setup guide', const SetupWizardScreen.guide()),
      ('pairing', const PairingScreen()),
    ]) {
      testWidgets('$name renders in ${mode.name} mode on the cover screen', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(344, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final provider = RouterProvider(
          authService: AuthPairingService(
            credentialStore: MemoryCredentialStore(),
          ),
          autoStart: false,
        );
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: mode,
              home: screen,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        provider.dispose();
      });
    }
  }
}
