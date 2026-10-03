/// Pure-Dart foundation shared by every package.
///
/// It declares **no** `flutter` dependency, and no UI, Firebase, plugin or
/// routing package. That is the whole point: this is the one package everything
/// else depends on, so its dependency list becomes everyone's. `arch_check`
/// rule R9 keeps it that way.
library;

// Auto-generated exports, do not edit manually.
export 'src/error/error_classifier.dart';
export 'src/error/error_handler.dart';
export 'src/error/exceptions.dart';
export 'src/error/failures.dart';
export 'src/flavor.dart';
export 'src/helpers/type_helper.dart';
export 'src/helpers/validation_helper.dart';
export 'src/profile/app_facts.dart';
export 'src/profile/app_platform.dart';
export 'src/profile/app_profile.dart';
export 'src/profile/app_runtime.dart';
export 'src/profile/capability_expectation.dart';
export 'src/profile/display_profile.dart';
export 'src/profile/env_rule.dart';
export 'src/profile/platform_facts.dart';
export 'src/profile/platform_switch.dart';
export 'src/profile/profile_problem.dart';
export 'src/profile/register_app_profile.dart';
export 'src/profile/router_profile.dart';
export 'src/profile/ssl_pinning.dart';
export 'src/service_locator.dart';
export 'src/ssl_pinning_config.dart';
export 'src/string_extension.dart';
export 'src/utils/env_constants.dart';
export 'src/utils/error_codes.dart';
export 'src/utils/profile_constants.dart';
