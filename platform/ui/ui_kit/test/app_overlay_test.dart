import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [ThemeSystemExtension.light]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => ResponsiveInit(
        child: Overlay.wrap(child: AppOverlayInitializer(child: child!)),
      ),
      home: const Scaffold(body: Text('page')),
    ),
  );
  // AppOverlay is created after the first frame.
  await tester.pump();
}

void main() {
  testWidgets('a dialog while a toast and the loading overlay are visible', (
    tester,
  ) async {
    await _pump(tester);

    AppOverlay.showLoading();
    AppOverlay.showToast(content: 'toast');
    unawaited(
      AppOverlay.showDialog<void>(builder: (_) => const Text('dialog')),
    );
    // The spinner never settles: pump past the transitions instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('dialog'), findsOneWidget);
    expect(find.text('toast'), findsOneWidget);
    expect(find.byType(LoadingOverlayWidget), findsOneWidget);

    AppOverlay.removeToastOverlay();
    AppOverlay.dismissDialog<void>();
    AppOverlay.removeLoadingOverlay();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('dialog'), findsNothing);
    expect(find.text('toast'), findsNothing);
    expect(find.byType(LoadingOverlayWidget), findsNothing);
  });

  testWidgets('a toast removes itself after its duration', (tester) async {
    await _pump(tester);

    AppOverlay.showToast(
      content: 'toast',
      duration: const Duration(seconds: 1),
    );
    await tester.pump();
    expect(find.text('toast'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('toast'), findsNothing);
  });

  testWidgets('dismissDialog completes the future with its result', (
    tester,
  ) async {
    await _pump(tester);

    int? result;
    unawaited(
      AppOverlay.showDialog<int>(
        builder: (_) => const Text('dialog'),
      ).then((value) => result = value),
    );
    await tester.pumpAndSettle();

    AppOverlay.dismissDialog(result: 7);
    await tester.pumpAndSettle();

    expect(result, 7);
    expect(find.text('dialog'), findsNothing);
  });

  testWidgets('a visible identity ignores a repeat request', (tester) async {
    await _pump(tester);

    unawaited(
      AppOverlay.showDialog<void>(
        identity: 'retry',
        builder: (_) => const Text('first'),
      ),
    );
    await tester.pumpAndSettle();

    var repeatCompleted = false;
    unawaited(
      AppOverlay.showDialog<void>(
        identity: 'retry',
        builder: (_) => const Text('second'),
      ).then((_) => repeatCompleted = true),
    );
    await tester.pumpAndSettle();

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);
    expect(repeatCompleted, isTrue);

    AppOverlay.clearDialogs();
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
  });

  testWidgets('the barrier dismisses a barrierDismissible dialog', (
    tester,
  ) async {
    await _pump(tester);

    var closed = false;
    unawaited(
      AppOverlay.showDialog<void>(
        barrierDismissible: true,
        builder: (_) => const Text('dialog'),
      ).then((_) => closed = true),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(find.text('dialog'), findsNothing);
  });

  testWidgets('RetryDialog closes itself before calling back', (tester) async {
    await _pump(tester);

    var retried = false;
    unawaited(
      AppOverlay.showDialog<void>(
        builder: (_) => RetryDialog(onRetry: () => retried = true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(retried, isTrue);
    expect(find.byType(RetryDialog), findsNothing);
  });
}
