import 'package:drift/drift.dart';

import 'i_database_handle.dart';

/// Default [IDatabaseHandle], wrapping one database instance.
///
/// Generic over the database type so `core_database` never names a concrete
/// database class — that is the whole point of keeping schema out of this
/// package. The owning package registers it for its own database:
///
/// ```dart
/// @module
/// abstract class CacheDatabaseModule {
///   @lazySingleton
///   IDatabaseHandle<CacheDatabase> handle(CacheDatabase db) =>
///       DatabaseHandle<CacheDatabase>(db);
/// }
/// ```
class DatabaseHandle<TDb extends GeneratedDatabase>
    implements IDatabaseHandle<TDb> {
  const DatabaseHandle(this._database);

  final TDb _database;

  @override
  T accessor<T extends DatabaseAccessor<TDb>>(
    DatabaseAccessorFactory<TDb, T> factory,
  ) {
    return factory(_database);
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) {
    return _database.transaction(action);
  }
}
