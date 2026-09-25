import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// `failureMessage` picks the translated sentence from a failure's code, so
/// no screen shows `AppFailure.message` (an English diagnostic).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('no connection', () {
    for (final code in [ErrorCodes.NO_INTERNET, ErrorCodes.CONNECTION_ERROR]) {
      expect(en.failureMessage(code), en.noInternetConnection);
    }
  });

  test('timeouts', () {
    for (final code in [
      ErrorCodes.CONNECTION_TIMEOUT,
      ErrorCodes.TRANSFORM_TIMEOUT,
    ]) {
      expect(en.failureMessage(code), en.connectionTimedOut);
    }
  });

  test('any other network code', () {
    for (final code in [
      ErrorCodes.NETWORK_ERROR,
      ErrorCodes.HTTP_ERROR,
      ErrorCodes.BAD_CERTIFICATE,
      ErrorCodes.NETWORK_UNKNOWN,
    ]) {
      expect(en.failureMessage(code), en.networkError);
    }
  });

  test('an HTTP 5xx', () {
    for (final code in [500, 503, 599]) {
      expect(en.failureMessage(code), en.serverUnavailable);
    }
  });

  test('everything else, and no code at all', () {
    for (final code in [
      null,
      400,
      403,
      ErrorCodes.RESPONSE_REJECTED,
      ErrorCodes.UNKNOWN,
    ]) {
      expect(en.failureMessage(code), en.somethingWentWrong);
    }
  });

  test('answers in the user\'s language', () {
    expect(
      vi.failureMessage(ErrorCodes.NO_INTERNET),
      isNot(en.failureMessage(ErrorCodes.NO_INTERNET)),
    );
    expect(vi.failureMessage(503), vi.serverUnavailable);
  });
}
