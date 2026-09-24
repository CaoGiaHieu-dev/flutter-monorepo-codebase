import 'package:material_ui/material_ui.dart';

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
}
