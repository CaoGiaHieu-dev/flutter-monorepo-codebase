import 'dart:io';

import 'package:data_core/data_core.dart';
import 'package:domain_core/domain_core.dart';
import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

class _Repository extends BaseRepository {}

void main() {
  final repository = _Repository();

  group('BaseRepository.execute', () {
    test('maps a response through the mapper', () async {
      final result = await repository.execute<int, String>(
        () async => 42,
        mapper: (value) => 'value $value',
      );
      expect(result, const Success<String>('value 42'));
    });

    test('a null response is a success for a nullable type', () async {
      final result = await repository.execute<String?, String?>(
        () async => null,
        mapper: (value) => 'never called',
      );
      expect(result, const Success<String?>(null));
    });

    test('a null response fails for a non-nullable type', () async {
      final result = await repository.execute<String?, String>(
        () async => null,
        mapper: (value) => value!,
      );
      expect(result.errorOrNull?.code, ErrorCodes.EMPTY_RESPONSE);
    });

    test('a rejected response is coded RESPONSE_REJECTED', () async {
      final result = await repository.execute<BaseEntity<int>, int?>(
        () async => const BaseEntity(statusCode: 400, message: 'nope'),
        mapper: (entity) => entity.data,
        successCondition: (entity) => entity.isSuccess,
      );
      final failure = result.errorOrNull;
      expect(failure, isA<ServerFailure<dynamic>>());
      expect(failure?.code, ErrorCodes.RESPONSE_REJECTED);
      expect(failure?.message, 'nope');
    });

    test('a thrown exception becomes a failure', () async {
      final result = await repository.execute<int, int>(
        () async => throw const SocketException('offline'),
      );
      expect(result.errorOrNull, isA<NetworkFailure<dynamic>>());
      expect(result.errorOrNull?.code, ErrorCodes.NO_INTERNET);
    });
  });

  group('BaseRepository.executeSync', () {
    test('returns the value when it already is the entity type', () {
      expect(repository.executeSync<int, int>(() => 7), const Success<int>(7));
    });

    test('a null result fails for a non-nullable type', () {
      final result = repository.executeSync<int?, int>(() => null);
      expect(result.errorOrNull?.code, ErrorCodes.EMPTY_RESPONSE);
      expect(result.errorOrNull?.message, 'Operation returned null');
    });

    test('reports a thrown error to onFailure', () {
      Object? reported;
      final result = repository.executeSync<int, int>(
        () => throw const FormatException('bad'),
        onFailure: (error) => reported = error,
      );
      expect(reported, isA<FormatException>());
      expect(result.errorOrNull?.code, ErrorCodes.INVALID_FORMAT);
    });
  });
}
