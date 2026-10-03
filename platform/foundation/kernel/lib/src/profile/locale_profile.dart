/// Which languages the app speaks, which one it falls back to, and which one
/// it opens in.
///
/// Every default is what the template did before an app could say anything:
/// every language the template ships translations for, `en` as the fallback,
/// and the device's language on a first launch.
///
/// Languages are plain language codes (`'en'`, `'vi'`) — the kernel is pure
/// Dart and holds no `Locale`. The shell turns them into a `LanguageSet`
/// (`core_base_ui`), which is the one place a locale decision is made: the
/// language the app renders in, the picker in settings, the `language` header
/// every request carries.
final class LocaleProfile {
  const LocaleProfile({this.supported, this.fallback = 'en', this.initial})
    : assert(fallback != '', 'The fallback language needs a language code.'),
      assert(initial != '', 'The initial language needs a language code.');

  /// The languages this app offers, as language codes — a subset of what the
  /// template ships (`assets/language/*.arb` in `core_base_ui`).
  ///
  /// The settings picker lists them in this order. Null (the default) is every
  /// language shipped, so adding an ARB file adds a language. A code the template does not ship is ignored; the list must
  /// leave at least one shipped language and must contain [fallback], or
  /// `LanguageSet` refuses it at boot.
  final List<String>? supported;

  /// Used when a stored, device or requested language is not [supported].
  /// Default `en`. It is also what a `NetworkConfig`-less client sends in the
  /// `language` header, so there is one fallback, not two.
  final String fallback;

  /// The language a first launch opens in, before the user picks one. Null
  /// (the default) is the device's language, resolved to a supported one.
  /// A language the user chose earlier always wins.
  final String? initial;
}
