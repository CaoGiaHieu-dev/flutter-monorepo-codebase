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
- `verify` names any capability that lost its last provider but the tool could not know (V3): declare it
  `{ state: absent, reason: "…" }` (RULE-81).

## A module you generated

Remove in this order — the manifest first, so no step leaves a manifest naming a package that is gone:

1. Delete its line (or only the layers you drop) under `modules:` in **every** `apps/<id>/app_manifest.yaml` that
   composes it. A core or custom package is a name under a `di_groups` entry's `packages:` instead.
2. `dart tools/composer/composer.dart sync` — regenerates `injection.dart`, each app's path dependencies, the root
   `workspace:` list, the `facts` regions and the README reports.
3. Delete the package directories: `modules/<name>/<layer>/` for each layer, then `modules/<name>/` when empty (or
   `platform/<group>/<name>`).
4. `flutter pub get && dart run build_runner build --workspace` — regenerates every app's `injection.config.dart`.
5. `dart tools/composer/composer.dart verify`. If a capability lost its last provider, declare it `absent` with a
   reason in each app's `capabilities:`, then `composer sync` again.
6. Fix the consumers (below), then run the Verify block.

Dropping a module from **one app** only is steps 1, 2 and 4 for that manifest (`--app <id>` limits `sync`); the root
`workspace:` list keeps the package while another app composes it.

## Check the consumers

The shell degrades gracefully, but another package may hold a hard dependency on what you delete. Search first:

```bash
grep -rn "<name>_api\|domain_<name>\|data_<name>\|feature_<name>" --include=pubspec.yaml --include=*.dart . | grep -v "^./modules/<name>/"
```

- A consumer that resolves the module's contract with `getItOrNull` degrades (the control is hidden, the screen shows
  its fallback). A consumer that depends on the **API package** keeps compiling while that package stays.
- Anything importing `domain_<name>`, `data_<name>` or `feature_<name>` directly is a layering violation
  (`arch_check` R3 / R10) — fix it before deleting, or the workspace stops resolving.
- A contract owned by a removable feature reaches its consumers through `getItOrNull` / `getAllOrEmpty` and a
  fallback, never as a required constructor parameter DI cannot satisfy once the owner is gone (RULE-12).
- Documentation that names the removed paths: `dart tools/docs_check/check.dart` fails on a dead path in a module
  that is **not** a sample bundle; remove or reword those lines ([`update_docs`](../update_docs/SKILL.md)).

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
cd apps/mobile && flutter test test/di_smoke_test.dart   # and cd apps/admin: the graph boots without the module
cd <each package that imported it> && flutter test
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77
```
