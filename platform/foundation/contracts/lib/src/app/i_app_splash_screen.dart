import 'package:flutter/widgets.dart';

/// Supplies the Dart-rendered splash screen shown while the app boots.
///
/// The app shell needs *a widget* during startup but must not know which
/// package draws it. Without this contract `main.dart` has to import
/// `feature_splash` for the `SplashPage` type, and deleting that package
/// breaks the entry point at compile time.
///
/// ## Optional by design
///
/// Resolve it with `getItOrNull<IAppSplashScreen>()`. When no feature
/// registers an implementation the shell simply passes `null` to `MainScope`,
/// which then keeps the **native** splash on screen until initialisation
/// finishes. A build without any splash feature is therefore still valid — it
/// just shows the platform splash instead of a Dart one.
///
/// ## Owner side
///
/// ```dart
/// @LazySingleton(as: IAppSplashScreen)
/// class SplashScreenImpl implements IAppSplashScreen {
///   @override
///   Widget build() => const SplashPage();
/// }
/// ```
abstract class IAppSplashScreen {
  /// Builds the splash widget handed to `MainScope.splashScreen`.
  Widget build();
}
