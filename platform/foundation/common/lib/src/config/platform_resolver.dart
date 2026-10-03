import 'package:flutter/foundation.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// Which [AppPlatform] this run is on — the one place that reads
/// `kIsWeb` / `defaultTargetPlatform`, so every other class asks the app's
/// declared `PlatformFacts` instead of forking on the operating system.
///
/// The web is checked first: on the web `defaultTargetPlatform` reports the
/// browser's operating system, and `dart:io`'s `Platform` throws.
///
/// [isWeb] and [target] stand in for the real values — a test names the
/// platform it means. With both left out, [debugAppPlatformOverride] (when a
/// test sets it) answers, else the real device does.
///
/// Throws [UnsupportedError] on Fuchsia: no app declares it, and guessing a
/// platform would hide the gap.
AppPlatform resolveAppPlatform({bool? isWeb, TargetPlatform? target}) {
  if (isWeb == null && target == null) {
    final override = debugAppPlatformOverride;
    if (override != null) return override;
  }
  if (isWeb ?? kIsWeb) return AppPlatform.web;
  return switch (target ?? defaultTargetPlatform) {
    TargetPlatform.android => AppPlatform.android,
    TargetPlatform.iOS => AppPlatform.ios,
    TargetPlatform.macOS => AppPlatform.macos,
    TargetPlatform.windows => AppPlatform.windows,
    TargetPlatform.linux => AppPlatform.linux,
    TargetPlatform.fuchsia => throw UnsupportedError(
      'Fuchsia is not an app platform: AppPlatform has no value for it.',
    ),
  };
}

/// Makes [resolveAppPlatform] answer this platform when called with no
/// arguments. A test on the VM reports Android and never the web; this lets it
/// run the boot as another platform. `null` (the default) reads the device.
@visibleForTesting
AppPlatform? debugAppPlatformOverride;
