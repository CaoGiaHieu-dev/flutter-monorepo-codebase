import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';

import '../../utils/auth_constants.dart';

/// Local data source for the session token.
///
/// Owns its [StorageValue] — no shared storage object, so no other package can
/// reach the key. A lazy singleton (never `@injectable`) so the in-memory cache
/// stays hydrated for the app's lifetime: reads are synchronous, writes return
/// a future that completes once the value is on disk.
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  /// Hydrates the cache from disk at startup, so [getUserToken] is correct from
  /// the first read.
  @PostConstruct(preResolve: true)
  Future<void> initialize() => _token.readFromStorage();

  Future<void> saveUserToken(String token) => _token.save(token);

  String? getUserToken() => _token.value;

  Future<void> clearUserToken() => _token.remove();
}
