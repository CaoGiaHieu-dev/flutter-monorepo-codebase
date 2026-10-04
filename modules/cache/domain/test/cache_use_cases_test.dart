import 'package:domain_cache/domain_cache.dart';
import 'package:domain_core/domain_core.dart';
import 'package:test/test.dart';

/// A hand-written [ICacheEntryRepository] backed by a map, so a save followed
/// by a get is observable end to end through the real use cases.
class _FakeCacheRepository implements ICacheEntryRepository {
  final rows = <String, CacheEntryEntity>{};
  Result<void>? saveFailure;
  Result<CacheEntryEntity?>? getFailure;

  final requestedKeys = <String>[];

  @override
  Future<Result<CacheEntryEntity?>> getByKey(String key) async {
    requestedKeys.add(key);
    return getFailure ?? Result.success(rows[key]);
  }

  @override
  Future<Result<void>> save(CacheEntryParams params) async {
    final failure = saveFailure;
    if (failure != null) return failure;
    rows[params.key] = CacheEntryEntity(
      key: params.key,
      value: params.value,
      updatedAt: DateTime.utc(2026),
    );
    return const Result.success();
  }
}

void main() {
  late _FakeCacheRepository repository;

  setUp(() => repository = _FakeCacheRepository());

  group('SaveCacheEntryUseCase', () {
    test('hands the key and value to the repository', () async {
      final result = await SaveCacheEntryUseCase(repository)(
        const CacheEntryParams(key: 'greeting', value: 'hello'),
      );

      expect(result.isSuccess, isTrue);
      expect(repository.rows['greeting']?.value, 'hello');
    });

    test('returns the repository failure as a failure', () async {
      const failure = StorageFailure<dynamic>(message: 'disk full');
      repository.saveFailure = const Result.failure(failure);

      final result = await SaveCacheEntryUseCase(repository)(
        const CacheEntryParams(key: 'k', value: 'v'),
      );

      expect(result.errorOrNull, failure);
      expect(repository.rows, isEmpty);
    });
  });

  group('GetCacheEntryUseCase', () {
    test('returns the saved entry for the key it asked for', () async {
      await SaveCacheEntryUseCase(repository)(
        const CacheEntryParams(key: 'greeting', value: 'hello'),
      );

      final result = await GetCacheEntryUseCase(repository)('greeting');

      expect(result.dataOrNull?.value, 'hello');
      expect(repository.requestedKeys, ['greeting']);
    });

    test('a missing key is a success with no entry, not a failure', () async {
      final result = await GetCacheEntryUseCase(repository)('absent');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, isNull);
    });

    test('returns the repository failure as a failure', () async {
      const failure = CacheFailure<dynamic>(message: 'db closed');
      repository.getFailure = const Result.failure(failure);

      final result = await GetCacheEntryUseCase(repository)('k');

      expect(result.errorOrNull, failure);
    });
  });

  group('CacheEntryEntity', () {
    test('is a value over key, value and updatedAt', () {
      final at = DateTime.utc(2026, 5, 1);
      final a = CacheEntryEntity(key: 'k', value: 'v', updatedAt: at);
      final b = CacheEntryEntity(key: 'k', value: 'v', updatedAt: at);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(b.copyWith(value: 'other')));
      expect(a, isNot(b.copyWith(updatedAt: DateTime.utc(2026, 5, 2))));
    });
  });
}
