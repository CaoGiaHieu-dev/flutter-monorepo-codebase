import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/firebase/firebase_module.dart';
import 'package:mobile_app/firebase/firebase_options_dev.dart' as dev;
import 'package:mobile_app/firebase/firebase_options_prod.dart' as prod;
import 'package:mobile_app/firebase/firebase_options_staging.dart' as stg;

/// The module as injectable's generated code builds it.
class _M extends FirebaseModule {}

PlatformFacts _facts({required bool push}) => PlatformFacts(
  runner: RunnerKind.scaffold,
  splash: SplashMode.native,
  orientation: OrientationPolicy.phonesPortrait,
  deepLinks: false,
  push: push,
);

void main() {
  final module = _M();

  group('FirebaseModule reads the generated options only where push is on', () {
    test('push off: every flavor gets the placeholder, never currentPlatform '
        '(which throws on web and Linux)', () {
      final off = _facts(push: false);
      expect(module.devFirebaseOptions(off).projectId, 'push-off');
      expect(module.stagingFirebaseOptions(off).projectId, 'push-off');
      expect(module.prodFirebaseOptions(off).projectId, 'push-off');
    });

    test("push on: each flavor gets its own project's currentPlatform", () {
      final on = _facts(push: true);
      expect(
        module.devFirebaseOptions(on).projectId,
        dev.DefaultFirebaseOptions.currentPlatform.projectId,
      );
      expect(
        module.stagingFirebaseOptions(on).projectId,
        stg.DefaultFirebaseOptions.currentPlatform.projectId,
      );
      expect(
        module.prodFirebaseOptions(on).projectId,
        prod.DefaultFirebaseOptions.currentPlatform.projectId,
      );
    });
  });
}
