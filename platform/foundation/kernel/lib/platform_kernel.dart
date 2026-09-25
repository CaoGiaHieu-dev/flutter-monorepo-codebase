/// Pure-Dart foundation shared by every package.
///
/// It declares **no** `flutter` dependency, and no UI, Firebase, plugin or
/// routing package. That is the whole point: this is the one package everything
/// else depends on, so its dependency list becomes everyone's. `arch_check`
/// rule R9 keeps it that way.
library;

// Auto-generated exports, do not edit manually.
export 'src/config/ssl_pinning_config.dart';
export 'src/di/service_locator.dart';
export 'src/enums/app_enums.dart';
export 'src/error/error_classifier.dart';
export 'src/error/error_handler.dart';
export 'src/error/exceptions.dart';
export 'src/error/failures.dart';
export 'src/extensions/list_extension.dart';
export 'src/extensions/string_extension.dart';
export 'src/utils/env_constants.dart';
export 'src/utils/error_codes.dart';
export 'src/utils/helpers/json_converters.dart';
export 'src/utils/helpers/type_helper.dart';
export 'src/utils/helpers/validation_helper.dart';
export 'src/utils/message_queue.dart';
