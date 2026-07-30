import 'package:flutter/widgets.dart';

/// Interface for feature localization delegates.
/// Enables safe registration and retrieval via getIt.getAll<IFeatureLocalization>() in the root app.
abstract class IFeatureLocalization {
  LocalizationsDelegate get delegate;
}
