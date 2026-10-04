/// Constants owned by `domain_core`.
///
/// Domain sits at the centre of the architecture and depends on nothing, so
/// the handful of values its entities need are declared here rather than
/// imported from an infrastructure package.
class DomainConstants {
  DomainConstants._();

  /// The lowest status code a [BaseEntity] treats as a successful envelope —
  /// and the `@Default` of an envelope without a `statusCode`.
  static const int SUCCESS_STATUS_CODE = 200;

  /// The first status code above the successful range: `2xx` is
  /// `SUCCESS_STATUS_CODE <= code < SUCCESS_STATUS_CEILING`.
  static const int SUCCESS_STATUS_CEILING = 300;
}
