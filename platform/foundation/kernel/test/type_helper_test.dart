import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

enum SampleEnum { one }

/// `TypeHelper<T>` makes a type comparable at runtime (`>=` is "can hold") and
/// says which types the storage codec can persist.
void main() {
  group('subtype operators', () {
    test('a type holds itself and its subtypes', () {
      expect(const TypeHelper<num>() >= const TypeHelper<int>(), isTrue);
      expect(const TypeHelper<num>() >= const TypeHelper<num>(), isTrue);
      expect(const TypeHelper<int>() >= const TypeHelper<num>(), isFalse);
    });

    test('<= is the mirror of >=', () {
      expect(const TypeHelper<int>() <= const TypeHelper<num>(), isTrue);
      expect(const TypeHelper<num>() <= const TypeHelper<int>(), isFalse);
    });

    test('> and < are strict', () {
      expect(const TypeHelper<num>() > const TypeHelper<int>(), isTrue);
      expect(const TypeHelper<num>() > const TypeHelper<num>(), isFalse);
      expect(const TypeHelper<int>() < const TypeHelper<num>(), isTrue);
      expect(const TypeHelper<int>() < const TypeHelper<int>(), isFalse);
    });

    test('unrelated types compare false both ways', () {
      expect(const TypeHelper<int>() >= const TypeHelper<String>(), isFalse);
      expect(const TypeHelper<String>() >= const TypeHelper<int>(), isFalse);
      expect(const TypeHelper<int>() < const TypeHelper<String>(), isFalse);
    });

    test('everything is held by Object?', () {
      expect(const TypeHelper<Object?>() >= const TypeHelper<String>(), isTrue);
      expect(const TypeHelper<Object?>() > const TypeHelper<String>(), isTrue);
    });
  });

  group('supportType', () {
    test('the storable primitives and collections are supported', () {
      expect(TypeHelper.supportType(const TypeHelper<int>()), isTrue);
      expect(TypeHelper.supportType(const TypeHelper<double>()), isTrue);
      expect(TypeHelper.supportType(const TypeHelper<num>()), isTrue);
      expect(TypeHelper.supportType(const TypeHelper<String>()), isTrue);
      expect(TypeHelper.supportType(const TypeHelper<bool>()), isTrue);
      expect(TypeHelper.supportType(const TypeHelper<List<String>>()), isTrue);
      expect(TypeHelper.supportType(const TypeHelper<SampleEnum>()), isTrue);
      expect(
        TypeHelper.supportType(const TypeHelper<Map<String, dynamic>>()),
        isTrue,
      );
    });

    test('other types are not', () {
      expect(TypeHelper.supportType(const TypeHelper<DateTime>()), isFalse);
      expect(TypeHelper.supportType(const TypeHelper<Object>()), isFalse);
      expect(TypeHelper.supportType(const TypeHelper<Set<int>>()), isFalse);
    });
  });
}
