---
name: implement_dependency_injection
description: Use when registering or wiring anything in GetIt/injectable — "register a service/repository", "inject a provider or bloc", "fix <Type> is not registered", adding a package's DI module, binding a second interface, choosing @injectable vs @lazySingleton, or placing a package in an app manifest's di_groups. Declaring the contract provided or absent in the manifest is configure_app.
---

# Skill: Implement dependency injection

Use this skill to register a class, wire a package into an app, bind a second interface, or find the
cause of "`<Type>` is not registered".

> **Capabilities have three owners.** This skill registers the contract; declaring it `provided` or `absent` by decision is
> [`configure_app`](../configure_app/SKILL.md), and flipping the ones that lost their last provider is
> [`remove_module`](../remove_module/SKILL.md).

**Guide:** [`docs/en/guides/05_di.md`](../../../docs/en/guides/05_di.md); module order and why it
matters: [`06_app_shell.md` § 3](../../../docs/en/architecture/06_app_shell.md#3-di-assembly--and-why-the-order-matters).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-06, RULE-10, RULE-11, RULE-12,
RULE-13, RULE-14, RULE-15, RULE-16, RULE-45, RULE-47, RULE-63, RULE-80, RULE-81. Cite them; do not
restate them.

## 1. Choose the annotation

| Class | Annotation |
| :--- | :--- |
| Screen controller (Provider, Bloc, Cubit) | `@injectable` factory (RULE-10 — it also lists the few app-wide `@lazySingleton` controllers) |
| Use case | `@injectable` — a factory, never a singleton |
| Repository, service, data source | `@lazySingleton`; for an interface `@LazySingleton(as: IMyRepository)` |
| Stateless contribution resolved on demand (`IFeatureLocalization`, an action handler) | `@Injectable(as: I…)` |
| Storage owner (a class holding `StorageValue` fields) | `@lazySingleton` / `@singleton` + `@PostConstruct(preResolve: true)` (RULE-45) — [`implement_package_storage`](../implement_package_storage/SKILL.md) |
| Third-party or async object you do not own | a `@module` getter, `@preResolve` only where construction is async |

Prefer `@LazySingleton`: `@Singleton` is **eager**, built while the module registers, and may only depend
on types an earlier DI group registered (RULE-13). Constructor injection only (RULE-11): no `getIt<T>()`
inside a view model, bloc, repository or use case; the lookup sites are a route's `build` and the shell's
composition code.

## 2. Trap 1: an eager `@Singleton` that depends on a later module

If its constructor needs a type a later module registers, boot throws `… is not registered inside GetIt`.
Make it lazy — `@LazySingleton(as: NetworkConfig)` on `NetworkConfigImpl`
(`platform/shell/adapters/lib/src/network_config_impl.dart`) is the shape to copy; it also resolves
`ISessionGateway` at call time with `getItOrNull`, so it builds whether or not an auth module is composed.

`flutter analyze` cannot see this (RULE-13). Each app's `test/di_smoke_test.dart` boots the real graph for
every flavor, builds every lazy singleton, builds every `@injectable` factory one by one (`FactoryRecorder.buildEvery`
in `platform_app_shell`; GetIt's own `findAll(callFactories: true)` builds them all-or-nothing with `null`
arguments and names no registration), and holds the graph to the app's declaration with `checkAppContract`
(RULE-63). A failure names the type:

- a factory with a non-nullable `@factoryParam` cannot be built without its screen — list its type, with the
  reason, in `_factoriesNeedingArguments` in the test, or the test fails with `F01`; what a factory throws is `F02`;
- a contract registered but declared `absent`, or declared `provided` and not registered, fails with
  `C03` / `C02` (step 6);
- a plugin the graph touches during DI (`@preResolve`, `@PostConstruct(preResolve: true)`) needs its test double there.

To diagnose, read the generated files after `build_runner`: `apps/<id>/lib/di/injection.config.dart` holds the
module order (one `…PackageModule().init(gh)` per package); a type's registration, and the `gh<Dep>()` calls
its constructor makes, are in its package's `lib/di/module.module.dart`. Every `gh<Dep>()` of an eager
singleton must be registered on an earlier line there, or by a module whose `init` runs earlier.

```bash
grep -n "PackageModule().init" apps/mobile/lib/di/injection.config.dart   # module order
grep -rn -A4 "YourType" modules/*/*/lib/di/module.module.dart platform/*/*/lib/di/module.module.dart
```

## 3. Trap 2: GetIt does not resolve supertypes

GetIt looks up the **exact** registered type. Registering `AuthProvider` as a `@lazySingleton` leaves
`getItOrNull<ISessionState>()` returning `null` although `AuthProvider implements ISessionState`, and the shell
then treats every user as signed out (RULE-14). Bind each further interface with a `@module` — the live example is
`modules/auth/feature/lib/di/module.dart`:

```dart
@module
abstract class AuthDiModule {
  @singleton
  ISessionStatusStream bindISessionStatusStream(AuthStatusStreamImpl impl) => impl;

  @lazySingleton
  ISessionState bindISessionState(AuthProvider provider) => provider;

  @lazySingleton
  ISessionRefreshListenable bindISessionRefreshListenable(AuthProvider provider) =>
      provider;
}
```

The parameter is typed with the concrete class, so the upcast is compiler-checked. Match the scope of what you
bind: `AuthProvider` is lazy, so its bindings are lazy; `AuthStatusStreamImpl` is eager, so its binding is too.

### Third-party objects go through `@module`

Never call `SomeSdk.instance` or construct `Dio` inside a repository: it hides the dependency from the
container and leaves no seam for a fake. `modules/auth/data/lib/di/module.dart` builds the module's Retrofit
client from the shared `Dio`:

```dart
@module
abstract class AuthDataDiModule {
  @lazySingleton
  AuthRemoteDataSource authRemoteDataSource(Dio dio) => AuthRemoteDataSource(dio);
}
```

Where construction is genuinely async, `platform/infra/storage/lib/di/module.dart` uses
`@preResolve Future<SharedPreferences> getSharedPreferences() async => SharedPreferences.getInstance();`.

## 4. Trap 3: `getAll` throws when nothing is registered

`platform_kernel` (`platform/foundation/kernel/lib/src/service_locator.dart`, re-exported by `core_common`)
has four lookups:

| Function | Missing registration |
| :--- | :--- |
| `getIt<T>()` | **throws** |
| `getItOrNull<T>()` | returns `null` |
| `getAll<T>()` | **throws** |
| `getAllOrEmpty<T>()` | returns an empty iterable |

A contract implemented only under `modules/` is resolved outside its module with the `…OrNull` / `…OrEmpty`
variants plus a fallback, and never as a required constructor parameter of an injectable class (RULE-12,
`arch_check` R8).

## 5. Add a package to DI, and compose it into an app

1. `lib/di/module.dart` with `@InjectableInit.microPackage()` and no arguments (RULE-15); the module
   generator writes it. `lib/di/` holds DI only; the classes you annotate live under `lib/src/`.

   ```dart
   import 'package:injectable/injectable.dart';

   @InjectableInit.microPackage()
   void initMicroPackage() {}
   ```

2. Annotate the classes (step 1) and declare every import under `dependencies:` (RULE-06).
3. Compose it through the **manifest**, never `injection.dart` (its imports and modules regions are generated, outside them only comments; RULE-16). A module package
   (`domain_*`, `data_*`, `feature_*`) is a line under `modules:` with the layers the app takes
   (`- { id: payment, layers: [domain, data, feature] }`; the generator adds it); its group comes from
   `from_modules:`. A **platform** package goes into the right `di_groups` entry by name:

   | Group | Phase | When to use |
   |------|-------|-------------|
   | `core` | `before` | Mechanism that depends on nothing the app or shell registers (`core_common`, `core_network`, `core_storage`, `core_database`, `core_di`) |
   | *(the app's own `lib/`)* | between | Only what identifies the app — its per-flavor `FirebaseOptions` (`lib/firebase/firebase_module.dart`) |
   | `notifications` | after, **first** | `core_notifications` — its eager `PushNotificationService` injects the app's `FirebaseOptions` (mobile only) |
   | `shell` | after | `platform_shell_adapters` first (storage adapters, `AppBootStorage`, `NetworkConfig`), then `platform_app_shell` |
   | `ui` | after | `core_base_ui` only — injects the shell's `ILanguageStorage` / `IThemeStorage` |
   | `domain` | after | `domain_core`, then the modules' `domain` layers |
   | `data` | after | `data_core`, then the modules' `data` layers |
   | `feature` | after | the modules' `feature` layers |
   | `other` | after | `provider_state_management`, `bloc_state_management` |

   Every group carries a `why` and the template's groups keep their relative order (check V16). Then:

   ```bash
   dart tools/composer/composer.dart sync --app <id>
   ```

   Never put `core_base_ui` in `core` or `core_notifications` in `core`: both break RULE-13 and the smoke test
   catches it. An API package (`<id>_api`) needs no group: it is a workspace member only.

4. `dart run build_runner build --workspace`, then **hot restart** — hot reload does not apply new DI
   registrations. Barrels: [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator).

### A type that reads the app's profile

`runShellApp` registers `AppProfile`, `AppPlatform` and each section — `PlatformFacts`, `SslPinningPolicy`,
`RouterProfile`, `LocaleProfile`, `ThemeProfile`, `NetworkProfile` — **by exact type, before** the graph
(`registerAppProfile`, `platform/foundation/kernel/lib/src/profile/register_app_profile.dart`); the generated
`configureDependencies` adds `registerProfileDefaults` for any section still missing. A DI-built class takes the
section it needs as a constructor parameter, optional with a `const` default for a hand-built object:

```dart
@lazySingleton
class MyAdapter {
  MyAdapter([this._network = const NetworkProfile()]);
  final NetworkProfile _network;
}
```

Because the sections are registered first, even an eager `@Singleton` can inject one without breaking RULE-13.
A new per-app value is a profile section or a manifest key, never a constant in a `platform/` package
(RULE-80) — [`configure_app`](../configure_app/SKILL.md). Replacing a shell-owned type by registering your own is
unsupported: GetIt keeps the **first** registration of a type, so an app registration beats a type from an `after`
group and loses to one from `before`.

### Ordering when a module opens a database

A package that opens a database with `@preResolve` runs its collected `IDatabaseMigration` steps during its own
initialisation, so every step must be registered before the open. Inside the owning package `@Order(1)` on the
open guarantees that; across packages the contributing package must sit in an earlier DI group.
[`implement_package_database`](../implement_package_database/SKILL.md).

## 6. Declare what the app registers for the shell

If the package registers a contract the shell catalogues (`SHELL_CONTRACTS`: a splash, tabs, routes, a session,
an entry location, `IErrorReporter`, `IAnalytics`, …), every app that composes it declares the capability
`provided` under `capabilities:` in `app_manifest.yaml`, and `absent` with a reason where it does not (RULE-81).
`composer verify` (V3) names the key and the line to paste; `dart tools/composer/composer.dart describe --app <id>`
shows who implements each contract; a class under the app's own `lib/app/` counts. What a composed package
needs the app to register (`FirebaseOptions` per flavor for `core_notifications`) is check V10.

## Related

- [`docs/en/guides/13_app_composition.md`](../../../docs/en/guides/13_app_composition.md) — what an app declares; [`configure_app`](../configure_app/SKILL.md)
- [`implement_package_storage`](../implement_package_storage/SKILL.md) — why storage owners are singletons
- [`implement_package_database`](../implement_package_database/SKILL.md) — `@Order(1) @preResolve`, typed migration registrations

## Verify

```bash
dart run build_runner build --workspace
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R5 declared deps, R8 optional lookups, R10
dart tools/composer/composer.dart verify                 # generated regions, capabilities, V16 group order
dart tools/unused_checker/check_unused_packages.dart     # the reverse of R5: declared but never imported
cd apps/mobile && flutter test test/di_smoke_test.dart   # and cd apps/admin for every app that composes the package
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77: a DI change is proven by a build too
```
