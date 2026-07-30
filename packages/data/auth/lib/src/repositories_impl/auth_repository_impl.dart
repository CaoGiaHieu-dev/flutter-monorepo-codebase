import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:data_core/data_core.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';

import '../models/user/user_model.dart';

@Injectable(as: IAuthRepository)
class AuthRepositoryImpl extends IBaseRepository implements IAuthRepository {
  AuthRepositoryImpl(this._googleSignIn);

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FacebookAuth _facebookAuth = FacebookAuth.instance;
  final GoogleSignIn _googleSignIn;

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    return execute<UserModel, UserEntity>(() async {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: params.email,
        password: params.password,
      );
      final user = credential.user!;
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromJson(doc.data()!);
      } else {
        final newUser = UserModel(
          id: user.uid,
          email: user.email ?? params.email,
          name: user.displayName ?? 'User',
          role: UserRole.none,
        );
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(newUser.toJson());
        return newUser;
      }
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

      final newUser = UserModel(
        id: user.uid,
        email: email,
        name: name,
        role: UserRole.none,
      );
      await _firestore.collection('users').doc(user.uid).set(newUser.toJson());
      return newUser;
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
      if (doc.exists && doc.data() != null) {
        return UserModel.fromJson(doc.data()!);
      } else {
        final newUser = UserModel(
          id: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? 'Google User',
          role: UserRole.none,
        );
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(newUser.toJson());
        return newUser;
      }
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
      if (doc.exists && doc.data() != null) {
        return UserModel.fromJson(doc.data()!);
      } else {
        final newUser = UserModel(
          id: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? 'Facebook User',
          role: UserRole.none,
        );
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(newUser.toJson());
        return newUser;
      }
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
      if (doc.exists && doc.data() != null) {
        return UserModel.fromJson(doc.data()!);
      } else {
        throw Exception('User profile not found in database');
      }
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
      return model;
    }, mapper: (model) => model.toEntity());
  }

  @override
  Result<void> logout() {
    return executeSync<void, void>(() {
      _firebaseAuth.signOut();
      _googleSignIn.signOut();
      _facebookAuth.logOut();
    });
  }

  @override
  Future<Result<UserEntity>> refreshToken() async {
    return getCurrentUser();
  }
}
