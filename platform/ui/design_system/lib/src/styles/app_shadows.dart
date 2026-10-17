import 'package:material_ui/material_ui.dart';

import '../theme/theme_system_extensions.dart';

/// Elevation shadows, coloured from the palette's `shadow` token.
///
/// Context-free getters, like before the token existed: both palettes use
/// the same shadow colour, so they read it from [ThemeSystemExtension.light].
/// Give `ThemeSystemExtension.dark.shadow` its own value and these would have
/// to take a `BuildContext` (`context.colors.shadow`) to follow the theme.
class AppShadows {
  AppShadows._();

  static Color get _color => ThemeSystemExtension.light.shadow;

  static List<BoxShadow> get sm => [
    BoxShadow(
      color: _color.withValues(alpha: 0.05),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get md => [
    BoxShadow(
      color: _color.withValues(alpha: 0.1),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get lg => [
    BoxShadow(
      color: _color.withValues(alpha: 0.15),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];
}
