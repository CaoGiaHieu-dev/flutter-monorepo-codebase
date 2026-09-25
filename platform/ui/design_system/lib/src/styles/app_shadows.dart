import 'package:material_ui/material_ui.dart';

import '../extensions/context_extension.dart';

/// Elevation shadows, coloured from the palette's `shadow` token.
///
/// Like the other token classes each accessor takes a [BuildContext], so a
/// palette that wants a different shadow in dark mode only changes
/// `ThemeSystemExtension.dark.shadow`.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> sm(BuildContext context) => [
    BoxShadow(
      color: context.colors.shadow.withValues(alpha: 0.05),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> md(BuildContext context) => [
    BoxShadow(
      color: context.colors.shadow.withValues(alpha: 0.1),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> lg(BuildContext context) => [
    BoxShadow(
      color: context.colors.shadow.withValues(alpha: 0.15),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];
}
