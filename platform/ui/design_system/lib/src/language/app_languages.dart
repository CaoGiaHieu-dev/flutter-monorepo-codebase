import 'package:material_ui/material_ui.dart';

import '../gen/language/app_localizations.dart';

/// The languages the app ships, and the one it falls back to — the single
/// source every locale decision reads.
///
/// [supported] is generated from the ARB files in `assets/language/`, so
/// adding `ja.arb` adds Japanese here; [nameOf] then needs its display name.
/// `LanguageProvider` (the app's locale), `AppMaterialWrapper`'s
/// `localeResolutionCallback` (a device locale on first launch) and the
/// network adapter's `language` header all resolve through [resolve].
///
/// `core_network` cannot depend on this package (infra never depends on ui);
/// its own `NetworkConstants.DEFAULT_LANGUAGE_CODE`, used only by a client
/// built without an app `NetworkConfig`, must name the same language as
/// [fallback].
abstract final class AppLanguages {
  /// Every locale the app has translations for.
  static List<Locale> get supported => AppLocalizations.supportedLocales;

  /// Used when a requested locale is not [supported].
  static const Locale fallback = Locale('en');

  /// The supported locale with [locale]'s language code — a device's
  /// `vi_VN` resolves to `vi` — or [fallback].
  static Locale resolve(Locale? locale) {
    for (final candidate in supported) {
      if (candidate.languageCode == locale?.languageCode) return candidate;
    }
    return fallback;
  }

  /// [locale]'s display name in the current language, or its language tag
  /// when no name is translated for it.
  static String nameOf(Locale locale, AppLocalizations l10n) {
    return switch (locale.languageCode) {
      'en' => l10n.languageEn,
      'vi' => l10n.languageVi,
      _ => locale.toLanguageTag(),
    };
  }
}
