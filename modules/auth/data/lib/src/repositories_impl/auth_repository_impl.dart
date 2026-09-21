import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:data_core/data_core.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/auth_local_data_source.dart';
import '../models/user/user_model.dart';

/// Firebase-backed implementation of [IAuthRepository].
///
/// Every SDK arrives through the constructor rather than via `.instance`, so
/// each one is a visible dependency the container owns and a test can replace
/// with a fake. See `RegisterModule` in `lib/di/register_module.dart` for the
/// bindings.
@Injectable(as: IAuthRepository)
class AuthRepositoryImpl extends IBaseRepository implements IAuthRepository {
  AuthRepositoryImpl(
    this._googleSignIn,
    this._localDataSource,
    this._firebaseAuth,
    this._firestore,
    this._facebookAuth,
  );

  final GoogleSignIn _googleSignIn;
  final AuthLocalDataSource _localDataSource;
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final FacebookAuth _facebookAuth;

  /// Persists the session through its owner, [AuthLocalDataSource].
  ///
  /// Every successful authentication funnels through here so the Firebase ID
  /// token reaches local storage. Without it `NetworkConfig.getToken()` stays
  /// null, no `Authorization` header is ever sent, and the 401 refresh flow in
  /// `core_network` can never trigger.
  ///
  /// [forceRefreshToken] bypasses the Firebase SDK's token cache — used by
  /// [refreshToken], where the point is to obtain a *new* token.
  Future<UserModel> _persistSession(
    User firebaseUser,
    UserModel model, {
    bool forceRefreshToken = false,
  }) async {
    final token = await firebaseUser.getIdToken(forceRefreshToken);
    _localDataSource.saveUserToken(token);
    _localDataSource.saveUserData(model);
    return model;
  }

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    return execute<UserModel, UserEntity>(() async {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: params.email,
        password: params.password,
      );
      final user = credential.user!;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final UserModel model;
      if (doc.exists && doc.data() != null) {
        model = UserModel.fromJson(doc.data()!);
      } else {
        model = UserModel(
          id: user.uid,
          email: user.email ?? params.email,
          name: user.displayName ?? 'User',
          role: UserRole.none,
        );
        await _firestore.collection('users').doc(user.uid).set(model.toJson());
      }
      return _persistSession(user, model);
    }, mapper: (model) => model.toEntity());
  }

  @override
  Future<Result<UserEntity>> registerWithEmail(
    String email,
    String password,
    String name,
  ) async {
    return execute<UserModel, UserEntity>(() async {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user!;
      await user.updateDisplayName(name);

      final model = UserModel(
        id: user.uid,
        email: email,
        name: name,
        role: UserRole.none,
      );
      await _firestore.collection('users').doc(user.uid).set(model.toJson());
      return _persistSession(user, model);
    }, mapper: (model) => model.toEntity());
  }

  @override
  Future<Result<UserEntity>> loginWithGoogle() async {
    return execute<UserModel, UserEntity>(() async {
      final googleUser = await _googleSignIn.authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final clientAuth = await googleUser.authorizationClient.authorizeScopes([
        'email',
        'profile',
      ]);
      final idToken = googleAuth.idToken;
      final accessToken = clientAuth.accessToken;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );
      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );
      final user = userCredential.user!;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      final UserModel model;
      if (doc.exists && doc.data() != null) {
        model = UserModel.fromJson(doc.data()!);
      } else {
        model = UserModel(
          id: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? 'Google User',
          role: UserRole.none,
        );
        await _firestore.collection('users').doc(user.uid).set(model.toJson());
      }
      return _persistSession(user, model);
    }, mapper: (model) => model.toEntity());
  }

  @override
  Future<Result<UserEntity>> loginWithFacebook() async {
    return execute<UserModel, UserEntity>(() async {
      final LoginResult result = await _facebookAuth.login();
      if (result.status != LoginStatus.success) {
        throw Exception('Facebook Login failed: ${result.message}');
      }
      final AuthCredential credential = FacebookAuthProvider.credential(
        result.accessToken!.tokenString,
      );
      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );
      final user = userCredential.user!;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      final UserModel model;
      if (doc.exists && doc.data() != null) {
        model = UserModel.fromJson(doc.data()!);
      } else {
        model = UserModel(
          id: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? 'Facebook User',
          role: UserRole.none,
        );
        await _firestore.collection('users').doc(user.uid).set(model.toJson());
      }
      return _persistSession(user, model);
    }, mapper: (model) => model.toEntity());
  }

  @override
  Future<Result<UserEntity>> getCurrentUser() async {
    return execute<UserModel, UserEntity>(() async {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) {
        throw Exception('No user is currently authenticated');
      }
      final doc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (!doc.exists || doc.data() == null) {
        throw Exception('User profile not found in database');
      }
      return _persistSession(currentUser, UserModel.fromJson(doc.data()!));
    }, mapper: (model) => model.toEntity());
  }

  @override
  Future<Result<UserEntity>> updateUserProfile(UserEntity user) async {
    return execute<UserModel, UserEntity>(() async {
      final model = UserModel.fromEntity(user);
      await _firestore
          .collection('users')
          .doc(user.id)
          .set(model.toJson(), SetOptions(merge: true));
      // Keep the locally cached profile in step with the remote one.
      _localDataSource.saveUserData(model);
      return model;
    }, mapper: (model) => model.toEntity());
  }

  @override
  Result<void> logout() {
    return executeSync<void, void>(() {
      _firebaseAuth.signOut();
      _googleSignIn.signOut();
      _facebookAuth.logOut();
      // Drop the persisted token/profile as well — signing out of the SDKs
      // alone would leave a stale token that `NetworkConfig.getToken()` keeps
      // attaching to outgoing requests.
      _localDataSource.clearAllAuthData();
    });
  }

  @override
  Future<Result<UserEntity>> refreshToken() async {
    return execute<UserModel, UserEntity>(() async {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) {
        throw Exception('No user is currently authenticated');
      }
      final doc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (!doc.exists || doc.data() == null) {
        throw Exception('User profile not found in database');
      }
      // forceRefreshToken: the caller is here precisely because the cached
      // token was rejected, so reusing it would loop.
      return _persistSession(
        currentUser,
        UserModel.fromJson(doc.data()!),
        forceRefreshToken: true,
      );
    }, mapper: (model) => model.toEntity());
  }
}
