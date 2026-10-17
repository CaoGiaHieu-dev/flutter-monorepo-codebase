import 'package:core_common/core_common.dart';
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
/// that does not use Firebase has no such module and composes no
/// `core_notifications`, whose `PushNotificationService` injects these
/// options. (Its background-message handler runs in an isolate without DI,
/// so it initializes Firebase from the native config files instead.)
///
/// Each method takes the running platform's [PlatformFacts] and reads the
/// generated options only where push is on: `currentPlatform` throws on a
/// platform the Firebase project has no app for (web, Linux), and where push
/// is off nothing hands the options to Firebase.
@module
abstract class FirebaseModule {
  /// Provides development Firebase options.
  @lazySingleton
  @Environment('dev')
  FirebaseOptions devFirebaseOptions(PlatformFacts platform) =>
      platform.push ? dev.DefaultFirebaseOptions.currentPlatform : _pushOff;

  /// Provides staging Firebase options.
  @lazySingleton
  @Environment('staging')
  FirebaseOptions stagingFirebaseOptions(PlatformFacts platform) =>
      platform.push ? stg.DefaultFirebaseOptions.currentPlatform : _pushOff;

  /// Provides production Firebase options.
  @lazySingleton
  @Environment('prod')
  FirebaseOptions prodFirebaseOptions(PlatformFacts platform) =>
      platform.push ? prod.DefaultFirebaseOptions.currentPlatform : _pushOff;
}

/// Never handed to Firebase: `PushNotificationService` initialises nothing
/// where push is off, and `currentPlatform` throws on a platform the
/// Firebase project has no app for (web, Linux).
const FirebaseOptions _pushOff = FirebaseOptions(
  apiKey: 'push-off',
  appId: 'push-off',
  messagingSenderId: 'push-off',
  projectId: 'push-off',
);
