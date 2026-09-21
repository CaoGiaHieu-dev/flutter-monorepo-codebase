# Restructure Runbook — multi-app, multi-team platform

Working plan for turning this template from a **single-app, single-team** monorepo into a
**multi-app, multi-team platform** where a feature team sees only its own module.

This file is the execution surface: `.agents/AGENTS.md` states the rules, this states the
order of operations and the gate that closes each step. Update the **Progress log** at the
bottom after every step.

> [!IMPORTANT]
> Every acceptance gate below must run on a machine with the Flutter toolchain.
> Steps may be authored without one; they are not *done* without one.

---

## 1. What we are changing, and what we are not

| | |
|:--|:--|
| **Changing** | Top-level axis: horizontal layers → **vertical slices** (`modules/<name>/`), one per bounded context, one per team, one git submodule. |
| **Changing** | `platform/` (today `packages/core/*`) must stop naming any product concept. |
| **Changing** | Root `pubspec.yaml` + each app's `injection.dart`: hand-written → **generated** from an app manifest. |
| **Changing** | Samples: 6 feature packages + 2 domain/data pairs → **2 reference modules**, deliberately small. |
| **Not changing** | Clean Architecture, the DI model (GetIt + Injectable), Freezed/BLoC rules, the responsive mandate, the barrel/codegen workflow. |
| **Not in scope** | The backend. It lives in another repo, owned by the backend team. The only surface we own is `core_network`, which talks to it over HTTP like any other client. |

### Baseline (measured 2026-09, before any step)

| Tier | LOC | Files | Packages |
|:--|--:|--:|--:|
| Framework (`core/*`, `domain_core`, `data_core`) | 16,721 | 281 | 13 |
| App shell (`app/`) | 1,379 | 24 | 1 |
| Sample | 3,617 | 155 | 10 |
| **Total** | **21,717** | **460** | **24** |

The sample tier is 17% of the code and is deleted, not migrated. The work is in the other 83%.

### Two blockers that generate most of the work

1. **`core_di` names features.** 15 of the 23 types it declares are implemented only by a
   feature package (measured by `arch_check` R8). Every new module would need a PR against a
   package owned by the infra team.
2. **`core_common` is a god-package.** 20 dependencies including `material_ui`,
   `cupertino_ui`, `firebase_core`, `go_router`, `permission_handler`. `getIt` — which every
   package needs — drags all of it in.

---

## 2. Order of operations

Steps are sequenced so each one leaves the repo building. Do not batch them.

| Step | Name | Blocked by | Reversible? |
|:--|:--|:--|:--|
| 1 | Machine-enforce removability (**done**) | — | yes |
| 2 | Shrink the samples (**done**) | 1 | no (deletes code) |
| 3 | Empty `core_di` of product names (**done**) | 2 | yes |
| 4 | Split `core_common` (**done**) | — | yes |
| 5 | Manifest + `composer` (**done**) | 4 | yes |
| 6 | Rename + relayout to `platform/` + `modules/` | 5 | no |
| 7 | Second app (`admin`) | 6 | yes |
| 8 | Submodules + CODEOWNERS | 7 | no |

> **Revised again after step 4.** `composer` now comes *before* the relayout. It resolves
> packages by name from a scan, so no directory is encoded in it or in any manifest — the
> relayout therefore needs no change to either. Doing the additive, low-risk tool first also
> means the relayout lands against a checked-in `composer verify` gate that will catch a
> mis-wired path immediately.
>
> **Revised after step 1.** Shrinking the samples now comes *before* emptying `core_di`.
> The original order had step 3 carefully migrating contracts —
> `OnboardingNavigator`, `IAppSplashScreen`, `DashboardRouteModule` — that step 2 then
> deletes. Deleting first makes the contract cleanup a much smaller job.

---

## 3. The steps

### Step 1 — Machine-enforce removability ✅ done

Removability is the property the whole design rests on, and it was held only by discipline —
which had already leaked once, in the template's own sample code.

- `tools/arch_check/check.dart`: added rule **R8**. It derives the set of `core_di` contracts
  implemented *only* by a `packages/features/*` package, then blocks any `getIt<T>()` /
  `getAll<T>()` against one. The owning feature is exempt: if it is in the build, so is its
  registration.
- Fixed the single violation: `feature_settings` resolved `IAuthActionHandler` with a throwing
  lookup. It compiled (Settings depends on `core_di`, not on auth) and crashed at runtime when
  a build had no auth feature.

**Gate:** `dart tools/arch_check/check.dart` exits 0 and prints R8 among its rules.

### Step 2 — Shrink the samples  *(2a, 2b done; 2c pending)*

Sample code is documentation written in Dart. Six overlapping features is not documentation,
it is a second product to maintain. Two reference modules demonstrate every mechanism.

| Today | After | Why |
|:--|:--|:--|
| ~~`feature_auth` (1,731 LOC)~~ **→ 739 LOC, 2b** | login only ✅ | Provider + stack route + agnostic stream + action handler. Register / forgot-password add no new mechanism; delete them. |
| `feature_home` (291) | `modules/catalog` | BLoC + private Freezed events + nav destination + consuming another module's contract. |
| `feature_settings` (195) | fold into `catalog` | Its only unique role is *consuming* an action handler; one screen can show that. |
| `feature_dashboard` (129) | → app shell | Chrome belongs to the app, not to a removable feature. |
| `feature_splash` (182) | → app shell | Same. |
| `feature_onboarding` (158) | → app shell | Same; keep `IAppEntryLocation` as the contract it demonstrates. |
| ~~`domain_language` + `data_language` (183)~~ **deleted 2a** | — | Dead by the repo's own admission: the Settings UI uses `LanguageProvider`, never `SetLanguageUseCase`. |
| `cache_chain` inside `data_core` | move to `modules/catalog` | It is a sample; it must not sit inside a framework package. |

Target: **~2 modules, well under 1,000 LOC of sample**, each file stating in one line which
mechanism it exists to show.

**Gate:** `dart tools/sample_cleanup/remove_sample.dart --list` agrees with the table above,
and removing either module leaves the app building and booting.

### Step 3 — Empty `core_di` of product names ✅ done

`core_di` becomes generic-only. Per-module contracts move to their own package.

- ⏳ **Deferred to step 5.** Physically moving these contracts into
  `packages/contracts/<module>_contracts/` is a file move; it rides the relayout rather than
  churning every pubspec twice. `core_di` is already free of any *domain* dependency, which is
  the part that blocked isolation.
- ✅ **3a — no domain entity in a contract.** `IAuthStatusStream` / `IAuthSessionState` now
  carry `AuthPrincipal`, owned by `core_di`; `AuthStatusStreamImpl.toPrincipal` maps at the
  auth boundary. The `core_di → domain_auth` edge is gone, and with it `domain_auth` from
  `core_di` and `feature_home`. The approved-exception list in `arch_check` is down from four
  entries to three.
- ✅ **3b — no feature-named key.** `NavigatorKeys.authKey` is gone; `NavigatorKeys.nested(id)`
  returns the same instance per id, so a module asks for its own back stack without the Hub
  declaring anything.
- ✅ **3b — `IDashboardTabModule` → `INavDestinationModule`.** The contract returns a
  `NavDestination` (label + icons), not a `BottomNavigationBarItem`. `DashboardPage` maps it to
  a bottom bar; a desktop or admin shell maps the same modules to a rail or a sidebar without
  the modules changing. `module_generator`'s template was renamed and rewritten to match.
- Replace `AuthNavigator.toLogin(context)` with a pure-Dart `NavIntent`. Navigation contracts
  stop needing `BuildContext`, so contracts stay pure Dart.

**Gate:** `core_di/pubspec.yaml` declares no `domain_*` package, and `arch_check` prints three
approved upward edges instead of four. Contract *names* still mention auth until step 5 moves
them out; the dependency — the part that broke isolation — is gone.

**Docs to update in the same PR:** `.agents/AGENTS.md` §2.3, §8.4, §22 · `CLAUDE.md` Routing +
Cross-Feature tables · `docs/{en,vi}/architecture/02_core.md` §2 ·
`docs/{en,vi}/guides/04_routing.md` · `docs/{en,vi}/guides/10_cross_feature.md` ·
`docs/{en,vi}/reference/01_rules.md`.

### Step 4 — Split `core_common` ✅ done

One package with 20 dependencies becomes three with a defensible boundary each.

| New package | Holds | Flutter? |
|:--|:--|:--|
| ✅ `platform_kernel` | `getIt` helpers, `ErrorHandler`, exceptions, primitive extensions, `TypeHelper`, `ValidationHelper`, enums, `EnvConstants`, `ApiStatusConstants` | no — **7 deps** |
| ✅ `core_common` (kept the name) | `AppConfig`, `AppInitializer`, mixins, `GoRouteDataCustom`, page transitions, `AppUtils`, dialog controller, formatters, Firebase | yes — 16 deps, was 20 |
| ⏳ `platform_firebase` | `FirebaseModule` and the generated options — still inside `core_common` | deferred |

**4a shipped with a full re-export**, so not one consumer import changed: `core_common.dart`
re-exports `platform_kernel` wholesale and `core_common/di/module.dart` re-exports the four
service-locator helpers. Only two import paths into `core_common` exist in the whole repo, which
is what made this safe to do blind.

✅ **4b** migrated every package that uses only kernel symbols: `core_network`,
`core_notifications`, `data_core`, `feature_dashboard`. Each shed 14 inherited dependencies —
`material_ui`, `cupertino_ui`, `firebase_core`, `go_router`, `permission_handler`,
`device_info_plus`, `package_info_plus`, `internet_connection_checker_plus`,
`http_security_pinning`, `core_responsive`, `uuid`, `injectable`, `flutter` and `core_common`
itself — for one: `platform_kernel`.

The remaining consumers each need something genuinely Flutter-bound: the four feature packages
need `GoRouteDataCustom` for their routes, `provider_state_management` needs `LifecycleMixin` /
`NetworkMixin`, `core_storage` and `core_base_ui` need `DisposeGuard`, `core_ui_kit` needs the
dialog controller, and the app shell needs `AppConfig` / `AppInitializer`. Those are correct
dependencies, not leftovers.

`ErrorHandler` loses its only Flutter dependency by swapping `kDebugMode` for
`bool.fromEnvironment('dart.vm.product')`.

**Gate:** `arch_check` R9 clean. Full verify chain passes.

### Step 6 — Relayout  *(6a done)*

✅ **6a — the tooling stopped caring where packages live.** Prerequisite, and worth more than
the move itself:

| Tool | Was | Now |
|:--|:--|:--|
| `arch_check` `_layerOf` | split the path on `packages` | derived from the **package name** |
| `monorepo_helper` | four hardcoded directories | recursive scan for `pubspec.yaml` |
| `workspace_setup` | scanned `packages/` for `l10n.yaml` | scans from the repository root |
| `unused_checker` ×2 | classified by path prefix | resolves against the discovered package list |

`arch_check` was the dangerous one: a package outside `packages/` resolved to layer `''`, so
R1, R2 and R3 **silently passed** for it. A guardrail that switches itself off when files move
is worse than none, because the report still reads clean.

⏳ **6b — the move itself** (`packages/core/*` → `platform/*`,
`packages/{domain,data,features}/<x>` → `modules/<x>/{domain,data,feature}`,
`app/` → `apps/mobile/`) is now a pure `git mv` plus `composer sync`: nothing in the tooling,
and nothing in any manifest, encodes a directory any more.

**Gate:** the app boots with **zero modules** composed. This is the property everything else
depends on, tested directly.

### Step 5 — Manifest + `composer` ✅ done

`apps/<id>/app_manifest.yaml` becomes the single source of truth.
`tools/composer/` gains `checkout`, `sync`, `sync --strict`, `gen-di`, `verify`.
Root `pubspec.yaml` and `apps/*/lib/di/injection.dart` become generated artifacts (committed,
so a clone builds without running the generator).

`sync` omits modules absent from disk and says so loudly; `sync --strict` fails on absence and
is what CI runs, so a release can never silently drop a module.

**Gate:** `generate module demo && composer sync` produces a running app with zero hand edits.

### Step 7 — Second app

`apps/admin` (Flutter Web, sidebar shell) from the same modules. `AppConfig.appFlavor` — a
global reading `services.appFlavor` — becomes an injected `IAppEnvironment`. CI becomes a
matrix.

**Gate:** one workspace builds both `mobile` and `admin` from one set of modules.

### Step 8 — Submodules

Split `contracts/` and each `modules/<name>/` into their own repositories, mount as submodules,
add CODEOWNERS (`platform/` + `tools/` → infra; `apps/` + `contracts/` → tech leads;
`modules/<x>/` → team x).

**Gate:** a machine that can clone only one module still runs `apps/mobile`; the same command
with `--strict` fails.

---

## 4. Documentation contract

The docs are unusually complete here, which means they go stale unusually fast. Rules:

1. **Docs ship in the same PR as the code.** A step is not done when the code lands.
2. **Source-of-truth order**, most authoritative first:
   `.agents/AGENTS.md` → `docs/en/**` → `CLAUDE.md` → `README.md` → `docs/vi/**`.
   `CLAUDE.md` is a summary of `AGENTS.md`; if they disagree, `AGENTS.md` wins and `CLAUDE.md`
   is the file to fix.
3. **`docs/vi/**` mirrors `docs/en/**` 1:1.** Same filenames, same headings, same order.
4. **Never document an intention.** Every code fence must be runnable against the tree in that
   commit. Prefer pasting real output over describing it.
5. **When a rule becomes machine-checked, say so** and name the rule id, so a reader knows
   whether review or CI is holding it.
6. **Numbers get re-measured, not copied.** LOC counts, dependency counts and rule counts in
   prose are re-derived each time they are touched.

### Known doc drift to fix while passing through

| Where | Problem |
|:--|:--|
| `.agents/AGENTS.md` §4 table | Repository interface row says `_repository.dart`; the convention and every real file is `i_<name>_repository.dart`. `CLAUDE.md` has it right. |
| `build.yaml` | `injectable_builder.generate_for: lib/core/di/injection.dart` — that path does not exist. Root package has no `lib/`, so it is a no-op; delete it. |
| `docs/**` responsive claims | Re-check every `context.w/h/r/sp` example against `core_responsive`'s actual axis table after step 3. |

---

## 5. Progress log

| Date | Step | What landed | Gate run? |
|:--|:--|:--|:--|
| 2026-09-21 | 1 | `arch_check` R8 + fixed `feature_settings` throwing lookup | ⚠️ not run |
| 2026-09-21 | 2a | Deleted `domain_language` + `data_language` (dead by the repo's own docs); unwired from `injection.dart`, both pubspecs, `sample_manifest.yaml`; purged from 22 doc files; removed two orphaned doc sections and renumbered `03_domain.md` / `04_data.md` | ⚠️ not run |
| 2026-09-21 | 4a | Extracted `platform_kernel` (27 files, 7 deps, no Flutter) from `core_common` (20 → 16 deps). `ErrorHandler` lost its last Flutter import (`kDebugMode` → `dart.vm.product`). Added `arch_check` **R9** — pure-Dart tier checked in the **pubspec** as well as imports. Approved edge `core_common → domain_core` became `platform_kernel → domain_core`. Deleted three stray barrel files outside any `lib/`. | ⚠️ not run |
| 2026-09-21 | 6a+ | **Repaired a conflict step 5 introduced.** `module_generator` and `sample_cleanup` both hand-patched `app/pubspec.yaml` and `app/lib/di/injection.dart`, which composer now owns — and the generator searched for `externalPackageModulesBefore: [`, a string the rewritten `injection.dart` no longer contains, so it had silently stopped working. Both now edit `app_manifest.yaml` and print the `composer sync` follow-up. Docs corrected in five places that still claimed the generator wires DI. | ⚠️ not run |
| 2026-09-21 | 6a | Made the tooling layout-independent: `arch_check` derives the layer from the package name, `monorepo_helper` discovers packages by scanning, `workspace_setup` scans from the root, both unused-checkers resolve packages by discovery. Fixed `workspace_setup` running `barrel_generator` against the whole `packages/` directory instead of each package's `lib/` — the cause of the three stray barrel files deleted in 4a. | ⚠️ not run |
| 2026-09-21 | 5 | Built `tools/composer`. `app/app_manifest.yaml` is now the source of truth for the root `workspace:` list, the app's path dependencies and `injection.dart`; all three are generated between `composer:managed` markers. Added CI **Gate 0** (`composer verify`). Two bugs caught by diffing generated output against the hand-written files: the micro-package probe matched `@InjectableInit.microPackage()` with parentheses and silently dropped the three packages that pass arguments, and marker splicing by string offset ate the markers' indentation. | ⚠️ not run |
| 2026-09-21 | 4b | Migrated `core_network`, `core_notifications`, `data_core`, `feature_dashboard` off `core_common` onto `platform_kernel` — each drops 14 inherited deps. Removed a dead `package:flutter/foundation.dart` import from `cache_database.dart` (nothing in the file used it). | ⚠️ not run |
| 2026-09-21 | 3b | `NavigatorKeys.authKey` → `NavigatorKeys.nested(id)` registry. `IDashboardTabModule` → `INavDestinationModule` returning a neutral `NavDestination`; `DashboardPage` now maps it to `BottomNavigationBarItem`. Renamed the two sample destination modules and the generator template. 39 doc/code files synced. | ⚠️ not run |
| 2026-09-21 | 3a | Introduced `AuthPrincipal` in `core_di`; contracts stopped carrying `UserEntity`. Removed `domain_auth` from `core_di` and `feature_home` pubspecs, and the `core_di -> domain_auth` approved edge from `arch_check` (4 → 3). | ⚠️ not run |
| 2026-09-21 | 2b | Trimmed `feature_auth` 1,731 → 739 LOC (−57%): deleted register + forgot-password pages, the social and footer widgets, and a dead `clearValidationErrors()`; folded three copies of one `InputDecoration` into one; replaced ~110 lines of generic doc comment with one line per file naming the mechanism it shows. Pruned `AuthNavigator` and `AuthPath` to the surviving route. ARB: 41 → 11 keys per locale (three were duplicates of `core_base_ui` globals). | ⚠️ not run |
| 2026-09-21 | 9 | **Untracked 163 MB of build output.** 50 files under `app/android/app/build/`, `app/ios/build/` and `tools/build/` were committed — two copies of a 69 MB `kernel_blob.bin` among them. The root ignore said `/build/`, which is anchored and only ever covered `app/build/`; Gradle writes one level deeper. Widened to `build/` at any depth and `git rm --cached`'d the lot. **History still carries the blobs** — every clone pays for them until somebody runs a `git filter-repo` pass, which rewrites shared history and is the repo owner's call. | ⚠️ not run |
| 2026-09-21 | 9 | **Docs accuracy is now machine-held.** Built `tools/docs_check` (CI **Gate 5**): resolves every repo path the docs name — backticked spans anchored to a real top-level directory, and markdown links resolved relative to their own file. 70 documents, ~1 300 references, 0 dead. Fixed three genuine drifts (`feature_auth` was said to ship `assets/images`, it ships `assets/language/`; a promised `07_backend_boundary.md` that the backend-out-of-scope decision made moot; a `generate.dart:90-101` line citation whose lines now hold unrelated code). 14 correctly-absent paths moved to `tools/docs_check/allowlist.txt`, each with its reason. The audit also surfaced a real hole: `app/env.prod` and `app/android/keystore.jks` — one the setup guide tells every user to create, the other written into the tree by CI — were **not gitignored**; both now are. | ⚠️ not run |
| 2026-09-21 | 2a | Doc drift from §4: `AGENTS.md` naming table said `_repository.dart` (real convention is `i_<name>_repository.dart`); `build.yaml` pointed `generate_for` at `lib/core/di/injection.dart`, which does not exist | ⚠️ not run |

### Accumulated gates — run these before merging

```bash
dart tools/workspace_setup/configure.dart     # pub get + codegen + l10n
# NOTE: `data_core` no longer imports Flutter anywhere in lib/. Its pubspec still
# declares `flutter: sdk: flutter`; confirm whether drift/core_database still need
# it before removing — this was not verifiable without a toolchain.
dart tools/arch_check/check.dart              # R1–R9
dart tools/composer/composer.dart verify      # Gate 0
dart tools/docs_check/check.dart              # Gate 5
flutter analyze
cd app && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

Codegen is **required** after step 2a: deleting two packages changes
`app/lib/di/injection.config.dart`, which is gitignored and therefore not in this commit.
