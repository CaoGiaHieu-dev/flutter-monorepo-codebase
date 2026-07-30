import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/cupertino.dart';
import 'package:injectable/injectable.dart';

import '../../core_base_ui.dart';

@lazySingleton
class LanguageProvider extends ChangeNotifier {
  final ILanguageStorage _storage;

  LanguageProvider(this._storage);

  Locale _locale = AppConfig.defaultLanguage;

  Locale get locale => _locale;

  /// Sets the default language for the application.
  @PostConstruct(preResolve: true)
  Future<void> setDefaultLanguage() async {
    final storageLanguageCode = _storage.getLanguage();
    if (AppLocalizations.supportedLocales.contains(storageLanguageCode)) {
      _locale = storageLanguageCode;
      return;
    }
    if (AppLocalizations.supportedLocales.contains(AppConfig.defaultLanguage)) {
      _locale = AppConfig.defaultLanguage;
      return;
    }
    // Device locale isn't one of the app's shipped languages — fall back to
    // the first supported locale instead of passing an unsupported Locale
    // straight to MaterialApp (which bypasses localeResolutionCallback).
    _locale = AppLocalizations.supportedLocales.first;
  }

  void setLocale(Locale locale) {
    _locale = locale;
    _storage.saveLanguage(locale);
    notifyListeners();
  }
}
