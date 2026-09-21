import 'package:freezed_annotation/freezed_annotation.dart';

part 'extra_request.freezed.dart';
part 'extra_request.g.dart';

/// Typed builder for Dio's `RequestOptions.extra`, read by `core_network`'s
/// interceptors.
///
/// Pass [toExtra] wherever a request is issued — Retrofit exposes `@Extras()`,
/// plain Dio takes `Options(extra: ...)`:
///
/// ```dart
/// @POST(AuthApiConstants.LOGIN)
/// Future<UserResponse> login(
///   @Body() LoginRequest body,
///   @Extras() Map<String, dynamic> extras,
/// );
///
/// api.login(body, const ExtraRequest(needAuthentication: false).toExtra());
/// ```
///
/// > The field names are a **wire contract** with `core_network`: they must
/// > stay equal to `NetworkConstants.EXTRA_NEED_AUTHENTICATION` and
/// > `EXTRA_CAN_RETRY`. `data_core` deliberately does not depend on
/// > `core_network`, so nothing but `extra_request_test.dart` enforces that —
/// > renaming a field here silently disables the flag instead of failing the
/// > build.
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

  /// The map to hand to Dio as `RequestOptions.extra`.
  ///
  /// Both flags default to `true`, matching the interceptors' own fallback, so
  /// sending the full map is always safe.
  Map<String, dynamic> toExtra() => toJson();
}
