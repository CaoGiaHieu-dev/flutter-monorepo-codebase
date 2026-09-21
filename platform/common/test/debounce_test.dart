import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(EasyDebounce.cancelAll);

  tearDown(EasyDebounce.cancelAll);

  group('EasyDebounce', () {
    test('should execute action after duration', () async {
      var executedCount = 0;
      EasyDebounce.debounce('test-tag', const Duration(milliseconds: 100), () {
        executedCount++;
      });

      expect(executedCount, equals(0));
      expect(EasyDebounce.count(), equals(1));

      await Future.delayed(const Duration(milliseconds: 150));
      expect(executedCount, equals(1));
      expect(EasyDebounce.count(), equals(0));
    });

    test('should debounce and execute only the last action', () async {
      var executedCount = 0;
      EasyDebounce.debounce('test-tag', const Duration(milliseconds: 100), () {
        executedCount = 1;
      });
      EasyDebounce.debounce('test-tag', const Duration(milliseconds: 100), () {
        executedCount = 2;
      });

      await Future.delayed(const Duration(milliseconds: 50));
      expect(executedCount, equals(0));

      await Future.delayed(const Duration(milliseconds: 100));
      expect(executedCount, equals(2));
    });

    test('should fire immediate execution when duration is zero', () {
      var executedCount = 0;
      EasyDebounce.debounce('test-tag', Duration.zero, () {
        executedCount++;
      });

      expect(executedCount, equals(1));
      expect(EasyDebounce.count(), equals(0));
    });

    test('should cancel pending action', () async {
      var executedCount = 0;
      EasyDebounce.debounce('test-tag', const Duration(milliseconds: 100), () {
        executedCount++;
      });

      expect(EasyDebounce.count(), equals(1));
      EasyDebounce.cancel('test-tag');
      expect(EasyDebounce.count(), equals(0));

      await Future.delayed(const Duration(milliseconds: 150));
      expect(executedCount, equals(0));
    });

    test('should fire pending action manually', () {
      var executedCount = 0;
      EasyDebounce.debounce('test-tag', const Duration(milliseconds: 500), () {
        executedCount++;
      });

      expect(executedCount, equals(0));
      EasyDebounce.fire('test-tag');
      expect(executedCount, equals(1));
    });
  });
}
