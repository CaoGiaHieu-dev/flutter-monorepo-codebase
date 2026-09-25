import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../services/auth_status_stream_impl.dart';
import 'auth_error_state.dart';

/// Global auth controller, and the auth feature's side of two `core_di`
/// contracts.
///
/// Implementing [ISessionState] and [ISessionRefreshListenable] here is what
/// lets the app shell drive its boot redirect and refresh routing without
/// importing this package — delete `feature_auth` and the shell's optional
/// lookups simply return `null`.
@lazySingleton
class AuthProvider extends BaseProvider<UserEntity>
    implements ISessionState, ISessionRefreshListenable {
  AuthProvider(
    this._loginUseCase,
    this._logoutUseCase,
    this._refreshTokenUseCase,
    this._authStream,
  ) : super();

  final LoginUseCase _loginUseCase;
  final LogoutUseCase _logoutUseCase;
  final RefreshTokenUseCase _refreshTokenUseCase;
  final AuthStatusStreamImpl _authStream;

  StreamSubscription<ViewStateModel<UserEntity>>? _authSubscription;

  final _failureController = StreamController<SessionFailure>.broadcast();

  /// Marks whether the first session restore has finished.
  /// Used by the shell to ignore the bootstrap success it already handled.
  bool _hasRestoredSession = false;

  @override
  bool get hasRestoredSession => _hasRestoredSession;

  // --- ISessionState -----------------------------------------------------
  //
  // The session view the app shell consumes. `sessionChanges` reuses the same
  // broadcast stream `ISessionStatusStream` publishes, so shell and features
  // observe one source of truth rather than two that can drift.

  @override
  SessionPrincipal? get signedInUser => AuthStatusStreamImpl.toPrincipal(data);

  @override
  Stream<SessionPrincipal?> get sessionChanges =>
      _authStream.sessionStatusStream;

  @override
  Stream<SessionFailure> get sessionFailures => _failureController.stream;

  @override
  Future<void> initialize() async {
    updateState(state: const ViewState.loading());

    _authSubscription ??= listen(_syncAuthStream);
    await _restoreSession();
    await super.initialize();
  }

  /// Fans this provider's state out to the two neutral channels.
  ///
  /// Hooking both here — rather than inside [login] — means every error
  /// transition is published, including ones from operations that supply no
  /// `errorStateBuilder` (e.g. [logout]).
  void _syncAuthStream(ViewStateModel<UserEntity> value) {
    if (value.isSuccess) {
      _authStream.updateAuthStatus(value.data);
      return;
    }
    if (value.isError) {
      _failureController.add(_toSessionFailure(value));
    }
  }

  /// Translates this feature's error state into the shell-facing contract.
  ///
  /// Classification stays here because only the auth feature knows what its
  /// backend's codes mean; the shell just picks a string per variant.
  SessionFailure _toSessionFailure(ViewStateModel<UserEntity> value) {
    final error = value.state.whenOrNull(error: (error) => error);
    if (error is AuthErrorState) {
      return error.maybeWhen(
        invalidCredentials: () => const SessionInvalidCredentialsFailure(),
        userNotFound: () => const SessionUserNotFoundFailure(),
        serverError: (message, code) =>
            SessionServerFailure(message: message, code: code),
        orElse: () => const SessionUnknownFailure(),
      );
    }
    return const SessionUnknownFailure();
  }

  Future<void> _restoreSession() async {
    try {
      final result = await _refreshTokenUseCase(const NoParams());
      await result.whenAsync(
        success: (user) {
          updateState(state: const ViewState.success(), data: user);
        },
        failure: (_) => _setLoggedOut(),
        none: _setLoggedOut,
        cancel: () {},
      );
    } catch (e) {
      DynamicLogger.log('Session restore failed: $e');
      _setLoggedOut();
    } finally {
      _hasRestoredSession = true;
    }
  }

  void _setLoggedOut() {
    updateState(
      state: const ViewState.success(),
      data: null,
      retainOldData: false,
    );
  }

  Future<void> login(String email, String password) async {
    updateState(state: const ViewState.loading());
    await executeOperation(
      OperationConfig(
        operation: () =>
            _loginUseCase(LoginParams(email: email, password: password)),
        onSuccess: (user) async {
          DynamicLogger.log('Login successful for user: ${user?.name}');
        },
        errorStateBuilder: mapAuthFailure,
      ),
    );
  }

  /// Clears the session. Navigation is handled by the app shell, which listens
  /// to [sessionChanges] — do not navigate from here.
  ///
  /// Clearing local storage is synchronous and cannot meaningfully fail, so
  /// this skips `executeOperation` — [login] is where that pattern is shown.
  /// The transport cleared a session the server refused to renew; the stored
  /// credentials are already gone, so only the state changes.
  @override
  void onSessionLost() => _setLoggedOut();

  Future<void> logout() async {
    _logoutUseCase(const NoParams());
    _setLoggedOut();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _failureController.close();
    super.dispose();
  }

  /// Classifies a failed sign-in into this feature's error state.
  ///
  /// Matches what `ErrorHandler` actually produces: an HTTP 401/403 arrives
  /// as an [AuthFailure] carrying that status, and every other 4xx/5xx — 404
  /// included — as a [ServerFailure] carrying its status. This used to match
  /// `network` failures with codes 401 and 404, which `ErrorHandler` never
  /// produces (a network failure has no HTTP status), so a wrong password
  /// and an unknown user both fell through to a generic server error.
  ///
  /// A 403 stays a server error with the backend's message: it means "not
  /// allowed" (a disabled or locked account), not "wrong password".
  static ErrorState? mapAuthFailure(AppFailure<dynamic> failure) {
    return failure.whenOrNull(
      auth: (message, code, data) {
        if (code == 401) return const AuthErrorState.invalidCredentials();
        return AuthErrorState.serverError(message: message, code: code);
      },
      server: (message, code, data) {
        if (code == 404) return const AuthErrorState.userNotFound();
        return AuthErrorState.serverError(message: message, code: code);
      },
      network: (message, code, data) =>
          AuthErrorState.serverError(message: message, code: code),
    );
  }
}
