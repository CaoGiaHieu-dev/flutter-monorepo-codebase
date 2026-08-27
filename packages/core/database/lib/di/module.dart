import 'package:injectable/injectable.dart';

/// `core_database` registers nothing on its own.
///
/// It provides the persistence MECHANISM — [DriftDatabaseOpener],
/// [driftMigrationStrategy], [IDatabaseMigration], [IDatabaseHandle] — and
/// deliberately owns no database, no table and no DAO. Registering a database
/// here would mean this package had to name the tables of whichever package
/// owns them.
///
/// The package that owns data registers its own database instead; see
/// `data_core`'s DI module for the reference wiring.
@InjectableInit.microPackage()
void initMicroPackage() {}
