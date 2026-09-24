import 'package:injectable/injectable.dart';

/// Registers the shell's own singletons: the storage adapters behind
/// `ILanguageStorage` / `IThemeStorage`, the boot flag, `NetworkConfig`, the
/// router and the two app-level providers.
///
/// ## Where it runs
///
/// Each app lists `platform_app_shell` in its own DI group, **after** `core`
/// and **before** `ui`. That is exactly where these registrations ran while
/// they lived inside the app: `core_base_ui`'s `ThemeProvider` and
/// `LanguageProvider` inject the two storage adapters, so the adapters must
/// already be registered when the `ui` group initialises. Move this group
/// later and boot throws `"<Type> is not registered"` — which `flutter
/// analyze` cannot see.
@InjectableInit.microPackage()
void initMicroPackage() {}
