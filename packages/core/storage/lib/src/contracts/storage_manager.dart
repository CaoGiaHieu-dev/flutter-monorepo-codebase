import 'package:injectable/injectable.dart';

import 'storage_interface.dart';
import 'storage_type.dart';

/// Central coordinator for all registered storage backends.
///
/// Handles asynchronous initialization of all backends in parallel
/// and acts as a factory provider based on [StorageType].
@singleton
class StorageManager {
  final Map<StorageType, StorageInterface> _backends;

  /// Creates a [StorageManager] with registered implementations.
  StorageManager(
    @Named('Pref') StorageInterface pref,
    @Named('Secure') StorageInterface secure,
  ) : _backends = {StorageType.pref: pref, StorageType.secure: secure};

  /// Retrieve the [StorageInterface] backend for the given [type].
  StorageInterface getStorage(StorageType type) {
    final backend = _backends[type];
    if (backend == null) {
      throw ArgumentError('Storage backend for type $type is not registered.');
    }
    return backend;
  }

  /// Initialize all registered storage backends in parallel.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait(_backends.values.map((backend) => backend.init()));
  }
}
