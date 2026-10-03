import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:core_common/core_common.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

/// What a test that runs `runShellApp` must put back afterwards: the shell
/// installs global error hooks and certificate handling, and the test binding
/// restores only `FlutterError.onError` itself.
class BootHarness {
  late HttpOverrides? _httpOverrides;
  late bool Function(Object, StackTrace)? _platformOnError;

  void setUp() {
    _httpOverrides = HttpOverrides.current;
    _platformOnError = PlatformDispatcher.instance.onError;
    AppInitializer.debugResetBeforeRunApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (_) async => ['wifi'],
        );
  }

  Future<void> tearDown() async {
    HttpOverrides.global = _httpOverrides;
    PlatformDispatcher.instance.onError = _platformOnError;
    ErrorHandler.onUnclassifiedError = null;
    debugAppPlatformOverride = null;
    AppInitializer.debugResetBeforeRunApp();
    await getIt.reset();
  }
}

/// Lets the app zone make progress — real async work, which the test clock
/// does not drive — until [done] holds or about two seconds have passed.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  });
  await tester.pump();
}

/// Lets a finished boot settle, then removes the app so nothing outlives the
/// test.
Future<void> settleAndTearDown(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
}
