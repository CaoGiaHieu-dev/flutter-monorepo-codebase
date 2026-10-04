import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// `TextScaleDown` shrinks its text to fit the width it is given instead of
/// wrapping or overflowing, and never enlarges it.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double width,
    required Widget child,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );

  const long = 'A rather long title that cannot fit on one narrow line';
  const style = TextStyle(fontSize: 20);

  testWidgets('text wider than its box is scaled down to fit', (tester) async {
    await pump(
      tester,
      width: 100,
      child: const TextScaleDown(long, style: style),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextScaleDown)).width, 100);
    expect(
      tester.widget<FittedBox>(find.byType(FittedBox)).fit,
      BoxFit.scaleDown,
    );
    // The Text keeps its natural layout width; the FittedBox scales it so the
    // painted right edge lands inside the 100-wide box.
    expect(tester.getSize(find.text(long)).width, greaterThan(100));
    expect(tester.getTopRight(find.text(long)).dx, lessThanOrEqualTo(100.01));
  });

  testWidgets('text that fits is not enlarged', (tester) async {
    await pump(
      tester,
      width: 400,
      child: const TextScaleDown('Short', style: style),
    );

    final natural = tester.getSize(find.text('Short')).width;
    expect(natural, lessThan(400));
    // Painted at its natural size: the right edge is the layout width.
    expect(tester.getTopRight(find.text('Short')).dx, closeTo(natural, 0.01));
  });

  testWidgets('a null text renders as an empty string', (tester) async {
    await pump(tester, width: 100, child: const TextScaleDown(null));

    expect(tester.widget<Text>(find.byType(Text)).data, '');
  });

  testWidgets('alignment defaults to the start edge', (tester) async {
    await pump(tester, width: 100, child: const TextScaleDown('x'));

    expect(
      tester.widget<FittedBox>(find.byType(FittedBox)).alignment,
      AlignmentDirectional.centerStart,
    );
  });

  testWidgets('style, maxLines and the semantics label reach the Text', (
    tester,
  ) async {
    await pump(
      tester,
      width: 200,
      child: const TextScaleDown(
        'Total',
        style: style,
        maxLines: 1,
        semanticsLabel: 'Order total',
        textAlign: TextAlign.end,
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style, style);
    expect(text.maxLines, 1);
    expect(text.semanticsLabel, 'Order total');
    expect(text.textAlign, TextAlign.end);
  });
}
