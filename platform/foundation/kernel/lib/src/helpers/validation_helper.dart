import 'package:email_validator/email_validator.dart';

/// Helper class for common validation operations.
///
/// This utility class provides static methods for validating various types
/// of user input including emails, passwords, phone numbers, and more.
/// All validation methods return null for valid input or an error message
/// string for invalid input, making them compatible with Flutter form validators.
///
/// Example usage:
/// ```dart
/// TextFormField(
///   validator: ValidationHelper.validateEmail,
/// )
///
/// // Or combine multiple validators
/// TextFormField(
///   validator: (value) => ValidationHelper.combineValidators(value, [
///     ValidationHelper.validateRequired,
///     ValidationHelper.validateEmail,
///   ]),
/// )
/// ```
class ValidationHelper {
  /// Validates an email address format.
  ///
  /// Uses the email_validator package to check if the email format is valid.
  /// Returns null if valid, error message if invalid or empty.
  ///
  /// Parameters:
  /// - [email]: The email string to validate
  ///
  /// Returns null for valid emails, error message for invalid ones.
  static String? validateEmail(String? email) {
    if (email == null || email.isEmpty) {
      return 'Email is required';
    }

    if (!EmailValidator.validate(email)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validates a password against configurable security requirements.
  ///
  /// Checks password strength based on length and character requirements.
  /// All requirements are configurable through optional parameters.
  ///
  /// Parameters:
  /// - [password]: The password string to validate
  /// - [minLength]: Minimum required length (default: 8)
  /// - [requireUppercase]: Whether uppercase letters are required (default: true)
  /// - [requireLowercase]: Whether lowercase letters are required (default: true)
  /// - [requireNumbers]: Whether numbers are required (default: true)
  /// - [requireSpecialChars]: Whether special characters are required (default: false)
  ///
  /// Returns null if valid, specific error message if requirements not met.
  static String? validatePassword(
    String? password, {
    int minLength = 8,
    bool requireUppercase = true,
    bool requireLowercase = true,
    bool requireNumbers = true,
    bool requireSpecialChars = false,
  }) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < minLength) {
      return 'Password must be at least $minLength characters long';
    }

    if (requireUppercase && !password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (requireLowercase && !password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (requireNumbers && !password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    if (requireSpecialChars &&
        !password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character';
    }

    return null;
  }

  /// Validates that password confirmation matches the original password.
  ///
  /// Ensures that the confirmation password field matches the original
  /// password field exactly. Used in registration and password change forms.
  ///
  /// Parameters:
  /// - [password]: The original password
  /// - [confirmPassword]: The confirmation password to validate
  ///
  /// Returns null if passwords match, error message if they don't match or confirmation is empty.
  static String? validatePasswordConfirmation(
    String? password,
    String? confirmPassword,
  ) {
    if (confirmPassword == null || confirmPassword.isEmpty) {
      return 'Password confirmation is required';
    }

    if (password != confirmPassword) {
      return 'Passwords do not match';
    }

    return null;
  }

  /// Validates a phone number format and length.
  ///
  /// Checks that the phone number contains an appropriate number of digits
  /// (between 10 and 15) after removing all non-digit characters.
  /// This provides basic validation suitable for most international formats.
  ///
  /// Parameters:
  /// - [phoneNumber]: The phone number string to validate
  ///
  /// Returns null if valid, error message if invalid format or length.
  static String? validatePhoneNumber(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      return 'Phone number is required';
    }

    // Remove all non-digit characters for validation
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.length < 10) {
      return 'Phone number must be at least 10 digits';
    }

    if (digitsOnly.length > 15) {
      return 'Phone number cannot exceed 15 digits';
    }

    return null;
  }

  /// Validates that a field is not empty or null.
  ///
  /// Checks that the value is not null and contains non-whitespace characters.
  /// Commonly used as the first validator in a chain of validations.
  ///
  /// Parameters:
  /// - [value]: The value to validate
  /// - [fieldName]: Name of the field for error messages (default: 'Field')
  ///
  /// Returns null if value is present, error message if empty or null.
  static String? validateRequired(String? value, {String fieldName = 'Field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validates minimum length
  /// Returns null if valid, error message if invalid
  static String? validateMinLength(
    String? value,
    int minLength, {
    String fieldName = 'Field',
  }) {
    if (value == null || value.length < minLength) {
      return '$fieldName must be at least $minLength characters long';
    }
    return null;
  }

  /// Validates maximum length
  /// Returns null if valid, error message if invalid
  static String? validateMaxLength(
    String? value,
    int maxLength, {
    String fieldName = 'Field',
  }) {
    if (value != null && value.length > maxLength) {
      return '$fieldName cannot exceed $maxLength characters';
    }
    return null;
  }

  /// Validates that a value is numeric
  /// Returns null if valid, error message if invalid
  static String? validateNumeric(String? value, {String fieldName = 'Field'}) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }

    if (double.tryParse(value) == null) {
      return '$fieldName must be a valid number';
    }

    return null;
  }

  /// Validates that a value is a positive number
  /// Returns null if valid, error message if invalid
  static String? validatePositiveNumber(
    String? value, {
    String fieldName = 'Field',
  }) {
    final numericValidation = validateNumeric(value, fieldName: fieldName);
    if (numericValidation != null) return numericValidation;

    final number = double.parse(value!);
    if (number <= 0) {
      return '$fieldName must be a positive number';
    }

    return null;
  }

  /// Validates a URL
  /// Returns null if valid, error message if invalid
  static String? validateUrl(String? url) {
    if (url == null || url.isEmpty) {
      return 'URL is required';
    }

    final urlRegex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$',
    );

    if (!urlRegex.hasMatch(url)) {
      return 'Please enter a valid URL';
    }

    return null;
  }

  /// Validates a date string in YYYY-MM-DD format.
  ///
  /// The date has to exist: `2026-13-45` and `2026-02-30` are refused (Dart's
  /// `DateTime.parse` would roll them over into the next month or year and
  /// accept them), and a leap day only in a leap year.
  ///
  /// Returns null if valid, error message if invalid
  static String? validateDate(String? date) {
    if (date == null || date.isEmpty) {
      return 'Date is required';
    }

    if (_parseDate(date) == null) {
      return 'Please enter a valid date (YYYY-MM-DD)';
    }
    return null;
  }

  /// Validates that a date is not in the past: today and later pass.
  ///
  /// Compared by calendar day, not by instant — a date-only string reads as
  /// midnight, which is before "now" for the whole of today.
  ///
  /// Returns null if valid, error message if invalid
  static String? validateFutureDate(String? date) {
    final dateValidation = validateDate(date);
    if (dateValidation != null) return dateValidation;

    if (_parseDate(date!)!.isBefore(_today())) {
      return 'Date cannot be in the past';
    }

    return null;
  }

  /// Validates that a date is not in the future: today and earlier pass.
  ///
  /// Returns null if valid, error message if invalid
  static String? validatePastDate(String? date) {
    final dateValidation = validateDate(date);
    if (dateValidation != null) return dateValidation;

    if (_parseDate(date!)!.isAfter(_today())) {
      return 'Date cannot be in the future';
    }

    return null;
  }

  /// [date] (`YYYY-MM-DD`) as local midnight, or null when it is not a real
  /// calendar date.
  static DateTime? _parseDate(String date) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    // `DateTime` normalises an overflowing month or day instead of failing.
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  /// Local midnight of the current day.
  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Combines multiple validators into a single validation function.
  ///
  /// Executes validators in sequence and returns the first error message
  /// encountered. If all validators pass, returns null. This allows for
  /// complex validation logic by chaining simple validators together.
  ///
  /// Parameters:
  /// - [value]: The value to validate
  /// - [validators]: List of validator functions to execute
  ///
  /// Returns the first error message found, or null if all validators pass.
  ///
  /// Example:
  /// ```dart
  /// ValidationHelper.combineValidators(value, [
  ///   ValidationHelper.validateRequired,
  ///   ValidationHelper.validateEmail,
  ///   (v) => ValidationHelper.validateMinLength(v, 5),
  /// ])
  /// ```
  static String? combineValidators(
    String? value,
    List<String? Function(String?)> validators,
  ) {
    for (final validator in validators) {
      final result = validator(value);
      if (result != null) return result;
    }
    return null;
  }
}
