import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart' show LocaleProfile;

import '../gen/language/app_localizations.dart';

/// The languages one app offers, and the one it falls back to — the single
/// source every locale decision of that app reads.
///
/// It is the app's [LocaleProfile] meeting what the template ships: the ARB
/// files in `assets/language/`, listed by the generated
/// `AppLocalizations.supportedLocales`. [supported] is the profile's languages
/// that are shipped, in the profile's order (every shipped language, in the
/// generated order, when the profile names none), so adding `ja.arb` adds
/// Japanese for an app that offers everything, and an app that offers `vi`
/// alone never lists anything else.
///
/// `LanguageProvider` owns the instance and hands it on: it resolves the
/// app's locale, `AppMaterialWrapper` takes `supportedLocales` and its
/// `localeResolutionCallback` from it, the settings picker lists
/// [supported], and the network adapter's `language` header resolves through
/// the same profile. A language that is not [supported] never reaches
/// `MaterialApp`, which would otherwise receive a locale it has no
/// translations for.
///
/// A profile that cannot be honoured is refused when it is built, at boot —
/// not on the first screen that reads it: no shipped language is left, or the
/// [fallback] is not among the supported ones.
final class LanguageSet {
  /// The set for [profile]; [shipped] defaults to every language the template
  /// ships (a test passes its own).
  factory LanguageSet([
    LocaleProfile profile = const LocaleProfile(),
    Iterable<Locale>? shipped,
  ]) {
    final available = [...(shipped ?? AppLocalizations.supportedLocales)];
    final codes = profile.supported;
    final supported = <Locale>[];
    if (codes == null) {
      supported.addAll(available);
    } else {
      for (final code in codes) {
        for (final locale in available) {
          if (locale.languageCode == code && !supported.contains(locale)) {
            supported.add(locale);
          }
        }
      }
    }

    final shippedCodes = available.map((l) => l.languageCode).join(', ');
    if (supported.isEmpty) {
      throw ArgumentError.value(
        codes,
        'LocaleProfile.supported',
        'names no language the app ships ($shippedCodes). Name at least one, '
            'or leave it null for all of them.',
      );
    }
    final fallback = supported
        .where((l) => l.languageCode == profile.fallback)
        .firstOrNull;
    if (fallback == null) {
      throw ArgumentError.value(
        profile.fallback,
        'LocaleProfile.fallback',
        'is not a supported language '
            '(${supported.map((l) => l.languageCode).join(', ')}). The '
            'fallback must be one of the languages the app offers.',
      );
    }
    return LanguageSet._(List.unmodifiable(supported), fallback);
  }

  const LanguageSet._(this.supported, this.fallback);

  /// Every locale the app offers and has translations for.
  final List<Locale> supported;

  /// Used when a requested locale is not [supported].
  final Locale fallback;

  /// The supported locale with [locale]'s language code — a device's
  /// `vi_VN` resolves to `vi` — or [fallback].
  Locale resolve(Locale? locale) {
    for (final candidate in supported) {
      if (candidate.languageCode == locale?.languageCode) return candidate;
    }
    return fallback;
  }
}
