# Module Isolation with Git Submodules

## Goal

A team checks out only its own module, builds the whole app from it, and never sees another team's source. You split a module into its own repository, work in a partial checkout, restore the composition before you commit, and give a module an API package other features can depend on.

## Prerequisites

- A full checkout that builds — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).
- **Why this works at all**, why submodules beat a private pub registry here, and what isolation does *not* buy you — [`../architecture/01_overview.md` § 6](../architecture/01_overview.md#6-module-isolation--why-it-works-and-its-limits).
- Who owns what, module by module — [`../architecture/01_overview.md` § 4](../architecture/01_overview.md#4-who-owns-what).

---

## 1. Extract a module into its own repository

Done once per module, by whoever owns the monorepo. The example is `auth`.

```bash
# 1. Carve the module out with its history intact.
#    git-filter-repo is the maintained tool; git-subtree also works.
git clone <monorepo-url> /tmp/auth-extract
cd /tmp/auth-extract
git filter-repo --path modules/auth/ --path-rename modules/auth/:

# 2. Push it to its own repository.
git remote add origin <auth-repo-url>
git push -u origin main

# 3. Back in the monorepo, replace the directory with a submodule.
cd <monorepo>
git rm -r --cached modules/auth
rm -rf modules/auth
git submodule add <auth-repo-url> modules/auth
git commit -m "chore: auth becomes a submodule"
```

Nothing else changes. `app_manifest.yaml` still says `- { id: auth, layers: [api, domain, data, feature] }`, because a manifest names modules, not directories.

> [!IMPORTANT]
> Do this **after** the module is stable. Moving a file between two modules stops being a rename and becomes a delete-plus-add across two repositories, with the review split in half.

## 2. Work in a partial checkout

A developer on the auth team clones the monorepo without other teams' sources:

```bash
git clone <monorepo-url> && cd <monorepo>
git submodule update --init modules/auth      # only theirs
dart tools/composer/bootstrap.dart            # prune what is not on disk, so pub can resolve
flutter pub get                               # composer needs a resolved workspace
dart tools/composer/composer.dart sync        # compose what is present (every app)
dart tools/workspace_setup/configure.dart     # pub get + l10n + codegen + barrels
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev
```

**Why the `bootstrap` step.** `composer.dart` imports `package:path` and `package:yaml`, so it only runs in a resolved workspace. A fresh partial checkout does not resolve:

- the committed root `workspace:` list and each app's path dependencies still name every module;
- an uninitialised submodule is an empty directory with no `pubspec.yaml`;
- so `flutter pub get` refuses the whole workspace (*"No workspace packages matching `modules/home/api`"*).

`tools/composer/bootstrap.dart` breaks that cycle. It imports no package, so it runs with no `.dart_tool/` at all. It only **removes** entries, and only from the `composer:managed` regions of the root `pubspec.yaml` and of each `apps/<id>/pubspec.yaml`: every entry whose directory has no `pubspec.yaml`. `sync` then rewrites those regions, and each app's `injection.dart`, properly from the manifests. On a full checkout `bootstrap` finds nothing to prune and writes nothing, so it is safe to run every time. `--dry-run` shows what it would prune.

`bootstrap` refuses — writing nothing, exit 1 — when a module that **is** present declares a hand-written path dependency on one that is not (`modules/auth/data` without `modules/auth/domain`, say): no managed region can drop that line, so pub would still fail. Initialise the missing submodule as well.

Run `sync` for **every app** — do not narrow it with `--app mobile`. The root `workspace:` list is always rebuilt from all apps and drops what is not on disk, but `--app mobile` leaves `apps/admin/pubspec.yaml` untouched, still declaring path dependencies on the missing modules (`settings`, say) — and `flutter pub get` then fails to resolve the workspace.

`sync` prints one warning per declared package that is not on disk, and — because the manifests still declare `tabs`, `dashboard`, `entry` and the like as `provided` while the modules that register them are absent — a warning per capability that nothing composed now registers (V3), ending *"`composer verify` fails until each is fixed"*. In a partial checkout that is expected: `sync` still writes. Do not edit the manifest to silence it.

The app runs. In an auth-only checkout it has no home screen, no settings, no dashboard — and it boots, because every shell lookup for a module-owned contract is `getItOrNull` or `getAllOrEmpty` (`arch_check` R8), and no shell file imports a module (`arch_check` R10 in the app, R1 in `platform_app_shell`).

`dart tools/composer/composer.dart verify` **fails** in a partial checkout, and should: it implies `--strict`, so a module declared in a manifest but absent from disk is an error (*"N declared package(s) missing from disk"*, exit 1). That is the check CI Gate 0 runs, on a runner with every submodule. The app's DI smoke test fails the same way, by design — it holds the graph to the manifest's `capabilities:` (RULE-81), and a capability declared `provided` has no implementer. Locally, `flutter analyze` is the check that means something.

Other teams' code is not merely unbuilt — it is **not on the disk**, and `modules/home` is an empty directory rather than source: `.gitmodules` records only its path and URL, and the pinned commit is a gitlink entry in the superproject's tree.

## 3. Restore the composition before you commit

`composer sync` — and `bootstrap` before it — edits files that are **committed**:

- the root `pubspec.yaml` `workspace:` list
- `apps/<id>/pubspec.yaml` path dependencies, for each app it syncs
- `apps/<id>/lib/di/injection.dart`, likewise
- the `report` region of `apps/<id>/README.md` — it lists what the app composes — and, when a derived default moves, the `facts` region of `apps/<id>/lib/app/app_profile.dart`

Without `--app` that is every app — up to nine files with `mobile` and `admin`.

In a partial checkout it writes a partial composition into them. That is correct locally and wrong to commit: it would drop the other modules from the app for everyone.

`sync` says so, names the files it just rewrote, and prints the restore command. After `bootstrap` has already pruned the root `pubspec.yaml` and the two app pubspecs, an auth-only checkout prints:

```
⚠️ PARTIAL COMPOSITION — 8 declared package(s) are not on disk.
  What was just written composes only what is present, which is exactly right
  for working on one module. It is wrong to commit: it would drop the other
  modules from the app for everyone.

  Files changed:
    apps/admin/lib/di/injection.dart
    apps/admin/README.md
    apps/mobile/lib/di/injection.dart
    apps/mobile/README.md

  Restore them before you commit:
    git checkout -- apps/admin/lib/di/injection.dart apps/admin/README.md apps/mobile/lib/di/injection.dart apps/mobile/README.md
```

`sync` names only what *it* changed; `bootstrap` printed its own restore line for the pubspecs, and `git status` shows every one of them. Before you commit, restore each:

```bash
git checkout -- pubspec.yaml apps/mobile/pubspec.yaml apps/admin/pubspec.yaml \
  apps/mobile/lib/di/injection.dart apps/admin/lib/di/injection.dart \
  apps/mobile/README.md apps/admin/README.md \
  apps/mobile/lib/app/app_profile.dart apps/admin/lib/app/app_profile.dart
```

`pubspec.lock` is not among them: it is generated and git-ignored, so pruning a member leaves nothing of it to commit.

And if it is committed anyway, **CI Gate 0 fails**. `composer verify` regenerates from the manifest on a runner where every submodule *is* checked out, and diffs against the committed files. A composition missing modules cannot match, so the mistake stops at the pull request rather than in a release.

That is the safety net worth understanding: the local state is allowed to be partial, the committed state is not, and a machine — not a reviewer — holds the difference.

## 4. Create a module API package

`core_di` holds only contracts the platform itself needs, named for what it needs — a session (`ISessionState`), a location (`ISignInLocation`, `IPostSignInLocation`). A contract that exists so *one feature can reach another module* belongs to that module: its API package, `modules/<id>/api`, named `<id>_api`. The samples ship two — `auth_api` (`AuthNavigator`, `IAuthActionHandler`) and `home_api` (`HomeNavigator`).

The module generator builds one (type 6):

```bash
# payment_api at modules/payment/api: a PaymentNavigator stub, no DI module.
# Adds `layers: [api, …]` to every app_manifest.yaml (or only --apps ids), runs
# composer sync, pub get and the barrel generator. If feature_payment exists
# with its route, it also gets payment_api in its dependencies: and a
# PaymentNavigatorImpl in routing/.
dart tools/module_generator/generate.dart 6 payment
```

Add `payment_api` to each consumer's `dependencies:`, and implement further contracts (an action handler, a builder) in the owning feature, with `payment_api` in its `dependencies:`. Consumers resolve every one with `getItOrNull`. A new file in the API package reaches consumers only through the package barrel — regenerate it with `dart tools/barrel_generator/generate.dart modules/payment/api/lib` (RULE-75).

What `arch_check` holds you to:

- **R3** — the API package depends on `platform/foundation/*` and Flutter/pub packages only: not its own module's domain/data/feature, not another module or its API, not another platform group. A feature may import another module's API, never its feature, data or domain package; a data package imports no other module's API.
- **R8** — a type declared in an API package and implemented only under `modules/` is resolved with `getItOrNull` outside its module.
- **R1 / R10** — no platform package and no app file (bar `injection.dart`) imports it.

The `api` layer needs no `di_groups` entry: `composer` makes it a workspace member, never an app dependency or an `injection.dart` line. In a partial checkout (§2) a module you import an API from must be checked out too — its API package lives inside it. `remove_sample <id>` keeps an API package that another package still imports, reports who, and leaves the manifest entry as `{ id: <id>, layers: [api] }`; run it again once nothing imports the package.

---

## Verify

```bash
# In a partial checkout
flutter analyze                             # No issues found! — the check that means something locally
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev   # boots without the absent modules
git status                                  # before committing: no composition file listed

# On a full checkout (what CI runs)
dart tools/composer/composer.dart verify    # ✅ Generated artifacts are up to date.
dart tools/arch_check/check.dart            # R1, R3, R8, R10 hold
```

`composer verify` **fails** in a partial checkout by design (*"N declared package(s) missing from disk"*, exit 1). Run it on a full checkout, or leave it to CI Gate 0.

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `flutter pub get`: *No workspace packages matching `modules/home/api`* | The committed composition names a module that is not on disk | `dart tools/composer/bootstrap.dart`, then `pub get` and `composer sync` (§2) |
| `bootstrap` exits 1 and writes nothing | A present module has a hand-written path dependency on an absent one | Initialise that submodule too (§2) |
| `pub get` still fails after `sync` | `sync` ran with `--app mobile`, leaving `apps/admin/pubspec.yaml` pointing at missing modules | Run `sync` for every app (§2) |
| CI Gate 0 fails on your PR | A partial composition was committed | Restore the composition files and push again (§3) |
| `composer verify` fails locally | You are in a partial checkout | Expected; run it on a full checkout (*Verify*) |
| A consumer cannot see a type from `<id>_api` | The API package's barrel does not export it, or the module is not checked out | Run the barrel generator; initialise the module (§4) |

## Related

- Rules: RULE-04 (reach a module only through its `<id>_api`), RULE-05 (every module is removable), RULE-12 (optional lookups), RULE-16 (composition via manifests) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/01_overview.md` § 6](../architecture/01_overview.md#6-module-isolation--why-it-works-and-its-limits) — why isolation works, and its limits
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — `composer` and `bootstrap`
