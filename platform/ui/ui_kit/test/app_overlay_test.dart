import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'showDialogOverlay while a toast and the loading overlay are visible',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [ThemeSystemExtension.light]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ResponsiveInit(
            child: Overlay.wrap(child: AppOverlayInitializer(child: child!)),
          ),
          home: const Scaffold(body: Text('page')),
        ),
      );
      // AppOverlay is created after the first frame.
      await tester.pump();

      AppOverlay.showLoading();
      AppOverlay.showToast(content: 'toast');
      // Both neighbours exist: passing `above:` and `below:` together used to
      // trip OverlayState.insert's assertion.
      AppOverlay.showDialogOverlay(child: const Text('dialog'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('dialog'), findsOneWidget);
      expect(find.text('toast'), findsOneWidget);

      AppOverlay.removeToastOverlay();
      AppOverlay.removeDialogOverlay();
      AppOverlay.removeLoadingOverlay();
      await tester.pump();
    },
  );
}
