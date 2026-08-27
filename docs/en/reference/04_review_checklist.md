# PR Review Checklist

**This file answers:** what must hold before this PR merges?

**After reading you can:** review a change against the architecture in a few minutes, and know which boxes a command can tick for you.

Skip sections the PR does not touch. Anything with a **Verify** line should be *run*, not eyeballed.

---

## 0. Automated gate — run these first

```bash
dart tools/dependency_sync.dart --check              # version catalog drift
dart tools/unused_checker/check_unused_packages.dart # unused / undeclared deps
dart run build_runner build -d --workspace           # generated code up to date
flutter analyze                                      # static analysis
```

- [ ] All four pass clean
- [ ] Tests pass in every touched package — `cd packages/<layer>/<pkg> && flutter test`
- [ ] No file under `lib/` was hand-edited if it ends in `.g.dart`, `.freezed.dart`, `.module.dart` or `.config.dart`
- [ ] Barrel generator was re-run if any file was added, renamed or deleted

---

## 1. Package structure

- [ ] New package declares `resolution: workspace` in its `pubspec.yaml`
- [ ] New package is listed in the root `pubspec.yaml` `workspace:` block
- [ ] Public API is exported through the barrel `lib/<package_name>.dart`; implementation stays under `src/`
- [ ] Package name matches its layer prefix — `core_` / `domain_` / `data_` / `feature_`
- [ ] Package has a `utils/` folder holding **its own** constants ([rule 3](01_rules.md#3-mandatory-utils-folder))

---

## 2. Dependency direction

- [ ] No `core/*` package imports or declares `feature_*` / `data_*`
- [ ] Any new upward dependency is one of the three approved exceptions, or `AGENTS.md` was updated in the same PR
- [ ] Every `package:` import under `lib/` has a matching `pubspec.yaml` entry
- [ ] Production imports are in `dependencies`, not `dev_dependencies`
- [ ] Removed code also removed its now-unused dependency entries

**Verify**

```bash
grep -rn "package:feature_\|package:data_" packages/core/*/lib   # must be empty
dart tools/unused_checker/check_unused_packages.dart
```

---

## 3. Domain layer

- [ ] No `flutter` / `dio` / `retrofit` import in `packages/domain/*`
- [ ] No domain `pubspec.yaml` declares the Flutter SDK
- [ ] Entities use `freezed` with the `const Class._()` private constructor
- [ ] Each use case does one thing and returns `Result<T>`
- [ ] Use cases are `@injectable`

**Verify**

```bash
grep -rn "package:flutter" packages/domain/*/lib   # must be empty
```

---

## 4. Data layer

- [ ] Directories are `data_sources/remote/` and `data_sources/local/` — not `datasources/`
- [ ] **DataSources return Models, never Entities**
- [ ] No Drift-generated class appears in a public signature — convert at the boundary (`CacheEntryModel`)
- [ ] Models provide `.toEntity()` and implement `BaseModel<E>`
- [ ] `RepositoryImpl` extends `IBaseRepository` and wraps work in `execute()` / `executeSync()`
- [ ] Errors go through `ErrorHandler.handleError(e)` — **not** `AppFailure.fromException()`
- [ ] Nothing `throw`s from Data to UI; failures come back as `Result.failure(AppFailure)`

---

## 5. Storage ownership

- [ ] New storage keys live in the **owning package's** `utils/`, not in `core_common`
- [ ] The owner declares its own `StorageValue<T>` from an injected `StorageManager`
- [ ] The owner is registered as a **singleton** (`@singleton` / `@lazySingleton` / `@Singleton(as:)`) with `@PostConstruct(preResolve: true)`
- [ ] It is **not** `@injectable` — a factory would hand out empty caches
- [ ] Backend chosen deliberately: `StorageType.secure` for tokens/PII, `StorageType.pref` for settings
- [ ] No `StorageValue` is passed between packages; cross-package access goes through a `core_di` interface

---

## 6. Dependency injection

- [ ] New package declares `@InjectableInit.microPackage()` at `lib/di/module.dart`
- [ ] Its module is registered in the right group in `app/lib/di/injection.dart`
- [ ] Screen-scoped controllers are `@injectable` — **never** `@singleton` / `@lazySingleton`
- [ ] Global controllers that are singletons are genuinely app-wide
- [ ] No eager `@Singleton` depends on a type registered by a later module ([rule 5](01_rules.md#5-di-registration-order))
- [ ] Dependencies arrive via constructor; no `getIt<T>()` inside a ViewModel, Repository or UseCase
- [ ] Binding an impl to a second interface uses an explicit `@module` — GetIt does not resolve supertypes

**Verify** — after any DI change, read the generated assembly and confirm each eager registration's dependencies appear earlier in `init()`:

```bash
grep -n "PackageModule().init\|gh.singleton<" app/lib/di/injection.config.dart
```

---

## 7. Feature boundaries and removability

- [ ] One bounded UI concern per feature package
- [ ] No feature imports another feature (no exception — shared widgets come from `core_ui_kit`)
- [ ] Cross-feature navigation uses a `core_di` Navigator interface, not a direct import
- [ ] Cross-feature UI actions use an `I*ActionHandler`
- [ ] Optional contributions are read with `getAllOrEmpty` / `getItOrNull` + a fallback — **never `getAll`**
- [ ] The app shell gained no new hard reference to a feature outside `injection.dart`
- [ ] If a new `core_di` contract was added, its consumer degrades safely when nothing registers it

**Verify** — for a feature that should be removable, remove it per the four steps in `injection.dart` and confirm:

```bash
flutter pub get && dart analyze app
```

---

## 8. Routing

- [ ] `app_router.dart` was **not** edited to add a route
- [ ] The feature registers `IFeatureRouteModule` and/or `IDashboardTabModule` (plus optional `IAppEntryLocation`)
- [ ] `IDashboardTabModule.order` matches the intended bottom-nav index
- [ ] `IDashboardTabModule` is used only for real bottom-nav destinations, not push-only screens
- [ ] `feature_dashboard` stays chrome-only — no tab pages, no hardcoded nav item list
- [ ] Route path constants live in `lib/src/utils/<feature>_path.dart`
- [ ] Controllers are created at the route; the `Page` does **not** wrap itself again
- [ ] `BuildContext` is passed from the UI caller, not taken from `NavigatorKeys`

---

## 9. UI and presentation

- [ ] Controllers extend `BaseProvider` / `BaseBloc`
- [ ] BLoC events are private subclasses using `part` / `part of`
- [ ] Every `on<Event>` handler is `async` and takes `(event, emit)`
- [ ] The right `ViewState` is used — `BlocViewState<T>` on the BLoC side, `ViewState` on the Provider side
- [ ] All sizing uses `.w` / `.h` / `.sp` / `.r`; no raw doubles in layout
- [ ] Reusable widgets in `core_ui_kit` take **unscaled** values and do not scale internally
- [ ] Dialogs and bottom sheets are separate widget classes, not inline builders
- [ ] Colors come from `context.colors.*`, typography from `AppTextStyles.*(context)`

---

## 10. Localization

- [ ] No hardcoded user-facing strings
- [ ] Feature strings live in that feature's `assets/language/*.arb`
- [ ] The feature registers `IFeatureLocalization` — `root_app.dart` was not edited
- [ ] Strings are read through the feature extension (`context.l10nAuth.someKey`)
- [ ] `core_ui_kit` defines no `.arb` of its own; it uses `core_base_ui`
- [ ] Feature-specific assets live in that feature's `assets/`, not in `core_base_ui`

---

## 11. Tooling and hygiene

- [ ] CLI tools use `stdout.writeln` / `stderr.writeln`, never `print()`
- [ ] No `// ignore_for_file:` or other lint suppression was added
- [ ] No `.ps1` script was added
- [ ] Deprecation warnings were resolved by real migration, not silenced
- [ ] Versions were changed in `pubspec_dependencies.yaml` and synced — not hardcoded per package
- [ ] Secrets were not committed (env files, keystores, API keys)

---

## 12. Documentation

- [ ] Behaviour changes are reflected in `docs/en/` **and** `docs/vi/`
- [ ] A new architectural rule was added to `.agents/AGENTS.md` and to [`01_rules.md`](01_rules.md)
- [ ] Code samples in docs were copied from real files, not written from memory
- [ ] Known limitations are stated plainly rather than omitted

---

**See also:** [`01_rules.md`](01_rules.md) · [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md)
