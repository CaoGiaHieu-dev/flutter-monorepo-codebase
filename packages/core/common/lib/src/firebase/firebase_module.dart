import 'package:firebase_core/firebase_core.dart';
import 'package:injectable/injectable.dart';

import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as stg;

/// DI Module providing env-specific [FirebaseOptions].
@module
abstract class FirebaseModule {
  /// Provides development Firebase options.
  @lazySingleton
  @Environment('dev')
  FirebaseOptions get devFirebaseOptions =>
      dev.DefaultFirebaseOptions.currentPlatform;

  /// Provides staging Firebase options.
  @lazySingleton
  @Environment('staging')
  FirebaseOptions get stagingFirebaseOptions =>
      stg.DefaultFirebaseOptions.currentPlatform;

  /// Provides production Firebase options.
  @lazySingleton
  @Environment('prod')
  FirebaseOptions get prodFirebaseOptions =>
      prod.DefaultFirebaseOptions.currentPlatform;
}
