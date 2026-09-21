import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';

/// Binds the third-party auth SDKs so repositories receive them through the
/// constructor instead of reaching for `.instance` themselves.
///
/// Touching the singletons directly inside a repository hides a dependency
/// from the container and makes the class untestable — there is no seam to
/// pass a fake through. Registering them here keeps the wiring visible and
/// lets a test override any one of them.
@module
abstract class RegisterModule {
  @preResolve
  Future<GoogleSignIn> get googleSignIn async {
    final instance = GoogleSignIn.instance;
    await GoogleSignIn.instance.initialize();
    return instance;
  }

  /// Firebase Authentication, already initialised by `Firebase.initializeApp`
  /// during app bootstrap.
  @lazySingleton
  FirebaseAuth get firebaseAuth => FirebaseAuth.instance;

  /// Cloud Firestore client used for the user profile documents.
  @lazySingleton
  FirebaseFirestore get firestore => FirebaseFirestore.instance;

  /// Facebook Login SDK.
  @lazySingleton
  FacebookAuth get facebookAuth => FacebookAuth.instance;
}
