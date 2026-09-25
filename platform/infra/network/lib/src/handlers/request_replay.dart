import 'package:dio/dio.dart';

/// Replaying a failed request — after a token refresh or a retry prompt.
extension RequestReplay on RequestOptions {
  /// These options, ready to be sent again.
  ///
  /// A [FormData] body is a stream that can be read only once, so it is
  /// rebuilt with the same fields and cloned files; any other body is reused
  /// as is.
  RequestOptions forReplay() {
    final body = data;
    if (body is! FormData) return this;
    final formData = FormData()..fields.addAll(body.fields);
    for (final file in body.files) {
      formData.files.add(MapEntry(file.key, file.value.clone()));
    }
    return copyWith(data: formData);
  }
}
