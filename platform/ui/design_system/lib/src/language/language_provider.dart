import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:injectable/injectable.dart';

import 'language_set.dart';

/// The app's current locale, persisted through [ILanguageStorage].
///
/// Always one of [languageSet]'s supported locales: a stored or device locale
/// is resolved through the set before it reaches `MaterialApp`, which would
/// otherwise receive a locale it has no translations for.
///
/// The set is built from the app's [LocaleProfile] — registered by
/// `runShellApp` before the graph — so this provider is where a locale
/// decision of the app starts; a hand-built provider takes the template's.
@lazySingleton
class LanguageProvider extends ChangeNotifier with DisposeGuard {
  final ILanguageStorage _storage;

  LanguageProvider(
    ILanguageStorage storage, [
    LocaleProfile profile = const LocaleProfile(),
  ]) : this._(storage, LanguageSet(profile));

  LanguageProvider._(this._storage, this.languageSet)
    : _locale = languageSet.fallback;

  /// The languages this app offers and its fallback: what the settings picker
  /// lists, what `MaterialApp` supports, how a requested locale resolves.
  final LanguageSet languageSet;

  Locale _locale;

  Locale get locale => _locale;

  /// Loads the stored locale — on first launch the app's initial language, else
  /// the device's — resolved to a supported one.
  @PostConstruct(preResolve: true)
  Future<void> setDefaultLanguage() async {
    _locale = languageSet.resolve(_storage.getLanguage());
  }

  /// Switches the app locale and persists the choice.
  ///
  /// Re-selecting the current locale is a no-op: notifying here would rebuild
  /// the whole app for nothing. Mirrors the guard in `ThemeProvider.themeMode`.
  void setLocale(Locale locale) {
    final resolved = languageSet.resolve(locale);
    if (_locale == resolved) return;
    _locale = resolved;
    _storage.saveLanguage(resolved);
    notifyListeners();
  }
}
