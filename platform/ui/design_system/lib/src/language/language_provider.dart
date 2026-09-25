import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:injectable/injectable.dart';

import 'app_languages.dart';

/// The app's current locale, persisted through [ILanguageStorage].
///
/// Always one of [AppLanguages.supported]: a stored or device locale is
/// resolved through [AppLanguages.resolve] before it reaches `MaterialApp`,
/// which would otherwise receive a locale it has no translations for.
@lazySingleton
class LanguageProvider extends ChangeNotifier with DisposeGuard {
  final ILanguageStorage _storage;

  LanguageProvider(this._storage);

  Locale _locale = AppLanguages.fallback;

  Locale get locale => _locale;

  /// Loads the stored locale — on first launch the device's — resolved to a
  /// supported one.
  @PostConstruct(preResolve: true)
  Future<void> setDefaultLanguage() async {
    _locale = AppLanguages.resolve(_storage.getLanguage());
  }

  /// Switches the app locale and persists the choice.
  ///
  /// Re-selecting the current locale is a no-op: notifying here would rebuild
  /// the whole app for nothing. Mirrors the guard in `ThemeProvider.themeMode`.
  void setLocale(Locale locale) {
    final resolved = AppLanguages.resolve(locale);
    if (_locale == resolved) return;
    _locale = resolved;
    _storage.saveLanguage(resolved);
    notifyListeners();
  }
}
