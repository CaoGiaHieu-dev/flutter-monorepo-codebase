import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('StringExtension.isValidEmail', () {
    test('accepts ordinary addresses', () {
      for (final email in [
        'ada@example.com',
        'ada.lovelace@example.co.uk',
        'ada+news@example.org',
        'a_b-c@sub.example.io',
      ]) {
        expect(email.isValidEmail, isTrue, reason: email);
      }
    });

    test('accepts a top-level domain longer than four letters', () {
      for (final email in [
        'shop@brand.store',
        'me@company.online',
        'it@firm.technology',
        'x@example.museum',
      ]) {
        expect(email.isValidEmail, isTrue, reason: email);
      }
    });

    test('refuses what is not an address', () {
      for (final email in [
        '',
        'ada',
        'ada@',
        '@example.com',
        'ada@example',
        'ada@example.c',
        'ada @example.com',
        'ada@exa mple.com',
        'ada@@example.com',
      ]) {
        expect(email.isValidEmail, isFalse, reason: '"$email"');
      }
    });
  });

  group('StringExtension helpers', () {
    test('capitalize and capitalizeWords', () {
      expect('hELLO'.capitalize(), 'Hello');
      expect(''.capitalize(), '');
      expect('hello big world'.capitalizeWords(), 'Hello Big World');
    });

    test('isValidPhoneNumber and isNumeric', () {
      expect('+84901234567'.isValidPhoneNumber, isTrue);
      expect('0901234567'.isValidPhoneNumber, isFalse);
      expect('12345'.isNumeric, isTrue);
      expect('12a45'.isNumeric, isFalse);
      expect(''.isNumeric, isFalse);
    });

    test('removeWhitespace, truncate and reverse', () {
      expect(' a b\tc\n'.removeWhitespace, 'abc');
      expect('abcdef'.truncate(3), 'abc...');
      expect('abc'.truncate(3), 'abc');
      expect('abcdef'.truncate(2, ellipsis: '~'), 'ab~');
      expect('abc'.reverse(), 'cba');
    });

    test('toSnakeCase and toCamelCase', () {
      expect('helloWorldFoo'.toSnakeCase, 'hello_world_foo');
      expect('hello_world foo'.toCamelCase, 'helloWorldFoo');
    });
  });

  group('StringPriceExtension', () {
    test('formatPrice groups thousands and keeps decimals and sign', () {
      expect('1234567.89'.formatPrice, '1,234,567.89');
      expect('1234567'.formatPrice, '1,234,567');
      expect('-1234567.89'.formatPrice, '-1,234,567.89');
      expect('999'.formatPrice, '999');
    });

    test('formatCurrency prefixes the symbol', () {
      expect('1234'.formatCurrency(), r'$1,234');
      expect('1234'.formatCurrency(symbol: '€'), '€1,234');
    });
  });
}
