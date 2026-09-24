import 'package:data_auth/data_auth.dart';
import 'package:dio/dio.dart';
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

  group('isTransient', () {
    test('only network faults, real 5xx and cancellation are transient', () {
      expect(
        AuthSessionGatewayImpl.isTransient(
          const NetworkFailure(message: 'offline', code: 1005),
        ),
        isTrue,
      );
      for (final code in [500, 502, 599, ErrorCodes.REQUEST_CANCELLED]) {
        expect(
          AuthSessionGatewayImpl.isTransient(
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
          AuthSessionGatewayImpl.isTransient(
            ServerFailure(message: 'x', code: code),
          ),
          isFalse,
          reason: 'code $code',
        );
      }
      expect(
        AuthSessionGatewayImpl.isTransient(
          const AuthFailure(message: 'x', code: 401),
        ),
        isFalse,
      );
      expect(AuthSessionGatewayImpl.isTransient(null), isFalse);
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
  void saveUserToken(String? value) => token = value;

  @override
  String? getUserToken() => token;

  @override
  void saveUserData(UserModel? value) => user = value;

  @override
  UserModel? getUserData() => user;

  @override
  void clearAllAuthData() {
    token = null;
    user = null;
  }
}
