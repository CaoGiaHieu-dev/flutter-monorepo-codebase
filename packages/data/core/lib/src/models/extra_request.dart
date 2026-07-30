import 'package:freezed_annotation/freezed_annotation.dart';

part 'extra_request.freezed.dart';
part 'extra_request.g.dart';

/// Extra request configuration model for HTTP requests.
@freezed
abstract class ExtraRequest with _$ExtraRequest {
  const ExtraRequest._();

  /// Creates an [ExtraRequest] with optional configuration parameters.
  const factory ExtraRequest({
    /// Whether this request requires authentication token.
    @JsonKey(defaultValue: true) @Default(true) bool needAuthentication,

    /// Whether this request can be retried on failure.
    @JsonKey(defaultValue: true) @Default(true) bool canRetry,
  }) = _ExtraRequest;

  factory ExtraRequest.fromJson(Map<String, dynamic> json) =>
      _$ExtraRequestFromJson(json);
}
