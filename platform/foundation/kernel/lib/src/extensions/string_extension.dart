import 'package:dynamic_logger/dynamic_logger.dart';

/// Extension on [String] to provide helper methods for string manipulation
extension StringExtension on String {
  /// Capitalizes the first letter of the string and converts the rest to lowercase
  ///
  /// Example:
  /// ```dart
  /// "hello world".capitalize() // Output: "Hello world"
  /// ```
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }

  /// Capitalizes the first letter of each word in the string
  ///
  /// Example:
  /// ```dart
  /// "hello world".capitalizeWords() // Output: "Hello World"
  /// ```
  String capitalizeWords() {
    if (isEmpty) return this;
    return split(' ').map((word) => word.capitalize()).join(' ');
  }

  /// Checks if the string is a valid email address
  bool get isValidEmail {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);
  }

  /// Checks if the string is a valid phone number
  bool get isValidPhoneNumber {
    return RegExp(r'^\+?[1-9]\d{1,14}$').hasMatch(this);
  }

  /// Checks if the string contains only numeric characters
  bool get isNumeric {
    return RegExp(r'^[0-9]+$').hasMatch(this);
  }

  /// Removes all whitespace from the string
  String get removeWhitespace {
    return replaceAll(RegExp(r'\s+'), '');
  }

  /// Truncates the string to the specified [length] and adds ellipsis if needed
  String truncate(int length, {String ellipsis = '...'}) {
    if (this.length <= length) return this;
    return '${substring(0, length)}$ellipsis';
  }

  /// Converts the string to snake_case
  String get toSnakeCase {
    return replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    ).replaceFirst(RegExp(r'^_'), '');
  }

  /// Converts the string to camelCase
  String get toCamelCase {
    final words = split(RegExp(r'[_\s]+'));
    if (words.isEmpty) return this;

    final first = words.first.toLowerCase();
    final rest = words.skip(1).map((word) => word.capitalize());

    return [first, ...rest].join();
  }

  /// Reverses the string
  String reverse() {
    return split('').reversed.join();
  }
}

/// Extension on [String] for price formatting
extension StringPriceExtension on String {
  /// Formats the string as a price with commas and decimal point
  ///
  /// Example:
  /// ```dart
  /// "1234567.89".formatPrice // Output: "1,234,567.89"
  /// "1234567".formatPrice // Output: "1,234,567"
  /// "-1234567.89".formatPrice // Output: "-1,234,567.89"
  /// ```
  String get formatPrice {
    try {
      // Check if the string is negative
      bool isNegative = contains('-');

      final buffer = StringBuffer();

      // Split the string into integer and decimal parts
      String value = this;
      String decimal = '';
      final valueSplitter = split('.');
      if (valueSplitter.length == 2) {
        value = valueSplitter[0];
        decimal = valueSplitter[1];
      }

      // Reverse the integer part and add commas every 3 digits
      int counter = 0;
      final revertList = value
          .replaceAll('-', '')
          .replaceAll(',', '')
          .split('')
          .toList()
          .reversed
          .toList();

      for (final item in revertList) {
        if (counter == 3) {
          buffer.write(',');
          counter = 0;
        }
        buffer.write(item);
        counter++;
      }

      // Combine the formatted integer part, decimal part and negative sign
      if (decimal.isEmpty) {
        return (isNegative ? '-' : '') + buffer.toString().reverse();
      }

      String result = buffer.toString().reverse();
      if (result.isNotEmpty && result[result.length - 1] == ',') {
        result = result.substring(0, result.length - 1);
      }

      if (isNegative) {
        result = '-$result';
      }

      return [result, decimal].join('.');
    } catch (e) {
      DynamicLogger.log('Cannot format $this', level: LogLevel.ERROR);
      return this;
    }
  }

  /// Formats the string as currency with symbol
  String formatCurrency({String symbol = r'$'}) {
    return '$symbol$formatPrice';
  }
}
