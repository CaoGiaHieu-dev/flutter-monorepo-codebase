import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigatorKeys.nested', () {
    test('the same id always yields the same key', () {
      // A shell branch rebuilt with a fresh key would drop its navigation
      // stack, so the key for an id must be created once and reused.
      expect(
        identical(NavigatorKeys.nested('tab-a'), NavigatorKeys.nested('tab-a')),
        isTrue,
      );
    });

    test('different ids yield different keys', () {
      expect(
        NavigatorKeys.nested('tab-b'),
        isNot(NavigatorKeys.nested('tab-c')),
      );
    });

    test('the key is labelled with its id for debugging', () {
      expect(
        NavigatorKeys.nested('tab-d').toString(),
        contains('nested:tab-d'),
      );
    });
  });

  test('the app and root navigators are distinct, stable keys', () {
    expect(NavigatorKeys.appKey, isNot(NavigatorKeys.rootKey));
    expect(identical(NavigatorKeys.appKey, NavigatorKeys.appKey), isTrue);
  });
}
