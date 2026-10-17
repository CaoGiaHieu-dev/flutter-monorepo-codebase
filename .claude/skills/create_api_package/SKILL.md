---
name: create_api_package
description: Use when another feature must reach a module without importing it — "add an API package", "let feature A navigate to feature B", "expose a contract from my module", "create <id>_api". Generates modules/<id>/api (package <id>_api) with generator type 6, adds the api layer to the manifests, wires an existing feature, and covers what belongs in an API package (navigators, action handlers, widget builders, module-owned storage interfaces) and what arch_check holds it to. Not for a screen's own route inside a feature (use implement_navigation_route).
---

# Skill: Create a module API package

Use this skill when a feature needs a contract to **another module**: a navigator, an action handler, a
widget-builder interface or a module-owned storage interface. Such a contract belongs to the module that
implements it — its API package `modules/<id>/api`, named `<id>_api` — never to `core_di` (RULE-04, RULE-08,
RULE-22, RULE-25).

> **Use [`implement_navigation_route`](../implement_navigation_route/SKILL.md) instead when** the task is a screen or a route
> inside one feature; it comes back here only for the cross-module navigator. **Use
> [`create_feature_module`](../create_feature_module/SKILL.md) instead when** the package is a feature, domain, data, core or
> custom one (generator types 1-5).

**Guide:** [`docs/en/guides/12_module_isolation.md` § 4](../../../docs/en/guides/12_module_isolation.md#4-create-a-module-api-package).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-04, RULE-05, RULE-08, RULE-12, RULE-22,
RULE-25, RULE-75. Cite them; do not restate them.

The samples ship two: `auth_api` (`AuthNavigator`, `IAuthActionHandler`) and `home_api` (`HomeNavigator`).

## Step 1: Generate

```bash
dart tools/module_generator/generate.dart 6 payment                  # payment_api at modules/payment/api
dart tools/module_generator/generate.dart 6 payment --apps mobile    # compose it into mobile only
```

Type 6 takes only `<type> <name>` (a non-empty third argument is refused); `--apps` and an unknown id behave as for
every type ([`create_feature_module`](../create_feature_module/SKILL.md)). It:

- writes `pubspec.yaml` (Flutter only — no DI module, no code generation, no `utils/`) and a navigator stub
  `lib/src/navigators/payment_navigator.dart` with `PaymentNavigator.toPayment(BuildContext)`;
- adds `api` to the module's `layers:` in every `apps/<id>/app_manifest.yaml` (or only `--apps`), creating
  `- { id: payment, layers: [api] }` when the module has no entry, then runs `composer sync`, `dependency_sync`,
  `pub get`, the package barrel, `build_runner`, the barrel again and `dart fix`;
- when `modules/<name>/feature` exists with the route the generator wrote, declares `payment_api` in the feature's
  `dependencies:` and writes `routing/payment_navigator_impl.dart` (`@LazySingleton(as: PaymentNavigator)`
  calling `const PaymentRoute().go(context)`); a feature generated **after** the API package gets the same wiring.
  Either order works.

If the feature has no route named `<Name>Route`, nothing is wired and the tool prints what to do by hand.

## Step 2: Shape the contract

Edit `lib/src/navigators/<name>_navigator.dart`: **one method per route the feature owns, and only its own**
(`PaymentNavigator` never gets a `toSettings`). Add other contracts beside it:

| Contract | Where | Implemented by |
| :--- | :--- | :--- |
| Navigator | `lib/src/navigators/<name>_navigator.dart` | `routing/<name>_navigator_impl.dart` in the feature |
| Action handler (`I*ActionHandler`) | `lib/src/actions/i_<name>_action_handler.dart` | `handlers/<name>_action_handler_impl.dart` — [`implement_action_handler`](../implement_action_handler/SKILL.md) |
| Widget-builder interface | `lib/src/…` | the owning feature |
| Module-owned storage interface | `lib/src/…` | the owning data package — [`implement_package_storage`](../implement_package_storage/SKILL.md) |

An API package depends on `platform/foundation/*` and Flutter / pub packages only (`arch_check` R3): not its own
module's domain, data or feature, and not another module or its API. A contract carries its own value types.

A new file in the package reaches consumers only through the package barrel (RULE-75): [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator) says when to regenerate it.

## Step 3: Implement and consume

- The owning feature declares `<id>_api` under `dependencies:` and implements the contracts (the generator did for
  the navigator). Keep the contract and the implementation in step.
- A consumer lists `<id>_api` under `dependencies:` — never the feature — and resolves with
  `getItOrNull<PaymentNavigator>()?.toPayment(context)` (RULE-12; `arch_check` R8 blocks a throwing `getIt` outside
  the module). The route side is [`implement_navigation_route`](../implement_navigation_route/SKILL.md).

## What the tooling does with an API package

- The `api` layer needs no `di_groups` entry: composer makes it a workspace member, never an app dependency or an
  `injection.dart` line.
- `arch_check` R1 / R10: no platform package and no app file (bar `injection.dart`) imports it.
- In a partial checkout a module you import an API from must be checked out too — its API package lives inside it.
- `remove_sample <id>` keeps an API package while another package imports it and leaves the manifest entry as
  `{ id: <id>, layers: [api] }` ([`remove_module`](../remove_module/SKILL.md)).

## Related

- [`docs/en/architecture/05_features.md`](../../../docs/en/architecture/05_features.md) § 9 — why cross-module navigation goes through the target's navigator
- [`implement_navigation_route`](../implement_navigation_route/SKILL.md), [`implement_action_handler`](../implement_action_handler/SKILL.md)

## Verify

```bash
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R3 API deps, R8 getItOrNull, R1 / R10
dart tools/composer/composer.dart verify                 # the api layer is in the manifests, regions in sync
dart tools/unused_checker/check_unused_packages.dart     # every consumer imports what it declares
cd modules/<id>/feature && flutter test                  # and each consumer's package
cd apps/mobile && flutter test test/di_smoke_test.dart   # the contract implementation resolves
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77
```
