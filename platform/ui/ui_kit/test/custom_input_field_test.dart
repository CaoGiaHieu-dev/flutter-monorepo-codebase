import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [ThemeSystemExtension.light]),
  home: ResponsiveInit(child: Scaffold(body: child)),
);

void main() {
  group('CustomInputField focus node', () {
    testWidgets('follows a focusNode swapped in by the caller', (
      tester,
    ) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await tester.pumpWidget(_app(CustomInputField(focusNode: first)));
      await tester.pumpWidget(_app(CustomInputField(focusNode: second)));

      await tester.tap(find.byType(TextFormField));
      await tester.pump();

      expect(second.hasFocus, isTrue);
      expect(first.hasFocus, isFalse);
    });

    testWidgets('switches from its own node to a caller node', (
      tester,
    ) async {
      final external = FocusNode();
      addTearDown(external.dispose);

      await tester.pumpWidget(_app(const CustomInputField()));
      await tester.pumpWidget(_app(CustomInputField(focusNode: external)));

      await tester.tap(find.byType(TextFormField));
      await tester.pump();

      expect(external.hasFocus, isTrue);
    });

    testWidgets('never disposes a caller-provided node', (tester) async {
      final external = FocusNode();
      addTearDown(external.dispose);

      await tester.pumpWidget(_app(CustomInputField(focusNode: external)));
      await tester.pumpWidget(_app(const SizedBox()));

      // A disposed ChangeNotifier throws on addListener in debug builds.
      void listener() {}
      expect(() => external.addListener(listener), returnsNormally);
      external.removeListener(listener);
    });
  });
}
