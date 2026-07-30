import 'package:flutter/material.dart';

import '../theme/theme_system_extensions.dart';

class AppGradients {
  AppGradients._();

  static LinearGradient primaryGradient(BuildContext context) {
    final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors.primaryGradientColors,
    );
  }

  /// Flowing blue, violet, and magenta gradient for onboarding
  static LinearGradient liquidOnboarding(BuildContext context) {
    final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors.liquidOnboardingColors,
    );
  }

  /// Flowing teal, cyan, and slate gradient for customer mode
  static LinearGradient liquidCustomer(BuildContext context) {
    final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors.liquidCustomerColors,
    );
  }

  /// Flowing violet, magenta, and deep midnight gradient for owner mode
  static LinearGradient liquidOwner(BuildContext context) {
    final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors.liquidOwnerColors,
    );
  }

  /// Flowing violet, neon blue, and deep orange for authentication
  static LinearGradient liquidAuth(BuildContext context) {
    final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors.liquidAuthColors,
    );
  }
}
