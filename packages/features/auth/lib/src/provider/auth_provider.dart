import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../services/services.dart';
import 'auth_error_state.dart';

/// Global auth controller, and the auth feature's side of two `core_di`
/// contracts.
///
/// Implementing [IAuthSessionState] and [IAuthRefreshListenable] here is what
/// lets the app shell drive its boot redirect and refresh routing without
/// importing this package — delete `feature_auth` and the shell's optional
/// lookups simply return `null`.
@lazySingleton
class AuthProvider extends BaseProvider<UserEntity>
    implements IAuthSessionState, IAuthRefreshListenable {
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

  bool get isAuthenticated => isSuccess && data != null;

  UserEntity? get currentUser => isAuthenticated ? data : null;

  StreamSubscription<ViewStateModel<UserEntity>>? _authSubscription;

  final _failureController = StreamController<AuthSessionFailure>.broadcast();

  /// Marks whether the first session restore has finished.
  /// Used by the shell to ignore the bootstrap success it already handled.
  bool _hasRestoredSession = false;

  @override
  bool get hasRestoredSession => _hasRestoredSession;

  // --- IAuthSessionState -----------------------------------------------------
  //
  // The session view the app shell consumes. `sessionChanges` reuses the same
  // broadcast stream `IAuthStatusStream` publishes, so shell and features
  // observe one source of truth rather than two that can drift.

  @override
  UserEntity? get signedInUser => data;

  @override
  Stream<UserEntity?> get sessionChanges => _authStream.authStatusStream;

  @override
  Stream<AuthSessionFailure> get sessionFailures => _failureController.stream;

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
  /// `errorStateBuilder` (e.g. [logout]). That matches what the shell's
  /// previous listener saw when it observed the raw view state.
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
  AuthSessionFailure _toSessionFailure(ViewStateModel<UserEntity> value) {
    final error = value.state.whenOrNull(error: (error) => error);
    if (error is AuthErrorState) {
      return error.maybeWhen(
        invalidCredentials: () => const AuthInvalidCredentialsFailure(),
        userNotFound: () => const AuthUserNotFoundFailure(),
        serverError: (message, code) =>
            AuthServerFailure(message: message, code: code),
        orElse: () => const AuthUnknownFailure(),
      );
    }
    return const AuthUnknownFailure();
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
        errorStateBuilder: _mapAuthFailure,
      ),
    );
  }

  /// Clears the session. Navigation is handled by the app shell, which listens
  /// to [sessionChanges] — do not navigate from here.
  Future<void> logout() async {
    updateState(state: const ViewState.loading());
    executeOperation(
      OperationConfig(
        operation: () => _logoutUseCase(const NoParams()),
        showLoading: false,
        onSuccess: (_) async {},
      ),
    );
    _setLoggedOut();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _failureController.close();
    super.dispose();
  }

  ErrorState? _mapAuthFailure(AppFailure failure) {
    return failure.whenOrNull(
      server: (message, code, data) {
        return AuthErrorState.serverError(message: message, code: code);
      },
      network: (message, code, data) {
        if (code == 404) {
          return const AuthErrorState.userNotFound();
        }

        if (code == 401) {
          return const AuthErrorState.invalidCredentials();
        }

        return AuthErrorState.serverError(message: message, code: code);
      },
    );
  }
}
