import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Half the default 375×812 artboard: every down-only factor is 0.5.
const _halfDesign = Size(187.5, 406);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = _halfDesign
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [ThemeSystemExtension.light]),
      home: ResponsiveInit(
        designSize: const Size(375, 812),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

/// Size of the logo `EmptyWidget` centres. Only its height is asserted: the
/// SVG keeps its aspect ratio, so the drawn width follows from the height.
Size _logoSize(WidgetTester tester) {
  final center = tester.renderObject(
    find.descendant(
      of: find.byType(EmptyWidget),
      matching: find.byType(Center),
    ),
  );
  Size? size;
  center.visitChildren((child) => size = (child as RenderBox).size);
  return size!;
}

void main() {
  group('ui_kit default sizes scale with the window', () {
    testWidgets('EmptyWidget scales its default logo size', (tester) async {
      await _pump(tester, const EmptyWidget());

      expect(
        _logoSize(tester).height,
        equals(SharedUiConstants.EMPTY_WIDGET_HEIGHT / 2),
      );
    });

    testWidgets('EmptyWidget uses a caller size as-is', (tester) async {
      await _pump(tester, const EmptyWidget(width: 80, height: 40));

      expect(_logoSize(tester).height, equals(40));
    });

    testWidgets('LoadingWidget scales its default square', (tester) async {
      await _pump(tester, const LoadingWidget());

      final box = tester.getSize(
        find.descendant(
          of: find.byType(LoadingWidget),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.width, equals(SharedUiConstants.LOADING_WIDGET_DIMENSION / 2));
      expect(box.height, equals(box.width));
    });

    testWidgets('CustomButton.rectangle scales its default height', (
      tester,
    ) async {
      await _pump(
        tester,
        CustomButton.rectangle(onPressed: () {}, child: const Text('go')),
      );

      final button = tester.widget<MaterialButton>(find.byType(MaterialButton));
      expect(button.height, equals(SharedUiConstants.BUTTON_HEIGHT / 2));
    });

    testWidgets('CustomButton.rectangle keeps a caller height as-is', (
      tester,
    ) async {
      await _pump(
        tester,
        CustomButton.rectangle(
          height: 30,
          onPressed: () {},
          child: const Text('go'),
        ),
      );

      final button = tester.widget<MaterialButton>(find.byType(MaterialButton));
      expect(button.height, equals(30));
    });
  });
}
