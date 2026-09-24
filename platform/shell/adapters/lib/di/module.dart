import 'package:injectable/injectable.dart';

/// Registers the shell's infrastructure adapters: the storage adapters behind
/// `ILanguageStorage` / `IThemeStorage`, the `AppBootStorage` boot flag,
/// `NetworkConfig` and its `SslPinningConfig` binding.
///
/// ## Where it runs
///
/// Each app lists `platform_shell_adapters` first in its `shell` DI group —
/// **after** `core` (every adapter injects `StorageManager`, registered by
/// `core_storage`), **before** `platform_app_shell` and **before** `ui`:
/// `core_base_ui`'s `ThemeProvider` and `LanguageProvider` inject the two
/// storage adapters, so they must already be registered when the `ui` group
/// initialises. Move it later and boot throws `"<Type> is not registered"` —
/// which `flutter analyze` cannot see; the apps' `test/di_smoke_test.dart`
/// can.
///
/// `NetworkConfig` is lazy, and so is every Dio client that needs it, so its
/// position only has to precede the first request — the adapters' slot is
/// far ahead of anything that issues one.
@InjectableInit.microPackage()
void initMicroPackage() {}
