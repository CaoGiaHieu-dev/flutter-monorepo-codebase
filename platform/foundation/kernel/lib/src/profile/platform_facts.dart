/// Whether the platform's native project is in the repository.
enum RunnerKind {
  /// The runner folder (`android/`, `ios/`, …) is committed in the app.
  committed,

  /// The platform is declared, but its runner folder is not committed: the
  /// app owner runs `flutter create --platforms=<p> .` to generate it.
  scaffold,
}

/// Which splash the app shows while it boots.
enum SplashMode {
  /// A Dart splash built from the app's `IAppSplashScreen`.
  dart,

  /// The native splash, kept (`FlutterNativeSplash.preserve`) until boot ends.
  native,
}

/// How the app locks the screen orientation on one platform.
enum OrientationPolicy {
  /// Phone-sized displays (shortest side below the phone threshold) are locked
  /// to portrait, larger displays rotate freely.
  phonesPortrait,

  /// Never locked.
  free,

  /// Always portrait.
  portrait,

  /// Always landscape.
  landscape,
}

/// A width × height in logical pixels. Both sides are positive: a size with no
/// area is refused where it is written, as a compile error in a `const`.
final class SizeSpec {
  const SizeSpec(this.width, this.height)
    : assert(
        width > 0 && height > 0,
        'a size needs a positive width and height',
      );

  final double width;
  final double height;
}

/// The window a desktop platform opens with.
///
/// The shell only *delivers* these sizes to the app's window hook; it brings
/// no window-management plugin.
final class WindowFacts {
  const WindowFacts({required this.initial, this.min});

  /// The size the window opens at.
  final SizeSpec initial;

  /// The smallest size the window may be resized to, or `null` for no floor.
  final SizeSpec? min;
}

/// What one platform does for this app.
///
/// Generated from the manifest with every field explicit, so a generated app
/// never depends on a Dart default. The defaults of a hand-built object —
/// [PlatformFacts.today] — equal what the template did before apps could
/// declare anything: push and deep links on, the Dart splash, phone-sized
/// displays locked to portrait.
final class PlatformFacts {
  const PlatformFacts({
    required this.runner,
    required this.splash,
    required this.orientation,
    required this.deepLinks,
    required this.push,
    this.window,
  });

  /// What a class gets when nobody told it better: the behaviour the template
  /// had before an app could declare its platforms.
  const PlatformFacts.today()
    : runner = RunnerKind.committed,
      splash = SplashMode.dart,
      orientation = OrientationPolicy.phonesPortrait,
      deepLinks = true,
      push = true,
      window = null;

  final RunnerKind runner;
  final SplashMode splash;
  final OrientationPolicy orientation;

  /// Whether the app subscribes to incoming links on this platform.
  final bool deepLinks;

  /// Whether push notifications are initialised on this platform.
  final bool push;

  /// The window a desktop platform opens with, or `null` when the app
  /// declares none.
  final WindowFacts? window;
}
