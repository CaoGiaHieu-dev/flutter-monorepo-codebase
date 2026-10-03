import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

void main() {
  tearDown(getIt.reset);

  group('NetworkConfigImpl without a session owner', () {
    late NetworkConfigImpl config;

    setUp(() async {
      config = NetworkConfigImpl(await _languageStorage());
    });

    test('sends no token', () {
      expect(config.getToken(), isNull);
    });

    test('offers no refresh, so a 401 fails outright', () {
      expect(config.onRefreshToken, isNull);
      expect(config.onRefreshFailed, isNull);
    });
  });

  group('NetworkConfigImpl with a session owner', () {
    late _FakeGateway gateway;
    late _FakeSessionState session;
    late NetworkConfigImpl config;

    setUp(() async {
      gateway = _FakeGateway();
      session = _FakeSessionState();
      getIt
        ..registerSingleton<ISessionGateway>(gateway)
        ..registerSingleton<ISessionState>(session);
      config = NetworkConfigImpl(await _languageStorage());
    });

    test('reads the token through the gateway, on every call', () {
      gateway.token = 'a';
      expect(config.getToken(), 'a');
      gateway.token = 'b';
      expect(config.getToken(), 'b');
    });

    test('refreshes through the gateway', () async {
      gateway.refreshed = 'new';
      expect(await config.onRefreshToken!(), 'new');
    });

    test('a refused refresh clears the session and signs out', () async {
      await config.onRefreshFailed!();
      expect(gateway.cleared, isTrue);
      expect(session.lost, isTrue);
    });
  });

  group('NetworkConfigImpl.getLocale', () {
    test('sends the stored language', () async {
      final storage = await _languageStorage();
      storage.saveLanguage(const Locale('vi'));
      expect(NetworkConfigImpl(storage).getLocale(), 'vi');
    });

    test('resolves an unsupported language to the app fallback', () async {
      final storage = await _languageStorage();
      storage.saveLanguage(const Locale('ja'));
      expect(NetworkConfigImpl(storage).getLocale(), 'en');
    });
  });

  group('LanguageStorageImpl', () {
    test('round-trips a locale through storage', () async {
      final backend = _MemoryStorage();
      final first = await _languageStorage(backend);
      first.saveLanguage(const Locale('vi'));
      await _settle();

      final reopened = await _languageStorage(backend);
      expect(reopened.getLanguage(), const Locale('vi'));
    });

    test('falls back to the device locale when nothing is stored', () async {
      final storage = await _languageStorage();
      expect(storage.getLanguage(), AppConfig.defaultLanguage);
    });
  });

  group('ThemeStorageImpl', () {
    test('round-trips a theme mode through storage', () async {
      final backend = _MemoryStorage();
      final first = ThemeStorageImpl(_manager(backend));
      await first.initialize();
      first.saveThemeMode(ThemeMode.dark);
      await _settle();

      final reopened = ThemeStorageImpl(_manager(backend));
      await reopened.initialize();
      expect(reopened.getThemeMode(), ThemeMode.dark);
    });

    test('defaults to the system mode', () async {
      final storage = ThemeStorageImpl(_manager(_MemoryStorage()));
      await storage.initialize();
      expect(storage.getThemeMode(), ThemeMode.system);
    });
  });

  group('AppBootStorage', () {
    test('onboarding is unseen until marked, and stays marked', () async {
      final backend = _MemoryStorage();
      final boot = AppBootStorage(_manager(backend));
      await boot.initialize();
      expect(boot.viewedOnboard, isFalse);

      await boot.markOnboardViewed();
      expect(boot.viewedOnboard, isTrue);

      final reopened = AppBootStorage(_manager(backend));
      await reopened.initialize();
      expect(reopened.viewedOnboard, isTrue);
    });
  });
}

/// Lets a fire-and-forget `StorageValue` write reach the backend.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

StorageManager _manager(StorageInterface backend) =>
    StorageManager(backend, backend);

Future<LanguageStorageImpl> _languageStorage([
  StorageInterface? backend,
]) async {
  final storage = LanguageStorageImpl(_manager(backend ?? _MemoryStorage()));
  await storage.initialize();
  return storage;
}

/// A key-value backend held in memory, encoding like the real backends.
class _MemoryStorage implements StorageInterface {
  final _values = <String, String>{};

  @override
  Future<void> init() async {}

  @override
  bool isValidKey(String key) => true;

  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) async {
    final json = _values[key];
    return json == null
        ? null
        : StorageCodec.decode<T>(json, key, reviver: reviver);
  }

  @override
  Future<void> write<T>(String key, T? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = StorageCodec.encode(value);
    }
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _FakeGateway implements ISessionGateway {
  String? token;
  String? refreshed;
  bool cleared = false;

  @override
  String? readToken() => token;

  @override
  Future<String?> refreshToken() async => refreshed;

  @override
  Future<void> clearSession() async => cleared = true;
}

class _FakeSessionState implements ISessionState {
  bool lost = false;

  @override
  void onSessionLost() => lost = true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  bool get hasRestoredSession => true;

  @override
  SessionPrincipal? get signedInUser => null;

  @override
  Stream<SessionPrincipal?> get sessionChanges => const Stream.empty();

  @override
  Stream<SessionFailure> get sessionFailures => const Stream.empty();
}
