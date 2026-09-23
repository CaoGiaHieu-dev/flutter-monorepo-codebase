/// Constants owned by `domain_core`.
///
/// Domain sits at the centre of the architecture and depends on nothing, so
/// the handful of values its entities need are declared here rather than
/// imported from an infrastructure package.
class DomainConstants {
  DomainConstants._();

  /// Status code a [BaseEntity] treats as a successful envelope.
  static const int SUCCESS_STATUS_CODE = 200;
}
