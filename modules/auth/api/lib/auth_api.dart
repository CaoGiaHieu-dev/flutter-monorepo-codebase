/// SAMPLE CODE — the public API of the `auth` module.
///
/// The contracts *other features* use to reach auth without depending on
/// `feature_auth`: `AuthNavigator` (onboarding's "Get started") and
/// `IAuthActionHandler` (settings' logout row). `feature_auth` implements
/// them; consumers resolve them with `getItOrNull`.
///
/// An API package depends on the foundation and Flutter only — never on this
/// module's domain/data/feature or on another module (arch_check R3). Shell-
/// facing, product-neutral contracts (the session, the sign-in location) live
/// in `core_di` instead.
///
/// `remove_sample.dart auth` keeps this package while another package still
/// imports it, and says so.
library;

// Auto-generated exports, do not edit manually.
export 'src/src.dart';
