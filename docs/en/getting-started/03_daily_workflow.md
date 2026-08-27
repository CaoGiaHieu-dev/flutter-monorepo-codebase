# 03 · Daily Workflow

**This page answers:** which command do I run, and when? What breaks if I skip it?

**After reading you can:** work in this monorepo without the two classic time-sinks — stale generated code and missing barrel exports.

---

## 1. The loop

```text
   edit source
        │
        ├─ touched an annotation?  ──► dart run build_runner build -d --workspace
        │
        ├─ added/renamed/deleted a file in lib/?  ──► dart tools/barrel_generator/generate.dart <pkg>/lib
        │
        ├─ edited pubspec_dependencies.yaml?  ──► dart tools/dependency_sync.dart
        │
        ▼
   flutter analyze  ──►  flutter test (per package)  ──►  commit
```

---

## 2. `build_runner` — after touching an annotation

```bash
dart run build_runner build -d --workspace
```

Run it whenever you add, remove, or edit any of these:

| Annotation / change | Generator | Produces |
| :--- | :--- | :--- |
| `@freezed`, a new union case, a new field | `freezed` | `*.freezed.dart` |
| `@JsonSerializable`, `fromJson` / `toJson` | `json_serializable` | `*.g.dart` |
| `@injectable`, `@lazySingleton`, `@Singleton(as:)`, `@module`, `@PostConstruct`, `@disposeMethod` | `injectable_generator` | `*.module.dart`, `app/lib/di/injection.config.dart` |
| `@RestApi`, `@GET`, `@POST` | `retrofit_generator` | `*.g.dart` |
| `@DriftDatabase`, `@DriftAccessor`, a new table | `drift_dev` | `app_database.g.dart` |
| `@TypedGoRoute`, `@TypedShellRoute` | `go_router_builder` | `*_route_module.g.dart` |
| New asset in an `assets/` folder | `flutter_gen_runner` | `gen/assets.gen.dart` |

> [!WARNING]
> Symptoms of forgetting: `Undefined class '_$SomethingImpl'`, `The getter '$myRoute' isn't defined`, `Type X is not registered inside GetIt`, or your new DI binding silently not existing.

> [!CAUTION]
> Never hand-edit generated files (`*.g.dart`, `*.freezed.dart`, `*.module.dart`, `injection.config.dart`). Your edit is destroyed on the next run. Change the annotated source instead.

### Watch mode

For a tight edit loop:

```bash
dart run build_runner watch -d --workspace
```

---

## 3. Barrel generator — after adding, renaming, or deleting a file

Every package exposes its public API through barrel files (`src.dart`, `<package>.dart`, and one per folder). They are generated, not hand-maintained.

```bash
dart tools/barrel_generator/generate.dart packages/features/auth/lib
dart tools/barrel_generator/generate.dart packages/domain/auth/lib
dart tools/barrel_generator/generate.dart packages/core/storage/lib
```

The tool skips generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*_test.dart`) and `part of` files, then formats what it wrote.

> [!WARNING]
> Symptom of forgetting: your new class compiles inside its own package but is **invisible** to importers — `Undefined class` even though the file clearly exists.

---

## 4. `dependency_sync` — after editing the version catalog

Package versions are **never** written by hand into a package's `pubspec.yaml`. The single source of truth is `pubspec_dependencies.yaml` at the repo root.

```bash
# 1. Edit pubspec_dependencies.yaml
# 2. Push the versions down into every workspace member:
dart tools/dependency_sync.dart

# Verify only — exits 1 on any mismatch. Use in CI / pre-commit:
dart tools/dependency_sync.dart --check
```

The tool also repairs broken local `path:` entries for workspace packages.

> [!NOTE]
> Native Android dependencies in `app/android/app/build.gradle.kts` are **outside** this catalog. Bumping `play-services-auth` or `androidx.window` is a manual Gradle edit.

---

## 5. The rest of `tools/`

| Tool | Command | Use it when |
| :--- | :--- | :--- |
| **Module generator** | `dart tools/module_generator/generate.dart <type> <name> [dir] [SM] [route]` | Scaffolding a new Feature / Domain / Data / Core package. It also registers the package in the root workspace, `app/pubspec.yaml` and `app/lib/di/injection.dart`. Run with no arguments for interactive mode. |
| **Unused checker** | `dart tools/unused_checker/check_script.dart` | Periodic cleanup. Sub-commands exist for assets, files, packages, translations. |
| **Outdated checker** | `dart tools/check_outdated.dart` | Before a dependency-bump session — lists what pub.dev has newer. |
| **AI code review** | `dart tools/code_review/code_review.dart --changed` | Optional pre-PR pass. Needs a Gemini API key in `tools/code_review/code_review_config.json`. Also supports `--all`, `--file <path>`, `--focus architecture,security`. |
| **Workspace setup** | `dart tools/workspace_setup/configure.dart` | After a big rebase, or when things are inexplicably broken — does clean + pub get + l10n + build_runner in one pass. |

Module generator examples:

```bash
# Feature 'profile', Provider state management, stack routes:
dart tools/module_generator/generate.dart 1 profile "" 1 1

# Feature 'chat', BLoC, bottom-nav tab:
dart tools/module_generator/generate.dart 1 chat "" 2 2

# Domain + Data micro-packages for 'payment':
dart tools/module_generator/generate.dart 2 payment
dart tools/module_generator/generate.dart 3 payment
```

> [!NOTE]
> All CLI tools in `tools/` use `stdout.writeln()` / `stderr.writeln()`. `print()` is forbidden — keep that rule if you add a tool.

---

## 6. Before you commit

```bash
# 1. Static analysis — must be clean across the whole workspace
flutter analyze

# 2. Tests — they live per package, so run them per package
cd packages/core/common                  && flutter test && cd -
cd packages/core/database                && flutter test && cd -
cd packages/core/network                 && flutter test && cd -
cd packages/core/provider_state_management && flutter test && cd -
cd packages/core/storage                 && flutter test && cd -
cd packages/data/auth                    && flutter test && cd -

# 3. Version catalog is in sync
dart tools/dependency_sync.dart --check

# 4. No undeclared / unused package dependencies
dart tools/unused_checker/check_unused_packages.dart
```

Tests live at `packages/<layer>/<package>/test/`. Only the six packages above ship tests today; add yours next to the code you write.

> [!CAUTION]
> `flutter analyze` **cannot** catch DI ordering faults. An eager `@Singleton` that depends on a type registered by a *later* module compiles fine and then throws `not registered` at boot. After changing DI registration, open the generated `app/lib/di/injection.config.dart` and check the order. See [../guides/05_di.md](../guides/05_di.md).

### Optional: prove the app still builds

Static analysis passing does not mean the Android build passes (Gradle/Kotlin errors live outside Dart):

```bash
cd app
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

---

## 7. Common traps

| Trap | Symptom | Fix |
| :--- | :--- | :--- |
| Forgot `build_runner` after an annotation change | `Undefined class '_$…Impl'`, DI type not registered | `dart run build_runner build -d --workspace` |
| Forgot the barrel generator after adding a file | New class invisible outside its package | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Hand-edited a generated file | Change vanishes on next codegen | Edit the annotated source |
| Ran `pub get` inside a sub-package | Stray `pubspec.lock` files | Delete them, run `flutter pub get` at the root |
| Ran `flutter build apk` from the repo root | `Target file "lib\main.dart" not found` | `cd app` first |
| Hardcoded a version in a package pubspec | `dependency_sync --check` fails | Move it to `pubspec_dependencies.yaml`, re-sync |
| Imported a package without declaring it | Compiles locally (workspace shares `package_config.json`), breaks when extracted | Declare it in that package's `pubspec.yaml`; verify with the unused checker |
| Registered a screen controller as a singleton | State leaks between screen visits | Feature controllers are `@injectable` (factory) — see [../guides/05_di.md](../guides/05_di.md) |

---

## Where to go next

| You want to… | Read |
| :--- | :--- |
| Understand the architecture | [../architecture/01_overview.md](../architecture/01_overview.md) |
| Create your first feature | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
| See the full rule list | [../reference/01_rules.md](../reference/01_rules.md) |
| Tooling reference | [../reference/03_tooling.md](../reference/03_tooling.md) |
