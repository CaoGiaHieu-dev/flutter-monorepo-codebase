import 'package:flutter/material.dart';

/// Interface for language storage, decoupling [LanguageProvider] from persistence.
abstract class ILanguageStorage {
  /// Gets the current [Locale] from storage.
  Locale getLanguage();

  /// Saves the given [Locale] to storage.
  void saveLanguage(Locale mode);
}
