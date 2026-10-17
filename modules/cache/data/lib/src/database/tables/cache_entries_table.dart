import 'package:drift/drift.dart';

/// Example table — string payloads keyed by a unique id.
class CacheEntries extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
