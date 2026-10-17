import 'package:core_common/core_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

/// A `RootApp` that needs no DI: the stage reads only the widget's type.
class _Root extends RootApp {
  const _Root();

  @override
  Widget build(BuildContext c) => const SizedBox();
}

const _problems = [
  ProfileProblem(
    code: 'P01',
    description: 'Boot stopped: `mobile` is running on linux.',
    action: 'Add `linux: { runner: scaffold }` under `platforms:`.',
  ),
];

/// `debugBootStage()` is what every app's `integration_test/boot_test.dart`
/// waits for. "Built" is not "shown": a tree whose first frame is still held
/// back reads `starting`, which is the blank page reproduced on the VM.
void main() {
  testWidgets('a boot-error screen is failed', (tester) async {
    await tester.pumpWidget(
      const BootErrorApp(problems: _problems, detailed: true),
    );

    expect(debugBootStage(), BootStage.failed);
  });

  testWidgets('a mounted RootApp whose frames reach the engine is shown', (
    tester,
  ) async {
    await tester.pumpWidget(const _Root());

    expect(debugBootStage(), BootStage.shown);
  });

  testWidgets('a RootApp built while the first frame is held is starting', (
    tester,
  ) async {
    tester.binding.deferFirstFrame();
    try {
      await tester.pumpWidget(const _Root());

      // Built and laid out — `find.byType` sees it — and never drawn.
      expect(find.byType(_Root), findsOneWidget);
      expect(debugBootStage(), BootStage.starting);
    } finally {
      tester.binding.allowFirstFrame();
    }
  });

  testWidgets('the same tree is shown once the first frame is allowed', (
    tester,
  ) async {
    tester.binding.deferFirstFrame();
    await tester.pumpWidget(const _Root());
    expect(debugBootStage(), BootStage.starting);

    tester.binding.allowFirstFrame();
    await tester.pump();

    expect(debugBootStage(), BootStage.shown);
  });
}
