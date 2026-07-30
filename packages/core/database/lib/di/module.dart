import 'package:injectable/injectable.dart';

import '../src/database/app_database.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class CoreDatabaseDiModule {
  /// Opens [AppDatabase] on a background isolate before the app graph is ready.
  @preResolve
  @lazySingleton
  Future<AppDatabase> appDatabase() => AppDatabase.open();
}
