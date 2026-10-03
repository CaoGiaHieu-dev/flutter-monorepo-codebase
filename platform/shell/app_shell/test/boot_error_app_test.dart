import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

const _problems = [
  ProfileProblem(
    code: 'P01',
    description: 'Boot stopped: `mobile` is running on linux.',
    action: 'Add `linux:` under `platforms:` in apps/mobile/app_manifest.yaml.',
  ),
  ProfileProblem(
    code: 'C02',
    description: '`capabilities.splash` is declared provided.',
    action: 'Compose the module that registers it.',
  ),
];

/// What a person sees instead of a blank window when the app stops itself
/// before it can show anything — with no DI, router or theme provider.
void main() {
  group('BootErrorApp', () {
    testWidgets('detailed: every problem with its code, text and action', (
      tester,
    ) async {
      await tester.pumpWidget(
        const BootErrorApp(problems: _problems, detailed: true),
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.textContaining(
          '[P01] Boot stopped: `mobile` is running on linux.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Action: Add `linux:` under `platforms:` in '
          'apps/mobile/app_manifest.yaml.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('[C02]'), findsOneWidget);
      expect(find.text('Please try again'), findsNothing);
    });

    testWidgets('generic: a message, and none of the diagnostics', (
      tester,
    ) async {
      await tester.pumpWidget(
        const BootErrorApp(problems: _problems, detailed: false),
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Please try again'), findsOneWidget);
      expect(find.textContaining('P01'), findsNothing);
      expect(find.textContaining('linux'), findsNothing);
      expect(find.textContaining('app_manifest'), findsNothing);
    });

    testWidgets('a long report scrolls on a small phone instead of '
        'overflowing', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 480)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        BootErrorApp(
          problems: [
            for (var i = 0; i < 12; i++)
              ProfileProblem(
                code: 'C0${i % 9 + 1}',
                description: 'Problem number $i. ' * 12,
                action: 'Do something about number $i. ' * 8,
              ),
          ],
          detailed: true,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
