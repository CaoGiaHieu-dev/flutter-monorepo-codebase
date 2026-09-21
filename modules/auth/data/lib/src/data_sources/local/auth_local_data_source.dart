import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';

import '../../../data_auth.dart';

/// Local data source for authentication-related data.
///
/// Declares and owns its own [StorageValue] instances via [StorageManager] —
/// no shared cross-domain storage object, so no other package can reach
/// these keys. Registered as a singleton (never `@injectable`) so the
/// in-memory cache stays hydrated for the app's lifetime.
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  late final _authUser = StorageValue<Map<String, dynamic>>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.AUTH_USER,
  );

  /// Hydrates the in-memory cache from disk at startup so synchronous
  /// getters below return correct values immediately.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }

  /// Save user token securely
  void saveUserToken(String? token) {
    _token.value = token;
  }

  /// Get user token
  String? getUserToken() {
    return _token.value;
  }

  /// Clear user token
  void clearUserToken() {
    _token.value = null;
  }

  /// Save user data
  void saveUserData(UserModel? user) {
    _authUser.value = user?.toJson();
  }

  /// Get user data
  UserModel? getUserData() {
    final userData = _authUser.value;
    if (userData != null) {
      return UserModel.fromJson(userData);
    }
    return null;
  }

  /// Clear user data
  void clearUserData() {
    _authUser.value = null;
  }

  /// Clear all auth data
  void clearAllAuthData() {
    clearUserToken();
    clearUserData();
  }
}
