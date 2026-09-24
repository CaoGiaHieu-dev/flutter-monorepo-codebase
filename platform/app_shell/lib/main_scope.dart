import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:material_ui/material_ui.dart';

import 'presentation/app_material_wrapper.dart';

/// Minimum delay time for splash screen to avoid flicker
const _minimumDelay = Duration(seconds: 2);

/// MainScope is responsible for initializing the app, displaying a splash screen,
/// and transitioning to the main application once initialization is complete.
class MainScope {
  /// Creates an instance of MainScope.
  ///
  /// [splashScreen] is the widget to be displayed while the app is initializing.
  /// [root] is the root widget of the application to be displayed after initialization.
  /// [initService] is a function that performs any necessary initialization tasks.
  const MainScope({
    this.splashScreen,
    required this.root,
    required this.initService,
  });

  /// The splash screen widget to be displayed while the app is initializing.
  final Widget? splashScreen;

  /// The root widget of the application to be displayed after initialization.
  final Widget root;

  /// A function that performs any necessary initialization tasks.
  final Future<void> Function() initService;

  /// Runs the application, displaying the splash screen initially and then
  /// transitioning to the main application once initialization is complete.
  Future<void> run() async {
    // Ensure that widget binding is initialized.
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

    // Check if a splash screen is provided.
    if (splashScreen == null) {
      // Preserve the splash screen until initialization is complete.
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      // Perform initialization tasks and delay for 2 seconds.
      await Future.wait([initService.call(), Future.delayed(_minimumDelay)]);

      // Remove the splash screen after initialization.
      FlutterNativeSplash.remove();

      // Run the app with the root widget wrapped in a responsive wrapper.
      runApp(_ResponsiveWrapper(child: root));
      return;
    }

    // Remove the splash screen after initialization.
    FlutterNativeSplash.remove();

    // Create an AppMaterialWrapper with the splash screen.
    final splash = AppMaterialWrapper(home: splashScreen);

    // Use a ValueNotifier to manage the current widget being displayed.
    final widget = ValueNotifier<Widget>(splash);

    // Run the app with a ValueListenableBuilder to listen for widget changes.
    runApp(
      ValueListenableBuilder<Widget>(
        valueListenable: widget,
        builder: (context, value, _) {
          return _ResponsiveWrapper(
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

    // Perform initialization tasks and delay for 2 seconds.
    await Future.wait([initService.call(), Future.delayed(_minimumDelay)]);

    // Update the widget to the root widget after initialization.
    widget.value = root;
  }
}

/// A wrapper widget that initializes screen utilities and adapts the UI for different screen sizes.
class _ResponsiveWrapper extends StatelessWidget {
  /// Creates an instance of _ResponsiveWrapper.
  ///
  /// [child] is the widget to be wrapped with screen utility initialization.
  const _ResponsiveWrapper({required this.child});

  /// The widget to be wrapped with screen utility initialization.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ResponsiveInit(
      // The phone artboard every window class starts from.
      designSize: AppConfig.design,
      // Left at their defaults, `scaleBounds` and `textScaleBounds` are
      // `ScaleBounds.downOnly()`: a phone narrower than the artboard scales
      // the design down to fit, and nothing ever scales up — a tablet or a
      // desktop window draws it 1:1 and gives the extra room to the layout
      // (see `AdaptiveLayout`). To let a class grow, opt in with a bound:
      // `ResponsiveProfile(scaleBounds: ScaleBounds(max: 1.2))`.
      profiles: const {
        // Tablets in landscape, unfolded foldables and desktop windows are
        // laid out in real logical pixels. (Phones never get here: the
        // shell locks phone-sized displays to portrait — see
        // `AppInitializer.preferredOrientationsFor`.) Without this, a laptop window
        // shorter than the 812-tall phone artboard would still shrink every
        // vertical gap and radius.
        WindowSizeClass.expanded: ResponsiveProfile(
          scaleBounds: ScaleBounds.fixed(),
          textScaleBounds: ScaleBounds.fixed(),
        ),
      },
      // Keeps height scaling sane when the app is a short split-screen pane.
      splitScreenMode: true,
      child: child,
    );
  }
}
