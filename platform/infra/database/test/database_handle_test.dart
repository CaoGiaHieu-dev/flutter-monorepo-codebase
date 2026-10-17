import 'package:core_database/core_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_database.dart';

/// `DatabaseHandle.transaction` is what a package uses to make several writes
/// atomic without being handed the database.
void main() {
  late TestDatabase database;
  late DatabaseHandle<TestDatabase> handle;

  setUp(() async {
    database = TestDatabase();
    handle = DatabaseHandle(database);
    await database.customStatement('CREATE TABLE t (k TEXT PRIMARY KEY)');
  });

  tearDown(() => database.close());

  Future<int> rows() async =>
      (await database.customSelect('SELECT k FROM t').get()).length;

  test('commits the block and returns its value', () async {
    final value = await handle.transaction(() async {
      await database.customStatement("INSERT INTO t VALUES ('a')");
      return 42;
    });

    expect(value, 42);
    expect(await rows(), 1);
  });

  test('a block that throws rolls back what it wrote', () async {
    await expectLater(
      handle.transaction(() async {
        await database.customStatement("INSERT INTO t VALUES ('a')");
        throw StateError('second write failed');
      }),
      throwsStateError,
    );

    expect(await rows(), 0);
  });
}
