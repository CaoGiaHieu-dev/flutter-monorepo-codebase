/// Flutter-side shared infrastructure.
///
/// Re-exports [platform_kernel] wholesale, so a
/// `package:core_common/core_common.dart` import keeps resolving everything it
/// used to. New code that needs only the pure-Dart foundation — a service
/// locator, `ErrorHandler`, a primitive extension, a global constant — should
/// import `package:platform_kernel/platform_kernel.dart` directly instead and
/// avoid pulling Flutter and go_router in with it.
library;

export 'package:platform_kernel/platform_kernel.dart';

export 'di/di.dart';
export 'src/src.dart';
