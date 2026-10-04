import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pump(WidgetTester tester, Widget body) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [ThemeSystemExtension.light]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => ResponsiveInit(
        child: Overlay.wrap(child: AppOverlayInitializer(child: child!)),
      ),
      home: Scaffold(body: body),
    ),
  );
  // AppOverlay is created after the first frame.
  await tester.pump();
}

/// What a screen reader gets from the kit's two transient feedback widgets:
/// a toast that is announced when it appears, and a spinner that says what
/// it is (WCAG 4.1.3 Status Messages, 1.1.1 Non-text Content).
void main() {
  testWidgets('a toast is a live region, so its message is announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const Text('page'));

    AppOverlay.showToast(content: 'Invalid credentials');
    await tester.pump();

    expect(
      tester.getSemantics(find.text('Invalid credentials')),
      isSemantics(label: 'Invalid credentials', isLiveRegion: true),
    );

    AppOverlay.removeToastOverlay();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('the loading spinner is labelled with the translated word', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const LoadingWidget());

    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('a host with no localisation delegates still builds the '
      'spinner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [ThemeSystemExtension.light]),
        home: const ResponsiveInit(child: Scaffold(body: LoadingWidget())),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
