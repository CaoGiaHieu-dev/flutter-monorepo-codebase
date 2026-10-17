import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _design = Size(360, 690);

/// Pumps an unbounded [ResponsiveInit] at twice the design width (height
/// unchanged), so `w` doubles and `h` does not — which tells the two axes
/// apart. Returns a context below it.
Future<BuildContext> _pumpDoubledWidth(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view
    ..physicalSize = const Size(720, 690)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late BuildContext ctx;
  await tester.pumpWidget(
    ResponsiveInit(
      designSize: _design,
      scaleBounds: const ScaleBounds.unbounded(),
      textScaleBounds: const ScaleBounds.unbounded(),
      child: Directionality(
        textDirection: direction,
        child: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return ctx;
}

void main() {
  testWidgets('start and end scale by width, top and bottom by height', (
    tester,
  ) async {
    final ctx = await _pumpDoubledWidth(tester);

    final insets = ctx.edgeInsetsDirectional(
      start: 10,
      end: 5,
      top: 10,
      bottom: 5,
    );

    expect(insets, const EdgeInsetsDirectional.fromSTEB(20, 10, 10, 5));
  });

  testWidgets('horizontal / vertical fill the sides not given', (
    tester,
  ) async {
    final ctx = await _pumpDoubledWidth(tester);

    expect(
      ctx.edgeInsetsDirectional(horizontal: 8, vertical: 8, start: 12),
      const EdgeInsetsDirectional.fromSTEB(24, 8, 16, 8),
    );
  });

  testWidgets('all scales by width, like edgeInsets(all:)', (tester) async {
    final ctx = await _pumpDoubledWidth(tester);

    expect(
      ctx.edgeInsetsDirectional(all: 4),
      const EdgeInsetsDirectional.all(8),
    );
    expect(
      ctx.edgeInsetsDirectional(all: 4).resolve(TextDirection.ltr),
      ctx.edgeInsets(all: 4),
    );
  });

  testWidgets('start is the left edge in LTR', (tester) async {
    final ctx = await _pumpDoubledWidth(tester);

    final resolved = ctx
        .edgeInsetsDirectional(start: 10)
        .resolve(Directionality.of(ctx));

    expect(resolved.left, 20);
    expect(resolved.right, 0);
  });

  testWidgets('start is the right edge in RTL — unlike edgeInsets(left:)', (
    tester,
  ) async {
    final ctx = await _pumpDoubledWidth(tester, direction: TextDirection.rtl);

    final resolved = ctx
        .edgeInsetsDirectional(start: 10)
        .resolve(Directionality.of(ctx));

    expect(resolved.right, 20);
    expect(resolved.left, 0);
    // The physical helper does not flip.
    expect(ctx.edgeInsets(left: 10).left, 20);
  });

  testWidgets('a Padding with it pads the start side in RTL', (tester) async {
    tester.view
      ..physicalSize = const Size(720, 690)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const childKey = Key('child');
    await tester.pumpWidget(
      ResponsiveInit(
        designSize: _design,
        scaleBounds: const ScaleBounds.unbounded(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: Builder(
              builder: (context) => Padding(
                padding: context.edgeInsetsDirectional(start: 10),
                child: const SizedBox(key: childKey, width: 10, height: 10),
              ),
            ),
          ),
        ),
      ),
    );

    // Aligned to the top-right in RTL, pushed 20 px in from the right edge.
    expect(tester.getTopRight(find.byKey(childKey)), const Offset(700, 0));
  });
}
