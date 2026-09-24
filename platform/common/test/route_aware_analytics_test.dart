import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Analytics implements IAnalytics {
  final screens = <String>[];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {}

  @override
  Future<void> setCurrentScreen(String screenName) async =>
      screens.add(screenName);
}

/// `RouteAwareWidget` — what every `GoRouteDataCustom` page is wrapped in —
/// reports a screen view whenever its route becomes the visible one.
void main() {
  late RouteObserver<ModalRoute<void>> observer;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() {
    observer = RouteObserver<ModalRoute<void>>();
    RouteAwareWidget.observer = observer;
  });

  tearDown(() async {
    RouteAwareWidget.observer = null;
    await getIt.reset();
  });

  Route<void> page(String name) => MaterialPageRoute<void>(
    builder: (_) => RouteAwareWidget(name, child: Text(name)),
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        onGenerateRoute: (_) => page('first'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('push, push, pop: each visible screen is reported', (
    tester,
  ) async {
    final analytics = _Analytics();
    getIt.registerSingleton<IAnalytics>(analytics);
    await pumpApp(tester);

    navigatorKey.currentState!.push(page('second'));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(analytics.screens, ['first', 'second', 'first']);
  });

  testWidgets('no IAnalytics registered: nothing is sent, nothing throws', (
    tester,
  ) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(page('second'));
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
