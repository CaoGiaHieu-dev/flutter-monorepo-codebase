/// REST endpoints owned by `data_auth`.
class AuthApiConstants {
  AuthApiConstants._();

  static const String LOGIN = '/user/login';
  static const String REFRESH_TOKEN = '/user/refresh-token';
}

/// Physical storage keys owned by `data_auth` — no other package reads them.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
}
