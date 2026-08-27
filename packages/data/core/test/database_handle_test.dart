import 'package:core_database/core_database.dart';
import 'package:data_core/data_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late CacheDatabase database;
  late IDatabaseHandle<CacheDatabase> handle;

  setUp(() {
    database = CacheDatabase.forTesting();
    handle = DatabaseHandle<CacheDatabase>(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('DatabaseHandle.accessor', () {
    test('returns an accessor that reads and writes its own table', () async {
      final dao = handle.accessor(CacheEntriesDao.new);

      await dao.upsert('greeting', 'hello');

      expect(await dao.getValue('greeting'), equals('hello'));
    });

    test('shares one connection across separately obtained accessors', () async {
      final writer = handle.accessor(CacheEntriesDao.new);
      final reader = handle.accessor(CacheEntriesDao.new);

      await writer.upsert('greeting', 'hello');

      // Two accessors are independent objects over the same connection, so a
      // write through one must be visible through the other.
      expect(identical(writer, reader), isFalse);
      expect(await reader.getValue('greeting'), equals('hello'));
    });

    test('accessor sees rows written directly on the database', () async {
      await database.cacheEntriesDao.upsert('greeting', 'hello');

      final dao = handle.accessor(CacheEntriesDao.new);

      expect(await dao.getValue('greeting'), equals('hello'));
    });
  });

  group('DatabaseHandle.transaction', () {
    test('commits every write in the block', () async {
      final dao = handle.accessor(CacheEntriesDao.new);

      await handle.transaction(() async {
        await dao.upsert('a', '1');
        await dao.upsert('b', '2');
      });

      expect(await dao.getValue('a'), equals('1'));
      expect(await dao.getValue('b'), equals('2'));
    });

    test('rolls the whole block back when it throws', () async {
      final dao = handle.accessor(CacheEntriesDao.new);
      await dao.upsert('existing', 'kept');

      await expectLater(
        handle.transaction(() async {
          await dao.upsert('rolled-back', 'value');
          throw StateError('abort');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await dao.getValue('rolled-back'), isNull);
      expect(await dao.getValue('existing'), equals('kept'));
    });

    test('returns the value produced by the block', () async {
      final result = await handle.transaction(() async => 42);

      expect(result, equals(42));
    });
  });
}
