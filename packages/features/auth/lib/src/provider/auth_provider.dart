import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../services/services.dart';
import 'auth_error_state.dart';

@lazySingleton
class AuthProvider extends BaseProvider<UserEntity> {
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

  /// Marks whether the first session restore has finished.
  /// Used by the shell [ProviderStateListener] to ignore bootstrap success.
  bool _hasRestoredSession = false;
  bool get hasRestoredSession => _hasRestoredSession;

  @override
  Future<void> initialize() async {
    updateState(state: const ViewState.loading());

    _authSubscription ??= listen(_syncAuthStream);
    await _restoreSession();
    await super.initialize();
  }

  void _syncAuthStream(ViewStateModel<UserEntity> value) {
    if (!value.isSuccess) return;
    _authStream.updateAuthStatus(value.data);
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

  /// Clears the session. Navigation is handled by [ProviderStateListener]
  /// in the app shell — do not navigate from here.
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
