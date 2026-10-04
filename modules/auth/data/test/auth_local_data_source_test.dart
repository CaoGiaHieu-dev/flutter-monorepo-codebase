import 'package:core_storage/core_storage.dart';
import 'package:data_auth/data_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the session actually writes to storage: the token under its own key,
/// the user without that token, and both gone after a clear.
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

void main() {
  late _MemoryStorage secure;
  late AuthLocalDataSource local;

  setUp(() {
    secure = _MemoryStorage();
    local = AuthLocalDataSource(StorageManager(_MemoryStorage(), secure));
  });

  test('the token round-trips and null removes it', () async {
    await local.saveUserToken('tok');
    expect(local.getUserToken(), 'tok');
    expect(secure.values[AuthStorageKeys.TOKEN], isNotNull);

    await local.saveUserToken(null);

    expect(local.getUserToken(), isNull);
    expect(secure.values.containsKey(AuthStorageKeys.TOKEN), isFalse);
  });

  test('the stored user never carries the session token', () async {
    await local.saveUserData(
      const UserModel(id: 'u1', name: 'Ada', role: 'owner', token: 'tok'),
    );

    final stored = local.getUserData();

    expect(stored?.id, 'u1');
    expect(stored?.name, 'Ada');
    expect(stored?.role, 'owner');
    expect(stored?.token, isNull);
    final raw =
        secure.values[AuthStorageKeys.AUTH_USER]! as Map<String, dynamic>;
    expect(raw['token'], isNull);
    expect(raw.values, isNot(contains('tok')));
  });

  test('no stored user reads as null', () {
    expect(local.getUserData(), isNull);
    expect(local.getUserToken(), isNull);
  });

  test('initialize hydrates a session written by a previous run', () async {
    secure.values[AuthStorageKeys.TOKEN] = 'tok';
    secure.values[AuthStorageKeys.AUTH_USER] = {'id': 'u1', 'name': 'Ada'};

    expect(local.getUserToken(), isNull, reason: 'not read until initialize');
    await local.initialize();

    expect(local.getUserToken(), 'tok');
    expect(local.getUserData()?.name, 'Ada');
  });

  test('clearAllAuthData drops the token and the user together', () async {
    await local.saveUserToken('tok');
    await local.saveUserData(const UserModel(id: 'u1'));

    await local.clearAllAuthData();

    expect(local.getUserToken(), isNull);
    expect(local.getUserData(), isNull);
    expect(secure.values, isEmpty);
  });
}
