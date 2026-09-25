/// The app shell's infrastructure adapters, shared by every app under
/// `apps/`: `NetworkConfigImpl` (+ its `SslPinningConfig` binding),
/// `LanguageStorageImpl` / `ThemeStorageImpl` behind `core_di`'s
/// `ILanguageStorage` / `IThemeStorage`, and the `AppBootStorage` boot flag.
///
/// Split out of `platform_app_shell` so the shell package keeps composition,
/// UI and app state only. Like it, this package imports no module (arch_check
/// R1): the session arrives through `core_di`'s `ISessionGateway`,
/// resolved with `getItOrNull`.
library;

// Auto-generated exports, do not edit manually.
export 'di/module.dart';
export 'di/module.module.dart';
export 'di/network_binding_module.dart';
export 'src/app_boot_storage.dart';
export 'src/language_storage_impl.dart';
export 'src/network_config_impl.dart';
export 'src/theme_storage_impl.dart';
export 'src/utils/app_boot_storage_keys.dart';
export 'src/utils/language_storage_keys.dart';
export 'src/utils/theme_storage_keys.dart';
