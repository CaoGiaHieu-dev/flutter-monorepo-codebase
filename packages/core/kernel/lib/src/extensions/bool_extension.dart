part of 'extensions.dart';

/// Extension methods for boolean values
extension BoolExtension on bool {
  /// Toggles the boolean value
  ///
  /// Returns the opposite of the current boolean value.
  ///
  /// Example:
  /// ```dart
  /// bool isVisible = true;
  /// bool hidden = isVisible.toggle(); // false
  /// ```
  bool toggle() {
    return !this;
  }
}
