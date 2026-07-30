import 'package:flutter/material.dart';

abstract class ThemeSystemInterface<T extends ThemeExtension<T>>
    extends ThemeExtension<T> {
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

  // Additional mapped variables for chat, etc.
  final Color chatMe;

  // Theme Gradients
  final List<Color> primaryGradientColors;
  final List<Color> liquidOnboardingColors;
  final List<Color> liquidCustomerColors;
  final List<Color> liquidOwnerColors;
  final List<Color> liquidAuthColors;

  ThemeSystemInterface({
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
    required this.chatMe,
    required this.primaryGradientColors,
    required this.liquidOnboardingColors,
    required this.liquidCustomerColors,
    required this.liquidOwnerColors,
    required this.liquidAuthColors,
  });

  @override
  ThemeExtension<T> copyWith() {
    throw UnimplementedError();
  }

  @override
  ThemeExtension<T> lerp(covariant ThemeExtension<T>? other, double t) {
    throw UnimplementedError();
  }
}
