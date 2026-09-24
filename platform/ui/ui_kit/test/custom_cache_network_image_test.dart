import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

({int? width, int? height}) _resolve({
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  double dpr = 2,
}) => CustomCacheNetworkImage.resolveMemCacheSize(
  width: width,
  height: height,
  fit: fit,
  devicePixelRatio: dpr,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = const Size(800, 1200)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('resolveMemCacheSize', () {
    test('no layout size: decode at full size', () {
      expect(_resolve(), (width: null, height: null));
    });

    test('one side known: that side, times the pixel ratio', () {
      expect(_resolve(width: 48), (width: 96, height: null));
      expect(_resolve(height: 48), (width: null, height: 96));
    });

    test('rounds up, never down', () {
      expect(_resolve(width: 10.2, dpr: 3), (width: 31, height: null));
    });

    test('contain / scaleDown / fitWidth: the width only', () {
      for (final fit in [BoxFit.contain, BoxFit.scaleDown, BoxFit.fitWidth]) {
        expect(
          _resolve(width: 100, height: 50, fit: fit),
          (width: 200, height: null),
          reason: '$fit',
        );
      }
    });

    test('fitHeight: the height only', () {
      expect(
        _resolve(width: 100, height: 50, fit: BoxFit.fitHeight),
        (width: null, height: 100),
      );
    });

    test('fill: both sides — it stretches anyway', () {
      expect(
        _resolve(width: 100, height: 50, fit: BoxFit.fill),
        (width: 200, height: 100),
      );
    });

    test('cover with both sides, or none: left to the caller', () {
      expect(
        _resolve(width: 100, height: 50, fit: BoxFit.cover),
        (width: null, height: null),
      );
      expect(
        _resolve(width: 100, fit: BoxFit.none),
        (width: null, height: null),
      );
    });

    test('an unbounded or empty side counts as unknown', () {
      expect(
        _resolve(width: double.infinity, height: 50),
        (width: null, height: 100),
      );
      expect(_resolve(width: 0), (width: null, height: null));
    });
  });

  group('CustomCacheNetworkImage', () {
    testWidgets('passes the derived decode size to the image', (
      tester,
    ) async {
      await _pump(
        tester,
        const CustomCacheNetworkImage(
          'https://example.com/a.png',
          width: 100,
          height: 50,
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.memCacheWidth, 200);
      expect(image.memCacheHeight, isNull);
    });

    testWidgets('an explicit decode size wins over the derived one', (
      tester,
    ) async {
      await _pump(
        tester,
        const CustomCacheNetworkImage(
          'https://example.com/a.png',
          width: 100,
          height: 50,
          fit: BoxFit.cover,
          memCacheHeight: 300,
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.memCacheWidth, isNull);
      expect(image.memCacheHeight, 300);
    });

    testWidgets('semanticLabel labels the image in every state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // An empty URL renders the error icon; the label still describes it.
      await _pump(
        tester,
        const CustomCacheNetworkImage('', semanticLabel: 'Profile photo'),
      );

      expect(find.bySemanticsLabel('Profile photo'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Profile photo')),
        isSemantics(label: 'Profile photo', isImage: true),
      );
      semantics.dispose();
    });
  });
}
