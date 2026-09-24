import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Mirrors the app shell: a router app whose `builder` wraps the Router in
/// an Overlay hosting [AppDialogControllerInitializer].
Future<GoRouter> _pumpApp(WidgetTester tester) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('first')),
        routes: [
          GoRoute(
            path: 'second',
            builder: (_, _) => const Scaffold(body: Text('second')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          Overlay.wrap(child: AppDialogControllerInitializer(child: child!)),
    ),
  );
  // The controller is created at the end of the first frame.
  await tester.pump();

  router.push('/second');
  await tester.pumpAndSettle();
  expect(find.text('second'), findsOneWidget);
  return router;
}

void main() {
  group('AppDialogController system back', () {
    testWidgets('a non-dismissible dialog swallows the back', (tester) async {
      await _pumpApp(tester);

      AppDialogController.show<void>(builder: (_) => const Text('dialog'));
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('dialog'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('a barrierDismissible dialog is dismissed by the back', (
      tester,
    ) async {
      await _pumpApp(tester);

      var closed = false;
      AppDialogController.show<void>(
        barrierDismissible: true,
        builder: (_) => const Text('dialog'),
      ).then((_) => closed = true);
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('dialog'), findsNothing);
      expect(closed, isTrue);
      // The page behind the dialog was not popped.
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('with no dialog visible the back pops the page', (
      tester,
    ) async {
      await _pumpApp(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('second'), findsNothing);
      expect(find.text('first'), findsOneWidget);
    });
  });
}
