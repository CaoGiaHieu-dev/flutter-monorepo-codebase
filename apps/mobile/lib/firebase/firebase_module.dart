import 'package:firebase_core/firebase_core.dart';
import 'package:injectable/injectable.dart';

import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as stg;

/// DI module providing this app's per-flavor [FirebaseOptions].
///
/// It lives in the app, not in `platform/`, because Firebase options identify
/// *one* app: they carry its bundle ID / package name. When this file sat in
/// `core_common` every app in the workspace inherited the mobile app's
/// options, so a second app would have booted against a Firebase app
/// registered for someone else's bundle ID.
///
/// The three imported files are generated per project and git-ignored; create
/// them with `dart tools/firebase/firebase_config.dart --app mobile`. An app
/// that does not use Firebase simply has no such module: `core_notifications`
/// resolves [FirebaseOptions] with `getItOrNull`.
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
