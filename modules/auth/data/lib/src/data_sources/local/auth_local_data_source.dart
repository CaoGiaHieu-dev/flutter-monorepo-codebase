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

  void saveUserToken(String? token) => _token.value = token;

  String? getUserToken() => _token.value;

  void saveUserData(UserModel? user) => _authUser.value = user?.toJson();

  UserModel? getUserData() {
    final userData = _authUser.value;
    return userData == null ? null : UserModel.fromJson(userData);
  }

  void clearAllAuthData() {
    _token.value = null;
    _authUser.value = null;
  }
}
