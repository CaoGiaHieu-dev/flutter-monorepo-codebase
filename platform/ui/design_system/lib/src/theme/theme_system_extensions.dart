import 'package:material_ui/material_ui.dart';

/// The app's colour palette, carried on [ThemeData.extensions] and read with
/// `context.colors`.
///
/// It is the single source of every colour: `ThemeProvider` builds
/// Material's [ColorScheme] from these tokens too (see
/// [ThemeSystemExtension.toColorScheme]), so `context.colors.primary` and
/// `Theme.of(context).colorScheme.primary` always agree.
///
/// [light] and [dark] are the two palettes; to rebrand, change their values.
/// A new token is a field here, a line in [copyWith], [lerp] and both
/// palettes — the analyzer points at each place a required argument is
/// missing.
@immutable
class ThemeSystemExtension extends ThemeExtension<ThemeSystemExtension> {
  const ThemeSystemExtension({
    required this.primary,
    required this.primaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.textInverse,
    required this.border,
    required this.divider,
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    required this.shadow,
    required this.scrim,
    required this.primaryGradientColors,
    required this.liquidOnboardingColors,
  });

  // Core colors
  final Color primary;
  final Color primaryContainer;
  final Color secondary;
  final Color secondaryContainer;

  // Backgrounds & Surfaces
  final Color background;
  final Color surface;
  final Color surfaceVariant;

  // Texts
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color textInverse;

  // Borders & Dividers
  final Color border;
  final Color divider;

  // Status
  final Color success;
  final Color error;
  final Color warning;
  final Color info;

  // Elevation & overlays

  /// Base colour of `AppShadows`; each shadow applies its own alpha. The
  /// same in both palettes — `AppShadows` is context-free and reads the
  /// light one.
  final Color shadow;

  /// The dim layer behind a modal — dialog barrier, loading overlay.
  ///
  /// Black with an alpha in **both** palettes, on purpose: a scrim dims
  /// whatever is behind it, and Flutter's own `ModalBarrier` is a fixed black
  /// for the same reason. A theme-inverting value would *lighten* the screen
  /// in dark mode.
  final Color scrim;

  // Theme Gradients
  final List<Color> primaryGradientColors;
  final List<Color> liquidOnboardingColors;

  /// Light theme palette.
  static const ThemeSystemExtension light = ThemeSystemExtension(
    primary: Color(0xff0A7E8C),
    primaryContainer: Color(0xff8B5CF6),
    secondary: Color(0xff1E293B), // iOS slate secondary
    secondaryContainer: Color(0xffF1F5F9), // iOS slate container
    background: Color(0xffF8FAFC), // Light iOS layout background
    surface: Color(0xffFFFFFF), // Frosted glass layout surface
    surfaceVariant: Color(0xffF1F5F9),
    textPrimary: Color(0xff0F172A),
    textSecondary: Color(0xff64748B),
    textDisabled: Color(0xff94A3B8),
    textInverse: Color(0xffFFFFFF),
    border: Color(0xffE2E8F0),
    divider: Color(0xffF1F5F9),
    success: Color(0xff10B981),
    error: Color(0xffEF4444),
    warning: Color(0xffF59E0B),
    info: Color(0xff3B82F6),
    shadow: Color(0xff000000),
    scrim: Color(0x8A000000), // black, 54%
    primaryGradientColors: [
      Color(0xff0A7E8C), // primary
      Color(0xff8B5CF6), // primaryContainer
    ],
    liquidOnboardingColors: [
      Color(0xff3B82F6), // blue
      Color(0xff8B5CF6), // violet/pink
      Color(0xffEF4444), // red
    ],
  );

  /// Dark theme palette.
  static const ThemeSystemExtension dark = ThemeSystemExtension(
    primary: Color(0xff22D3EE),
    primaryContainer: Color(0xffA78BFA),
    secondary: Color(0xff94A3B8),
    secondaryContainer: Color(0xff1E293B),
    background: Color(0xff0B0F19), // Dark iOS midnight background
    surface: Color(0xff151F32), // Glassmorphism dark card surface
    surfaceVariant: Color(0xff1E293B),
    textPrimary: Color(0xffF8FAFC),
    textSecondary: Color(0xff94A3B8),
    textDisabled: Color(0xff475569),
    textInverse: Color(0xff0F172A),
    border: Color(0xff1E293B),
    divider: Color(0xff1E293B),
    success: Color(0xff34D399),
    error: Color(0xffF87171),
    warning: Color(0xffFBBF24),
    info: Color(0xff60A5FA),
    shadow: Color(0xff000000),
    scrim: Color(0x8A000000), // black, 54%
    primaryGradientColors: [
      Color(0xff22D3EE), // primary
      Color(0xffA78BFA), // primaryContainer
    ],
    liquidOnboardingColors: [
      Color(0xff60A5FA), // info/blue
      Color(0xffA78BFA), // primaryContainer/violet
      Color(0xffF87171), // error/red
    ],
  );

  /// The palette for [mode]; [ThemeMode.system] reads as light, since this
  /// has no platform brightness to resolve it against.
  static ThemeSystemExtension withMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => light,
      ThemeMode.light => light,
      ThemeMode.dark => dark,
    };
  }

  /// Material's [ColorScheme] built from this palette, for [brightness].
  ///
  /// Every slot a widget in this repository reads — and the ones Material's
  /// own components default to (`onSurface` for text fields, `outline` for
  /// borders, `surfaceContainerHighest` for filled inputs, `scrim` for
  /// barriers) — comes from a palette token, so the stock
  /// `ColorScheme.light()` / `.dark()` colours never leak into a screen.
  ColorScheme toColorScheme(Brightness brightness) {
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: textInverse,
      primaryContainer: primaryContainer,
      onPrimaryContainer: textInverse,
      secondary: secondary,
      onSecondary: textInverse,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: textPrimary,
      tertiary: info,
      onTertiary: textInverse,
      error: error,
      onError: textInverse,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerHighest: surfaceVariant,
      outline: border,
      outlineVariant: divider,
      shadow: shadow,
      scrim: scrim,
      inverseSurface: textPrimary,
      onInverseSurface: surface,
      inversePrimary: primaryContainer,
    );
  }

  @override
  ThemeSystemExtension copyWith({
    Color? primary,
    Color? primaryContainer,
    Color? secondary,
    Color? secondaryContainer,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? textInverse,
    Color? border,
    Color? divider,
    Color? success,
    Color? error,
    Color? warning,
    Color? info,
    Color? shadow,
    Color? scrim,
    List<Color>? primaryGradientColors,
    List<Color>? liquidOnboardingColors,
  }) {
    return ThemeSystemExtension(
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      secondary: secondary ?? this.secondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      textInverse: textInverse ?? this.textInverse,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
      primaryGradientColors:
          primaryGradientColors ?? this.primaryGradientColors,
      liquidOnboardingColors:
          liquidOnboardingColors ?? this.liquidOnboardingColors,
    );
  }

  @override
  ThemeSystemExtension lerp(
    covariant ThemeExtension<ThemeSystemExtension>? other,
    double t,
  ) {
    if (other is! ThemeSystemExtension) return this;
    return ThemeSystemExtension(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer: Color.lerp(
        primaryContainer,
        other.primaryContainer,
        t,
      )!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryContainer: Color.lerp(
        secondaryContainer,
        other.secondaryContainer,
        t,
      )!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      primaryGradientColors: _lerpColorList(
        primaryGradientColors,
        other.primaryGradientColors,
        t,
      ),
      liquidOnboardingColors: _lerpColorList(
        liquidOnboardingColors,
        other.liquidOnboardingColors,
        t,
      ),
    );
  }

  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    return [
      for (var i = 0; i < a.length; i++)
        i < b.length ? Color.lerp(a[i], b[i], t)! : a[i],
    ];
  }
}
