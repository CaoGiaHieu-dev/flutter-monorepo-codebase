import 'package:core_database/core_database.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

import '../src/database/cache_database.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class DataCacheDiModule {
  /// Opens [CacheDatabase] while the module initialises, which runs the
  /// collected migrations — so every step must be registered by then.
  /// `@Order(1)` makes a step declared in this package (default order 0)
  /// register before the open; a step from another package needs an earlier
  /// DI group. The collection is typed to [CacheDatabase], so another
  /// package's steps never reach it.
  @Order(1)
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() => CacheDatabase.open(
    migrations: getAllOrEmpty<IDatabaseMigration<CacheDatabase>>(),
  );

  /// Data sources take this handle instead of [CacheDatabase], so each gets
  /// only the DAO it asks for.
  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);
}
