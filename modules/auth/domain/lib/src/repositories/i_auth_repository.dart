import 'package:domain_core/domain_core.dart';

import '../entities/user/user.dart';
import '../params/auth_params/login_params.dart';

/// Abstract repository interface for authentication operations
///
/// This repository defines the contract for all authentication-related
/// operations in the domain layer. It provides a clean interface that
/// abstracts the underlying data sources and network operations, allowing
/// the domain layer to remain independent of implementation details.
///
/// The repository follows Clean Architecture principles by:
/// - Defining business-focused method signatures
/// - Using domain entities and value objects as parameters and return types
/// - Providing consistent error handling through Result pattern
/// - Abstracting away data source implementation details
/// - Following the Result pattern for explicit error handling
///
/// All authentication operations return [Result] to provide consistent
/// error handling and success/failure state management throughout the
/// application. This allows the presentation layer to handle authentication
/// states uniformly regardless of the underlying implementation.
///
/// Note: This repository focuses on authentication-specific operations
/// rather than implementing [BaseRepository] since auth operations are
/// quite different from standard CRUD operations.
///
/// Example implementation usage:
/// ```dart
/// class AuthRepositoryImpl implements IAuthRepository {
///   @override
///   Future<Result<UserEntity>> login(LoginParams params) async {
///     // Implementation details...
///   }
/// }
/// ```
abstract class IAuthRepository {
  /// Authenticates a user with the provided login credentials
  Future<Result<UserEntity>> login(LoginParams params);

  /// Authenticates a user using Google Sign-In
  Future<Result<UserEntity>> loginWithGoogle();

  /// Authenticates a user using Facebook Login
  Future<Result<UserEntity>> loginWithFacebook();

  /// Registers a new user with Email, Password, and Name
  Future<Result<UserEntity>> registerWithEmail(
    String email,
    String password,
    String name,
  );

  /// Fetches the currently authenticated user profile from the database
  Future<Result<UserEntity>> getCurrentUser();

  /// Updates the user profile in Firestore
  Future<Result<UserEntity>> updateUserProfile(UserEntity user);

  /// Refreshes the current authentication token
  Future<Result<UserEntity>> refreshToken();

  /// Logs out the current user and clears their local session.
  Result<void> logout();
}
