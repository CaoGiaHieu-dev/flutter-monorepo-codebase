import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_splash.dart';

/// Publishes this feature's [SplashPage] to the app shell.
///
/// The shell resolves [IAppSplashScreen] optionally, so registering here is
/// what makes a Dart splash appear at all — remove this package and the shell
/// falls back to the native splash without any edit on its side.
@LazySingleton(as: IAppSplashScreen)
class SplashScreenImpl implements IAppSplashScreen {
  @override
  Widget build() => const SplashPage();
}
