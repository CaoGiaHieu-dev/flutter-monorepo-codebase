# 03 · Daily Workflow

**This page answers:** which command do I run, and when? What breaks if I skip it?

**After reading you can:** work in this monorepo without the two classic time-sinks — stale generated code and missing barrel exports.

---

## 1. The loop

```text
   edit source
        │
        ├─ touched an annotation?  ──► dart run build_runner build --workspace
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
dart run build_runner build --workspace
```

Run it whenever you add, remove, or edit any of these:

| Annotation / change | Generator | Produces |
| :--- | :--- | :--- |
| `@freezed`, a new union case, a new field | `freezed` | `*.freezed.dart` |
| `@JsonSerializable`, `fromJson` / `toJson` | `json_serializable` | `*.g.dart` |
| `@injectable`, `@lazySingleton`, `@Singleton(as:)`, `@module`, `@PostConstruct`, `@disposeMethod` | `injectable_generator` | `*.module.dart`, `apps/mobile/lib/di/injection.config.dart` |
| `@RestApi`, `@GET`, `@POST` | `retrofit_generator` | `*.g.dart` |
| `@DriftDatabase`, `@DriftAccessor`, a new table | `drift_dev` | `<name>_database.g.dart`, next to your database (e.g. `cache_database.g.dart`) |
| `@TypedGoRoute`, `@TypedShellRoute` | `go_router_builder` | `*_route_module.g.dart` |
| New asset in `platform/ui/design_system/assets/` | `flutter_gen_runner` (declared only by `core_base_ui`) | `lib/src/gen/assets.gen.dart` |

> [!WARNING]
> Symptoms of forgetting: `Undefined class '_$SomethingImpl'`, `The getter '$myRoute' isn't defined`, `Type X is not registered inside GetIt`, or your new DI binding silently not existing.

> [!CAUTION]
> Never hand-edit generated files (`*.g.dart`, `*.freezed.dart`, `*.module.dart`, `injection.config.dart`). Your edit is destroyed on the next run. Change the annotated source instead.

### Watch mode

For a tight edit loop:

```bash
dart run build_runner watch --workspace
```

---

## 3. Barrel generator — after adding, renaming, or deleting a file

Every package exposes its public API through barrel files (`src.dart`, `<package>.dart`, and one per folder). They are generated, not hand-maintained.

```bash
dart tools/barrel_generator/generate.dart modules/auth/feature/lib
dart tools/barrel_generator/generate.dart modules/auth/domain/lib
dart tools/barrel_generator/generate.dart platform/infra/storage/lib
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
> Native Android dependencies in `apps/mobile/android/app/build.gradle.kts` are **outside** this catalog. Bumping `play-services-auth` or `androidx.window` is a manual Gradle edit.

---

## 5. The rest of `tools/`

| Tool | Command | Use it when |
| :--- | :--- | :--- |
| **Module generator** | `dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<SM>] [<route>]` | Scaffolding a new Feature / Domain / Data / Core / Custom package. It adds the module to **every** `app_manifest.yaml`, both `apps/mobile` and `apps/admin`, and runs `composer sync`, which registers it in the workspace and in every app. `apps/admin` composes only auth + settings. If the new module does not belong there, delete its entry from `apps/admin/app_manifest.yaml` and run `dart tools/composer/composer.dart sync`. Run with no arguments on a terminal for interactive mode. A feature missing `<SM>` or `<route>` prompts for it on a terminal and exits `64` without one, so always pass both; an invalid name (it must be a Dart package name) or value is rejected up front, before anything is written. `--help` prints the usage. |
| **Unused checker** | `dart tools/unused_checker/check_script.dart` | Periodic cleanup. Sub-commands exist for assets, files, packages, translations. |
| **Outdated checker** | `dart tools/check_outdated.dart` | Before a dependency-bump session. It lists what pub.dev has newer. In a terminal it then shows an interactive checklist: `a` applies the selected versions to the catalog and runs `dependency_sync` + `pub get`, and `q` quits. Without a TTY (CI, a pipe) it only reports. Exits `1` if resolving, `pub outdated` or applying an update fails. |
| **AI code review** | `dart tools/code_review/code_review.dart --changed` | Optional pre-PR pass. Needs a Gemini API key (`GEMINI_API_KEY`, `--api-key`, or saved when prompted). Also supports `--all`, `--file <path>`, `--focus architecture,security`, and `--language <code>` for that run only. Generated files, tests and git-ignored files are always excluded. Without a key and without a terminal it exits `1`. |
| **Workspace setup** | `dart tools/workspace_setup/configure.dart` | First setup of a clone, after a big rebase, or when things are inexplicably broken. It runs, in order: activate `flutterfire_cli` → `flutter clean` → `flutter pub get` → `flutter gen-l10n` in every package with an `l10n.yaml` → `dart run build_runner build --workspace` → the barrel generator for every package with a `lib/` (apps skipped). Stops at the first failing step. |

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

# 2. Tests — they live per package, so run every package that has a test/
#    directory (the same discovery CI Gate 3 uses; bash — Git Bash on Windows)
for pubspec in $(find apps modules platform -name pubspec.yaml -not -path '*/build/*' -not -path '*/.dart_tool/*' | sort); do
  dir=$(dirname "$pubspec")
  [ -d "$dir/test" ] || continue
  (cd "$dir" && flutter test) || { echo "FAILED: $dir"; break; }
done

# 2b. Changed anything under tools/? The gate tools have their own suite
#     (throwaway temp workspaces, ~15 s) — CI runs it right after Gate 1
(cd tools && dart test)

# 3. Version catalog is in sync
dart tools/dependency_sync.dart --check

# 4. No undeclared dependency (arch_check R5: an import missing from
#    `dependencies:`) and no unused one (declared but never imported)
dart tools/arch_check/check.dart
dart tools/unused_checker/check_unused_packages.dart
```

Tests live at `<package>/test/`, wherever the package lives. The loop finds them rather than listing them, so it keeps working when you add a package with tests or remove a sample that had some — CI Gate 3 discovers them the same way. It stops at the first failing package and names it; add your tests next to the code you write, with hand-written fakes (the repo uses no mockito/mocktail) — `flutter_test` in a Flutter package, `package:test` in a pure-Dart one. The loop covers `apps/`, `modules/` and `platform/`; `tools/` is step 2b. On Windows, run it in Git Bash (it ships with Git for Windows) — PowerShell and `cmd` have no `find`/`dirname` of this kind.

> [!CAUTION]
> `flutter analyze` **cannot** catch DI ordering faults. An eager `@Singleton` that depends on a type registered by a *later* module compiles fine and then throws `not registered` at boot. After changing DI registration, check the module order in the generated `apps/mobile/lib/di/injection.config.dart`, and your type's registration and its `gh<Dep>()` calls in the package's generated `lib/di/module.module.dart`. See [../guides/05_di.md](../guides/05_di.md).

### Optional: prove the app still builds

Static analysis passing does not mean the Android build passes (Gradle/Kotlin errors live outside Dart):

```bash
cd apps/mobile
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

---

## 7. Common traps

| Trap | Symptom | Fix |
| :--- | :--- | :--- |
| Forgot `build_runner` after an annotation change | `Undefined class '_$…Impl'`, DI type not registered | `dart run build_runner build --workspace` |
| Forgot the barrel generator after adding a file | New class invisible outside its package | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Hand-edited a generated file | Change vanishes on next codegen | Edit the annotated source |
| Ran `pub get` inside a sub-package | Stray `pubspec.lock` files | Delete them, run `flutter pub get` at the root |
| Ran `flutter build apk` from the repo root | `Target file "lib\main.dart" not found` | `cd apps/mobile` first |
| Hardcoded a version in a package pubspec | `dependency_sync --check` fails | Move it to `pubspec_dependencies.yaml`, re-sync |
| Imported a package without declaring it | Compiles locally (workspace shares `package_config.json`), breaks when extracted | Declare it in that package's `pubspec.yaml` (`dependencies:`, not `dev_dependencies:`); verify with `dart tools/arch_check/check.dart` (R5). The unused checker covers the reverse — declared but never imported |
| Registered a screen controller as a singleton | State leaks between screen visits | Feature controllers are `@injectable` (factory) — see [../guides/05_di.md](../guides/05_di.md) |

---

## Where to go next

| You want to… | Read |
| :--- | :--- |
| Understand the architecture | [../architecture/01_overview.md](../architecture/01_overview.md) |
| Create your first feature | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
| See the full rule list | [../reference/01_rules.md](../reference/01_rules.md) |
| Tooling reference | [../reference/03_tooling.md](../reference/03_tooling.md) |
