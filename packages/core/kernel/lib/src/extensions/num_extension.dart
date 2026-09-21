import 'dart:math' as math;

/// Extension methods for numeric values
extension NumExtension on num {
  /// Converts a decimal opacity value (0.0-1.0) to an integer opacity value (0-255)
  ///
  /// This is useful for converting Flutter's decimal opacity values to
  /// integer values used in color alpha channels.
  ///
  /// Example:
  /// ```dart
  /// double opacity = 0.5;
  /// int alphaValue = opacity.toOpacity; // 128
  /// ```
  int get toOpacity => (255.0 * this).round();

  /// Formats the number as a currency string
  String formatCurrency({String symbol = r'$', int decimalPlaces = 2}) {
    return '$symbol${toStringAsFixed(decimalPlaces)}';
  }

  /// Formats the number with thousand separators
  String get formatWithCommas {
    return toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match match) => '${match[1]},',
    );
  }

  /// Converts bytes to human readable format
  String get formatBytes {
    if (this < 1024) return '${this}B';
    if (this < 1024 * 1024) return '${(this / 1024).toStringAsFixed(1)}KB';
    if (this < 1024 * 1024 * 1024)
      return '${(this / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(this / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Clamps the number between [min] and [max] values
  num clampValue(num min, num max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }

  /// Checks if the number is between [min] and [max] (inclusive)
  bool isBetween(num min, num max) {
    return this >= min && this <= max;
  }

  /// Converts the number to a percentage string
  String toPercentage({int decimalPlaces = 1}) {
    return '${(this * 100).toStringAsFixed(decimalPlaces)}%';
  }

  /// Rounds the number to the specified number of decimal places
  double roundToDecimalPlaces(int decimalPlaces) {
    final factor = math.pow(10, decimalPlaces);
    return (this * factor).round() / factor;
  }
}

/// Extension methods for Duration
extension DurationExtension on num {
  /// Converts the number to a Duration in milliseconds
  Duration get milliseconds => Duration(milliseconds: toInt());

  /// Converts the number to a Duration in seconds
  Duration get seconds => Duration(seconds: toInt());

  /// Converts the number to a Duration in minutes
  Duration get minutes => Duration(minutes: toInt());

  /// Converts the number to a Duration in hours
  Duration get hours => Duration(hours: toInt());

  /// Converts the number to a Duration in days
  Duration get days => Duration(days: toInt());
}
