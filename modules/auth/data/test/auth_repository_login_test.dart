import 'package:core_network/core_network.dart';
import 'package:data_auth/data_auth.dart';
import 'package:dio/dio.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `login` is the only repository path the session-gateway test does not
/// reach: what it sends, what it persists, and what a 200 with an error body
/// does. Hand-written fakes stand in for the transport and the storage.
void main() {
  late _FakeRemote remote;
  late _FakeLocal local;
  late AuthRepositoryImpl repository;

  const params = LoginParams(email: 'ada@example.com', password: 'secret');

  setUpAll(DioFailureClassifier.ensureRegistered);

  setUp(() {
    remote = _FakeRemote();
    local = _FakeLocal();
    repository = AuthRepositoryImpl(remote, local);
  });

  test('sends the email and password, and nothing else', () async {
    remote.response = const BaseEntity(
      data: UserModel(id: 'u1', token: 't'),
    );

    await repository.login(params);

    expect(remote.loginBodies, [
      {'email': 'ada@example.com', 'password': 'secret'},
    ]);
  });

  test(
    'success persists the token and the user, and returns the entity',
    () async {
      remote.response = const BaseEntity(
        data: UserModel(
          id: 'u1',
          email: 'ada@example.com',
          name: 'Ada',
          role: 'owner',
          token: 'tok-1',
        ),
      );

      final result = await repository.login(params);

      expect(
        result.dataOrNull,
        const UserEntity(
          id: 'u1',
          email: 'ada@example.com',
          name: 'Ada',
          role: UserRole.owner,
        ),
      );
      expect(local.token, 'tok-1');
      expect(local.user?.id, 'u1');
    },
  );

  test(
    'a 200 whose envelope reports an error is a failure and stores nothing',
    () async {
      remote.response = const BaseEntity(
        statusCode: 401,
        message: 'wrong password',
        data: UserModel(id: 'u1', token: 'tok-1'),
      );

      final result = await repository.login(params);

      expect(result.isFailure, isTrue);
      expect(local.token, isNull);
      expect(local.user, isNull);
    },
  );

  test(
    'a success envelope without a user is a failure and stores nothing',
    () async {
      remote.response = const BaseEntity<UserModel>();

      final result = await repository.login(params);

      expect(result.isFailure, isTrue);
      expect(local.token, isNull);
      expect(local.user, isNull);
    },
  );

  test('a success envelope without a token is no session: a failure, and '
      'an old token is not wiped by it', () async {
    local.token = 'old';
    for (final token in [null, '']) {
      remote.response = BaseEntity(
        data: UserModel(id: 'u1', token: token),
      );

      final result = await repository.login(params);

      expect(result.isFailure, isTrue, reason: 'token: "$token"');
      expect(local.token, 'old');
      expect(local.user, isNull);
    }
  });

  test('an HTTP 401 is an AuthFailure and stores nothing', () async {
    final options = RequestOptions(path: '/login');
    remote.error = DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: options, statusCode: 401),
    );

    final result = await repository.login(params);

    expect(result.errorOrNull, isA<AuthFailure<dynamic>>());
    expect(local.token, isNull);
  });

  test('a failed login leaves a stored session untouched', () async {
    local
      ..token = 'old'
      ..user = const UserModel(id: 'u0');
    remote.response = const BaseEntity(statusCode: 401);

    await repository.login(params);

    expect(local.token, 'old');
    expect(local.user?.id, 'u0');
  });
}

class _FakeRemote implements AuthRemoteDataSource {
  BaseEntity<UserModel> response = const BaseEntity<UserModel>();
  Object? error;
  final loginBodies = <Map<String, dynamic>>[];

  @override
  Future<BaseEntity<UserModel>> login(Map<String, dynamic> loginData) async {
    loginBodies.add(loginData);
    final failure = error;
    if (failure != null) throw failure;
    return response;
  }

  @override
  Future<BaseEntity<UserModel>> refreshToken() =>
      throw UnimplementedError('login never renews a token');
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
