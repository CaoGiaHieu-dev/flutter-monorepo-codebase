import 'package:domain_core/domain_core.dart';
import 'package:test/test.dart';

BaseEntity<String> _envelope(int code) =>
    BaseEntity<String>(statusCode: code, data: 'x');

void main() {
  group('BaseEntity.isSuccess', () {
    test(
      'an envelope with no status code is a success (the default is 200)',
      () {
        const entity = BaseEntity<String>(data: 'x');

        expect(entity.statusCode, 200);
        expect(entity.isSuccess, isTrue);
        expect(entity.hasError, isFalse);
      },
    );

    test('every 2xx is a success: a 201 create and a 204 are not rejected', () {
      for (final code in [200, 201, 202, 204, 206, 299]) {
        expect(_envelope(code).isSuccess, isTrue, reason: '$code');
        expect(_envelope(code).hasError, isFalse, reason: '$code');
      }
    });

    test('anything outside 2xx is an error', () {
      for (final code in [0, 100, 199, 300, 304, 400, 401, 404, 500, 503]) {
        expect(_envelope(code).isSuccess, isFalse, reason: '$code');
        expect(_envelope(code).hasError, isTrue, reason: '$code');
      }
    });

    test('fromJson reads the envelope\'s statusCode', () {
      final created = BaseEntity<String>.fromJson({
        'statusCode': 201,
        'data': 'new',
      }, (json) => json! as String);

      expect(created.isSuccess, isTrue);
      expect(created.data, 'new');
    });
  });
}
