/// Re-exports `platform_kernel` wholesale, so one
/// `package:core_common/core_common.dart` import resolves the pure-Dart
/// foundation too. Code that needs only that foundation — a service locator,
/// `ErrorHandler`, a primitive extension, a global constant — should import
/// `package:platform_kernel/platform_kernel.dart` directly instead and avoid
/// pulling Flutter and go_router in with it.
///
/// A regular source file rather than a line in the barrel: the barrel
/// generator rewrites barrels and drops any hand-written `export`.
library;

export 'package:platform_kernel/platform_kernel.dart';
