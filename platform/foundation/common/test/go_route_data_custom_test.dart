import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class _Analytics implements IAnalytics {
  final screens = <String>[];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {}

  @override
  Future<void> setCurrentScreen(String screenName) async =>
      screens.add(screenName);
}

class _PlainRoute extends GoRouteDataCustom {
  const _PlainRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const Text('plain');
}

class _LockedRoute extends GoRouteDataCustom {
  const _LockedRoute();

  @override
  bool get canPop => false;

  @override
  ValueKey<Object?>? get pageKey => const ValueKey<Object?>('locked-key');

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const Text('locked');
}

/// `GoRouteDataCustom` builds one page shape per platform, and on every one of
/// them the child sits inside a `RouteAwareWidget` (so a screen view is
/// reported), honours `canPop` and `pageKey`.
void main() {
  late RouteObserver<ModalRoute<void>> observer;

  setUp(() {
    observer = RouteObserver<ModalRoute<void>>();
    RouteAwareWidget.observer = observer;
  });

  tearDown(() async {
    RouteAwareWidget.observer = null;
    await getIt.reset();
  });

  /// A widget test run as [platform]; the override is cleared before the
  /// framework's invariant check, which runs before any tearDown.
  void platformTest(
    String description,
    TargetPlatform platform,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// Pumps a router whose single route builds its page with [route] and
  /// returns the page it produced.
  Future<Page<void>> pumpRoute(
    WidgetTester tester,
    GoRouteDataCustom route,
  ) async {
    late Page<void> built;
    final router = GoRouter(
      observers: [observer],
      routes: [
        GoRoute(
          path: '/',
          name: 'home-screen',
          pageBuilder: (context, state) =>
              built = route.buildPage(context, state),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return built;
  }

  platformTest(
    'android: a custom transition page that reports the screen',
    TargetPlatform.android,
    (tester) async {
      final analytics = _Analytics();
      getIt.registerSingleton<IAnalytics>(analytics);

      final page = await pumpRoute(tester, const _PlainRoute());

      expect(page, isA<CustomTransitionPage<void>>());
      expect(find.text('plain'), findsOneWidget);
      expect(find.byType(RouteAwareWidget), findsOneWidget);
      expect(analytics.screens, ['home-screen']);
    },
  );

  platformTest(
    'iOS: a CupertinoPage that reports the screen',
    TargetPlatform.iOS,
    (tester) async {
      final analytics = _Analytics();
      getIt.registerSingleton<IAnalytics>(analytics);

      final page = await pumpRoute(tester, const _PlainRoute());

      expect(page, isA<CupertinoPage<void>>());
      expect(analytics.screens, ['home-screen']);
    },
  );

  platformTest(
    'canPop and pageKey overrides reach the page',
    TargetPlatform.iOS,
    (tester) async {
      final page = await pumpRoute(tester, const _LockedRoute());

      expect(page.canPop, isFalse);
      expect(page.key, const ValueKey<Object?>('locked-key'));
    },
  );

  platformTest(
    'defaults: popping allowed, the key comes from the state',
    TargetPlatform.iOS,
    (tester) async {
      final page = await pumpRoute(tester, const _PlainRoute());

      expect(page.canPop, isTrue);
      expect(page.key, isNotNull);
      expect(page.key, isNot(const ValueKey<Object?>('locked-key')));
    },
  );

  group('web (routePageFor with isWeb)', () {
    Future<Page<void>> pumpWeb(
      WidgetTester tester, {
      required bool canPop,
      ValueKey<Object?>? pageKey,
    }) async {
      late Page<void> built;
      final router = GoRouter(
        observers: [observer],
        routes: [
          GoRoute(
            path: '/',
            name: 'web-screen',
            pageBuilder: (context, state) => built = routePageFor(
              state: state,
              child: const Text('web child'),
              canPop: canPop,
              pageKey: pageKey,
              isWeb: true,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return built;
    }

    testWidgets('a MaterialPage that still reports the screen', (
      tester,
    ) async {
      final analytics = _Analytics();
      getIt.registerSingleton<IAnalytics>(analytics);

      final page = await pumpWeb(tester, canPop: true);

      expect(page, isA<MaterialPage<void>>());
      expect(find.text('web child'), findsOneWidget);
      expect(analytics.screens, ['web-screen']);
    });

    testWidgets('canPop and pageKey are honoured', (tester) async {
      final page = await pumpWeb(
        tester,
        canPop: false,
        pageKey: const ValueKey<Object?>('web-key'),
      );

      expect(page.canPop, isFalse);
      expect(page.key, const ValueKey<Object?>('web-key'));
    });
  });
}
