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
| **Not in scope** | The backend. It lives in another repo, owned by the backend team. Only the SDK boundary is our concern — see `docs/en/architecture/07_backend_boundary.md` (step 6). |

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
| 2 | Empty `core_di` of product names | 1 | yes |
| 3 | Split `core_common` | — | yes |
| 4 | Shrink the samples | 2 | no (deletes code) |
| 5 | Rename + relayout to `platform/` + `modules/` | 3, 4 | no |
| 6 | Manifest + `composer` | 5 | yes |
| 7 | Second app (`admin`) | 6 | yes |
| 8 | Submodules + CODEOWNERS | 7 | no |

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

### Step 2 — Empty `core_di` of product names

`core_di` becomes generic-only. Per-module contracts move to their own package.

- Create `packages/contracts/account_contracts/` (pure Dart, no `flutter` in `dependencies`).
- Move out of `core_di`: `IAuthSessionState`, `IAuthStatusStream`, `IAuthRefreshListenable`,
  `AuthSessionFailure`, `IAuthActionHandler`, `AuthNavigator`, `HomeNavigator`,
  `SettingsNavigator`, `OnboardingNavigator`.
- **Do not re-export a domain entity from a contract.** Replace `UserEntity` in
  `IAuthStatusStream` / `IAuthSessionState` with a contract-owned `AuthPrincipal`
  (`id`, `displayName`, `roles`). The owning module maps `UserEntity → AuthPrincipal` at the
  boundary. This is what removes the `core_di → domain_auth` edge.
- Replace `NavigatorKeys.authKey` with a registry: `INavigatorKeyRegistry.keyFor('auth')`.
- Generalise `IDashboardTabModule` → `INavDestinationModule` (drop `BottomNavigationBarItem`
  from the contract; return a neutral descriptor and let each app render it). This is what
  lets an admin app use a sidebar.
- Replace `AuthNavigator.toLogin(context)` with a pure-Dart `NavIntent`. Navigation contracts
  stop needing `BuildContext`, so contracts stay pure Dart.

**Gate:** `grep -rniE "auth|home|settings|onboard|dashboard" packages/core/di/lib` prints
nothing. `core_di/pubspec.yaml` no longer declares `domain_auth`. Full verify chain passes.

**Docs to update in the same PR:** `.agents/AGENTS.md` §2.3, §8.4, §22 · `CLAUDE.md` Routing +
Cross-Feature tables · `docs/{en,vi}/architecture/02_core.md` §2 ·
`docs/{en,vi}/guides/04_routing.md` · `docs/{en,vi}/guides/10_cross_feature.md` ·
`docs/{en,vi}/reference/01_rules.md`.

### Step 3 — Split `core_common`

One package with 20 dependencies becomes three with a defensible boundary each.

| New package | Holds | Flutter? |
|:--|:--|:--|
| `platform_kernel` | `getIt` helpers, `ErrorHandler`, exceptions, `TypeHelper`, `ValidationHelper`, enums, `EnvConstants`, `ApiStatusConstants` | no |
| `platform_flutter` | `AppConfig`, `AppInitializer`, mixins, `GoRouteDataCustom`, page transitions, `AppUtils`, dialog controller, formatters | yes |
| `platform_firebase` | `FirebaseModule` and the generated options | yes |

`ErrorHandler` loses its only Flutter dependency by swapping `kDebugMode` for
`bool.fromEnvironment('dart.vm.product')`.

**Gate:** `platform_kernel/pubspec.yaml` declares no `flutter:` and no UI package. Full verify
chain passes.

### Step 4 — Shrink the samples

Sample code is documentation written in Dart. Six overlapping features is not documentation,
it is a second product to maintain. Two reference modules demonstrate every mechanism.

| Today | After | Why |
|:--|:--|:--|
| `feature_auth` (1,731 LOC) | `modules/account` — **login only** | Provider + stack route + agnostic stream + action handler. Register / forgot-password add no new mechanism; delete them. |
| `feature_home` (291) | `modules/catalog` | BLoC + private Freezed events + nav destination + consuming another module's contract. |
| `feature_settings` (195) | fold into `catalog` | Its only unique role is *consuming* an action handler; one screen can show that. |
| `feature_dashboard` (129) | → app shell | Chrome belongs to the app, not to a removable feature. |
| `feature_splash` (182) | → app shell | Same. |
| `feature_onboarding` (158) | → app shell | Same; keep `IAppEntryLocation` as the contract it demonstrates. |
| `domain_language` + `data_language` (183) | **delete** | Dead by the repo's own admission: the Settings UI uses `LanguageProvider`, never `SetLanguageUseCase`. |
| `cache_chain` inside `data_core` | move to `modules/catalog` | It is a sample; it must not sit inside a framework package. |

Target: **~2 modules, well under 1,000 LOC of sample**, each file stating in one line which
mechanism it exists to show.

**Gate:** `dart tools/sample_cleanup/remove_sample.dart --list` agrees with the table above,
and removing either module leaves the app building and booting.

### Step 5 — Relayout

Physical move, no behaviour change. `packages/core/*` → `platform/*`;
`packages/{domain,data,features}/<name>` → `modules/<name>/<name>_{domain,data,feature}`;
`app/` → `apps/mobile/`. Update `tools/barrel_generator`, `tools/unused_checker`,
`tools/workspace_setup` — all three scan a hard-coded `packages/` today.

**Gate:** the app boots with **zero modules** composed. This is the property everything else
depends on, tested directly.

### Step 6 — Manifest + `composer`

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
| 2026-09-21 | 1 | `arch_check` R8 + fixed `feature_settings` throwing lookup | ⚠️ not run — no Flutter toolchain in the authoring environment. **Run `dart tools/arch_check/check.dart` before merging.** |
