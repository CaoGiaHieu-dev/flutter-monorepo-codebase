import 'dart:math';

import 'package:flutter/services.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// A [TextInputFormatter] that formats numeric input with currency-style formatting.
///
/// This formatter provides real-time formatting of numeric input with comma
/// separators for thousands, configurable decimal places, and length constraints.
/// It handles cursor positioning during formatting and supports both '.' and ','
/// as decimal separators (converting ',' to '.').
///
/// Features:
/// - Automatic comma insertion for thousands separation
/// - Configurable decimal place limits
/// - Maximum value length enforcement
/// - Proper cursor positioning during formatting
/// - Decimal separator normalization
///
/// Example usage:
/// ```dart
/// TextFormField(
///   inputFormatters: [
///     NumberCurrencyFormatter(decimalLength: 2, valueLength: 10),
///   ],
/// )
/// ```
class NumberCurrencyFormatter extends TextInputFormatter {
  /// Creates a [NumberCurrencyFormatter] with specified formatting constraints.
  ///
  /// Parameters:
  /// - [decimalLength]: Maximum digits after decimal point (default: 0, no decimals)
  /// - [valueLength]: Maximum total digits in the value (default: 12)
  NumberCurrencyFormatter({this.decimalLength = 0, this.valueLength = 12});

  /// The maximum number of digits allowed after the decimal point.
  final int decimalLength;

  /// The maximum number of digits allowed in the entire value, including the decimal part.
  final int valueLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Check if the new value is different from the old value and if it has a new character added.
    String nextInputChar = '';
    if (newValue.text != oldValue.text &&
        newValue.text.length > oldValue.text.length) {
      // Find the newly added character.
      if (newValue.text.contains(oldValue.text)) {
        nextInputChar = newValue.text[newValue.text.length - 1];
      } else {
        nextInputChar = newValue.text.substring(
          newValue.selection.extentOffset - 1,
          newValue.selection.extentOffset,
        );
      }
    }

    // Replace ',' with '.' for decimal separator.
    if (nextInputChar == ',') {
      newValue = newValue.copyWith(
        text: newValue.text.replaceRange(
          newValue.selection.baseOffset,
          newValue.selection.extentOffset,
          '.',
        ),
      );
    }

    // Get the text before the cursor in both the old and new values.
    final oldTextBeforeCursor = oldValue.text.formatPrice.substring(
      0,
      min(oldValue.selection.baseOffset, oldValue.text.formatPrice.length),
    );
    // Count the number of groups (separated by ',') in the old text before the cursor.
    final digestOldTextChar = oldTextBeforeCursor.split(',').length;

    final newTextBeforeCursor = newValue.text.formatPrice.substring(
      0,
      min(newValue.selection.baseOffset, newValue.text.formatPrice.length),
    );
    // Count the number of groups (separated by ',') in the new text before the cursor.
    final digestNewTextChar = newTextBeforeCursor.split(',').length;

    // Calculate the difference in the number of groups, which will be used to adjust the cursor position.
    final cursorPaddingLength = digestNewTextChar - digestOldTextChar;

    // Remove ',' from the new text value.
    final newValueCustom = newValue.copyWith(
      text: newValue.text.replaceAll(',', ''),
    );

    // If there's no decimal length specified, return the formatted text value with adjusted cursor position.
    if (decimalLength == 0) {
      return newValueCustom.copyWith(
        text: newValueCustom.text.formatPrice,
        selection: newValueCustom.selection.copyWith(
          baseOffset: min(
            newValueCustom.selection.baseOffset + cursorPaddingLength,
            newValueCustom.text.formatPrice.length,
          ),
          extentOffset: min(
            newValueCustom.selection.extentOffset + cursorPaddingLength,
            newValueCustom.text.formatPrice.length,
          ),
        ),
        composing: newValueCustom.composing,
      );
    }

    // Count the number of decimal dots in the new text value.
    int decimalDot = 0;
    for (int i = 0; i < newValueCustom.text.length; i++) {
      if (newValueCustom.text[i] == '.') {
        decimalDot++;
      }
      if (decimalDot > 1) {
        break;
      }
    }

    // If there are more than one decimal dots, return the old value.
    if (decimalDot >= 2) {
      return oldValue;
    }

    // Split the new and old text values by '.'.
    final textGroup = newValueCustom.text.split('.');
    final oldTextGroup = oldValue.text.split('.');

    // If there's a decimal part in the new text value, handle the decimal part.
    if (textGroup.length == 2) {
      // Extract and validate decimal and integer parts
      String decimalText = _validateDecimalPart(
        textGroup[1],
        oldTextGroup,
        decimalLength,
      );
      String valueText = _validateIntegerPart(
        textGroup[0],
        oldTextGroup,
        valueLength,
      );

      // Check if parts remain unchanged from old values
      bool keepDigits = _shouldKeepDigits(decimalText, oldTextGroup);
      bool keepDecimal = _shouldKeepDecimal(valueText, oldTextGroup);

      // Keep the cursor offset if both the decimal and integer parts are the same.
      bool keepCursorOffset = keepDigits && keepDecimal;

      // Construct the new text value by joining the formatted integer and decimal parts.
      var newText = [valueText.formatPrice, decimalText].join('.');

      // Calculate the additional length required for the dot in the new text.
      int addDotLength = 0;
      if (oldValue.text.split('.').length - 1 == 0) {
        addDotLength = 1;
      } else if (decimalText.isEmpty) {
        addDotLength = 1;
      }

      // Return the formatted text value with adjusted cursor position.
      return newValueCustom.copyWith(
        text: newText,
        selection: newValueCustom.selection.copyWith(
          baseOffset: keepCursorOffset
              ? oldValue.selection.baseOffset + addDotLength
              : min(
                  newValueCustom.selection.baseOffset + cursorPaddingLength,
                  newText.formatPrice.length + addDotLength,
                ),
          extentOffset: keepCursorOffset
              ? oldValue.selection.extentOffset + addDotLength
              : min(
                  newValueCustom.selection.extentOffset + cursorPaddingLength,
                  newText.formatPrice.length + addDotLength,
                ),
        ),
        composing: newValueCustom.composing,
      );
    } else {
      // If there's no decimal part in the new text value, handle the integer part.
      final newValueCustomPath = newValueCustom.text.split('.');
      int maxLength = valueLength;

      // Adjust the maximum length if there's a decimal part in the new text value.
      if (newValueCustomPath.length > 1) {
        maxLength += decimalLength;
      }

      // If the new text value is longer than the maximum allowed length, return the old value.
      if (newValueCustom.text.length > maxLength) {
        return oldValue;
      }

      // Return the formatted text value with adjusted cursor position.
      return newValueCustom.copyWith(
        text: newValueCustom.text.formatPrice,
        selection: newValueCustom.selection.copyWith(
          baseOffset: min(
            newValueCustom.selection.baseOffset + cursorPaddingLength,
            newValueCustom.text.formatPrice.length,
          ),
          extentOffset: min(
            newValueCustom.selection.extentOffset + cursorPaddingLength,
            newValueCustom.text.formatPrice.length,
          ),
        ),
        composing: newValueCustom.composing,
      );
    }
  }

  /// Validates and returns the decimal part, respecting length constraints.
  String _validateDecimalPart(
    String decimalText,
    List<String> oldTextGroup,
    int decimalLength,
  ) {
    final cleanDecimal = decimalText.replaceAll(',', '');
    // Reject only once the limit is exceeded — `decimalLength` digits are
    // allowed, so typing the last permitted digit must be kept.
    if (cleanDecimal.length > decimalLength && oldTextGroup.length > 1) {
      return oldTextGroup[1];
    }
    return cleanDecimal;
  }

  /// Validates and returns the integer part, respecting length constraints.
  String _validateIntegerPart(
    String valueText,
    List<String> oldTextGroup,
    int valueLength,
  ) {
    if (valueText.length > valueLength) {
      return oldTextGroup[0].replaceAll(',', '');
    }
    return valueText;
  }

  /// Determines if decimal digits should be kept unchanged.
  bool _shouldKeepDigits(String decimalText, List<String> oldTextGroup) {
    return oldTextGroup.length > 1 ? decimalText == oldTextGroup[1] : true;
  }

  /// Determines if decimal part should be kept unchanged.
  bool _shouldKeepDecimal(String valueText, List<String> oldTextGroup) {
    return valueText == oldTextGroup[0].replaceAll(',', '');
  }
}

/// A [TextInputFormatter] that restricts input to numeric characters only.
///
/// This formatter allows only digits and optionally decimal points,
/// rejecting all other characters. Useful for simple numeric input
/// fields that don't require currency formatting.
///
/// Example usage:
/// ```dart
/// TextFormField(
///   inputFormatters: [
///     NumericInputFormatter(allowDecimal: true),
///   ],
/// )
/// ```
class NumericInputFormatter extends TextInputFormatter {
  /// Creates a [NumericInputFormatter] with optional decimal support.
  ///
  /// Parameters:
  /// - [allowDecimal]: Whether to allow decimal points (default: false)
  NumericInputFormatter({this.allowDecimal = false});

  /// Whether decimal points are allowed in the input.
  final bool allowDecimal;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final regex = allowDecimal ? RegExp(r'^\d*\.?\d*$') : RegExp(r'^\d*$');

    if (regex.hasMatch(newValue.text)) {
      return newValue;
    }

    return oldValue;
  }
}

/// A [TextInputFormatter] that capitalizes the first letter of each word.
///
/// This formatter automatically converts text to title case, capitalizing
/// the first letter of each word while keeping other letters lowercase.
/// Useful for name fields and titles.
///
/// Example usage:
/// ```dart
/// TextFormField(
///   inputFormatters: [CapitalizeWordsFormatter()],
/// )
/// ```
class CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final capitalizedText = newValue.text.capitalizeWords();

    return newValue.copyWith(
      text: capitalizedText,
      selection: newValue.selection,
    );
  }
}

/// A [TextInputFormatter] that formats phone numbers with dashes.
///
/// This formatter automatically formats phone numbers in the pattern
/// XXX-XXX-XXXX as the user types. It removes non-digit characters
/// and inserts dashes at appropriate positions.
///
/// Example usage:
/// ```dart
/// TextFormField(
///   inputFormatters: [PhoneNumberFormatter()],
/// )
/// ```
class PhoneNumberFormatter extends TextInputFormatter {
  static final _nonDigit = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(_nonDigit, '');

    if (digitsOnly.length > 10) {
      return oldValue;
    }

    final formatted = _format(digitsOnly);
    final selection = newValue.selection;

    return TextEditingValue(
      text: formatted,
      // The edit's selection indexes the unformatted text; carried over
      // as-is it lands on the wrong digit once dashes are inserted (and can
      // point past the end). Map it through the digit count instead.
      selection: selection.isValid
          ? selection.copyWith(
              baseOffset: _mapOffset(
                selection.baseOffset,
                newValue.text,
                formatted,
              ),
              extentOffset: _mapOffset(
                selection.extentOffset,
                newValue.text,
                formatted,
              ),
            )
          : TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Formats up to ten digits as `XXX`, `XXX-XXX` or `XXX-XXX-XXXX`.
  String _format(String digits) {
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-'
        '${digits.substring(6)}';
  }

  /// Returns the offset in [formatted] that sits after the same number of
  /// digits as [offset] does in [raw].
  int _mapOffset(int offset, String raw, String formatted) {
    final digitsBefore = raw
        .substring(0, offset.clamp(0, raw.length))
        .replaceAll(_nonDigit, '')
        .length;
    if (digitsBefore == 0) return 0;

    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (!_nonDigit.hasMatch(formatted[i]) && ++seen == digitsBefore) {
        return i + 1;
      }
    }
    return formatted.length;
  }
}
