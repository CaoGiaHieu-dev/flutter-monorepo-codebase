import 'package:material_ui/material_ui.dart';

import 'theme_system_interface.dart';

/// Custom theme extension for additional theme properties
class ThemeSystemExtension extends ThemeSystemInterface<ThemeSystemExtension> {
  ThemeSystemExtension({
    required super.primary,
    required super.primaryContainer,
    required super.secondary,
    required super.secondaryContainer,
    required super.background,
    required super.surface,
    required super.surfaceVariant,
    required super.textPrimary,
    required super.textSecondary,
    required super.textDisabled,
    required super.textInverse,
    required super.border,
    required super.divider,
    required super.success,
    required super.error,
    required super.warning,
    required super.info,
    required super.primaryGradientColors,
    required super.liquidOnboardingColors,
  });

  @override
  ThemeSystemExtension lerp(covariant ThemeSystemExtension other, double t) {
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
    final result = <Color>[];
    for (var i = 0; i < a.length; i++) {
      if (i < b.length) {
        result.add(Color.lerp(a[i], b[i], t)!);
      } else {
        result.add(a[i]);
      }
    }
    return result;
  }

  /// Light theme extension
  static ThemeSystemExtension light = ThemeSystemExtension(
    primary: const Color(0xff0A7E8C),
    primaryContainer: const Color(0xff8B5CF6),
    secondary: const Color(0xff1E293B), // iOS slate secondary
    secondaryContainer: const Color(0xffF1F5F9), // iOS slate container
    background: const Color(0xffF8FAFC), // Light iOS layout background
    surface: const Color(0xffFFFFFF), // Frosted glass layout surface
    surfaceVariant: const Color(0xffF1F5F9),
    textPrimary: const Color(0xff0F172A),
    textSecondary: const Color(0xff64748B),
    textDisabled: const Color(0xff94A3B8),
    textInverse: const Color(0xffFFFFFF),
    border: const Color(0xffE2E8F0),
    divider: const Color(0xffF1F5F9),
    success: const Color(0xff10B981),
    error: const Color(0xffEF4444),
    warning: const Color(0xffF59E0B),
    info: const Color(0xff3B82F6),
    primaryGradientColors: const [
      Color(0xff0A7E8C), // primary
      Color(0xff8B5CF6), // primaryContainer
    ],
    liquidOnboardingColors: const [
      Color(0xff3B82F6), // blue
      Color(0xff8B5CF6), // violet/pink
      Color(0xffEF4444), // red
    ],
  );

  /// Dark theme extension
  static ThemeSystemExtension dark = ThemeSystemExtension(
    primary: const Color(0xff22D3EE),
    primaryContainer: const Color(0xffA78BFA),
    secondary: const Color(0xff94A3B8),
    secondaryContainer: const Color(0xff1E293B),
    background: const Color(0xff0B0F19), // Dark iOS midnight background
    surface: const Color(0xff151F32), // Glassmorphism dark card surface
    surfaceVariant: const Color(0xff1E293B),
    textPrimary: const Color(0xffF8FAFC),
    textSecondary: const Color(0xff94A3B8),
    textDisabled: const Color(0xff475569),
    textInverse: const Color(0xff0F172A),
    border: const Color(0xff1E293B),
    divider: const Color(0xff1E293B),
    success: const Color(0xff34D399),
    error: const Color(0xffF87171),
    warning: const Color(0xffFBBF24),
    info: const Color(0xff60A5FA),
    primaryGradientColors: const [
      Color(0xff22D3EE), // primary
      Color(0xffA78BFA), // primaryContainer
    ],
    liquidOnboardingColors: const [
      Color(0xff60A5FA), // info/blue
      Color(0xffA78BFA), // primaryContainer/violet
      Color(0xffF87171), // error/red
    ],
  );

  static ThemeSystemExtension withMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => light,
      ThemeMode.light => light,
      ThemeMode.dark => dark,
    };
  }
}
