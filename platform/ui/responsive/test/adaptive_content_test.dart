import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _child = ValueKey('child');

/// Sets the window to [size] and pumps [child] into it.
Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

/// Asks for no width of its own: whatever width it gets is the one
/// [AdaptiveContent] gave it.
const _content = SizedBox(key: _child, height: 100);

void main() {
  testWidgets('caps the width and centres the column on a wide window', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const Size(1200, 800),
      const AdaptiveContent(child: _content),
    );

    // (1200 - 640) / 2 = 280 either side; top-aligned.
    expect(
      tester.getRect(find.byKey(_child)),
      const Rect.fromLTWH(280, 0, 640, 100),
    );
  });

  testWidgets('changes nothing on a window narrower than the cap', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const Size(390, 800),
      const AdaptiveContent(child: _content),
    );

    expect(
      tester.getRect(find.byKey(_child)),
      const Rect.fromLTWH(0, 0, 390, 100),
    );
  });

  testWidgets('padding sits outside the cap', (tester) async {
    const padding = EdgeInsets.symmetric(horizontal: 16);

    // Narrow: the padding is all that applies.
    await _pumpAt(
      tester,
      const Size(390, 800),
      const AdaptiveContent(padding: padding, child: _content),
    );
    expect(
      tester.getRect(find.byKey(_child)),
      const Rect.fromLTWH(16, 0, 358, 100),
    );

    // Wide: the column keeps the full maxWidth, centred.
    await _pumpAt(
      tester,
      const Size(1200, 800),
      const AdaptiveContent(padding: padding, child: _content),
    );
    expect(tester.getSize(find.byKey(_child)).width, 640);
  });

  testWidgets('maxWidth and alignment are the caller\'s', (tester) async {
    await _pumpAt(
      tester,
      const Size(1200, 800),
      const AdaptiveContent(
        maxWidth: 400,
        alignment: Alignment.center,
        child: _content,
      ),
    );

    expect(
      tester.getRect(find.byKey(_child)),
      const Rect.fromLTWH(400, 350, 400, 100),
    );
  });

  testWidgets('a directional alignment follows the text direction', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: AdaptiveContent(
          alignment: AlignmentDirectional.topStart,
          child: _content,
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(_child)),
      const Rect.fromLTWH(560, 0, 640, 100),
    );
  });
}
