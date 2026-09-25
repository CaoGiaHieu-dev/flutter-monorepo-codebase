import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';

import '../../models/user_model.dart';
import '../../utils/auth_storage_keys.dart';

/// Local data source for authentication-related data.
///
/// Declares and owns its own [StorageValue] instances via [StorageManager] —
/// no shared cross-domain storage object, so no other package can reach
/// these keys. Registered as a singleton (never `@injectable`) so the
/// in-memory cache stays hydrated for the app's lifetime.
///
/// Reads are synchronous (from the hydrated cache); every write returns a
/// future that completes once the value is on disk.
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  /// The user of the last successful sign-in or renewal — what an offline
  /// start restores the session from.
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

  Future<void> saveUserToken(String? token) =>
      token == null ? _token.remove() : _token.save(token);

  String? getUserToken() => _token.value;

  /// Stored without its token: `AuthStorageKeys.TOKEN` is the one place the credential
  /// lives.
  Future<void> saveUserData(UserModel? user) => user == null
      ? _authUser.remove()
      : _authUser.save(user.copyWith(token: null).toJson());

  UserModel? getUserData() {
    final userData = _authUser.value;
    return userData == null ? null : UserModel.fromJson(userData);
  }

  Future<void> clearAllAuthData() async {
    await Future.wait([_token.remove(), _authUser.remove()]);
  }
}
