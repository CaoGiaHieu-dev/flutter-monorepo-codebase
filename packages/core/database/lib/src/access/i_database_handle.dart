import 'package:drift/drift.dart';

/// Builds a package's own [DatabaseAccessor] from its database.
typedef DatabaseAccessorFactory<
  TDb extends GeneratedDatabase,
  T extends DatabaseAccessor<TDb>
> = T Function(TDb database);

/// Narrow entry point to a package's database connection.
///
/// Holding the [GeneratedDatabase] directly hands a data source every DAO and
/// every table on it. Depending on `IDatabaseHandle` instead means a class
/// receives only the accessor it asks for, and the boundary is visible in the
/// constructor rather than implied.
///
/// ```dart
/// @LazySingleton(as: IProfileLocalDataSource)
/// class ProfileLocalDataSource implements IProfileLocalDataSource {
///   ProfileLocalDataSource(IDatabaseHandle<ProfileDatabase> handle)
///     : _dao = handle.accessor(ProfileDao.new);
///
///   final ProfileDao _dao;
/// }
/// ```
///
/// ## What this does and does not guarantee
///
/// This is **API-surface narrowing, not enforced isolation**: drift's
/// `DatabaseAccessor` requires the database, so the factory callback still
/// receives it and a determined caller could capture it. The value is that
/// reaching past the boundary takes a deliberate act that shows up in review,
/// not an ordinary constructor parameter.
///
/// Real isolation between packages comes from the layer above: each package
/// that owns data declares its **own** database (see `DriftDatabaseOpener`), so
/// there is no shared object through which one package could reach another's
/// tables in the first place.
abstract class IDatabaseHandle<TDb extends GeneratedDatabase> {
  /// Returns the accessor built by [factory], bound to this database.
  ///
  /// Accessors are cheap value objects over the connection, so calling this
  /// per data source is fine; no pooling is needed.
  T accessor<T extends DatabaseAccessor<TDb>>(
    DatabaseAccessorFactory<TDb, T> factory,
  );

  /// Runs [action] inside a single transaction on this database.
  ///
  /// Exposed here so a package can make its own multi-statement writes atomic
  /// without being handed the database to call `transaction` on.
  Future<T> transaction<T>(Future<T> Function() action);
}
