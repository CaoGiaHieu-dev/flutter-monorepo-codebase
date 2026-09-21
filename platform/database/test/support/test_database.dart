import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Table-less [GeneratedDatabase], used only to obtain a [Migrator].
///
/// `core_database` deliberately declares no tables of its own — every schema
/// lives in the package that owns it. The migration runner still needs a
/// [Migrator] to hand to the registered steps, so tests build one over this
/// empty database rather than borrowing a real schema from another package.
///
/// Written by hand instead of generated: `@DriftDatabase` would require
/// running `drift_dev` over this package's `test/` directory just to produce
/// an empty database, and the two members below are all [Migrator] needs.
class TestDatabase extends GeneratedDatabase {
  TestDatabase() : super(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const Iterable<TableInfo<Table, dynamic>>.empty();

  @override
  int get schemaVersion => 1;
}
