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

/// Smart-home palette (charcoal, slate, indigo, amber, off-white).
abstract final class Palette {
  static const charcoal = Color(0xff23242c);
  static const panel = Color(0xff2b2d37);
  static const panelRaised = Color(0xff353744);
  static const line = Color(0xff444651);
  static const slate = Color(0xff747782);

  /// Page background in dark mode: slate deepened so off-white text keeps
  /// at least 6.5:1 contrast (#747782 itself only reaches 4.1:1).
  static const slateDeep = Color(0xff545864);
  static const indigo = Color(0xff777dde);
  static const indigoLight = Color(0xff858ae9);
  static const indigoPale = Color(0xffc1c4fc);

  /// Indigo for light backgrounds: 5.25:1 against white.
  static const indigoDeep = Color(0xff5b61c9);
  static const amber = Color(0xfff0a85b);
  static const offWhite = Color(0xfff5f6fa);
  static const muted = Color(0xffb2b4be);
  static const lime = Color(0xffcbe89b);
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
    success: Color(0xff3d7a2a),
    successContainer: Color(0xffe3f2cf),
    onSuccessContainer: Color(0xff23471a),
    warning: Color(0xffa85e12),
    warningContainer: Color(0xfffcebd6),
    onWarningContainer: Color(0xff5c3307),
    info: Palette.indigoDeep,
    infoContainer: Color(0xffe6e7fb),
    onInfoContainer: Color(0xff2b2f7a),
    accent: Color(0xffa85e12),
    accentContainer: Color(0xfffcebd6),
    onAccentContainer: Color(0xff5c3307),
    navBar: Palette.charcoal,
    onNavBar: Palette.muted,
    navIndicator: Palette.offWhite,
    onNavIndicator: Palette.charcoal,
  );

  static const dark = StatusColors(
    success: Palette.lime,
    successContainer: Color(0xff2f3a26),
    onSuccessContainer: Palette.lime,
    warning: Palette.amber,
    warningContainer: Color(0xff463826),
    onWarningContainer: Color(0xffffd9ae),
    info: Palette.indigoPale,
    infoContainer: Palette.panelRaised,
    onInfoContainer: Palette.indigoPale,
    accent: Palette.amber,
    accentContainer: Palette.panelRaised,
    onAccentContainer: Palette.amber,
    navBar: Palette.offWhite,
    onNavBar: Color(0xff585d6a),
    navIndicator: Palette.charcoal,
    onNavIndicator: Palette.offWhite,
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
      primaryContainer: Color(0xffe6e7fb),
      onPrimaryContainer: Color(0xff2b2f7a),
      secondary: Palette.amber,
      onSecondary: Palette.charcoal,
      secondaryContainer: Color(0xffeceef3),
      onSecondaryContainer: Palette.charcoal,
      tertiary: Color(0xffa85e12),
      onTertiary: Colors.white,
      error: Color(0xffc23b3b),
      onError: Colors.white,
      errorContainer: Color(0xfffbe3e3),
      onErrorContainer: Color(0xff6e1515),
      surface: Colors.white,
      onSurface: Palette.charcoal,
      onSurfaceVariant: Color(0xff5d616d),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xfffafbfd),
      surfaceContainer: Color(0xfff1f2f6),
      surfaceContainerHigh: Color(0xffeceef3),
      surfaceContainerHighest: Color(0xffe4e6ec),
      outline: Color(0xff858895),
      outlineVariant: Color(0xffdfe1e8),
      inverseSurface: Palette.charcoal,
      onInverseSurface: Palette.offWhite,
      inversePrimary: Palette.indigoPale,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    background: Palette.offWhite,
    status: StatusColors.light,
  );

  static ThemeData dark() => _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: Palette.indigoLight,
      onPrimary: Color(0xff16172a),
      primaryContainer: Palette.panelRaised,
      onPrimaryContainer: Palette.indigoPale,
      secondary: Palette.amber,
      onSecondary: Palette.charcoal,
      secondaryContainer: Palette.panelRaised,
      onSecondaryContainer: Palette.offWhite,
      tertiary: Palette.amber,
      onTertiary: Palette.charcoal,
      error: Color(0xffff8a80),
      onError: Color(0xff3a0b08),
      errorContainer: Color(0xff4a2626),
      onErrorContainer: Color(0xffffd4cf),
      surface: Palette.charcoal,
      onSurface: Palette.offWhite,
      // Readable on both charcoal cards and the slate page background.
      onSurfaceVariant: Color(0xffd0d2da),
      surfaceContainerLowest: Palette.charcoal,
      surfaceContainerLow: Palette.charcoal,
      surfaceContainer: Palette.panel,
      surfaceContainerHigh: Palette.panel,
      surfaceContainerHighest: Palette.panelRaised,
      outline: Palette.slate,
      outlineVariant: Palette.line,
      inverseSurface: Palette.offWhite,
      onInverseSurface: Palette.charcoal,
      inversePrimary: Palette.indigoDeep,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    background: Palette.slateDeep,
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
      side: dark
          ? BorderSide.none
          : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
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
          foregroundColor: dark ? Palette.indigoPale : scheme.primary,
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
        selectedColor: dark ? Palette.offWhite : Palette.charcoal,
        labelStyle: text.labelLarge,
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: dark ? Palette.charcoal : Palette.offWhite,
        ),
        checkmarkColor: dark ? Palette.charcoal : Palette.offWhite,
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
              ? Palette.charcoal
              : (dark ? Palette.muted : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Palette.amber.withValues(
                  alpha: states.contains(WidgetState.disabled) ? 0.45 : 1,
                )
              : (dark ? Palette.panelRaised : const Color(0xffd5d7df)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dark ? Palette.indigoLight : scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark ? Palette.offWhite : Palette.charcoal,
        foregroundColor: dark ? Palette.charcoal : Palette.offWhite,
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
