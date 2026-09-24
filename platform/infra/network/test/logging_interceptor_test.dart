import 'package:core_network/core_network.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logs land in a shared console and get pasted into bug reports, so the
/// interceptor masks credentials before `DynamicLogger` ever sees them. These
/// pin the masking itself — the part that decides what leaks.
void main() {
  const redacted = '***REDACTED***';

  group('LoggingInterceptor.redactHeaders', () {
    test('masks Authorization and Cookie, whatever their case', () {
      final out = LoggingInterceptor.redactHeaders({
        'Authorization': 'Bearer secret-jwt',
        'cookie': 'session=abc',
        'Set-Cookie': 'session=def',
        'Proxy-Authorization': 'Basic xyz',
      });
      expect(out.values, everyElement(redacted));
    });

    test('keeps every other header as it was', () {
      final out = LoggingInterceptor.redactHeaders({
        'content-type': 'application/json',
        NetworkConstants.LANGUAGE_HEADER: 'VI',
      });
      expect(out, {'content-type': 'application/json', 'language': 'VI'});
    });

    test('never mutates the request\'s own headers', () {
      final headers = <String, dynamic>{'Authorization': 'Bearer t'};
      LoggingInterceptor.redactHeaders(headers);
      expect(headers['Authorization'], 'Bearer t');
    });
  });

  group('LoggingInterceptor.redactBody', () {
    test('masks password, token and access_token fields', () {
      final out = LoggingInterceptor.redactBody({
        'email': 'a@b.c',
        'password': 'hunter2',
        'token': 't',
        'access_token': 'at',
      });
      expect(out, {
        'email': 'a@b.c',
        'password': redacted,
        'token': redacted,
        'access_token': redacted,
      });
    });

    test('matches ignoring case, `_` and `-`', () {
      final out = LoggingInterceptor.redactBody({
        'refreshToken': 'r',
        'ID-TOKEN': 'i',
        'client_secret': 's',
      }) as Map;
      expect(out.values, everyElement(redacted));
    });

    test('masks at any depth, inside maps and lists', () {
      final out = LoggingInterceptor.redactBody({
        'data': {
          'user': {'id': '1', 'accessToken': 'deep'},
          'sessions': [
            {'token': 'x', 'device': 'phone'},
          ],
        },
      });
      expect(out, {
        'data': {
          'user': {'id': '1', 'accessToken': redacted},
          'sessions': [
            {'token': redacted, 'device': 'phone'},
          ],
        },
      });
    });

    test('leaves non-map bodies alone', () {
      expect(LoggingInterceptor.redactBody('password=plain'), 'password=plain');
      expect(LoggingInterceptor.redactBody(null), isNull);
      expect(LoggingInterceptor.redactBody([1, 2]), [1, 2]);
    });

    test('does not match a key that merely contains a secret word', () {
      final out = LoggingInterceptor.redactBody({
        'password_hint': 'pet name',
        'tokenType': 'Bearer',
      });
      expect(out, {'password_hint': 'pet name', 'tokenType': 'Bearer'});
    });
  });
}
