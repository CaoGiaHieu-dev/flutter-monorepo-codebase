import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('ValidationHelper', () {
    group('validateEmail', () {
      test('should return error message when email is null', () {
        final result = ValidationHelper.validateEmail(null);
        expect(result, equals('Email is required'));
      });

      test('should return error message when email is empty', () {
        final result = ValidationHelper.validateEmail('');
        expect(result, equals('Email is required'));
      });

      test('should return error message when email is invalid', () {
        final result = ValidationHelper.validateEmail('invalid-email');
        expect(result, equals('Please enter a valid email address'));
      });

      test('should return null when email is valid', () {
        final result = ValidationHelper.validateEmail('test@example.com');
        expect(result, isNull);
      });
    });

    group('validatePassword', () {
      test('should return error message when password is null', () {
        final result = ValidationHelper.validatePassword(null);
        expect(result, equals('Password is required'));
      });

      test('should return error message when password is too short', () {
        final result = ValidationHelper.validatePassword('Short1');
        expect(result, equals('Password must be at least 8 characters long'));
      });

      test(
        'should return error message when password missing uppercase letter',
        () {
          final result = ValidationHelper.validatePassword('lowercase1');
          expect(
            result,
            equals('Password must contain at least one uppercase letter'),
          );
        },
      );

      test(
        'should return error message when password missing lowercase letter',
        () {
          final result = ValidationHelper.validatePassword('UPPERCASE1');
          expect(
            result,
            equals('Password must contain at least one lowercase letter'),
          );
        },
      );

      test('should return error message when password missing number', () {
        final result = ValidationHelper.validatePassword('NoNumberCase');
        expect(result, equals('Password must contain at least one number'));
      });

      test(
        'should return error message when password missing special char if required',
        () {
          final result = ValidationHelper.validatePassword(
            'WithNumber1',
            requireSpecialChars: true,
          );
          expect(
            result,
            equals('Password must contain at least one special character'),
          );
        },
      );

      test('should return null when password meets all criteria', () {
        final result = ValidationHelper.validatePassword('ValidPass1!');
        expect(result, isNull);
      });
    });

    group('validatePasswordConfirmation', () {
      test('should return error message when confirmation is null', () {
        final result = ValidationHelper.validatePasswordConfirmation(
          'pass',
          null,
        );
        expect(result, equals('Password confirmation is required'));
      });

      test('should return error message when passwords do not match', () {
        final result = ValidationHelper.validatePasswordConfirmation(
          'pass',
          'different',
        );
        expect(result, equals('Passwords do not match'));
      });

      test('should return null when passwords match', () {
        final result = ValidationHelper.validatePasswordConfirmation(
          'pass',
          'pass',
        );
        expect(result, isNull);
      });
    });

    group('validatePhoneNumber', () {
      test('should return error message when phone number is null', () {
        final result = ValidationHelper.validatePhoneNumber(null);
        expect(result, equals('Phone number is required'));
      });

      test('should return error message when phone number is too short', () {
        final result = ValidationHelper.validatePhoneNumber('123');
        expect(result, equals('Phone number must be at least 10 digits'));
      });

      test('should return error message when phone number is too long', () {
        final result = ValidationHelper.validatePhoneNumber(
          '123456789012345678',
        );
        expect(result, equals('Phone number cannot exceed 15 digits'));
      });

      test('should return null when phone number is valid', () {
        final result = ValidationHelper.validatePhoneNumber('0987654321');
        expect(result, isNull);
      });
    });

    group('validateRequired', () {
      test('should return error message when value is null', () {
        final result = ValidationHelper.validateRequired(
          null,
          fieldName: 'Name',
        );
        expect(result, equals('Name is required'));
      });

      test('should return error message when value is empty', () {
        final result = ValidationHelper.validateRequired(
          '   ',
          fieldName: 'Name',
        );
        expect(result, equals('Name is required'));
      });

      test('should return null when value is not empty', () {
        final result = ValidationHelper.validateRequired(
          'John Doe',
          fieldName: 'Name',
        );
        expect(result, isNull);
      });
    });

    group('validateNumeric', () {
      test('should return error message when value is null', () {
        final result = ValidationHelper.validateNumeric(null, fieldName: 'Age');
        expect(result, equals('Age is required'));
      });

      test('should return error message when value is not numeric', () {
        final result = ValidationHelper.validateNumeric(
          'abc',
          fieldName: 'Age',
        );
        expect(result, equals('Age must be a valid number'));
      });

      test('should return null when value is numeric', () {
        final result = ValidationHelper.validateNumeric('25', fieldName: 'Age');
        expect(result, isNull);
      });
    });

    group('validateUrl', () {
      test('should return error message when url is invalid', () {
        final result = ValidationHelper.validateUrl('invalid-url');
        expect(result, equals('Please enter a valid URL'));
      });

      test('should return null when url is valid', () {
        final result = ValidationHelper.validateUrl('https://google.com');
        expect(result, isNull);
      });
    });

    group('dates', () {
      String two(int n) => n.toString().padLeft(2, '0');
      String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

      final today = DateTime.now();
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);

      test('validateDate requires a value', () {
        expect(ValidationHelper.validateDate(null), 'Date is required');
        expect(ValidationHelper.validateDate(''), 'Date is required');
      });

      test('validateDate accepts a real date, a leap day only in a leap '
          'year', () {
        expect(ValidationHelper.validateDate('2026-10-04'), isNull);
        expect(ValidationHelper.validateDate('2024-02-29'), isNull);
        expect(ValidationHelper.validateDate('2026-12-31'), isNull);
      });

      test(
        'validateDate refuses dates that DateTime.parse would roll over',
        () {
          const invalid = 'Please enter a valid date (YYYY-MM-DD)';
          for (final date in [
            '2026-13-45',
            '2026-13-01',
            '2026-02-30',
            '2026-02-29',
            '2026-04-31',
            '2026-00-10',
            '2026-10-00',
            '2026-10-32',
          ]) {
            expect(ValidationHelper.validateDate(date), invalid, reason: date);
          }
        },
      );

      test('validateDate refuses anything that is not YYYY-MM-DD', () {
        const invalid = 'Please enter a valid date (YYYY-MM-DD)';
        for (final date in [
          'tomorrow',
          '2026/10/04',
          '04-10-2026',
          '2026-1-4',
          '2026-10-04T10:00:00',
          ' 2026-10-04',
        ]) {
          expect(ValidationHelper.validateDate(date), invalid, reason: date);
        }
      });

      test('validateFutureDate: today and later pass, yesterday does not', () {
        expect(ValidationHelper.validateFutureDate(ymd(today)), isNull);
        expect(ValidationHelper.validateFutureDate(ymd(tomorrow)), isNull);
        expect(
          ValidationHelper.validateFutureDate(ymd(yesterday)),
          'Date cannot be in the past',
        );
      });

      test('validatePastDate: today and earlier pass, tomorrow does not', () {
        expect(ValidationHelper.validatePastDate(ymd(today)), isNull);
        expect(ValidationHelper.validatePastDate(ymd(yesterday)), isNull);
        expect(
          ValidationHelper.validatePastDate(ymd(tomorrow)),
          'Date cannot be in the future',
        );
      });

      test('both range checks report an invalid date first', () {
        expect(
          ValidationHelper.validateFutureDate('2026-02-30'),
          'Please enter a valid date (YYYY-MM-DD)',
        );
        expect(
          ValidationHelper.validatePastDate(null),
          'Date is required',
        );
      });
    });

    group('combineValidators', () {
      test('should return first error encountered', () {
        final result = ValidationHelper.combineValidators('', [
          ValidationHelper.validateEmail,
          (v) => ValidationHelper.validateMinLength(v, 8),
        ]);
        expect(result, equals('Email is required'));
      });

      test('should return null if all validators pass', () {
        final result = ValidationHelper.combineValidators('test@example.com', [
          ValidationHelper.validateRequired,
          ValidationHelper.validateEmail,
        ]);
        expect(result, isNull);
      });
    });
  });
}
