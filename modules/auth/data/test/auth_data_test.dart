import 'package:core_network/core_network.dart';
import 'package:core_storage/core_storage.dart';
import 'package:data_auth/data_auth.dart';
import 'package:dio/dio.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The data layer end to end, with hand-written fakes (RULE-61) for the
/// transport and the platform storage: the repository's `execute()` shape, the
/// local data source's `StorageValue`, and what the session gateway tells the
/// transport after a failed renewal.
void main() {
  late _MemoryStorage secure;
  late _FakeRemote remote;
  late AuthLocalDataSource local;
  late AuthRepositoryImpl repository;
  late AuthSessionGatewayImpl gateway;

  const params = LoginParams(email: 'ada@example.com', password: 'secret');
  const ada = UserModel(id: 'u1', email: 'ada@example.com', name: 'Ada');

  // In the app core_network's DI module registers it; built by hand, the
  // DioExceptions below would otherwise stay unclassified.
  setUpAll(DioFailureClassifier.ensureRegistered);

  setUp(() {
    secure = _MemoryStorage();
    remote = _FakeRemote();
    local = AuthLocalDataSource(StorageManager(_MemoryStorage(), secure));
    repository = AuthRepositoryImpl(remote, local);
    gateway = AuthSessionGatewayImpl(local, repository);
  });

  group('login', () {
    test(
      'sends the credentials, stores the token, returns the entity',
      () async {
        remote.respond = () async => const BaseEntity(
          data: UserModel(id: 'u1', name: 'Ada', token: 'tok-1'),
        );

        final result = await repository.login(params);

        expect(remote.loginBodies, [
          {'email': 'ada@example.com', 'password': 'secret'},
        ]);
        expect(result.dataOrNull, const UserEntity(id: 'u1', name: 'Ada'));
        expect(local.getUserToken(), 'tok-1');
        expect(secure.values[AuthStorageKeys.TOKEN], 'tok-1');
      },
    );

    test('a 200 with an error body, or no token, is a failure', () async {
      remote.respond = () async => const BaseEntity(
        statusCode: 401,
        data: UserModel(id: 'u1', token: 'tok-1'),
      );
      expect((await repository.login(params)).isFailure, isTrue);

      remote.respond = () async => const BaseEntity(data: ada);
      expect((await repository.login(params)).isFailure, isTrue);

      expect(local.getUserToken(), isNull);
    });

    test('an HTTP 401 is an AuthFailure', () async {
      remote.respond = () async => throw _badResponse(401);

      final result = await repository.login(params);

      expect(result.errorOrNull, isA<AuthFailure<dynamic>>());
    });
  });

  group('local data source', () {
    test('hydrates a token written by a previous run, and clears it', () async {
      secure.values[AuthStorageKeys.TOKEN] = 'tok';
      expect(local.getUserToken(), isNull, reason: 'not read until initialize');

      await local.initialize();
      expect(local.getUserToken(), 'tok');

      await repository.logout();
      expect(local.getUserToken(), isNull);
      expect(secure.values, isEmpty);
    });
  });

  group('refreshToken', () {
    test('with no stored token fails without a network call', () async {
      var calls = 0;
      remote.respond = () async {
        calls++;
        return const BaseEntity(data: ada);
      };

      final result = await repository.refreshToken();

      expect(result.errorOrNull, isA<AuthFailure<dynamic>>());
      expect(calls, 0);
    });

    test('a renewal without a token keeps the stored one', () async {
      await local.saveUserToken('old');
      remote.respond = () async => const BaseEntity(data: ada);

      final result = await repository.refreshToken();

      expect(result.isSuccess, isTrue);
      expect(local.getUserToken(), 'old');
    });

    test('a refusal drops the stored token', () async {
      await local.saveUserToken('old');
      remote.respond = () async => throw _badResponse(401);

      await repository.refreshToken();

      expect(local.getUserToken(), isNull);
    });
  });

  group('session gateway', () {
    setUp(() => local.saveUserToken('stale'));

    test('a renewed session returns the fresh token', () async {
      remote.respond = () async => const BaseEntity(
        data: UserModel(id: 'u1', token: 'fresh'),
      );

      expect(await gateway.refreshToken(), 'fresh');
    });

    test(
      'a refusal (4xx, or an error envelope) is null: end the session',
      () async {
        remote.respond = () async => throw _badResponse(400);
        expect(await gateway.refreshToken(), isNull);

        remote.respond = () async =>
            const BaseEntity<UserModel>(statusCode: 401, message: 'revoked');
        expect(await gateway.refreshToken(), isNull);
      },
    );

    test('no answer (5xx, offline) throws: keep the session', () async {
      remote.respond = () async => throw _badResponse(503);
      await expectLater(gateway.refreshToken(), throwsStateError);

      remote.respond = () async => throw DioException(
        requestOptions: RequestOptions(path: '/refresh'),
        type: DioExceptionType.connectionError,
      );
      await expectLater(gateway.refreshToken(), throwsStateError);
      expect(gateway.readToken(), 'stale');
    });
  });
}

DioException _badResponse(int status) {
  final options = RequestOptions(path: '/refresh');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status),
  );
}

class _FakeRemote implements AuthRemoteDataSource {
  Future<BaseEntity<UserModel>> Function() respond = () async =>
      const BaseEntity<UserModel>();
  final loginBodies = <Map<String, dynamic>>[];

  @override
  Future<BaseEntity<UserModel>> login(Map<String, dynamic> loginData) {
    loginBodies.add(loginData);
    return respond();
  }

  @override
  Future<BaseEntity<UserModel>> refreshToken() => respond();
}

class _MemoryStorage implements StorageInterface {
  final values = <String, Object?>{};

  @override
  Future<void> init() async {}

  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) async => values[key] as T?;

  @override
  Future<void> write<T>(String key, T? value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  bool isValidKey(String key) => true;
}
