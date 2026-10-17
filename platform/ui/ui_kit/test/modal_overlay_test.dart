import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _behindFocus = FocusNode(debugLabel: 'behind');

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [ThemeSystemExtension.light]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => ResponsiveInit(
        child: Overlay.wrap(child: AppOverlayInitializer(child: child!)),
      ),
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            focusNode: _behindFocus,
            onPressed: () {},
            child: const Text('Behind'),
          ),
        ),
      ),
    ),
  );
  // AppOverlay is created after the first frame.
  await tester.pump();
}

/// Whether any node under the semantics root carries [label].
bool _inSemanticsTree(WidgetTester tester, String label) {
  var found = false;
  void walk(SemanticsNode node) {
    if (node.label == label) found = true;
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return found;
}

/// A modal overlay must be modal for a screen reader and for the keyboard,
/// not only look it: otherwise TalkBack / VoiceOver or Tab walks past the
/// dialog into the page behind it (WCAG 2.4.3, 4.1.2).
void main() {
  setUp(_behindFocus.unfocus);

  testWidgets('the page is in the semantics tree until a dialog opens', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(_inSemanticsTree(tester, 'Behind'), isTrue);

    unawaited(
      AppOverlay.showDialog<void>(
        builder: (_) => const Text('Dialog content'),
      ),
    );
    await tester.pumpAndSettle();

    expect(_inSemanticsTree(tester, 'Dialog content'), isTrue);
    expect(_inSemanticsTree(tester, 'Behind'), isFalse);

    AppOverlay.dismissDialog<void>();
    await tester.pumpAndSettle();

    expect(_inSemanticsTree(tester, 'Behind'), isTrue);
    semantics.dispose();
  });

  testWidgets('the loading overlay hides the page from assistive tech', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    AppOverlay.showLoading();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_inSemanticsTree(tester, 'Behind'), isFalse);

    AppOverlay.removeLoadingOverlay();
    await tester.pump();

    expect(_inSemanticsTree(tester, 'Behind'), isTrue);
    semantics.dispose();
  });

  testWidgets('a toast does not hide the page', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    AppOverlay.showToast(content: 'Saved');
    await tester.pump();

    expect(_inSemanticsTree(tester, 'Saved'), isTrue);
    expect(_inSemanticsTree(tester, 'Behind'), isTrue);

    AppOverlay.removeToastOverlay();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('keyboard focus leaves the page while a dialog is open', (
    tester,
  ) async {
    await _pump(tester);
    _behindFocus.requestFocus();
    await tester.pump();
    expect(_behindFocus.hasPrimaryFocus, isTrue);

    unawaited(
      AppOverlay.showDialog<void>(
        builder: (_) => const Text('Dialog content'),
      ),
    );
    await tester.pumpAndSettle();

    expect(_behindFocus.hasFocus, isFalse);

    // Tab stays in the dialog: the page's button never takes the focus back.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_behindFocus.hasFocus, isFalse);

    AppOverlay.dismissDialog<void>();
    await tester.pumpAndSettle();
  });
}
