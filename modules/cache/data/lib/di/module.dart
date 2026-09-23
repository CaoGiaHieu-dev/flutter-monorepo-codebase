import 'package:core_database/core_database.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import '../src/database/cache_database.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class DataCacheDiModule {
  /// Opens this package's [CacheDatabase] before the app graph is ready.
  ///
  /// Schema steps are collected here rather than inside the database so it
  /// stays free of service-locator calls and can be constructed directly in
  /// tests.
  ///
  /// `@preResolve` opens the database — and therefore runs migrations — while
  /// this module initialises. An [IDatabaseMigration] registered by a module
  /// that initialises *later* would be invisible at that moment, so a package
  /// contributing a step for this database must sit in an earlier DI group.
  ///
  /// Only an app that composes this module pays for opening the file.
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() =>
      CacheDatabase.open(migrations: _registeredMigrations());

  /// Narrow accessor handle for this package's data sources.
  ///
  /// Data sources depend on this rather than on [CacheDatabase] itself, so
  /// they receive only the DAO they ask for.
  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);

  /// Reads contributed migrations without throwing when none are registered.
  static Iterable<IDatabaseMigration> _registeredMigrations() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<IDatabaseMigration>()) {
      return const <IDatabaseMigration>[];
    }
    return getIt.getAll<IDatabaseMigration>();
  }
}
