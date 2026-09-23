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
| **Changing** | `platform/` (today `platform/*`) must stop naming any product concept. |
| **Changing** | Root `pubspec.yaml` + each app's `injection.dart`: hand-written → **generated** from an app manifest. |
| **Changing** | Samples: 6 feature packages + 2 domain/data pairs → **2 reference modules**, deliberately small. |
| **Not changing** | Clean Architecture, the DI model (GetIt + Injectable), Freezed/BLoC rules, the responsive mandate, the barrel/codegen workflow. |
| **Not in scope** | The backend. It lives in another repo, owned by the backend team. The only surface we own is `core_network`, which talks to it over HTTP like any other client. |

### Baseline (measured 2026-09, before any step)

| Tier | LOC | Files | Packages |
|:--|--:|--:|--:|
| Framework (`core/*`, `domain_core`, `data_core`) | 16,721 | 281 | 13 |
| App shell (`apps/mobile/`) | 1,379 | 24 | 1 |
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
  implemented *only* by a `modules/*/feature` package, then blocks any `getIt<T>()` /
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
  `modules/<module>/contracts/` is a file move; it rides the relayout rather than
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

### Step 6 — Relayout ✅ done

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

✅ **6b — the move itself.** `packages/core/*` → `platform/*`; `packages/{domain,data,features}/<x>`
→ `modules/<x>/{domain,data,feature}`; `domain_core` and `data_core` → `platform/`, because a
layer foundation is framework, not product. `packages/` no longer exists. Every move was a
`git mv`, so blame and history follow the files.

Package **names** did not change, deliberately. `core_di` lives at `platform/di` and is still
imported as `package:core_di/...`. The directory tree is what CODEOWNERS matches and what a
submodule splits on; the package name is the import surface, and renaming it would rewrite
every import in the repository to buy nothing.

Path dependencies and the root `workspace:` list were **recomputed from where packages actually
are**, not hand-patched — the same calculation `composer sync` performs, so CI Gate 0 agrees.

✅ **`app/` → `apps/mobile/`.** The last move, and the only one reaching the native build. The
Flutter project's own files needed nothing: `settings.gradle.kts`, `build.gradle.kts` and the
Xcode project address everything relative to the app root (`../..`, `../../build`), so they
travelled intact. Everything pointing *in* did need updating, and three of those were live
breaks rather than cosmetics:

| Broke | Why |
|:--|:--|
| `fastlane` `workspace_root` | `File.expand_path("..", APP_DIR)` resolved to `apps/`, not the repo root. Now walks up to the pubspec declaring `workspace:` |
| CI `--dart-define-from-file=../.env` | `.env` is written to the repo root; from one directory deeper `../` no longer reaches it. Now absolute, via `$GITHUB_WORKSPACE` / `$(Build.SourcesDirectory)` |
| `unused_checker` entry point | tested `endsWith('/app/lib/main.dart')`, so the application's own entrypoint became an "orphaned file". Now any `lib/main.dart` |

A fourth was already broken before the move and only surfaced here: fastlane globbed
`packages/**/l10n.yaml` for translation generation, and `packages/` stopped existing one commit
earlier. `.rb` was not in that commit's sweep. It now scans from the workspace root.

The app package is still **named** `app`, not `mobile_app`. Renaming is nearly free — nothing
imports `package:app/` — but injectable writes that name into generated code, and there is no
toolchain here to confirm the regeneration. It rides step 7, where a second app makes the
asymmetry concrete and testable.

✅ **`.github/CODEOWNERS`.** The reason `modules/<name>/` exists, written down: one line per
team, because CODEOWNERS matches paths and cannot express "the auth rows of three sibling
directories". Handles are placeholders — GitHub silently ignores a team that does not exist, so
a rule can look enforced and not be.

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

### Step 7 — Second app  *(7a, 7b done; 7c — the app itself — needs a toolchain)*

`apps/admin` composing a **different subset** of the same modules is the only real test of the
composition design — and the direct answer to whether a team can detach and reattach modules
freely. An admin app with auth + settings and no dashboard, splash or onboarding exercises every
`getItOrNull` / `getAllOrEmpty` fallback at once, permanently, in-repo.

#### 7b — extract the shell first (prerequisite) ✅ done

A second app today means copying **1,369 lines across 24 files**. That is not a second app, it is
a fork. The shell has to become a package before `apps/admin` is worth writing.

The good news, measured rather than assumed: after step 3c the shell imports **no module at all**
outside `injection.dart`, and only two files reference `configureDependencies`. The split is
therefore clean:

| Stays in `apps/<id>/lib/` | Moves to `platform/app_shell/` |
|:--|:--|
| `main.dart` — entrypoint and flavor | `main_scope.dart`, `app.dart` |
| `di/injection.dart` — `@InjectableInit`, must live in the app package so `injection.config.dart` is generated for it | all of `presentation/` (router, material wrapper, root app, the two providers, the two widgets) |
| | `di/` storage adapters + `network_config_impl.dart` + `network_binding_module.dart` + `di/utils/` keys |

Keeping the same folder layout inside the package leaves every relative import untouched; only
`main.dart`'s four imports become `package:platform_app_shell/...`.

Two things the move must get right:

1. **Its own `@InjectableInit.microPackage()`.** The storage adapters are `@LazySingleton`, so
   without a module nothing registers them.
2. **DI group order.** `core_base_ui` depends on `ILanguageStorage` / `IThemeStorage`, so the new
   group sits between `core` and `ui` in each `app_manifest.yaml`. Get this wrong and boot throws
   `"<Type> is not registered"` — invisible to `flutter analyze` (AGENTS §18).

**Done as planned**, with two corrections to the plan above. `app.dart` did not stay: it was a
barrel over files that all moved, so it was deleted and `platform_app_shell.dart` replaces it. And
`main.dart`'s three relative imports became one package import, not four.

The DI order is unchanged, which was the risk. The storage adapters, `NetworkConfigImpl` and
`AppRouter` used to be app-local registrations, which injectable runs *between* the `before` and
`after` phases. They now register through `platform_app_shell`'s own module in a new `shell` DI
group, placed first in `after` — the same slot. `ui` still initialises after them.

`injection.dart`, the app's path dependencies and the root workspace list were regenerated with a
Python port of composer's generation logic, validated first by reproducing the three committed
artifacts byte for byte. `composer verify` should therefore agree; it is still the check to trust.

#### 7c — then the app itself

`AppConfig.appFlavor` — a global reading `services.appFlavor` — becomes an injected
`IAppEnvironment`, because two apps cannot share one global flavor. CI becomes a matrix. The app
package is also renamed `mobile_app` at this point: nothing imports `package:app/`, so the rename
is nearly free, but injectable writes the package name into generated code and that wants a
toolchain to confirm.

**Gate:** one workspace builds both `mobile` and `admin` from one set of modules, and the admin
build contains no `feature_dashboard`, `feature_splash` or `feature_onboarding`.

### Step 8 — Submodules  *(8a done: the mechanism and the guide; 8b needs real remotes)*

✅ **8a — everything that does not require a second git remote.**

The mechanism was already finished by earlier steps and had simply never been written down:
`composer` resolves packages by name, `arch_check` derives layers from names, `MonorepoHelper`
scans — so a module that is absent is just not found, and `sync` composes whatever is present.
R8 (optional lookups) and R10 (no module import in the shell) are what let the app boot without
it.

What was missing was the *procedure*, and one sharp edge in it. `composer sync` edits three
**committed** files, so a partial checkout leaves a partial composition in the working tree.
That is right locally and wrong to commit — it would drop every other team's module from the
app. `sync` now prints a `PARTIAL COMPOSITION` block naming the three files and the exact
`git checkout --` line to undo it, and CI Gate 0 catches it regardless, because `verify`
regenerates from the manifest on a runner where every submodule is present.

[`docs/{en,vi}/guides/12_module_isolation.md`](../docs/en/guides/12_module_isolation.md) covers
extraction with `git filter-repo`, the partial-checkout workflow, that hazard and its net, why a
private pub registry is the wrong trade here, and the three things isolation explicitly does not
buy (it is not a security boundary, it does not remove the contract discipline, and every
guardrail stops working the moment someone adds a direct import).

⏳ **8b — the extraction itself.** Splitting `modules/<name>/` into real repositories needs git
remotes that do not exist in the environment these changes were made in. The commands are in the
guide and were reasoned through rather than executed; run them against one module first.

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

## 5. Open decisions — for the repo owner, not for me

None open.

### ✅ Resolved: the asset picker in `core_ui_kit` — deleted

The `assets_picker/` folder under `core_ui_kit`'s `media/` was 1,003 lines across six files that nothing
imported, in a package classified framework. The repo owner chose deletion.

Removed with it: six `core_ui_kit` dependencies only the picker used (`photo_manager`,
`image_picker`, `extended_image`, `permission_handler`, `device_info_plus`, `dynamic_logger`),
three catalog pins nothing else declares, and 29 of `core_base_ui`'s 46 global strings — one
product's photo-library vocabulary (`smartAlbumLivePhotos`, `albumSyncedFaces`, …) sitting in
the file documented as *global strings only*.

It also could never have worked as shipped: neither `Info.plist` nor any `AndroidManifest.xml`
declared a photo-library permission, and iOS terminates an app that touches the library
without `NSPhotoLibraryUsageDescription`.

The four documents that cited `photo_grid_item.dart` as *the* example of reading from context
before an `await` now carry an illustrative snippet instead, labelled as such — no screen in the
template needs the pattern today, and the documentation contract forbids pointing at a file
that does not exist.

---

## 6. Progress log

| Date | Step | What landed | Gate run? |
|:--|:--|:--|:--|
| 2026-09-21 | 1 | `arch_check` R8 + fixed `feature_settings` throwing lookup | ⚠️ not run |
| 2026-09-21 | 2a | Deleted `domain_language` + `data_language` (dead by the repo's own docs); unwired from `injection.dart`, both pubspecs, `sample_manifest.yaml`; purged from 22 doc files; removed two orphaned doc sections and renumbered `03_domain.md` / `04_data.md` | ⚠️ not run |
| 2026-09-21 | 4a | Extracted `platform_kernel` (27 files, 7 deps, no Flutter) from `core_common` (20 → 16 deps). `ErrorHandler` lost its last Flutter import (`kDebugMode` → `dart.vm.product`). Added `arch_check` **R9** — pure-Dart tier checked in the **pubspec** as well as imports. Approved edge `core_common → domain_core` became `platform_kernel → domain_core`. Deleted three stray barrel files outside any `lib/`. | ⚠️ not run |
| 2026-09-21 | 6a+ | **Repaired a conflict step 5 introduced.** `module_generator` and `sample_cleanup` both hand-patched `apps/mobile/pubspec.yaml` and `apps/mobile/lib/di/injection.dart`, which composer now owns — and the generator searched for `externalPackageModulesBefore: [`, a string the rewritten `injection.dart` no longer contains, so it had silently stopped working. Both now edit `app_manifest.yaml` and print the `composer sync` follow-up. Docs corrected in five places that still claimed the generator wires DI. | ⚠️ not run |
| 2026-09-21 | 6a | Made the tooling layout-independent: `arch_check` derives the layer from the package name, `monorepo_helper` discovers packages by scanning, `workspace_setup` scans from the root, both unused-checkers resolve packages by discovery. Fixed `workspace_setup` running `barrel_generator` against the whole `packages/` directory instead of each package's `lib/` — the cause of the three stray barrel files deleted in 4a. | ⚠️ not run |
| 2026-09-21 | 5 | Built `tools/composer`. `apps/mobile/app_manifest.yaml` is now the source of truth for the root `workspace:` list, the app's path dependencies and `injection.dart`; all three are generated between `composer:managed` markers. Added CI **Gate 0** (`composer verify`). Two bugs caught by diffing generated output against the hand-written files: the micro-package probe matched `@InjectableInit.microPackage()` with parentheses and silently dropped the three packages that pass arguments, and marker splicing by string offset ate the markers' indentation. | ⚠️ not run |
| 2026-09-21 | 4b | Migrated `core_network`, `core_notifications`, `data_core`, `feature_dashboard` off `core_common` onto `platform_kernel` — each drops 14 inherited deps. Removed a dead `package:flutter/foundation.dart` import from `cache_database.dart` (nothing in the file used it). | ⚠️ not run |
| 2026-09-21 | 3b | `NavigatorKeys.authKey` → `NavigatorKeys.nested(id)` registry. `IDashboardTabModule` → `INavDestinationModule` returning a neutral `NavDestination`; `DashboardPage` now maps it to `BottomNavigationBarItem`. Renamed the two sample destination modules and the generator template. 39 doc/code files synced. | ⚠️ not run |
| 2026-09-21 | 3a | Introduced `AuthPrincipal` in `core_di`; contracts stopped carrying `UserEntity`. Removed `domain_auth` from `core_di` and `feature_home` pubspecs, and the `core_di -> domain_auth` approved edge from `arch_check` (4 → 3). | ⚠️ not run |
| 2026-09-21 | 2b | Trimmed `feature_auth` 1,731 → 739 LOC (−57%): deleted register + forgot-password pages, the social and footer widgets, and a dead `clearValidationErrors()`; folded three copies of one `InputDecoration` into one; replaced ~110 lines of generic doc comment with one line per file naming the mechanism it shows. Pruned `AuthNavigator` and `AuthPath` to the surviving route. ARB: 41 → 11 keys per locale (three were duplicates of `core_base_ui` globals). | ⚠️ not run |
| 2026-09-21 | 9 | **Semantic doc audit** — the path checker proves references *resolve*, not that prose is *true*, so the checkable claims were re-derived from code: 24 workspace members / 22 packages, `platform_kernel`'s 7 dependencies, `Result`'s 4 variants vs Provider `ViewState`'s 5, the interceptor order (Auth → RefreshToken → Retry → Logging), `AppRouter` being `@singleton`, `NavigatorKeys`' members. All held. Two stale: `CLAUDE.md` still advertised `--help` as `R1-R9`, and **R10 was machine-enforced but documented nowhere** — §4 rule 5 of this contract says a rule that becomes machine-checked must say so and name its id. Now in `AGENTS.md` §22 and both rules references. | ⚠️ not run |
| 2026-09-23 | 7c− | **Two boot bugs, found by reading the boot path as an app without onboarding and home would run it.** (1) `_goToOnboarding()` returned `true` on every first launch whether or not an onboarding module existed, so any build without one started on its fallback tab, returned early, and skipped the login redirect — first launch opened signed-out on a protected screen. (2) After sign-in, `getItOrNull<HomeNavigator>()?.toHome()` was a no-op without a home module, leaving a signed-in user on the login screen. Both invisible so far because every sample app composed onboarding and home. `AppRouter.fallbackLocation` is now public and the single definition — `UndefineRouteWidget` had its own copy. Also: `docs_check` now validates placeholder and glob paths (≥1 real match), which caught 42 `modules/*/feature/<name>/…` shapes the relayout had produced; its limit — a placeholder in the last segment matches anything — is written into the tool. | ⚠️ not run |
| 2026-09-23 | 7b | **The app shell is a package.** 20 files moved from `apps/mobile/lib/` to `platform/app_shell/` (`platform_app_shell`); what stays is `main.dart` and the generated `injection.dart`. New `shell` DI group, first in `after` — the slot app-local registrations always occupied, so boot order is unchanged. The package imports no module, and now R1 holds that instead of R10. Regenerated artifacts with a composer port validated byte-for-byte against the committed output. Docs rewritten rather than patched: `06_app_shell.md` (both locales) now describes the two-part shell; `05_di.md` §3 had described a `_databaseModules` group that does not exist and a `CoreDatabasePackageModule` that "runs LAST" while `injection.dart` runs it first; and 19 places still said `NetworkConfigImpl` injects `AuthLocalDataSource`, untrue since step 3c. | ⚠️ not run |
| 2026-09-23 | 5+ | **Fixed a build-breaking bug step 5 introduced, and the blind spot that hid it.** `apps/mobile/pubspec.yaml` declared `core_responsive` twice — once in the `composer:managed:deps` region (composer adds `extra_dependencies` there) and once in the hand-written block below. Pub rejects a duplicate key, so the workspace has not resolved since commit `f7dfd2f`. Every audit on this branch missed it because they parsed YAML with PyYAML, which keeps the last duplicate silently. Removed the hand-written entry; `composer sync` and `verify` now refuse any managed package also declared outside the markers; the verification table gains check 10, a strict-loader scan of all 50 YAML files, validated against the broken file as a control. | ⚠️ not run |
| 2026-09-23 | 2f | **Deleted the asset picker** (repo owner's decision, §5). 1,003 LOC, six `core_ui_kit` dependencies, three catalog pins, 29 global ARB keys. It could not have run as shipped — no photo-library permission was declared on either platform. Four docs re-pointed at an illustrative snippet; the setup guide's KGP note no longer lists `firebase_auth` / `photo_manager` / `google_sign_in` as current. | ⚠️ not run |
| 2026-09-21 | 9 | **A rule the docs stated backwards, in eight places.** "Reusable widgets in `core_ui_kit` take **unscaled** values — caller scales before passing in" cannot both be true: if the caller scales, the widget receives a value that is already scaled. The operative half was right (never scale a parameter), the description was not, and it also implied widgets never scale at all — which would make them non-responsive. `custom_input_field.dart` has done it correctly the whole time: `widget.paddingBottom ?? context.h(10)` — parameter as received, own default scaled. Corrected in both locales across the rules reference, architecture, design-system guide, localization guide, review checklist, AGENTS.md, CLAUDE.md and an agent skill. Also recorded *why* the colour and font-size rules are review-held rather than machine-held: seven legitimate literal-colour uses against two real ones, and no suppression comments allowed — a rule whose exception list outweighs its findings teaches people to skim it. | ⚠️ not run |
| 2026-09-21 | 2e | **Residue audit of `platform/common`, `platform/notifications`, `core_ui_kit`.** Mostly clean — "unused" is the normal state of a widget library and a utility toolbox, so that signal was the wrong criterion here. What it did find were three dark-mode bugs in `core_ui_kit`, all from hardcoded colours the design-system rule already forbids: `BottomWrapperDialog` was `Colors.white` while its children use theme colours (light text on white in dark mode); `ToastOverlayWidget` inverted its background with the theme but kept white text (white on light in dark mode); a transparent button's ripple was `Colors.white70`, invisible on a light surface. Also two raw `fontSize: context.sp(13)` overrides on already-scaled text tokens. The one remaining hardcoded colour, the loading scrim, now carries a comment saying why it must stay. | ⚠️ not run |
| 2026-09-21 | 8a | **The submodule story, written down and de-fanged.** The mechanism was already complete — name-based resolution, R8, R10 — but undocumented, and it had one sharp edge: `composer sync` edits three committed files, so a partial checkout leaves a partial composition in the tree that would drop other teams' modules if committed. `sync` now prints the files and the `git checkout --` line to undo it; CI Gate 0 was already the net. New guide `12_module_isolation.md` in both locales: extraction with `git filter-repo`, the partial-checkout workflow, why a private registry is the wrong trade, and what isolation does *not* buy. | ⚠️ not run |
| 2026-09-21 | 3c | **Removability was false, and is now machine-held.** `network_config_impl.dart` imported `data_auth` and `domain_auth` to read and refresh the session token, so deleting the auth module broke the app shell at compile time — while four documents promised modules were removable. `getItOrNull` cannot guard an import. Declared `IAuthSessionGateway` in `core_di` (read / refresh / clear — only what `NetworkConfig` asks for), implemented it in `data_auth`, and rewrote `NetworkConfigImpl` to resolve it at call time. `onRefreshToken` now returns null with no gateway present, so `ApiClient` installs no refresh interceptor in a build with no auth. Added `arch_check` **R10**: an app may import a module package in exactly one file, `injection.dart`. The app shell is now module-free apart from its composition root. | ⚠️ not run |
| 2026-09-21 | 2d | **The auth sample now follows the template's own documented pattern.** `AuthRepositoryImpl` called `FirebaseAuth`, `GoogleSignIn` and `FacebookAuth` directly and never touched `AuthRemoteDataSource` — the repo shipped the Retrofit pattern it teaches, unused, beside an implementation that ignored it, and every auth error arrived as `ServerFailure(9999)` because `ErrorHandler` has no Firebase branch. Five of eight repository methods (`registerWithEmail`, `loginWithGoogle`, `loginWithFacebook`, `getCurrentUser`, `updateUserProfile`) had zero callers. Rewritten onto the Retrofit + `StorageValue` + `execute()` path: 243 → 68 LOC, four SDK dependencies dropped. `UserEntity` lost `bankName`, `bankAccount` and `fcmToken`; `UserModel` gained `token`, which the mapper deliberately drops, with a test asserting it. Dead `CompleteLoginFlowParams` and five unrouted API constants deleted. Catalog pruned of six pins nothing declared. Docs rewritten in both locales: `04_data.md` §6, `05_di.md`'s third-party section, two agent skills, `sample_manifest.yaml`. | ⚠️ not run |
| 2026-09-21 | 6b+7a | **`app/` → `apps/mobile/`, and CODEOWNERS.** Native project files needed no edit (all internally relative). Four live breaks found and fixed: fastlane's `workspace_root` resolved to `apps/`; CI's `--dart-define-from-file=../.env` no longer reached the root-written env file (now absolute via `$GITHUB_WORKSPACE` / `$(Build.SourcesDirectory)`); `unused_checker` classed `lib/main.dart` as orphaned; and fastlane still globbed `packages/**/l10n.yaml`, broken one commit earlier because `.rb` was not in that sweep. `theme_generator` stopped hardcoding `Directory('app')` and now locates the app by its manifest. `.github/CODEOWNERS` gives each module, platform and the apps layer an owner. | ⚠️ not run |
| 2026-09-21 | 6b | **Relayout complete.** `packages/core/*` → `platform/*` (infra team's ground); `packages/{domain,data,features}/<x>` → `modules/<x>/{domain,data,feature}` (one vertical slice per bounded context); `domain_core` / `data_core` → `platform/`, since layer foundations are framework, not product. `packages/` is gone. All 298 files moved with `git mv`, so history follows. Package **names** unchanged on purpose — the directory tree is what submodules and CODEOWNERS split on, the package name is the import surface. Path deps and the workspace list recomputed from disk, not patched. Two silent failures caught: CI Gate 3's `packages/*/*/` glob would have kept passing while skipping six of eight test suites, and `module_generator`'s pubspec template had hardcoded paths that were **already** wrong before the move (`../../core/core_common` has never existed) — it now resolves every dependency by name. | ⚠️ not run |
| 2026-09-21 | 2c | **Samples now teach the rules they document.** `splash_page` 107 → 45 lines (107 lines of glassmorphism for a one-line lesson, with two hardcoded English strings beside an *empty* ARB and an unused delegate). `onboarding` and `home` dropped raw `TextStyle(fontSize:)` for `AppTextStyles`, and `context.h(...)` gaps for `AppSpacing`'s `H` variants; `feature_home` no longer depends on `core_responsive`. `settings` stopped using the radius axis for padding. All 26 snake_case ARB keys → lowerCamelCase, because `gen-l10n` copies a key into a getter name and the generated file is excluded from analysis, so nothing ever warned. Convention now written into AGENTS.md, CLAUDE.md and both rules references. | ⚠️ not run |
| 2026-09-21 | 9 | **Correctness sweep of the nine preceding commits** — no toolchain here, so each refactor was re-checked mechanically instead. Three real breaks found and fixed: `home_page.dart` still read `user.name` after step 3a renamed it to `AuthPrincipal.displayName`; `app_utils.dart` and `download_image.dart` still imported `../enums/app_enums.dart` and `api_status_constants.dart` by relative path after step 4a moved both into `platform_kernel`. Also added the `network_binding_module.dart` export the barrel generator would add on its next run. Clean: 0 dangling relative imports, 0 undeclared package imports, 0 missing l10n keys, 0 stale references to any symbol renamed in steps 2–4. | ⚠️ not run |
| 2026-09-21 | 9 | **Untracked 163 MB of build output.** 50 files under `apps/mobile/android/app/build/`, `apps/mobile/ios/build/` and `tools/build/` were committed — two copies of a 69 MB `kernel_blob.bin` among them. The root ignore said `/build/`, which is anchored to the repo root and so only ever covered Flutter's own output directory inside `apps/mobile/`; Gradle writes one level deeper. Widened to `build/` at any depth and `git rm --cached`'d the lot. **History still carries the blobs** — every clone pays for them until somebody runs a `git filter-repo` pass, which rewrites shared history and is the repo owner's call. | ⚠️ not run |
| 2026-09-21 | 9 | **Docs accuracy is now machine-held.** Built `tools/docs_check` (CI **Gate 5**): resolves every repo path the docs name — backticked spans anchored to a real top-level directory, and markdown links resolved relative to their own file. 70 documents, ~1 300 references, 0 dead. Fixed three genuine drifts (`feature_auth` was said to ship `assets/images`, it ships `assets/language/`; a promised `07_backend_boundary.md` that the backend-out-of-scope decision made moot; a `generate.dart:90-101` line citation whose lines now hold unrelated code). 14 correctly-absent paths moved to `tools/docs_check/allowlist.txt`, each with its reason. The audit also surfaced a real hole: `apps/mobile/env.prod` and `apps/mobile/android/keystore.jks` — one the setup guide tells every user to create, the other written into the tree by CI — were **not gitignored**; both now are. | ⚠️ not run |
| 2026-09-21 | 2a | Doc drift from §4: `AGENTS.md` naming table said `_repository.dart` (real convention is `i_<name>_repository.dart`); `build.yaml` pointed `generate_for` at `lib/core/di/injection.dart`, which does not exist | ⚠️ not run |

### What was verified here, and what was not

There is no Dart or Flutter toolchain in the environment these changes were made in, so every
claim below is the result of a mechanical check over the tree, not a build. Ten checks, all
clean at the last commit:

| # | Check | Catches |
|--:|:--|:--|
| 1 | every `path:` dependency resolves, and the package there has the declared name | a move that missed a pubspec |
| 2 | every relative `import` / `export` / `part` target exists | a file moved without its referrers |
| 3 | every `package:` import is declared in that package's pubspec | the failure Pub Workspaces hide until extraction |
| 4 | no `platform/*` declares a product module (R1) | the dependency direction inverting |
| 5 | no domain package imports Flutter, Dio, Retrofit or a `core_*` (R2) | the pure-Dart mandate |
| 6 | no feature imports another feature or a data package (R3) | module isolation |
| 7 | no app file outside `injection.dart` imports a module (R10) | removability silently becoming false |
| 8 | every `context.l10nX.key` exists in that package's ARB | a rename that missed a call site |
| 9 | the root `workspace:` list matches disk exactly, both directions | a package that resolves but is not a member |
| 10 | every YAML file parses with a loader that **rejects duplicate keys** | a key declared twice — which pub rejects and lenient parsers silently accept |

What they cannot see is everything a type-checker would: a wrong argument type, a missing
`@override`, a Freezed companion that no longer exists. **The four commands below are still the
real gate** — nothing here substitutes for them.

### Accumulated gates — run these before merging

```bash
dart tools/workspace_setup/configure.dart     # pub get + codegen + l10n
# NOTE: `data_core` declares `flutter: sdk: flutter` and imports no `package:flutter`
# anywhere in lib/ — checked. Removing it looks right, and is deliberately NOT done
# here: the Flutter binding arrives anyway through core_database -> sqlite3_flutter_libs,
# so nothing is gained at runtime, and the one thing that could break it is generated
# code emitting a Flutter import (drift and freezed both can, depending on options).
# That needs a build to settle. If `flutter analyze` is clean after codegen, drop it.
dart tools/arch_check/check.dart              # R1–R10
dart tools/composer/composer.dart verify      # Gate 0
dart tools/docs_check/check.dart              # Gate 5
flutter analyze
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

Codegen is **required** before analyze: several packages changed shape (`UserEntity` lost three
fields, `UserModel` gained one, `AuthRepositoryImpl` changed its constructor, a new
`IAuthSessionGateway` implementation appeared), and all of those live in `.freezed.dart` /
`.config.dart` files that are gitignored and therefore not in any commit here.

Codegen is **required** after step 2a: deleting two packages changes
`apps/mobile/lib/di/injection.config.dart`, which is gitignored and therefore not in this commit.
