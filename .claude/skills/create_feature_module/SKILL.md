---
name: create_feature_module
description: Use when the user asks to create, scaffold or add a new package or module — a feature (feature_<name>), domain_<name>, data_<name>, core_<name> or a custom platform package. Runs tools/module_generator/generate.dart with every argument, picks the state management and route contribution, chooses which apps compose it, then walks the follow-up (translations, capabilities, tests, verify). An <name>_api package is create_api_package instead.
---

# Skill: Create a module or package

Use this skill when asked to create a package in the monorepo: `feature_profile`, `domain_payment`,
`data_payment`, `payment_api`, `core_logging`, and so on.

> **Use [`create_api_package`](../create_api_package/SKILL.md) instead when** the package is `<name>_api` (generator type 6) or
> the task is "let feature A reach module B": it wires the feature and says what belongs in an API package. This skill covers
> generator types 1-5.

**Guide:** [`docs/en/guides/01_new_feature.md`](../../../docs/en/guides/01_new_feature.md) ·
[`02_new_domain_data.md`](../../../docs/en/guides/02_new_domain_data.md) · generator reference:
[`03_tooling.md` § module_generator](../../../docs/en/reference/03_tooling.md#module_generator).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-04, RULE-05, RULE-09, RULE-16,
RULE-20, RULE-24, RULE-34, RULE-81 — cite them, do not restate them.

## Ask first (if the request does not say)

1. What type? `1` Feature, `2` Domain, `3` Data, `4` Core, `5` Custom, `6` API (`<name>_api`).
2. A feature: which state management? `1` Provider, `2` BLoC, `3` none.
3. A feature: how do its routes join the app shell? `1` `IFeatureRouteModule` (stack), `2`
   `INavDestinationModule` (bottom-nav tab), `3` none.
   - `2` only for a **primary authenticated bottom-nav destination**; read
     [`04_routing.md` § 1](../../../docs/en/guides/04_routing.md#1-pick-the-routing-contract) first (RULE-24).
     Login / detail / onboarding / push screens are `1`.
4. Which apps compose it? Without `--apps` the module joins **every** `apps/<id>/app_manifest.yaml`, `apps/admin`
   included.

The agent runs the command directly; it never answers the interactive prompts.

## Step 1: Generate

```bash
# dart tools/module_generator/generate.dart <type> <name> [prefix] [sm] [route] [--group <g>] [--apps <id,id>]
# <type>    1 Feature · 2 Domain · 3 Data · 4 Core (core_<name> at platform/<group>/<name>) · 5 Custom · 6 API (modules/<name>/api, package <name>_api)
# <name>    Dart package name: lowercase letters, digits, _, starting with a letter, not a keyword
# [prefix]  pass "" except for Custom, where it is the package-name PREFIX (<prefix>_<name>); a layer word is refused
# [sm]      Feature only: 1 Provider, 2 BLoC, 3 none
# [route]   Feature only: 1 IFeatureRouteModule, 2 INavDestinationModule, 3 none
# --group   Core/Custom only: foundation|layers|infra|ui|state|shell (default infra) — see docs/en/architecture/02_core.md
# --apps    any type: compose into these app.ids only (default every app); an unknown id exits 64 before anything is written
```

> **For a feature, always pass all five positional arguments.** A feature missing `[sm]` or `[route]` prompts on a
> terminal, which blocks an agent, and without a terminal exits `64`. Types 2–4 and 6 take only `<type> <name>`
> (a non-empty third argument is refused); type 5 needs the prefix.
>
> Arguments are checked **before anything is written**; each refusal exits `64` with the usage: a bad package name,
> `[sm]` / `[route]` outside `1`–`3` or on a non-feature, an unknown flag, a package name already declared by any
> `pubspec.yaml`. An existing module directory, a missing toolchain or a failed step exits `1`.
> `dart tools/module_generator/generate.dart --help` prints the usage.

Examples:

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1               # Provider feature, stack routes
dart tools/module_generator/generate.dart 1 chat "" 2 2 --apps mobile    # BLoC feature as a bottom-nav tab, mobile only
dart tools/module_generator/generate.dart 2 payment                      # domain_payment
dart tools/module_generator/generate.dart 3 payment                      # data_payment
dart tools/module_generator/generate.dart 6 payment                      # payment_api
dart tools/module_generator/generate.dart 4 analytics --group infra      # core_analytics at platform/infra/analytics
dart tools/module_generator/generate.dart 5 billing acme                 # acme_billing at platform/infra/billing
```

**A complete module is generated in the order `2` → `3` → `1`** (and `6` whenever another feature must reach
it), all with the **same `--apps`**: the data package then depends on `domain_<name>` and registers
`@LazySingleton(as: I<Name>Repository)`, and the feature starts from the same manifest entry
(`- { id: payment, layers: [feature, data, domain] }`). `6` works before or after `1`: the generator wires
whichever exists ([`create_api_package`](../create_api_package/SKILL.md)). Flows to build on top:
[`implement_domain_data_flow`](../implement_domain_data_flow/SKILL.md).

> **A module that registers a contract the shell catalogues changes each composing app's `capabilities:`.** The
> generator prints a reminder; `composer verify` (V3) names the key and the line to paste (a nav tab is
> `tabs: provided`, routes `routes: provided`, a splash `splash: provided`, …; `composer describe --catalog` lists
> the 14 optional contracts). Declare it in every app that composes the module (RULE-81). A second tab also needs
> `feature_dashboard` composed (check C12). A whole new *app* is not a module: `composer new`
> ([`configure_app`](../configure_app/SKILL.md)).

## What the tool guarantees

| Behaviour | Detail |
| :--- | :--- |
| Folders | The tool creates the tree, but the barrel pass deletes a directory that is still empty, so only folders holding a generated file remain: a domain package has `repositories/`, a data package `repositories_impl/`, and a package's constants go in a `utils/` you create with its first file (RULE-09). Every feature gets `utils/<name>_path.dart` and `routing/<name>_route_module.dart`, whatever the route choice; delete them if the feature contributes no routes. |
| State-management folder | `lib/src/provider/` or `lib/src/bloc/` — **singular**, like `feature_auth` / `feature_home`. |
| Toolchain | FVM is used only when a config (`.fvmrc` or `.fvm/fvm_config.json`) exists **and** `fvm --version` succeeds; otherwise the global `dart` / `flutter` (RULE-73). |
| Fail-safe | The toolchain is checked **before any write**; an existing module directory aborts instead of overwriting. |
| Rollback | Every `app_manifest.yaml` and what `composer sync` rewrites (root `pubspec.yaml`, and per app `pubspec.yaml`, `lib/di/injection.dart`, `lib/app/app_profile.dart` and `README.md`) is snapshotted first (no lock file: they are git-ignored); any later failure restores them, deletes the new directory and exits `1`. |
| Registration | A module layer (`1`, `2`, `3`, `6`) is added to `modules:` in each manifest; a core or custom package (`4`, `5`) is added to the `core` DI group's `packages:` — move it to the right group by hand when it belongs elsewhere ([`implement_dependency_injection`](../implement_dependency_injection/SKILL.md)). The entry is decided by parsing the YAML and re-parsed after the edit; a manifest the tool cannot edit rolls everything back. |
| Starts clean | A new package declares only the workspace packages its templates import, so `check_unused_packages` passes at once. Domain gets `domain_core` and an `I<Name>Repository` stub with a placeholder `ping()`; data gets `data_core` and `<Name>RepositoryImpl extends BaseRepository`, implementing the domain's interface when `domain_<name>` already exists; core, custom and API packages get no product dependency. |
| Nav order | A tab (`2`) gets `order` = the highest existing `INavDestinationModule.order` under `modules/*/feature` + 10 (10 when none), so generated tabs never tie. |
| Tests from the start | A feature gets `test/<name>_page_test.dart` and `test/<name>_provider_test.dart` / `<name>_bloc_test.dart` (none for SM `3`), passing as generated (a Provider feature's page test includes a failing-load case: the page's `onErrorBuilder` must show `somethingWentWrong`, never the diagnostic); keep them green as you build. |
| Pipeline | Manifest edit, `composer sync`, `dependency_sync`, `flutter pub get`, `gen-l10n` (features), the package barrel, `build_runner`, the barrel again, `dart fix --apply` — you do not run these for the first generation. |

Barrels after your own edits: [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator).

## Step 2: Review and fill what the generator left (a feature)

The generator wrote a working page, controller, route and tests. What is yours:

1. **Routes.** Review `routing/<name>_route_module.dart` (the `@TypedGoRoute`; the controller is created there,
   RULE-21) and the contract stub — `*_feature_route_module.dart` (`routes`) or `*_nav_destination.dart` (`order`,
   `path`, `routes`, `destination`: change the placeholder icon). Never edit `app_router.dart` (RULE-20).
   More routes and parameters: [`implement_navigation_route`](../implement_navigation_route/SKILL.md).
2. **Controller.** Replace the placeholder: [`implement_provider_ui`](../implement_provider_ui/SKILL.md) or
   [`implement_bloc_ui`](../implement_bloc_ui/SKILL.md). Provider: the generated `initialize()` is the hook
   `BaseProvider` calls after construction; a method named anything else never runs.
3. **Translations.** `assets/language/vi.arb` starts as a copy of the English text: translate it, add the
   feature's strings to both files, run `gen-l10n` — [`localize_feature`](../localize_feature/SKILL.md) (RULE-34).
4. **Navigator for other features.** `dart tools/module_generator/generate.dart 6 <name>` if `<name>_api` does
   not exist.
5. **First launch.** Optional: `@LazySingleton(as: IAppEntryLocation)` (later cold starts land on the first tab).
6. **Re-run codegen and restart.** After your edits `dart run build_runner build --workspace`, then a **full
   restart** — hot reload does not apply new DI registrations. If you changed a `lib/` file list, regenerate the barrel.

## Step 3: Keep the module removable

The app must still build after any feature package is deleted. Confirm:

- nothing outside the feature imports `package:feature_<name>/…` except each composing app's generated
  `apps/<id>/lib/di/injection.dart` (RULE-05, `arch_check` R10);
- what another feature consumes from you is a contract in your module's `<id>_api`; what the shell consumes is a
  product-neutral `core_di` contract (RULE-08), both resolved with `getItOrNull` / `getAllOrEmpty` and a fallback
  (RULE-12, `arch_check` R8).

To remove a module (manifest line, `composer sync`, **delete `modules/<name>/<layer>/`**, `pub get`, `build_runner`,
or `remove_sample` for a shipped sample): [`remove_module`](../remove_module/SKILL.md).

## Related

- [`implement_navigation_route`](../implement_navigation_route/SKILL.md), [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md),
  [`run_repo_tooling`](../run_repo_tooling/SKILL.md), [`configure_app`](../configure_app/SKILL.md)
- [`create_api_package`](../create_api_package/SKILL.md), [`localize_feature`](../localize_feature/SKILL.md),
  [`remove_module`](../remove_module/SKILL.md)

## Verify

```bash
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart
dart tools/composer/composer.dart verify                 # manifests vs generated regions, capabilities (V3)
dart tools/unused_checker/check_unused_packages.dart     # declared-but-unused dependencies
cd modules/<name>/feature && flutter test                # also each package you added tests to
cd apps/mobile && flutter test test/di_smoke_test.dart   # and apps/admin if it composes the module
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77
```
