/// Where the app sends errors it wants a person to look at later — a crash
/// reporter such as Firebase Crashlytics or Sentry.
///
/// ## Optional by design
///
/// Nothing in the template implements it. The app shell resolves it with
/// `getItOrNull<IErrorReporter>()` at the moment an error arrives, so an app
/// that registers no reporter still boots and still prints its errors to the
/// console; it just sends them nowhere.
///
/// ## What reaches it
///
/// `runShellApp` (`platform_app_shell`) funnels every *uncaught* error here
/// with `fatal: true` — errors escaping the root zone, errors the framework
/// catches (`FlutterError.onError`: build, layout, paint, image decoding) and
/// errors escaping to the engine (`PlatformDispatcher.instance.onError`).
/// It also forwards, with `fatal: false`, the exceptions `ErrorHandler`
/// could not classify and turned into a generic "unknown error" failure —
/// the handled failures that most likely point at a bug.
///
/// ## Owner side
///
/// Register the implementation in the **app** (its own `lib/`, next to
/// `firebase_module.dart`), or in a package the app composes:
///
/// ```dart
/// @LazySingleton(as: IErrorReporter)
/// class CrashlyticsErrorReporter implements IErrorReporter {
///   @override
///   Future<void> recordError(
///     Object error,
///     StackTrace? stack, {
///     bool fatal = false,
///     String? reason,
///   }) => FirebaseCrashlytics.instance.recordError(
///     error,
///     stack,
///     fatal: fatal,
///     reason: reason,
///   );
///
///   @override
///   void log(String message) => FirebaseCrashlytics.instance.log(message);
/// }
/// ```
///
/// An implementation must not throw: the shell swallows what it throws
/// rather than report a reporter failure through the same reporter.
abstract class IErrorReporter {
  /// Records [error] with its [stack].
  ///
  /// [fatal] marks an error nothing caught — the shell's hooks pass `true`;
  /// handled failures pass `false`. [reason] is a short, human-readable
  /// description of where the error was caught.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  });

  /// Adds a breadcrumb that will be attached to the next recorded error.
  void log(String message);
}
