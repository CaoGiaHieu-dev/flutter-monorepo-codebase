import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';

import '../../../data_auth.dart';

/// Local data source for authentication-related data.
///
/// All storage access goes through the DI-injected [StorageValuePresets]
/// instance — no static calls.
@injectable
class AuthLocalDataSource {
  final StorageValuePresets _storagePresets;

  /// Constructor – receives [StorageValuePresets] through DI.
  AuthLocalDataSource(this._storagePresets);

  /// Save user token securely
  void saveUserToken(String? token) {
    _storagePresets.token.value = token;
  }

  /// Get user token
  String? getUserToken() {
    return _storagePresets.token.value;
  }

  /// Clear user token
  void clearUserToken() {
    _storagePresets.token.value = null;
  }

  /// Save user data
  void saveUserData(UserModel? user) {
    _storagePresets.authUser.value = user?.toJson();
  }

  /// Get user data
  UserModel? getUserData() {
    final userData = _storagePresets.authUser.value;
    if (userData != null) {
      return UserModel.fromJson(userData);
    }
    return null;
  }

  /// Clear user data
  void clearUserData() {
    _storagePresets.authUser.value = null;
  }

  /// Clear all auth data
  void clearAllAuthData() {
    clearUserToken();
    clearUserData();
  }
}
