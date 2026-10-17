import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../root_app.dart';
import 'boot_error_app.dart';

/// How far the running boot has got — what `integration_test/boot_test.dart`
/// waits for (RULE-83).
enum BootStage {
  /// Neither the app nor a boot-error screen is up yet, or the app is built
  /// but its frames are still held back.
  starting,

  /// A boot-error screen is up (P01–P05, B01, a C code).
  failed,

  /// `RootApp` is mounted and its frames reach the engine.
  shown,
}

/// Where the boot is. "Built" is not "shown": with the first frame deferred
/// a whole app can be built, laid out and never drawn — which a
/// `find.byType` or a post-frame callback cannot tell apart.
BootStage debugBootStage() {
  var root = false;
  var failed = false;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is BootErrorApp) failed = true;
    if (widget is RootApp) root = true;
    if (!failed && !root) element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  if (failed) return BootStage.failed;
  if (root && RendererBinding.instance.sendFramesToEngine) {
    return BootStage.shown;
  }
  return BootStage.starting;
}
