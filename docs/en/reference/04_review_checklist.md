# PR Review Checklist

**This file answers:** what must hold before this PR merges?

**After reading you can:** review a change against the architecture in a few minutes, and know which boxes a command can tick for you.

Skip sections the PR does not touch. Anything with a **Verify** line should be *run*, not eyeballed.

---

## 0. Automated gate — run these first

The same gates `.github/workflows/pr_quality_check.yml` runs, in its order (CI first runs `dart tools/workspace_setup/configure.dart` — pub get, gen-l10n, build_runner, barrels):

```bash
dart run build_runner build --workspace              # generated code up to date
dart tools/composer/composer.dart verify             # Gate 0 — composition matches app_manifest.yaml
dart tools/arch_check/check.dart                     # Gate 1 — layering rules R1–R10 (R5: undeclared imports)
flutter analyze                                      # Gate 2 — static analysis
# Gate 3 — `flutter test` in every package that has a test/ directory
dart tools/dependency_sync.dart --check              # Gate 4 — version catalog drift
dart tools/docs_check/check.dart                     # Gate 5 — every repo path the docs name exists
dart tools/unused_checker/check_unused_packages.dart # advisory — declared but never imported
```

- [ ] Gates 0–5 pass clean (the unused-dependency audit is advisory)
- [ ] Tests pass in every touched package that has a `test/` directory — `cd modules/<module>/<layer> && flutter test`
- [ ] No file under `lib/` was hand-edited if it ends in `.g.dart`, `.freezed.dart`, `.module.dart` or `.config.dart`
- [ ] Barrel generator was re-run — after `build_runner` / `gen-l10n` — if any file was added, renamed or deleted

---

## 1. Package structure

- [ ] New package declares `resolution: workspace` in its `pubspec.yaml`
- [ ] New package is listed in the root `pubspec.yaml` `workspace:` block — written by `dart tools/composer/composer.dart sync` (the module generator runs it); a hand edit there fails Gate 0
- [ ] Public API is exported through the barrel `lib/<package_name>.dart`; implementation stays under `src/`
- [ ] Package name matches its layer prefix — `core_` / `domain_` / `data_` / `feature_`
- [ ] The package's public constants live in its own `utils/` folder — a package with no constants needs none ([rule 3](01_rules.md#3-constants-live-in-utils))

---

## 2. Dependency direction

- [ ] No `core/*` package imports or declares `feature_*`, `data_*` or `domain_*`, except the three approved `→ domain_core` edges (`arch_check` R1)
- [ ] Any new core → `domain_core` edge was added to the allow-list in `tools/arch_check/check.dart` and to `AGENTS.md` in the same PR
- [ ] Every `package:` import under `lib/` has a matching `pubspec.yaml` entry
- [ ] Production imports are in `dependencies`, not `dev_dependencies`
- [ ] Removed code also removed its now-unused dependency entries

**Verify**

```bash
dart tools/arch_check/check.dart                            # R1 dependency direction, R5 undeclared imports
grep -rn "package:feature_\|package:data_" platform/*/*/lib   # must be empty
dart tools/unused_checker/check_unused_packages.dart        # declared but unused
```

---

## 3. Domain layer

- [ ] No `flutter` / `dio` / `retrofit` import in `modules/*/domain`
- [ ] No domain `pubspec.yaml` declares the Flutter SDK
- [ ] Entities use `freezed` with the `const Class._()` private constructor
- [ ] Each use case does one thing and returns `Result<T>`
- [ ] Use cases are `@injectable`

**Verify**

```bash
grep -rn "package:flutter" modules/*/domain/lib   # must be empty
```

---

## 4. Data layer

- [ ] Directories are `data_sources/remote/` and `data_sources/local/` — not `datasources/`
- [ ] **DataSources return Models, never Entities** — the only allowed wrapper is `domain_core`'s `BaseEntity<T>` response envelope
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
- [ ] It is composed in each `apps/<id>/app_manifest.yaml` — a module under `modules:`, a platform package in the right `di_groups` entry — and `composer verify` is clean
- [ ] Screen-scoped controllers are `@injectable` — **never** `@singleton` / `@lazySingleton`
- [ ] Global controllers that are singletons are genuinely app-wide
- [ ] No eager `@Singleton` depends on a type registered by a later module ([rule 5](01_rules.md#5-di-registration-order))
- [ ] Dependencies arrive via constructor; no `getIt<T>()` inside a ViewModel, Repository or UseCase
- [ ] Binding an impl to a second interface uses an explicit `@module` — GetIt does not resolve supertypes

**Verify** — after any DI change, read the generated files: `apps/mobile/lib/di/injection.config.dart` holds only the module order; each package's `lib/di/module.module.dart` holds its per-type registrations and the `gh<Dep>()` calls each makes. Every dependency of an eager `gh.singleton…` must be registered above it or by a module whose `init` runs earlier:

```bash
grep -n "PackageModule().init" apps/mobile/lib/di/injection.config.dart
grep -rn -A4 "gh.singleton" platform/*/*/lib/di/module.module.dart modules/*/*/lib/di/module.module.dart
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

**Verify** — for a feature that should be removable, remove it from the app's manifest and confirm:

```bash
dart tools/composer/composer.dart sync
flutter pub get && dart run build_runner build --workspace
dart tools/arch_check/check.dart
flutter analyze
```

---

## 8. Routing

- [ ] `app_router.dart` was **not** edited to add a route
- [ ] The feature registers `IFeatureRouteModule` and/or `INavDestinationModule` (plus optional `IAppEntryLocation`)
- [ ] `INavDestinationModule.order` sorts the tab into the intended position (ascending sort key, not an index) and is unique
- [ ] `INavDestinationModule` is used only for real bottom-nav destinations, not push-only screens
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
- [ ] A `core_di` contract implemented under `modules/` (any layer) is resolved with `getItOrNull` / `getAllOrEmpty` outside its own module — `arch_check` R8 is clean
- [ ] No app-shell file outside `injection.dart` imports a module package — `arch_check` R1 (`platform_app_shell`) and R10 (`apps/*`) are clean
- [ ] All sizing goes through `BuildContext` — `context.w(x)` / `context.h(x)` / `context.sp(x)` / `context.r(x)`; no raw doubles, no bare `16.h` form (`arch_check` R7 blocks it)
- [ ] Design tokens called with context — `AppSpacing.lg(context)`, `AppRadius.md(context)`, never a bare getter, never double-scaled
- [ ] Values needed after an `await` were read from context **before** it, not across it
- [ ] Reusable widgets in `core_ui_kit` use their parameters **as received** — the caller scaled them — and scale only their own constants
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
- [ ] `flutter analyze` is clean under the strict modes: no raw generics, no uncast `dynamic`, fire-and-forget futures wrapped in `unawaited(...)` with a reason, every empty `catch` commented ([`01_rules.md` § 16](01_rules.md))
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
