import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/shell_fakes.dart';

/// `MainScope` without a Dart splash holds the first frame while the boot
/// runs, and releases it on every platform — the web once kept it held for
/// good and stayed a blank page (RULE-83).
///
/// The test binding calls `resetFirstFrameSent()` before each body, so
/// `sendFramesToEngine` is `false` exactly while a deferral is pending.
void main() {
  tearDown(getIt.reset);

  testWidgets('the native path holds frames until init completes', (
    tester,
  ) async {
    final gate = Completer<void>();
    final running = MainScope(
      root: const SizedBox(),
      initService: () => gate.future,
    ).run();

    expect(tester.binding.sendFramesToEngine, isFalse);

    gate.complete();
    await running;

    expect(tester.binding.sendFramesToEngine, isTrue);
  });

  testWidgets(
    'a throwing init releases the first frame before the error propagates',
    (tester) async {
      bool? framesWhenThrown;
      try {
        await MainScope(
          root: const SizedBox(),
          initService: () async => throw StateError('boot failed'),
        ).run();
      } on StateError {
        framesWhenThrown = tester.binding.sendFramesToEngine;
      }

      // Thrown at all, and with the frames already released: the shell's
      // boot-error screen can paint.
      expect(framesWhenThrown, isTrue);
    },
  );

  testWidgets('the Dart-splash path never defers', (tester) async {
    // What the splash's `AppMaterialWrapper` resolves.
    final router = AppRouter();
    getIt
      ..registerSingleton<ThemeProvider>(ThemeProvider(FakeThemeStorage()))
      ..registerSingleton<LanguageProvider>(
        LanguageProvider(FakeLanguageStorage()),
      )
      ..registerSingleton<AppRouter>(router)
      ..registerSingleton<DeeplinkProvider>(FakeDeeplinkProvider(router));
    final gate = Completer<void>();
    bool? framesDuringInit;
    final running = MainScope(
      splashScreen: const SizedBox(),
      root: const SizedBox(),
      initService: () {
        framesDuringInit = tester.binding.sendFramesToEngine;
        return gate.future;
      },
    ).run();

    expect(tester.binding.sendFramesToEngine, isTrue);
    // The Dart-splash path waits for the splash's first frame, then inits.
    await tester.pump();
    expect(framesDuringInit, isTrue);

    gate.complete();
    await running;
    expect(tester.binding.sendFramesToEngine, isTrue);

    // Let the splash-to-root cross-fade finish so nothing outlives the test.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
