import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

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
      designSize: AppConfig.design,
      minTextAdapt: true,
      // Carried over verbatim from the previous package so type scale does not
      // shift under existing screens.
      //
      // > [!NOTE]
      // > Supplying a resolver overrides text scaling completely, so
      // > `minTextAdapt: true` above is inert while this is set. Drop the
      // > resolver to let `minTextAdapt` take effect (text would then scale by
      // > the smaller axis instead of by width) — that is a visual change, so
      // > make it deliberately rather than as a side effect.
      fontSizeResolver: (fontSize, metrics) {
        final display = View.of(context).display;
        final screenSize = display.size / display.devicePixelRatio;
        final scaleWidth = screenSize.width / AppConfig.design.width;

        return fontSize * scaleWidth;
      },
      splitScreenMode: true,
      child: child,
    );
  }
}
