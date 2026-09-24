import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets the window to [size] and pumps [child] into it.
Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
}

/// A builder that renders a box keyed by its [name].
WidgetBuilder _slot(String name) =>
    (_) => SizedBox(key: ValueKey(name));

void main() {
  group('AdaptiveLayout', () {
    testWidgets('picks the slot for the window class', (tester) async {
      const cases = [
        (390.0, 'compact'),
        (700.0, 'medium'),
        (900.0, 'expanded'),
        (1300.0, 'large'),
        (1700.0, 'extraLarge'),
      ];
      final layout = AdaptiveLayout(
        compact: _slot('compact'),
        medium: _slot('medium'),
        expanded: _slot('expanded'),
        large: _slot('large'),
        extraLarge: _slot('extraLarge'),
      );

      for (final (width, slot) in cases) {
        await _pumpAt(tester, Size(width, 800), layout);

        expect(find.byKey(ValueKey(slot)), findsOneWidget, reason: '$width');
      }
    });

    testWidgets('a class with no slot uses the nearest smaller one', (
      tester,
    ) async {
      const cases = [
        (390.0, 'compact'),
        (700.0, 'compact'),
        (900.0, 'expanded'),
        (1300.0, 'expanded'),
        (1700.0, 'expanded'),
      ];
      final layout = AdaptiveLayout(
        compact: _slot('compact'),
        expanded: _slot('expanded'),
      );

      for (final (width, slot) in cases) {
        await _pumpAt(tester, Size(width, 800), layout);

        expect(find.byKey(ValueKey(slot)), findsOneWidget, reason: '$width');
      }
    });

    testWidgets('only the slot on screen is built', (tester) async {
      final built = <String>[];
      WidgetBuilder counting(String name) => (context) {
        built.add(name);
        return const SizedBox.shrink();
      };

      await _pumpAt(
        tester,
        const Size(900, 800),
        AdaptiveLayout(
          compact: counting('compact'),
          expanded: counting('expanded'),
        ),
      );

      expect(built, ['expanded']);
    });

    testWidgets('honours the breakpoints of a ResponsiveInit above', (
      tester,
    ) async {
      final layout = AdaptiveLayout(
        compact: _slot('compact'),
        expanded: _slot('expanded'),
      );

      // 750 is medium (-> compact slot) under Material 3...
      await _pumpAt(tester, const Size(750, 800), layout);
      expect(find.byKey(const ValueKey('compact')), findsOneWidget);

      // ...and expanded once the app moves the line to 700.
      await _pumpAt(
        tester,
        const Size(750, 800),
        ResponsiveInit(
          breakpoints: const ResponsiveBreakpoints(
            medium: 500,
            expanded: 700,
            large: 1000,
            extraLarge: 1400,
          ),
          child: layout,
        ),
      );
      expect(find.byKey(const ValueKey('expanded')), findsOneWidget);
    });
  });

  group('AdaptiveBuilder', () {
    testWidgets('hands the builder the current window class', (tester) async {
      final seen = <WindowSizeClass>[];
      final builder = AdaptiveBuilder(
        builder: (context, windowSizeClass) {
          seen.add(windowSizeClass);
          return const SizedBox.shrink();
        },
      );

      for (final width in [390.0, 700.0, 900.0, 1300.0, 1700.0]) {
        await _pumpAt(tester, Size(width, 800), builder);
      }

      expect(seen, WindowSizeClass.values);
    });

    testWidgets('rebuilds when the window is resized', (tester) async {
      final seen = <WindowSizeClass>[];
      await _pumpAt(
        tester,
        const Size(390, 800),
        AdaptiveBuilder(
          builder: (context, windowSizeClass) {
            seen.add(windowSizeClass);
            return const SizedBox.shrink();
          },
        ),
      );

      // Same widget, new window size: MediaQuery drives the rebuild.
      tester.view.physicalSize = const Size(900, 800);
      await tester.pump();

      expect(seen, [WindowSizeClass.compact, WindowSizeClass.expanded]);
    });
  });
}
