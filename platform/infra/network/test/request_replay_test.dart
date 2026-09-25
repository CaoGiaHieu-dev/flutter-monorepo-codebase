import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestOptions.forReplay', () {
    test('keeps a non-FormData body as is', () {
      final options = RequestOptions(path: '/x', data: {'a': 1});
      expect(options.forReplay(), same(options));
    });

    test('rebuilds a FormData body with the same fields and files', () {
      final original = FormData.fromMap({
        'name': 'value',
        'file': MultipartFile.fromString('content', filename: 'f.txt'),
      });
      final options = RequestOptions(path: '/upload', data: original);

      final replay = options.forReplay().data as FormData;

      expect(replay, isNot(same(original)));
      expect(replay.fields, original.fields);
      expect(replay.files.single.key, 'file');
      expect(
        replay.files.single.value,
        isNot(same(original.files.single.value)),
      );
      expect(replay.files.single.value.filename, 'f.txt');
    });
  });
}
