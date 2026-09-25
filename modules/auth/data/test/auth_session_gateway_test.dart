import 'package:core_network/core_network.dart';
import 'package:data_auth/data_auth.dart';
import 'package:dio/dio.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// The gateway decides whether a failed renewal signs the user out (null) or
/// keeps the session (throws). Misreading a refusal as transient keeps a dead
/// session forever, so every classification is pinned down here — through
/// the real repository, so the codes are the ones `execute` produces.
void main() {
  late _FakeRemote remote;
  late _FakeLocal local;
  late AuthSessionGatewayImpl gateway;

  // In the app core_network's DI module registers it; this test builds the
  // repository by hand, so DioExceptions would otherwise stay unclassified.
  setUpAll(DioFailureClassifier.ensureRegistered);

  setUp(() {
    remote = _FakeRemote();
    local = _FakeLocal()..token = 'stale-token';
    gateway = AuthSessionGatewayImpl(
      local,
      AuthRepositoryImpl(remote, local),
    );
  });

  test('returns the renewed token on success', () async {
    remote.respond = () async => const BaseEntity(
      data: UserModel(id: 'u1', token: 'fresh-token'),
    );

    expect(await gateway.refreshToken(), 'fresh-token');
  });

  test(
    'a 200 whose envelope reports failure is a refusal, not a 5xx',
    () async {
      remote.respond = () async => const BaseEntity<UserModel>(
        statusCode: 401,
        message: 'Token revoked',
      );

      final result = await AuthRepositoryImpl(remote, local).refreshToken();
      final failure = result.errorOrNull;
      expect(failure, isA<ServerFailure<dynamic>>());
      expect(failure?.code, ErrorCodes.RESPONSE_REJECTED);
      expect(failure?.message, 'Token revoked');

      expect(await gateway.refreshToken(), isNull);
    },
  );

  test('a success envelope without data is a refusal', () async {
    remote.respond = () async => const BaseEntity<UserModel>();

    expect(await gateway.refreshToken(), isNull);
  });

  test('an HTTP 401 is a refusal', () async {
    remote.respond = () async => throw _badResponse(401);

    expect(await gateway.refreshToken(), isNull);
  });

  test('an HTTP 400 is a refusal', () async {
    remote.respond = () async => throw _badResponse(400);

    expect(await gateway.refreshToken(), isNull);
  });

  test('an HTTP 503 keeps the session', () async {
    remote.respond = () async => throw _badResponse(503);

    await expectLater(gateway.refreshToken(), throwsStateError);
  });

  test('no network keeps the session', () async {
    remote.respond = () async => throw DioException(
      requestOptions: RequestOptions(path: '/refresh'),
      type: DioExceptionType.connectionError,
    );

    await expectLater(gateway.refreshToken(), throwsStateError);
  });

  test('a cancelled request keeps the session', () async {
    remote.respond = () async => throw DioException(
      requestOptions: RequestOptions(path: '/refresh'),
      type: DioExceptionType.cancel,
    );

    await expectLater(gateway.refreshToken(), throwsStateError);
  });

  group('restoreSession', () {
    late AuthRepositoryImpl repository;

    setUp(() {
      repository = AuthRepositoryImpl(remote, local);
      local.user = const UserModel(id: 'u1', name: 'Ada', role: 'owner');
    });

    test('renews the session when the server answers', () async {
      remote.respond = () async => const BaseEntity(
        data: UserModel(id: 'u1', name: 'Ada', token: 'fresh-token'),
      );

      final result = await repository.restoreSession();

      expect(result.dataOrNull?.name, 'Ada');
      expect(local.token, 'fresh-token');
    });

    test('offline, restores the stored user and keeps the token', () async {
      remote.respond = () async => throw DioException(
        requestOptions: RequestOptions(path: '/refresh'),
        type: DioExceptionType.connectionError,
      );

      final result = await repository.restoreSession();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.id, 'u1');
      expect(result.dataOrNull?.role, UserRole.owner);
      expect(local.token, 'stale-token');
    });

    test('a 5xx restores the stored user too', () async {
      remote.respond = () async => throw _badResponse(503);

      expect((await repository.restoreSession()).dataOrNull?.id, 'u1');
    });

    test('offline with no stored user stays a failure', () async {
      local.user = null;
      remote.respond = () async => throw DioException(
        requestOptions: RequestOptions(path: '/refresh'),
        type: DioExceptionType.connectionError,
      );

      final result = await repository.restoreSession();

      expect(result.errorOrNull, isA<NetworkFailure<dynamic>>());
    });

    test('a refusal ends the stored session', () async {
      remote.respond = () async => throw _badResponse(401);

      final result = await repository.restoreSession();

      expect(result.errorOrNull, isA<AuthFailure<dynamic>>());
      expect(local.token, isNull);
      expect(local.user, isNull);
    });

    test('no stored token never reaches the network', () async {
      local.token = null;
      var calls = 0;
      remote.respond = () async {
        calls++;
        return const BaseEntity<UserModel>();
      };

      final result = await repository.restoreSession();

      expect(result.errorOrNull, isA<AuthFailure<dynamic>>());
      expect(calls, 0);
    });
  });

  test('logout clears the stored token and user', () async {
    local.user = const UserModel(id: 'u1');

    final result = await AuthRepositoryImpl(remote, local).logout();

    expect(result.isSuccess, isTrue);
    expect(local.token, isNull);
    expect(local.user, isNull);
  });

  group('isTransientFailure', () {
    test('only network faults, real 5xx and cancellation are transient', () {
      expect(
        isTransientFailure(
          const NetworkFailure(message: 'offline', code: 1005),
        ),
        isTrue,
      );
      for (final code in [500, 502, 599, ErrorCodes.REQUEST_CANCELLED]) {
        expect(
          isTransientFailure(
            ServerFailure(message: 'x', code: code),
          ),
          isTrue,
          reason: 'code $code',
        );
      }
      for (final code in [
        400,
        404,
        ErrorCodes.RESPONSE_REJECTED,
        ErrorCodes.EMPTY_RESPONSE,
        ErrorCodes.UNKNOWN,
        null,
      ]) {
        expect(
          isTransientFailure(
            ServerFailure(message: 'x', code: code),
          ),
          isFalse,
          reason: 'code $code',
        );
      }
      expect(
        isTransientFailure(
          const AuthFailure(message: 'x', code: 401),
        ),
        isFalse,
      );
      expect(isTransientFailure(null), isFalse);
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

  @override
  Future<BaseEntity<UserModel>> login(Map<String, dynamic> loginData) =>
      respond();

  @override
  Future<BaseEntity<UserModel>> refreshToken() => respond();
}

class _FakeLocal implements AuthLocalDataSource {
  String? token;
  UserModel? user;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> saveUserToken(String? value) async => token = value;

  @override
  String? getUserToken() => token;

  @override
  Future<void> saveUserData(UserModel? value) async => user = value;

  @override
  UserModel? getUserData() => user;

  @override
  Future<void> clearAllAuthData() async {
    token = null;
    user = null;
  }
}
