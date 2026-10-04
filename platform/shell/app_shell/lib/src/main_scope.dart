import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:material_ui/material_ui.dart';

import 'app_material_wrapper.dart';

/// MainScope is responsible for initializing the app, displaying a splash screen,
/// and transitioning to the main application once initialization is complete.
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
      // Preserve the splash screen until initialization is complete.
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      // The splash stays exactly as long as initialization takes — no
      // artificial minimum on top of it.
      try {
        await initService();
      } catch (_) {
        // Hand the screen back before the error reaches the caller: a native
        // splash that is still preserved would hide the boot error screen
        // for good.
        _removeNativeSplash();
        rethrow;
      }

      // Remove the splash screen after initialization.
      _removeNativeSplash();

      // Run the app with the root widget wrapped in a responsive wrapper.
      runApp(_ResponsiveWrapper(display: display, child: root));
      return;
    }

    // Remove the splash screen after initialization.
    _removeNativeSplash();

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

/// Removes the native splash kept by `FlutterNativeSplash.preserve`.
///
/// Skipped on the web: no app here generates a web splash, so the plugin has
/// no web side and `remove()` throws `PlatformException(removeSplashFromWeb)`,
/// which would reach the crash reporter on every start.
void _removeNativeSplash() {
  if (kIsWeb) return;
  FlutterNativeSplash.remove();
}
