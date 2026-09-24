import 'package:core_common/core_common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates typing [char] at the current (collapsed) cursor of [old].
TextEditingValue _type(
  TextInputFormatter formatter,
  TextEditingValue old,
  String char,
) {
  final pos = old.selection.baseOffset;
  return formatter.formatEditUpdate(
    old,
    TextEditingValue(
      text: old.text.replaceRange(pos, pos, char),
      selection: TextSelection.collapsed(offset: pos + 1),
    ),
  );
}

/// Types every character of [input] into an empty field.
TextEditingValue _typeAll(TextInputFormatter formatter, String input) {
  var value = const TextEditingValue(
    selection: TextSelection.collapsed(offset: 0),
  );
  for (final char in input.split('')) {
    value = _type(formatter, value, char);
  }
  return value;
}

void main() {
  group('NumberCurrencyFormatter', () {
    test('groups thousands without decimals', () {
      final value = _typeAll(NumberCurrencyFormatter(), '1234567');
      expect(value.text, equals('1,234,567'));
    });

    test('accepts exactly decimalLength decimal digits', () {
      final value = _typeAll(
        NumberCurrencyFormatter(decimalLength: 2),
        '1234.56',
      );
      expect(value.text, equals('1,234.56'));
    });

    test('rejects a digit beyond decimalLength', () {
      final value = _typeAll(
        NumberCurrencyFormatter(decimalLength: 2),
        '1234.567',
      );
      expect(value.text, equals('1,234.56'));
    });

    test(
      'accepts the single allowed decimal digit when decimalLength is 1',
      () {
        final value = _typeAll(
          NumberCurrencyFormatter(decimalLength: 1),
          '9.5',
        );
        expect(value.text, equals('9.5'));
      },
    );
  });

  group('PhoneNumberFormatter', () {
    test('keeps digit order while dashes are inserted', () {
      final value = _typeAll(PhoneNumberFormatter(), '1234567890');

      expect(value.text, equals('123-456-7890'));
      expect(value.selection, const TextSelection.collapsed(offset: 12));
    });

    test('places the cursor after the typed digit at each dash', () {
      final formatter = PhoneNumberFormatter();

      final afterFour = _typeAll(formatter, '1234');
      expect(afterFour.text, equals('123-4'));
      expect(afterFour.selection.baseOffset, equals(5));

      final afterSeven = _typeAll(formatter, '1234567');
      expect(afterSeven.text, equals('123-456-7'));
      expect(afterSeven.selection.baseOffset, equals(9));
    });

    test('maps a mid-text cursor through the digit count', () {
      // Insert '9' between '1' and '2' of "123-45".
      final value = PhoneNumberFormatter().formatEditUpdate(
        const TextEditingValue(
          text: '123-45',
          selection: TextSelection.collapsed(offset: 1),
        ),
        const TextEditingValue(
          text: '1923-45',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(value.text, equals('192-345'));
      expect(value.selection, const TextSelection.collapsed(offset: 2));
    });

    test('a pasted formatted number keeps the selection in range', () {
      final value = PhoneNumberFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '(555) 123 4567',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );

      expect(value.text, equals('555-123-4567'));
      expect(value.selection, const TextSelection.collapsed(offset: 12));
    });

    test('rejects more than ten digits', () {
      const old = TextEditingValue(
        text: '123-456-7890',
        selection: TextSelection.collapsed(offset: 12),
      );
      final value = _type(PhoneNumberFormatter(), old, '1');

      expect(value, equals(old));
    });
  });
}
