---
name: remove_module
description: Use when a module or package must go — "remove the auth sample", "delete this feature", "drop a module from the admin app", "clean up the sample code", "remove_sample". Takes a module out of an app (manifest line, composer sync) or out of the repo (delete the directory, pub get, build_runner), flips the capabilities that lost their last provider, or runs remove_sample for a shipped sample.
---

# Skill: Remove a module

Use this skill to take a module out of one app, or out of the repository. The shipped modules (`auth`, `home`,
`settings`, `onboarding`, `dashboard`, `splash`, `cache`) are **sample** reference code — patterns to copy or delete,
not product logic — and have a tool; a module you generated has the manual path.

**Guide:** [`docs/en/guides/01_new_feature.md` § 9](../../../docs/en/guides/01_new_feature.md#9-remove-a-feature) · the
tutorial's [clean-up](../../../docs/en/getting-started/04_first_feature_tutorial.md#clean-up-remove-the-module).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-05, RULE-12, RULE-16, RULE-81. Cite them; do not restate them.

Every module is removable (RULE-05): only each app's generated `lib/di/injection.dart` names a module package, and the
shell resolves contributions with `getItOrNull` / `getAllOrEmpty`. Never hand-edit a `composer:managed` region
(RULE-16): the manifest is the input.

## A shipped sample: let the tool do it

```bash
dart tools/sample_cleanup/remove_sample.dart --list           # sample vs framework vs shell
dart tools/sample_cleanup/remove_sample.dart auth             # dry run: writes nothing
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

The dry run prints what would be removed, what breaks, which couplings degrade safely (`breaks` and
`safe_couplings` in `tools/sample_manifest.yaml`), and which docs go dead — **read it before applying**. `--apply`
removes the bundle (its feature, domain and data packages), drops it from every `app_manifest.yaml`, flips the
capabilities **only it** provided to `absent`, and runs `composer sync` (shared files are rolled back on a failure;
deleted directories are not — recover them with git). Then follow its printed next steps:

```bash
dart tools/composer/composer.dart verify
flutter pub get
dart run build_runner build --workspace
```

- A module's `<id>_api` package is **kept while another package still imports it** (`feature_onboarding` imports
  `auth_api`): the manifest keeps `{ id: auth, layers: [api] }`, its contracts have no implementation, and the
  consumers' `getItOrNull` lookups already handle that. Run the removal again once nothing imports it.
- `remove_sample` accepts only the bundles listed in `tools/sample_manifest.yaml` (an unknown one exits `64`) and
  never edits that file; `docs_check` therefore reports a documentation reference into a removed sample as INFO, not a failure.
- `--apply` flips the manifests but edits no test: update each app's `test/app_profile_test.dart` (and any
  `_factoriesNeedingArguments` entry) as [The app tests](#the-app-tests) says, or Gate 3 fails.
- `verify` names any capability that lost its last provider but the tool could not know (V3): declare it
  `{ state: absent, reason: "…" }` (RULE-81).

## A module you generated

Start with the consumers (below): the root `workspace:` list follows `dependencies` in every `pubspec.yaml`, so a
package that something else still lists stays in the workspace and `flutter pub get` fails when you delete its
directory. Then remove in this order — the manifest first, so no step leaves a manifest naming a package that is gone:

1. Drop every dependency on, and import of, the module's packages (`<name>_api`, `domain_<name>`, `data_<name>`,
   `feature_<name>`) outside the module — see **Check the consumers**.
2. Delete its line (or only the layers you drop) under `modules:` in **every** `apps/<id>/app_manifest.yaml` that
   composes it. A core or custom package is a name under a `di_groups` entry's `packages:` instead.
3. `dart tools/composer/composer.dart sync` — regenerates `injection.dart`, each app's path dependencies, the root
   `workspace:` list, the `facts` regions and the README reports.
4. Delete the package directories: `modules/<name>/<layer>/` for each layer, then `modules/<name>/` when empty (or
   `platform/<group>/<name>`). Run `composer sync` again if `pub get` still names the package.
5. `flutter pub get && dart run build_runner build --workspace` — regenerates every app's `injection.config.dart`.
6. `dart tools/composer/composer.dart verify`. If a capability lost its last provider, declare it `absent` with a
   reason in each app's `capabilities:`, then `composer sync` again.
7. Fix the app tests (below), then run the Verify block.

Dropping a module from **one app** only is steps 2, 3 and 5 for that manifest (`--app <id>` limits `sync`); the root
`workspace:` list keeps the package while another app composes it.

## The app tests

Gate 3 runs `cd apps/<id> && flutter test` — the whole package, not only the smoke test. Two files name what you removed:

- `apps/<id>/test/di_smoke_test.dart` — a factory with a non-nullable `@factoryParam` has an entry in
  `_factoriesNeedingArguments`. Once the module is gone the test fails with `FactoryProblem:F03 <Type> is listed in
  notBuilt but is not a factory the graph registers`: delete the entry.
- `apps/<id>/test/app_profile_test.dart` pins the capabilities the app provides ("declare every optional contract the
  sample modules provide"). After any capability flips to `absent` — by hand, by `remove_sample`, or from a V3
  finding — update the expectations in the same test files of **every** app you changed.

## Related

- [`create_feature_module`](../create_feature_module/SKILL.md) — the reverse; [`create_api_package`](../create_api_package/SKILL.md)
- [`run_repo_tooling`](../run_repo_tooling/SKILL.md) — `remove_sample`, `composer`, `docs_check`

## Verify

```bash
dart tools/composer/composer.dart verify                 # manifests, regions and capabilities agree (Gate 0)
flutter pub get && dart run build_runner build --workspace
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart
dart tools/unused_checker/check_unused_packages.dart
dart tools/docs_check/check.dart                         # no dead path
cd apps/<id> && flutter test                             # every app: smoke test and app_profile_test (Gate 3)
cd <each package that imported it> && flutter test
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77
```
