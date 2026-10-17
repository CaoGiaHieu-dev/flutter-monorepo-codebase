import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Recorder with LifecycleMixin {
  final calls = <String>[];
  final states = <AppLifecycleState>[];

  @override
  void onResume() => calls.add('resume');

  @override
  void onInactive() => calls.add('inactive');

  @override
  void onHide() => calls.add('hide');

  @override
  void onPause() => calls.add('pause');

  @override
  void onShow() => calls.add('show');

  @override
  void onRestart() => calls.add('restart');

  @override
  void onDetach() => calls.add('detach');

  @override
  void onStateChange(AppLifecycleState value) => states.add(value);
}

/// `LifecycleMixin` maps the app lifecycle onto its overridable callbacks
/// between `startListenOnLifecycleChange` and `stopListenOnLifecycleChange`.
void main() {
  testWidgets('does nothing before listening starts', (tester) async {
    final recorder = _Recorder();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(recorder.calls, isEmpty);
    expect(recorder.states, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a pause and a resume reach their callbacks in order', (
    tester,
  ) async {
    final recorder = _Recorder()..startListenOnLifecycleChange();
    addTearDown(recorder.stopListenOnLifecycleChange);

    // The test binding starts out resumed: step down, then back up.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(recorder.calls, [
      'inactive',
      'hide',
      'pause',
      'restart',
      'show',
      'resume',
    ]);
    expect(recorder.states, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
  });

  testWidgets('starting twice keeps one listener', (tester) async {
    final recorder = _Recorder()
      ..startListenOnLifecycleChange()
      ..startListenOnLifecycleChange();
    addTearDown(recorder.stopListenOnLifecycleChange);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    expect(recorder.states, [AppLifecycleState.inactive]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('stop ends the callbacks, and listening can start again', (
    tester,
  ) async {
    final recorder = _Recorder()..startListenOnLifecycleChange();
    recorder.stopListenOnLifecycleChange();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(recorder.states, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    recorder.startListenOnLifecycleChange();
    addTearDown(recorder.stopListenOnLifecycleChange);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    expect(recorder.states, [AppLifecycleState.inactive]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('stop without start is harmless', (tester) async {
    expect(_Recorder().stopListenOnLifecycleChange, returnsNormally);
  });
}
