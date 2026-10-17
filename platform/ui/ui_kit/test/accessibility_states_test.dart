import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support_contrast.dart';

/// The states a template user copies: a disabled button, a focused or invalid
/// field, a toast — in both palettes, and on the windows where a down-only
/// `context.h` used to shrink a tap target below 48 dp (RULE-39).
void main() {
  final palettes = {
    'light': ThemeSystemExtension.light,
    'dark': ThemeSystemExtension.dark,
  };

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeSystemExtension? palette,
    Size size = const Size(375, 812),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final colors = palette ?? ThemeSystemExtension.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: colors == ThemeSystemExtension.dark
              ? Brightness.dark
              : Brightness.light,
          extensions: [colors],
        ),
        home: ResponsiveInit(
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }

  group('CustomButton disabled state', () {
    for (final MapEntry(key: name, value: palette) in palettes.entries) {
      testWidgets('is a distinct, readable fill ($name)', (tester) async {
        await pump(
          tester,
          Column(
            children: [
              CustomButton.rectangle(
                onPressed: () {},
                child: const Text('Enabled'),
              ),
              const CustomButton.rectangle(disable: true, child: Text('Off')),
              CustomButton.rectangle(
                disable: true,
                gradientFillColors: palette.primaryGradientColors,
                child: const Text('Off gradient'),
              ),
            ],
          ),
          palette: palette,
        );

        final buttons = tester
            .widgetList<MaterialButton>(find.byType(MaterialButton))
            .toList();
        final enabled = buttons[0];
        final disabled = buttons[1];

        // Not the enabled fill, and not the page.
        expect(disabled.disabledColor, palette.surfaceVariant);
        expect(disabled.disabledColor, isNot(enabled.color));
        // The label is not the fill, and readable against it.
        expect(disabled.disabledTextColor, palette.textSecondary);
        expect(
          contrast(disabled.disabledTextColor!, disabled.disabledColor!),
          greaterThanOrEqualTo(4.0),
        );
        // A disabled gradient button drops the gradient for the same fill.
        expect(
          find.descendant(
            of: find.byType(CustomButton).last,
            matching: find.byType(DecoratedBox),
          ),
          findsNothing,
        );
        expect(buttons[2].disabledColor, palette.surfaceVariant);
      });

      testWidgets('an enabled label reads on the brand fill ($name)', (
        tester,
      ) async {
        await pump(
          tester,
          CustomButton.rectangle(onPressed: () {}, child: const Text('Go')),
          palette: palette,
        );

        final button = tester.widget<MaterialButton>(
          find.byType(MaterialButton),
        );
        expect(button.textColor, palette.textInverse);
        expect(contrast(button.textColor!, button.color!), greaterThan(4.5));
      });
    }

    testWidgets('a transparent button keeps no fill when disabled', (
      tester,
    ) async {
      await pump(
        tester,
        const CustomButton.rectangle(
          color: Colors.transparent,
          disable: true,
          child: Text('Skip'),
        ),
      );

      final button = tester.widget<MaterialButton>(find.byType(MaterialButton));
      expect(button.disabledColor, Colors.transparent);
    });
  });

  group('CustomInputField states', () {
    for (final MapEntry(key: name, value: palette) in palettes.entries) {
      testWidgets('border, hint and error meet WCAG AA ($name)', (
        tester,
      ) async {
        await pump(
          tester,
          const CustomInputField(hintText: 'Hint'),
          palette: palette,
        );

        final decoration = tester
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration;
        final enabled = decoration.enabledBorder! as OutlineInputBorder;
        final focused = decoration.focusedBorder! as OutlineInputBorder;
        final error = decoration.errorBorder! as OutlineInputBorder;
        final fill = decoration.fillColor!;

        // 1.4.11: the resting border is a 3:1 boundary of the field.
        expect(
          contrast(enabled.borderSide.color, fill),
          greaterThanOrEqualTo(3.0),
        );
        expect(
          contrast(enabled.borderSide.color, palette.background),
          greaterThanOrEqualTo(3.0),
        );
        // Focus and error read as different states, not the same hairline.
        expect(focused.borderSide.color, palette.primary);
        expect(focused.borderSide.width, greaterThan(enabled.borderSide.width));
        expect(error.borderSide.color, palette.error);
        expect(focused.borderSide, isNot(enabled.borderSide));
        expect(error.borderSide, isNot(enabled.borderSide));
        expect(contrast(focused.borderSide.color, fill), greaterThan(3.0));
        expect(contrast(error.borderSide.color, fill), greaterThan(3.0));
        // 1.4.3: placeholder and the error line are text.
        expect(
          contrast(decoration.hintStyle!.color!, fill),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(decoration.errorStyle!.color!, fill),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    for (final size in const [
      Size(375, 812),
      Size(360, 640),
      Size(320, 568),
      Size(800, 360),
    ]) {
      testWidgets('is at least 48 dp tall at ${size.width}x${size.height}', (
        tester,
      ) async {
        await pump(tester, const CustomInputField(), size: size);

        expect(
          tester.getSize(find.byType(CustomInputField)).height,
          greaterThanOrEqualTo(kMinInteractiveDimension),
        );
      });
    }
  });

  group('toast', () {
    for (final MapEntry(key: name, value: palette) in palettes.entries) {
      testWidgets('its label reads over a busy page ($name)', (tester) async {
        await pump(
          tester,
          const Stack(
            children: [ToastOverlayWidget(content: 'Invalid credentials')],
          ),
          palette: palette,
        );

        final pill =
            tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.text('Invalid credentials'),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        final label = tester.widget<Text>(find.text('Invalid credentials'));

        // Worst case: the pill over the opposite extreme of the page.
        for (final page in [palette.textPrimary, palette.surface]) {
          final fill = Color.alphaBlend(pill.color!, page);
          expect(
            contrast(label.style!.color!, fill),
            greaterThanOrEqualTo(4.5),
            reason: 'over ${page.toARGB32().toRadixString(16)}',
          );
        }
      });
    }
  });
}
