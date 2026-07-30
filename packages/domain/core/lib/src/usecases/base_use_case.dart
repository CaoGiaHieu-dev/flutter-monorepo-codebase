import 'dart:async';

import '../repositories/result.dart';

/// Base class for all use cases in the application
///
/// Use cases represent business logic operations and follow the Single
/// Responsibility Principle. Each use case should do one thing well.
///
/// Simplified design:
/// - No validation logic (params validate themselves at construction)
/// - Returns Result<RType> for consistent error handling
/// - Trusts that params are already validated
///
/// Example:
/// ```dart
/// class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
///   LoginUseCase(this._authRepository);
///
///   final IAuthRepository _authRepository;
///
///   @override
///   Future<Result<UserEntity>> call(LoginParams params) async {
///     // Params are already validated at construction
///     return await _authRepository.login(params);
///   }
/// }
/// ```
abstract class BaseUseCase<RType, Params> {
  /// Execute the use case with given parameters
  ///
  /// Parameters are expected to be already validated at construction time.
  /// Returns Result<RType> containing either Success with data or Failure with error.
  FutureOr<Result<RType>> call(Params params);
}
