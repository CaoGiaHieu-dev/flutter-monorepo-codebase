import 'package:flutter/widgets.dart';

/// Lets a feature install its own inherited widgets around the app's
/// `MaterialApp` without the shell naming them.
///
/// Some features expose a global controller their own pages read from the
/// widget tree (`context.read<AuthProvider>()`, a `BlocProvider`, …). Someone
/// has to mount it above the router. Doing that in the shell meant
/// `app_material_wrapper.dart` importing `feature_auth` for the
/// `ChangeNotifierProvider<AuthProvider>` *type* — a hard reference that
/// `getItOrNull` cannot soften, and the last thing keeping the auth feature
/// from being removable.
///
/// ## Deliberately state-management agnostic
///
/// [wrap] returns a plain `Widget` rather than a `provider` type, so `core_di`
/// stays free of any state-management dependency. A Provider feature returns a
/// `ChangeNotifierProvider`, a BLoC feature returns a `BlocProvider`, and
/// neither forces the other's package on the rest of the app.
///
/// ## Composition
///
/// The shell folds every registered wrapper around the app, lowest [order]
/// applied first (so it ends up innermost). Missing wrappers are not an error:
/// `getAllOrEmpty` yields nothing and the app is built unwrapped.
///
/// ```dart
/// @LazySingleton(as: IAppTreeWrapper)
/// class AuthTreeWrapper implements IAppTreeWrapper {
///   @override
///   int get order => 0;
///
///   @override
///   Widget wrap(BuildContext context, Widget child) =>
///       ChangeNotifierProvider<AuthProvider>.value(
///         value: getIt<AuthProvider>(),
///         child: child,
///       );
/// }
/// ```
abstract class IAppTreeWrapper {
  /// Relative position in the fold; lower values end up closer to the app.
  ///
  /// Only matters when one wrapper must be able to read another's value.
  int get order => 0;

  /// Returns [child] wrapped in whatever this feature needs above the router.
  Widget wrap(BuildContext context, Widget child);
}
