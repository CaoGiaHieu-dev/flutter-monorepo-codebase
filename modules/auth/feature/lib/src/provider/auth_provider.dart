import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../session/auth_status_stream_impl.dart';
import 'auth_error_state.dart';

/// The global auth controller, and the feature's side of the shell's session
/// contracts ([ISessionState], [ISessionRefreshListenable]): the shell drives
/// its boot redirect and routing through them without importing this package.
@lazySingleton
class AuthProvider extends BaseProvider<UserEntity>
    implements ISessionState, ISessionRefreshListenable {
  AuthProvider(this._loginUseCase, this._repository, this._authStream);

  final LoginUseCase _loginUseCase;
  final IAuthRepository _repository;
  final AuthStatusStreamImpl _authStream;

  final _failures = StreamController<SessionFailure>.broadcast();
  bool _hasRestoredSession = false;

  @override
  bool get hasRestoredSession => _hasRestoredSession;

  @override
  SessionPrincipal? get signedInUser => _authStream.currentUser;

  @override
  Stream<SessionPrincipal?> get sessionChanges =>
      _authStream.sessionStatusStream;

  @override
  Stream<SessionFailure> get sessionFailures => _failures.stream;

  /// Restores the stored session: no token, or a refused one, means signed out.
  @override
  Future<void> initialize() async {
    updateState(state: const ViewState.loading());
    final result = await _repository.refreshToken();
    _setUser(result.dataOrNull);
    _hasRestoredSession = true;
    await super.initialize();
  }

  /// Signs in. `executeOperation` shows loading, runs the use case and settles
  /// success or the classified error; the page reacts through
  /// `ProviderStateListener`, the shell through the session channels. No
  /// navigation here: the shell routes on [sessionChanges].
  Future<void> login(String email, String password) async {
    // One sign-in at a time: a second submit (the keyboard's Done pressed
    // twice) would race two outcomes.
    if (isLoading) return;
    await executeOperation(
      OperationConfig(
        operation: () =>
            _loginUseCase(LoginParams(email: email, password: password)),
        onSuccess: _authStream.updateAuthStatus,
        onFailure: (failure) => _failures.add(
          mapAuthFailure(failure) == const AuthErrorState.invalidCredentials()
              ? const SessionInvalidCredentialsFailure()
              : SessionServerFailure(code: failure.code),
        ),
        errorStateBuilder: mapAuthFailure,
      ),
    );
  }

  /// Clears the session; the state changes whatever the repository answers.
  Future<void> logout() async {
    await _repository.logout();
    _setUser(null);
  }

  /// The transport cleared a session the server refused to renew. A signed-in
  /// user is told why they are leaving: the shell sends them to sign-in and
  /// shows the expiry as a translated toast.
  @override
  void onSessionLost() {
    final wasSignedIn = signedInUser != null;
    _setUser(null);
    if (wasSignedIn) _failures.add(const SessionExpiredFailure());
  }

  /// Settles on signed in / signed out and publishes it — only when it
  /// changed, so a lost session nobody was signed in to tells the shell nothing.
  void _setUser(UserEntity? user) {
    final before = viewState;
    updateState(
      state: const ViewState.success(),
      data: user,
      retainOldData: false,
    );
    if (viewState != before) _authStream.updateAuthStatus(user);
  }

  @override
  void dispose() {
    _failures.close();
    super.dispose();
  }

  /// A 401 is a credential problem; every other failure keeps only its code.
  /// A network failure has no HTTP status, so it is never read as one, and a
  /// 403 is a locked account, not a wrong password.
  static AuthErrorState mapAuthFailure(AppFailure<dynamic> failure) {
    return switch (failure) {
      AuthFailure(code: 401) => const AuthErrorState.invalidCredentials(),
      _ => AuthErrorState.failed(code: failure.code),
    };
  }
}
