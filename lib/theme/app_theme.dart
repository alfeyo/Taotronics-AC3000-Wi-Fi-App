import 'package:flutter/material.dart';

/// Semantic tones used by status pills, banners, badges and tiles.
enum Tone { success, warning, danger, info, neutral, brand, accent }

/// Spacing scale (4 pt grid).
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Corner radii. Panels are generously rounded, controls are pills.
abstract final class Radii {
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 26.0;
  static const xl = 30.0;
}

/// Width breakpoints. The Galaxy Z Fold4 cover screen is ~344 dp wide and the
/// unfolded inner screen ~690 dp, so it crosses [medium].
abstract final class Breakpoints {
  static const medium = 600.0;
  static const expanded = 840.0;

  /// Upper bound for readable single-column content on wide screens.
  static const contentMaxWidth = 720.0;
}

/// Premium router palette: near-black layers, icy-blue accent, amber only
/// for LED activity, restrained green for confirmed positive states.
abstract final class Palette {
  static const background = Color(0xff17181b);
  static const charcoal = Color(0xff24252a);
  static const panel = Color(0xff24252a);
  static const panelRaised = Color(0xff30323a);
  static const line = Color(0xff3a3c44);
  static const slate = Color(0xff747782);
  static const softWhite = Color(0xffecedf0);

  /// Secondary text: >= 4.9:1 on every dark surface.
  static const muted = Color(0xff9da1ab);
  static const icy = Color(0xffc9d8f4);
  static const indigo = Color(0xffa9bceb);
  static const indigoDeep = Color(0xff4a5ca6);
  static const amber = Color(0xfff0a85b);
  static const green = Color(0xff9bd5a6);
  static const offWhite = Color(0xfff3f4f6);

  // Kept for existing references.
  static const slateDeep = background;
  static const indigoLight = icy;
  static const indigoPale = icy;
  static const lime = green;
}

/// Semantic colours that Material's ColorScheme does not cover.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.onSuccessContainer,
    required this.successContainer,
    required this.warning,
    required this.onWarningContainer,
    required this.warningContainer,
    required this.info,
    required this.onInfoContainer,
    required this.infoContainer,
    required this.accent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.navBar,
    required this.onNavBar,
    required this.navIndicator,
    required this.onNavIndicator,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color accent;
  final Color accentContainer;
  final Color onAccentContainer;

  /// Floating navigation bar colours.
  final Color navBar;
  final Color onNavBar;
  final Color navIndicator;
  final Color onNavIndicator;

  static const light = StatusColors(
    success: Color(0xff3c7a47),
    successContainer: Color(0xffe2f1e4),
    onSuccessContainer: Color(0xff1f4a28),
    warning: Color(0xffa85e12),
    warningContainer: Color(0xfffcebd6),
    onWarningContainer: Color(0xff5c3307),
    info: Palette.indigoDeep,
    infoContainer: Color(0xffe6ebf8),
    onInfoContainer: Color(0xff26346b),
    accent: Color(0xffa85e12),
    accentContainer: Color(0xfffcebd6),
    onAccentContainer: Color(0xff5c3307),
    navBar: Palette.background,
    onNavBar: Palette.muted,
    navIndicator: Palette.softWhite,
    onNavIndicator: Palette.background,
  );

  static const dark = StatusColors(
    success: Palette.green,
    successContainer: Color(0xff23302a),
    onSuccessContainer: Palette.green,
    warning: Palette.amber,
    warningContainer: Color(0xff3a3127),
    onWarningContainer: Color(0xffffd9ae),
    info: Palette.icy,
    infoContainer: Palette.panelRaised,
    onInfoContainer: Palette.icy,
    accent: Palette.amber,
    accentContainer: Color(0xff3a3127),
    onAccentContainer: Palette.amber,
    navBar: Palette.charcoal,
    onNavBar: Palette.muted,
    navIndicator: Palette.softWhite,
    onNavIndicator: Palette.background,
  );

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return StatusColors(
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      onInfoContainer: l(onInfoContainer, other.onInfoContainer),
      accent: l(accent, other.accent),
      accentContainer: l(accentContainer, other.accentContainer),
      onAccentContainer: l(onAccentContainer, other.onAccentContainer),
      navBar: l(navBar, other.navBar),
      onNavBar: l(onNavBar, other.onNavBar),
      navIndicator: l(navIndicator, other.navIndicator),
      onNavIndicator: l(onNavIndicator, other.onNavIndicator),
    );
  }
}

/// Foreground / container pair for a [Tone].
class ToneColors {
  const ToneColors(this.foreground, this.container, this.onContainer);

  final Color foreground;
  final Color container;
  final Color onContainer;
}

extension ToneTheme on BuildContext {
  StatusColors get statusColors =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;

  ToneColors tone(Tone tone) {
    final scheme = Theme.of(this).colorScheme;
    final status = statusColors;
    return switch (tone) {
      Tone.success => ToneColors(
        status.success,
        status.successContainer,
        status.onSuccessContainer,
      ),
      Tone.warning => ToneColors(
        status.warning,
        status.warningContainer,
        status.onWarningContainer,
      ),
      Tone.danger => ToneColors(
        scheme.error,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      Tone.info => ToneColors(
        status.info,
        status.infoContainer,
        status.onInfoContainer,
      ),
      Tone.brand => ToneColors(
        scheme.primary,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      Tone.accent => ToneColors(
        status.accent,
        status.accentContainer,
        status.onAccentContainer,
      ),
      Tone.neutral => ToneColors(
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
    };
  }
}

abstract final class AppTheme {
  /// Brand colour (indigo) for places that need one fixed value.
  static const brand = Palette.indigo;

  static ThemeData light() => _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: Palette.indigoDeep,
      onPrimary: Colors.white,
      primaryContainer: Color(0xffe6ebf8),
      onPrimaryContainer: Color(0xff26346b),
      secondary: Palette.amber,
      onSecondary: Palette.background,
      secondaryContainer: Color(0xffeceef3),
      onSecondaryContainer: Palette.background,
      tertiary: Color(0xffa85e12),
      onTertiary: Colors.white,
      error: Color(0xffc23b3b),
      onError: Colors.white,
      errorContainer: Color(0xfffbe3e3),
      onErrorContainer: Color(0xff6e1515),
      surface: Colors.white,
      onSurface: Palette.background,
      onSurfaceVariant: Color(0xff5d616d),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xfffafbfd),
      surfaceContainer: Color(0xfff1f2f6),
      surfaceContainerHigh: Color(0xffeceef3),
      surfaceContainerHighest: Color(0xffe4e6ec),
      outline: Color(0xff858895),
      outlineVariant: Color(0xffdfe1e8),
      inverseSurface: Palette.charcoal,
      onInverseSurface: Palette.softWhite,
      inversePrimary: Palette.icy,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    background: Palette.offWhite,
    status: StatusColors.light,
  );

  static ThemeData dark() => _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: Palette.icy,
      onPrimary: Palette.background,
      primaryContainer: Palette.panelRaised,
      onPrimaryContainer: Palette.icy,
      secondary: Palette.amber,
      onSecondary: Palette.background,
      secondaryContainer: Palette.panelRaised,
      onSecondaryContainer: Palette.softWhite,
      tertiary: Palette.amber,
      onTertiary: Palette.background,
      error: Color(0xffff8f86),
      onError: Color(0xff3a0b08),
      errorContainer: Color(0xff3d2628),
      onErrorContainer: Color(0xffffd4cf),
      surface: Palette.charcoal,
      onSurface: Palette.softWhite,
      onSurfaceVariant: Palette.muted,
      surfaceContainerLowest: Palette.background,
      surfaceContainerLow: Palette.charcoal,
      surfaceContainer: Palette.charcoal,
      surfaceContainerHigh: Palette.panelRaised,
      surfaceContainerHighest: Palette.panelRaised,
      outline: Color(0xff5a5d66),
      outlineVariant: Palette.line,
      inverseSurface: Palette.softWhite,
      onInverseSurface: Palette.background,
      inversePrimary: Palette.indigoDeep,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    background: Palette.background,
    status: StatusColors.dark,
  );

  static ThemeData _build(
    ColorScheme scheme, {
    required Color background,
    required StatusColors status,
  }) {
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: scheme.onSurface,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: scheme.onSurface,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: scheme.onSurface,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        );
    final dark = scheme.brightness == Brightness.dark;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
      side: BorderSide(
        color: dark
            ? const Color(0xff2e3037)
            : scheme.outlineVariant.withValues(alpha: 0.8),
      ),
    );
    const stadium = StadiumBorder();

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
        minVerticalPadding: Space.md,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          textStyle: text.labelLarge,
          shape: stadium,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          textStyle: text.labelLarge,
          shape: stadium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
          shape: stadium,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 44),
          textStyle: text.labelLarge,
          shape: stadium,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: 15,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        elevation: const WidgetStatePropertyAll(0),
        shape: const WidgetStatePropertyAll(stadium),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Space.lg),
        ),
        side: WidgetStatePropertyAll(
          dark ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
        ),
        constraints: const BoxConstraints(minHeight: 54),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surface,
        selectedColor: dark ? Palette.softWhite : Palette.background,
        labelStyle: text.labelLarge,
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: dark ? Palette.background : Palette.softWhite,
        ),
        checkmarkColor: dark ? Palette.background : Palette.softWhite,
        shape: stadium,
        side: dark ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: status.navBar,
        indicatorColor: status.navIndicator,
        surfaceTintColor: Colors.transparent,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? status.onNavIndicator
                : status.onNavBar,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: status.onNavBar,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        indicatorColor: status.navIndicator,
        selectedIconTheme: IconThemeData(color: status.onNavIndicator),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.outline
              : states.contains(WidgetState.selected)
              ? Palette.background
              : (dark ? Palette.muted : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (dark ? Palette.icy : Palette.indigoDeep).withValues(
                  alpha: states.contains(WidgetState.disabled) ? 0.45 : 1,
                )
              : (dark ? Palette.panelRaised : const Color(0xffd5d7df)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark ? Palette.softWhite : Palette.background,
        foregroundColor: dark ? Palette.background : Palette.softWhite,
        shape: stadium,
        elevation: 2,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        collapsedTextColor: scheme.onSurface,
      ),
    );
  }
}
