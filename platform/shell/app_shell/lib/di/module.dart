import 'package:injectable/injectable.dart';

/// Registers the shell's own singletons: the router and the app-level
/// `DeeplinkProvider`. The infrastructure adapters (`ILanguageStorage` /
/// `IThemeStorage`, `AppBootStorage`, `NetworkConfig`) are registered by
/// `platform_shell_adapters`.
///
/// ## Where it runs
///
/// Each app lists `platform_app_shell` in its `shell` DI group, right
/// **after** `platform_shell_adapters` and **before** `ui`. `AppRouter` is an
/// eager `@singleton`; it reads `AppBootStorage` only lazily, inside its
/// redirect, but keeping the adapters first means nothing here can ever
/// depend on a type registered later.
@InjectableInit.microPackage()
void initMicroPackage() {}
