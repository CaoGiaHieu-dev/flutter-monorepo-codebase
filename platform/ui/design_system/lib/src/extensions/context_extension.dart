import 'package:material_ui/material_ui.dart';

import '../gen/language/app_localizations.dart';
import '../theme/theme_system_extensions.dart';

/// Shorthands for the design system's per-context values.
///
/// Colours: prefer [colors] (the palette). [colorScheme] carries the same
/// tokens in Material's slots — `ThemeProvider` builds it from the palette —
/// for code that talks to Material components in their own terms. Text
/// styles come from `AppTextStyles`, sizes from `core_responsive`.
extension ContextExtension on BuildContext {
  /// The Material colour scheme, built from the palette.
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// `core_base_ui`'s global translations.
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  /// The app's palette (`context.colors.textPrimary`).
  ThemeSystemExtension get colors =>
      Theme.of(this).extension<ThemeSystemExtension>()!;
}
