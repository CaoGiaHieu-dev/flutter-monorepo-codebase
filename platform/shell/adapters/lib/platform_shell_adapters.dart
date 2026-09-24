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
export 'di/di.dart';
export 'src/src.dart';
