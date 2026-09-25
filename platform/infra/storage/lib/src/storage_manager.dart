import 'package:injectable/injectable.dart';

import 'contracts/storage_interface.dart';
import 'contracts/storage_type.dart';

/// Central coordinator for all registered storage backends.
///
/// Initializes every backend (secure first, see [initialize]) and acts as a
/// factory provider based on [StorageType].
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

  /// Initialize every registered backend — the secure one first.
  ///
  /// On a first launch the secure backend wipes its keystore namespace, and
  /// the pref backend keeps its own master key in that same namespace. Run in
  /// parallel, the wipe could land after pref had written its new key: the
  /// session would still work from RAM, but on the next launch the key is
  /// gone, a new one is generated, and every stored preference fails to
  /// decrypt and is deleted — onboarding, theme and language reset.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await _backends[StorageType.secure]?.init();
    await Future.wait(
      _backends.entries
          .where((entry) => entry.key != StorageType.secure)
          .map((entry) => entry.value.init()),
    );
  }
}
