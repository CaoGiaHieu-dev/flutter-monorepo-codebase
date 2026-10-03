/// Which theme mode an app opens in until the user picks one.
enum ThemeModeSetting {
  /// Follows the OS light / dark setting. The template default.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// A colour of the app palette (`ThemeSystemExtension` in `core_base_ui`) an
/// app may replace — the tokens `context.colors` reads.
///
/// Not listed, so not overridable: `shadow` and `scrim`. `AppShadows` is
/// context-free and reads one shadow colour for both palettes, and a scrim is
/// black with an alpha on purpose (a theme-inverting scrim would lighten the
/// screen behind a dialog in dark mode). The two gradients are derived, never
/// set: `primaryGradientColors` is `[primary, primaryContainer]` and
/// `liquidOnboardingColors` is `[info, primaryContainer, error]` — which is
/// what both template palettes already are.
enum PaletteToken {
  primary,
  primaryContainer,
  secondary,
  secondaryContainer,
  background,
  surface,
  surfaceVariant,
  textPrimary,
  textSecondary,
  textDisabled,
  textInverse,
  border,
  divider,
  success,
  error,
  warning,
  info,
}

/// How the app looks: the mode it opens in and its brand colours.
///
/// Defaults are the template's own: the system mode and the template palette.
/// A token an app does not list keeps the template's value, so rebranding is
/// `ThemeProfile(light: {PaletteToken.primary: 0xFF1D4ED8})` — one line, and
/// `context.colors.primary`, `Theme.of(context).colorScheme.primary` and the
/// gradients built from it all agree.
///
/// Colours are ARGB integers (`0xAARRGGBB`), because the kernel is pure Dart
/// and holds no `Color`.
final class ThemeProfile {
  const ThemeProfile({
    this.mode = ThemeModeSetting.system,
    this.light = const {},
    this.dark = const {},
  });

  /// The mode a first launch opens in. A mode the user picked earlier always
  /// wins. Default [ThemeModeSetting.system].
  final ThemeModeSetting mode;

  /// Replacements for the light palette, by token. Default: none.
  final Map<PaletteToken, int> light;

  /// Replacements for the dark palette, by token. Default: none.
  final Map<PaletteToken, int> dark;
}
