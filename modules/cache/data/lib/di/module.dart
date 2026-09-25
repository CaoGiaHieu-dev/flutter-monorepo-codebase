import 'package:core_database/core_database.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

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
  /// this module initialises, so every step must already be registered.
  ///
  /// `@Order(1)` makes that true inside this package: injectable registers a
  /// module's entries in ascending order, so a migration declared here with
  /// the default order (0) is registered before the open runs. Without it the
  /// open came first and a step written exactly as the database guide shows
  /// was never collected — the schema version moved and the schema did not.
  /// A step contributed by *another* package must still sit in an earlier DI
  /// group.
  ///
  /// Only an app that composes this module pays for opening the file.
  @Order(1)
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() => CacheDatabase.open(
    // Typed to [CacheDatabase]: a step another package registers for its
    // own database is a different GetIt type and never reaches this one.
    migrations: getAllOrEmpty<IDatabaseMigration<CacheDatabase>>(),
  );

  /// Narrow accessor handle for this package's data sources.
  ///
  /// Data sources depend on this rather than on [CacheDatabase] itself, so
  /// they receive only the DAO they ask for.
  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);
}
