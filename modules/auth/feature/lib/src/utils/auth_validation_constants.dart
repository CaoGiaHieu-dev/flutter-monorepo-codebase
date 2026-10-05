/// Input rules of the sign-in form, in one place.
///
/// The form checks a password against [MIN_PASSWORD_LENGTH] and the message it
/// shows (`passwordTooShort`) takes the same number as a placeholder, so the
/// rule and the sentence cannot drift apart.
class AuthValidationConstants {
  AuthValidationConstants._();

  /// Fewest characters the form accepts in the password field.
  static const int MIN_PASSWORD_LENGTH = 6;
}
