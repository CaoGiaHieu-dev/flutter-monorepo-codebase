import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import 'app_material_wrapper.dart';

/// MainScope is responsible for initializing the app and transitioning to the
/// main application once initialization is complete.
///
/// With a Dart [splashScreen] it shows that splash while initialization runs.
/// Without one it holds the first frame (`deferFirstFrame`) until
/// initialization ends, on every platform: the native launch screen stays up
/// on Android and iOS, and nothing half-built is painted on the web or the
/// desktop. The hold is released whether initialization succeeds or throws,
/// so a failed boot can always show its error screen (RULE-83).
class MainScope {
  /// Creates an instance of MainScope.
  ///
  /// [splashScreen] is the widget to be displayed while the app is initializing.
  /// [root] is the root widget of the application to be displayed after initialization.
  /// [initService] is a function that performs any necessary initialization tasks.
  /// [display] is the app's `DisplayProfile`: the design artboard, the
  /// per-window-class scale policy and the OS font-size cap. The template
  /// defaults when none is given.
  const MainScope({
    this.splashScreen,
    required this.root,
    required this.initService,
    this.display = const DisplayProfile(),
  });

  /// The splash screen widget to be displayed while the app is initializing.
  final Widget? splashScreen;

  /// The root widget of the application to be displayed after initialization.
  final Widget root;

  /// A function that performs any necessary initialization tasks.
  final Future<void> Function() initService;

  /// How the UI is sized and scaled for this app.
  final DisplayProfile display;

  /// Runs the application, displaying the splash screen initially and then
  /// transitioning to the main application once initialization is complete.
  Future<void> run() async {
    // Ensure that widget binding is initialized.
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

    // Check if a splash screen is provided.
    if (splashScreen == null) {
      // SplashMode.native: hold the first frame until initialization is
      // done. On Android and iOS the launch screen stays up meanwhile; on
      // the web and the desktop nothing half-built is painted. Released in
      // `finally`, so a failed boot shows its error screen everywhere — the
      // web once skipped this release and stayed blank (RULE-83).
      widgetsBinding.deferFirstFrame();
      try {
        await initService();
      } finally {
        widgetsBinding.allowFirstFrame();
      }
      runApp(_ResponsiveWrapper(display: display, child: root));
      return;
    }

    // Create an AppMaterialWrapper with the splash screen.
    final splash = AppMaterialWrapper(home: splashScreen, display: display);

    // Use a ValueNotifier to manage the current widget being displayed.
    final widget = ValueNotifier<Widget>(splash);

    // Run the app with a ValueListenableBuilder to listen for widget changes.
    runApp(
      ValueListenableBuilder<Widget>(
        valueListenable: widget,
        builder: (context, value, _) {
          return _ResponsiveWrapper(
            display: display,
            child: AnimatedSwitcher(
              duration: kThemeAnimationDuration,
              child: value,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        },
      ),
    );

    // Wait for the end of the current frame.
    await WidgetsBinding.instance.endOfFrame;

    // The splash stays exactly as long as initialization takes.
    await initService();

    // Update the widget to the root widget after initialization.
    widget.value = root;
  }
}

/// A wrapper widget that initializes screen utilities and adapts the UI for different screen sizes.
///
/// Everything it decides is the app's [DisplayProfile]: the artboard, the
/// scale policy of each window class and split-screen mode. The defaults are
/// the template's own: the 375x812 phone artboard, a window class `expanded`
/// laid out in real logical pixels, every other class shrinking to fit and
/// never growing.
class _ResponsiveWrapper extends StatelessWidget {
  /// Creates an instance of _ResponsiveWrapper.
  ///
  /// [child] is the widget to be wrapped with screen utility initialization.
  const _ResponsiveWrapper({required this.display, required this.child});

  /// The app's display settings.
  final DisplayProfile display;

  /// The widget to be wrapped with screen utility initialization.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ResponsiveInit(
      designSize: Size(display.designSize.width, display.designSize.height),
      // Left at their defaults, `scaleBounds` and `textScaleBounds` are
      // `ScaleBounds.downOnly()`: a phone narrower than the artboard scales
      // the design down to fit, and nothing ever scales up — a tablet or a
      // desktop window draws it 1:1 and gives the extra room to the layout
      // (see `AdaptiveLayout`). A class the app lists in
      // `DisplayProfile.scale` is scaled by its own policy instead — the
      // template lists `expanded`: tablets in landscape, unfolded foldables
      // and desktop windows are laid out in real logical pixels. (Phones
      // never get there: the shell locks phone-sized displays to portrait —
      // see `AppInitializer.preferredOrientationsFor`.) Without it, a laptop
      // window shorter than the 812-tall phone artboard would still shrink
      // every vertical gap and radius.
      profiles: {
        for (final entry in display.scale.entries)
          WindowSizeClass.values.byName(entry.key.name): _profileOf(
            entry.value,
          ),
      },
      // Keeps height scaling sane when the app is a short split-screen pane.
      splitScreenMode: display.splitScreenMode,
      child: child,
    );
  }
}

/// The `core_responsive` profile of one window class's [ScalePolicy].
ResponsiveProfile _profileOf(ScalePolicy policy) => switch (policy) {
  FixedScale() => const ResponsiveProfile(
    scaleBounds: ScaleBounds.fixed(),
    textScaleBounds: ScaleBounds.fixed(),
  ),
  DownOnlyScale() => const ResponsiveProfile(
    scaleBounds: ScaleBounds.downOnly(),
    textScaleBounds: ScaleBounds.downOnly(),
  ),
  BoundedScale(:final max, :final textMax) => ResponsiveProfile(
    scaleBounds: ScaleBounds(max: max ?? _designFactor),
    textScaleBounds: ScaleBounds(max: textMax ?? max ?? _designFactor),
  ),
};

/// The factor at which a design value is drawn at exactly its design size.
const double _designFactor = ResponsiveConstants.DESIGN_SCALE_FACTOR;
