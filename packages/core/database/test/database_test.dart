import 'package:core_database/core_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting();
  });

  tearDown(() async {
    await database.close();
  });

  group('CacheEntriesDao', () {
    test('upsert and getValue round-trip', () async {
      await database.cacheEntriesDao.upsert('greeting', 'hello');

      final value = await database.cacheEntriesDao.getValue('greeting');

      expect(value, equals('hello'));
    });

    test('upsert replaces existing row', () async {
      await database.cacheEntriesDao.upsert('greeting', 'hello');
      await database.cacheEntriesDao.upsert('greeting', 'world');

      final value = await database.cacheEntriesDao.getValue('greeting');

      expect(value, equals('world'));
    });

    test('deleteByKey removes row', () async {
      await database.cacheEntriesDao.upsert('greeting', 'hello');

      await database.cacheEntriesDao.deleteByKey('greeting');

      final value = await database.cacheEntriesDao.getValue('greeting');
      expect(value, isNull);
    });

    test('getEntry returns full row', () async {
      await database.cacheEntriesDao.upsert('meta', 'payload');

      final row = await database.cacheEntriesDao.getEntry('meta');

      expect(row, isNotNull);
      expect(row!.key, equals('meta'));
      expect(row.value, equals('payload'));
      expect(row.updatedAt, isA<DateTime>());
    });

    test('getAll returns every stored row', () async {
      await database.cacheEntriesDao.upsert('first', '1');
      await database.cacheEntriesDao.upsert('second', '2');

      final rows = await database.cacheEntriesDao.getAll();

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.key), containsAll(['first', 'second']));
    });

    test('clearAll removes every row', () async {
      await database.cacheEntriesDao.upsert('a', '1');
      await database.cacheEntriesDao.upsert('b', '2');

      await database.cacheEntriesDao.clearAll();

      final rows = await database.cacheEntriesDao.getAll();
      expect(rows, isEmpty);
    });
  });
}
