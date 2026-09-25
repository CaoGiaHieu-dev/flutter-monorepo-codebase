# PR Review Checklist

**This file answers:** what must hold before this PR merges?

**After reading you can:** review a change against the architecture in a few minutes, and know which boxes a command can tick for you.

Each box names the registry row it checks. The rule itself, its reason and its verification command live once, in [`01_rules.md`](01_rules.md) — this page only says what to look at. Skip sections the PR does not touch. Anything a gate enforces should be *run*, not eyeballed.

---

## 0. Automated gate — run these first

The same gates `.github/workflows/pr_quality_check.yml` runs, in its order (CI first runs `dart tools/workspace_setup/configure.dart` — pub get, gen-l10n, build_runner, barrels):

```bash
dart run build_runner build --workspace              # generated code up to date
dart tools/composer/composer.dart verify             # Gate 0 — composition matches app_manifest.yaml
dart tools/arch_check/check.dart                     # Gate 1 — rules R1–R15
(cd tools && dart test)                              # Gate 1 — the gate tools' own tests
flutter analyze                                      # Gate 2 — static analysis, 0 issues
# Gate 3 — `flutter test` in every package that has a test/ directory (apps/*: the DI smoke test)
dart tools/dependency_sync.dart --check              # Gate 4 — version catalog drift
dart tools/docs_check/check.dart                     # Gate 5 — doc paths, en ↔ vi parity, RULE-ID citations
dart tools/unused_checker/check_unused_packages.dart # advisory — declared but never imported
```

- [ ] Gates 0–5 pass clean (the unused-dependency audit is advisory)
- [ ] **RULE-60 · RULE-63** — tests pass in every touched package with a `test/` directory, including each app's DI smoke test
- [ ] **RULE-76** — no generated file (`.g.dart`, `.freezed.dart`, `.module.dart`, `.config.dart`) was hand-edited
- [ ] **RULE-75** — the barrel generator was re-run, after codegen, if a `lib/` file was added, renamed or deleted
- [ ] **RULE-77** — a DI, dependency or type-move change was followed by the debug APK build (CI's `build` job)

---

## 1. Package structure

- [ ] **RULE-16** — a new package declares `resolution: workspace` and reached the root `workspace:` list through `composer sync`, not a hand edit
- [ ] **RULE-78** — its name matches its layer prefix (`core_` / `domain_` / `data_` / `feature_` / `<id>_api`); files and classes follow the suffix table
- [ ] **RULE-75** — its public API is exported through the barrel; implementation stays under `src/`
- [ ] **RULE-09** — its public constants live in its own `utils/`

---

## 2. Dependency direction

- [ ] **RULE-01** — no platform package depends on a module; a new approved `→ domain_core` edge updated the allow-list and the registry in the same PR
- [ ] **RULE-02** — a new platform package sits in a group folder and its `dependencies:` follow the group DAG
- [ ] **RULE-06** — every `package:` import is declared under `dependencies:`; removed code removed its unused entries
- [ ] **RULE-04** — no feature imports another feature or a data package; module API packages depend on the foundation only

**Verify**

```bash
dart tools/arch_check/check.dart                            # R1, R2, R3, R5, R11
grep -rn "package:feature_\|package:data_" platform/*/*/lib   # must be empty
dart tools/unused_checker/check_unused_packages.dart        # declared but unused
```

---

## 3. Domain layer

- [ ] **RULE-03** — no Flutter, Dio, Retrofit or `core_*` import or dependency in `modules/*/domain`
- [ ] **RULE-49** — entities are Freezed with `const Class._()`; each use case is `@injectable`, does one thing and returns `Result<T>`

**Verify**

```bash
grep -rn "package:flutter" modules/*/domain/lib   # must be empty
```

---

## 4. Data layer

- [ ] **RULE-40** — data sources live under `data_sources/remote/` and `data_sources/local/`
- [ ] **RULE-41** — data sources return Models (`BaseEntity<T>` the only wrapper); no Drift row in a public signature; Models implement `BaseModel<E>` with `.toEntity()`
- [ ] **RULE-42** — `RepositoryImpl` extends `BaseRepository` and uses `execute()` / `executeSync()`; nothing throws to UI
- [ ] **RULE-43** — errors go through `ErrorHandler.handleError(e)`; a new exception family registered an `ErrorClassifier`

---

## 5. Storage and database

- [ ] **RULE-44** — a new key lives in the owning package's `utils/`; the owner declares its own `StorageValue<T>`, picks `secure` / `pref` deliberately, and shares it only through a `core_di` interface
- [ ] **RULE-45** — the storage owner is a singleton with `@PostConstruct(preResolve: true)`, never `@injectable`
- [ ] **RULE-46** — new tables and DAOs live in the owning package's own database
- [ ] **RULE-47** — a schema change bumped `schemaVersion` and registered `IDatabaseMigration<YourDatabase>`; the open carries `@Order(1)`
- [ ] **RULE-48** — a change touching networking keeps `SslPinningConfig` bound and says whether `sslPinningHashes` is filled

---

## 6. Dependency injection

- [ ] **RULE-15** — a new package declares `@InjectableInit.microPackage()` at `lib/di/module.dart`
- [ ] **RULE-16** — it is composed through each `apps/<id>/app_manifest.yaml` and `composer verify` is clean
- [ ] **RULE-10** — screen controllers are `@injectable`; singletons are genuinely app-wide
- [ ] **RULE-11** — dependencies arrive via the constructor; no `getIt<T>()` in a ViewModel, Bloc, Repository or UseCase
- [ ] **RULE-13 · RULE-63** — no eager `@Singleton` depends on a later group; a plugin touched during DI has its test double in the smoke tests
- [ ] **RULE-14** — a second interface on one implementation is bound through a `@module`

**Verify** — the DI smoke test boots the real graph for every flavor:

```bash
cd apps/mobile && flutter test test/di_smoke_test.dart
cd apps/admin && flutter test test/di_smoke_test.dart
```

---

## 7. Feature boundaries and removability

- [ ] **RULE-24** — one bounded UI concern per feature package
- [ ] **RULE-04 · RULE-22 · RULE-25** — cross-feature navigation and UI actions go through the owner's `<id>_api`
- [ ] **RULE-12** — module-owned contracts are resolved with `getItOrNull` / `getAllOrEmpty` + a fallback
- [ ] **RULE-05** — no app file outside `injection.dart`, and no shell package, imports a module
- [ ] **RULE-08** — a new `core_di` contract is product-neutral, carries its own value type, and its consumer degrades safely when nothing registers it

**Verify** — for a feature that should be removable, remove it from the app's manifest and confirm:

```bash
dart tools/composer/composer.dart sync
flutter pub get && dart run build_runner build --workspace
dart tools/arch_check/check.dart
flutter analyze
```

---

## 8. Routing

- [ ] **RULE-20** — `app_router.dart` was not edited; the feature contributes `IFeatureRouteModule` / `INavDestinationModule` / `IAppEntryLocation`
- [ ] **RULE-24** — `INavDestinationModule` is used only for a primary destination, its `order` is unique, and `feature_dashboard` stays chrome only
- [ ] **RULE-09** — route path constants live in `lib/src/utils/<feature>_path.dart`
- [ ] **RULE-21** — controllers are created at the route; the `Page` does not wrap itself again
- [ ] **RULE-23** — `BuildContext` comes from the UI caller, not `NavigatorKeys`

---

## 9. UI and presentation

- [ ] **RULE-50** — controllers extend `BaseProvider` / `BaseBloc` (`BaseCubit` only without events)
- [ ] **RULE-51 · RULE-52** — BLoC events are private `part` subclasses; every `on<Event>` handler is `async (event, emit)`
- [ ] **RULE-53** — a `BlocViewState<T>` state settles through `emitResult`; generic code writes the type argument
- [ ] **RULE-54** — cross-feature state is a neutral `Stream` / `ValueListenable` interface, dual-registered
- [ ] **RULE-30** — all sizing goes through `BuildContext`; values needed after an `await` were read before it
- [ ] **RULE-31** — reusable widgets use parameters as received; nothing is scaled twice
- [ ] **RULE-32** — layout choices use the window size class, not `Platform.is*` or a device check
- [ ] **RULE-33** — colours, typography, spacing and radii come from the design tokens
- [ ] **RULE-36** — dialogs and bottom sheets are separate widget classes

---

## 10. Localization, assets and accessibility

- [ ] **RULE-34** — no hardcoded user-facing string; feature strings in its own ARB, registered through `IFeatureLocalization`
- [ ] **RULE-35** — new ARB keys are `lowerCamelCase`
- [ ] **RULE-37** — feature-specific assets live in the feature's `assets/`
- [ ] **RULE-38** — no text-scaling override or fixed-height text container; icon-only buttons have a `tooltip`, meaningful images a `semanticLabel`
- [ ] **RULE-39** — tap targets are at least 48 × 48 dp; start/end padding uses `edgeInsetsDirectional`

---

## 11. Tooling, testing and hygiene

- [ ] **RULE-70 · RULE-71** — `flutter analyze` is clean with no suppression added; deprecations were migrated
- [ ] **RULE-72** — no `.ps1` script was added
- [ ] **RULE-73** — no command or tool hardcodes `fvm`
- [ ] **RULE-74** — versions were changed in `pubspec_dependencies.yaml` and synced
- [ ] **RULE-65 · RULE-66** — no `print`; nothing secret was committed or logged
- [ ] **RULE-67** — error reporting goes through `IErrorReporter`, not a reassigned `FlutterError.onError`
- [ ] **RULE-61 · RULE-62** — fakes are hand-written; scaled widget tests wrap the subject in `ResponsiveInit`
- [ ] **RULE-64** — a change to a gate tool added a case to `tools/test/`

---

## 12. Documentation

- [ ] **RULE-79** — behaviour changes are reflected in `docs/en/` **and** `docs/vi/`, and `docs_check` passes
- [ ] A new or changed rule is a registry row in both locales, with **Enforced by** telling the truth; other pages cite its id instead of restating it
- [ ] Code samples in docs were copied from real files, not written from memory
- [ ] Known limitations are stated plainly rather than omitted

---

**See also:** [`01_rules.md`](01_rules.md) · [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md)
