import 'package:core_database/core_database.dart';
import 'package:data_cache/data_cache.dart';
import 'package:domain_cache/domain_cache.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

/// A data source whose every call fails, to prove the repository turns a
/// thrown error into a `Result.failure` instead of letting it reach the UI.
class _ThrowingDataSource implements ICacheEntryLocalDataSource {
  @override
  Future<CacheEntryModel?> getEntry(String key) async =>
      throw StateError('database is closed');

  @override
  Future<void> save(String key, String value) async =>
      throw StateError('database is closed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late CacheDatabase database;
  late CacheEntryRepositoryImpl repository;

  setUp(() {
    database = CacheDatabase.forTesting();
    repository = CacheEntryRepositoryImpl(
      CacheEntryLocalDataSource(DatabaseHandle<CacheDatabase>(database)),
    );
  });

  tearDown(() => database.close());

  group('with a real in-memory database', () {
    test('a saved value comes back as a domain entity', () async {
      final saved = await repository.save(
        const CacheEntryParams(key: 'greeting', value: 'hello'),
      );
      final read = await repository.getByKey('greeting');

      expect(saved.isSuccess, isTrue);
      final entry = read.dataOrNull;
      expect(entry, isA<CacheEntryEntity>());
      expect(entry?.key, 'greeting');
      expect(entry?.value, 'hello');
    });

    test('saving the same key again replaces its value', () async {
      await repository.save(const CacheEntryParams(key: 'k', value: 'one'));
      await repository.save(const CacheEntryParams(key: 'k', value: 'two'));

      expect((await repository.getByKey('k')).dataOrNull?.value, 'two');
    });

    test('keys do not bleed into each other', () async {
      await repository.save(const CacheEntryParams(key: 'a', value: '1'));
      await repository.save(const CacheEntryParams(key: 'b', value: '2'));

      expect((await repository.getByKey('a')).dataOrNull?.value, '1');
      expect((await repository.getByKey('b')).dataOrNull?.value, '2');
    });

    test('a missing key is a success carrying no entry', () async {
      final result = await repository.getByKey('absent');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, isNull);
    });
  });

  group('when the data source throws', () {
    test('getByKey returns a failure instead of throwing', () async {
      final result = await CacheEntryRepositoryImpl(
        _ThrowingDataSource(),
      ).getByKey('k');

      expect(result.isFailure, isTrue);
    });

    test('save returns a failure instead of throwing', () async {
      final result = await CacheEntryRepositoryImpl(
        _ThrowingDataSource(),
      ).save(const CacheEntryParams(key: 'k', value: 'v'));

      expect(result.isFailure, isTrue);
    });
  });

  group('CacheEntryModel', () {
    test('fromRow then toEntity keeps key, value and updatedAt', () {
      final at = DateTime.utc(2026, 3, 4, 5, 6);
      final model = CacheEntryModel.fromRow(
        CacheEntry(key: 'k', value: 'v', updatedAt: at),
      );

      expect(
        model.toEntity(),
        CacheEntryEntity(key: 'k', value: 'v', updatedAt: at),
      );
    });
  });
}
