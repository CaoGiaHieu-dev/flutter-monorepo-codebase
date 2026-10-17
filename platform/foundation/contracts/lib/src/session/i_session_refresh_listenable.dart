import 'package:flutter/foundation.dart';

/// Neutral [Listenable] the router rebuilds on when the session changes.
///
/// `GoRouter.refreshListenable` needs *something that notifies*; it does not
/// care what. Wiring `AuthProvider` straight into it forced `app_router.dart`
/// to import `feature_auth` purely for the type, so removing the auth module
/// broke routing at compile time even though the value was already looked up
/// with `getItOrNull`.
///
/// ```dart
/// GoRouter(
///   refreshListenable: getItOrNull<ISessionRefreshListenable>(),
///   // …
/// )
/// ```
///
/// `refreshListenable` is nullable, so a build with no session owner simply
/// passes `null` and the router never refreshes on session changes — correct
/// behaviour when there are no session changes to react to.
///
/// ## Owner side
///
/// Any `ChangeNotifier` already satisfies [Listenable], so the session
/// owner's global controller implements this with no extra code and is bound
/// through a DI `@module`:
///
/// ```dart
/// @module
/// abstract class AuthDiModule {
///   @lazySingleton
///   ISessionRefreshListenable bindRefreshListenable(AuthProvider provider) =>
///       provider;
/// }
/// ```
abstract class ISessionRefreshListenable implements Listenable {}
