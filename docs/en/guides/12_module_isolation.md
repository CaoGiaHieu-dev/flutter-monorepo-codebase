# Module Isolation with Git Submodules

**This file answers:** how does a team check out only its own module, build the whole app from it, and never see another team's source?

**After reading you can:** split a module into its own repository, work in a partial checkout, and know exactly which mistake CI is protecting you from.

---

## 1. What makes this possible

Nothing in this repository encodes where a package lives.

`composer` resolves packages **by name**, discovered by scanning for `pubspec.yaml`. `arch_check` derives a package's layer from its name. `MonorepoHelper` walks the tree. So a module that is absent is simply not found — no tool has a list to fall out of date.

That is the whole mechanism. `composer sync` writes a composition from *what is on disk*, and a build composed of five modules is as valid as one composed of six.

The directory layout does the rest: `modules/<name>/` holds every layer of one bounded context, so a submodule boundary and an ownership boundary are the same line. (See [the ownership table](../architecture/01_overview.md#4-who-owns-what).)

---

## 2. Extracting a module into its own repository

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

Nothing else changes. `app_manifest.yaml` still says `- { id: auth, layers: [domain, data, feature] }`, because a manifest names modules, not directories.

> [!IMPORTANT]
> Do this **after** the module is stable. Moving a file between two modules stops being a rename and becomes a delete-plus-add across two repositories, with the review split in half.

---

## 3. Working in a partial checkout

A developer on the auth team clones the monorepo without other teams' sources:

```bash
git clone <monorepo-url> && cd <monorepo>
git submodule update --init modules/auth      # only theirs
dart tools/composer/composer.dart sync              # compose what is present (every app)
dart tools/workspace_setup/configure.dart     # pub get + l10n + codegen + barrels
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev
```

Run `sync` for **every app** — do not narrow it with `--app mobile`. The root `workspace:` list is always rebuilt from all apps and drops what is not on disk, but `--app mobile` leaves `apps/admin/pubspec.yaml` untouched, still declaring path dependencies on the missing modules (`settings`, say) — and `flutter pub get` then fails to resolve the workspace.

The app runs. It has no home screen, no settings, no dashboard — and it boots, because every shell lookup for a module-owned contract is `getItOrNull` or `getAllOrEmpty` (`arch_check` R8), and no shell file imports a module (`arch_check` R10 in the app, R1 in `platform_app_shell`).

Other teams' code is not merely unbuilt — it is **not on the disk**, and `modules/home` is an empty directory rather than source: `.gitmodules` records only its path and URL, and the pinned commit is a gitlink entry in the superproject's tree.

---

## 4. The one hazard, and what catches it

`composer sync` edits files that are **committed**:

- the root `pubspec.yaml` `workspace:` list
- `apps/<id>/pubspec.yaml` path dependencies, for each app it syncs
- `apps/<id>/lib/di/injection.dart`, likewise

Without `--app` that is every app — five files with `mobile` and `admin`.

In a partial checkout it writes a partial composition into them. That is correct locally and wrong to commit: it would drop the other modules from the app for everyone.

`sync` says so, names the files, and prints the restore command:

```
⚠️ PARTIAL COMPOSITION — 7 declared package(s) are not on disk.
  What was just written composes only what is present, which is exactly right
  for working on one module. It is wrong to commit: it would drop the other
  modules from the app for everyone.

  Files changed:
    apps/mobile/pubspec.yaml
    apps/mobile/lib/di/injection.dart
    apps/admin/pubspec.yaml
    apps/admin/lib/di/injection.dart
    pubspec.yaml

  Restore them before you commit:
    git checkout -- apps/mobile/pubspec.yaml apps/mobile/lib/di/injection.dart apps/admin/pubspec.yaml apps/admin/lib/di/injection.dart pubspec.yaml
```

And if it is committed anyway, **CI Gate 0 fails**. `composer verify` regenerates from the manifest on a runner where every submodule *is* checked out, and diffs against the committed files. A composition missing modules cannot match, so the mistake stops at the pull request rather than in a release.

That is the safety net worth understanding: the local state is allowed to be partial, the committed state is not, and a machine — not a reviewer — holds the difference.

---

## 5. Why not a private pub registry

A private registry (`dart pub publish` to a self-hosted server) is the other way to hide one team's source from another, and it is the right answer for a package with **many consumers and a slow release cadence** — a design system, an analytics SDK.

It is the wrong answer here:

| | Submodule | Private registry |
|:--|:--|:--|
| Cross-module change | one PR per repository, ordinary review | publish, wait, bump, publish again |
| Local iteration | edit the source you already have | `dependency_overrides` in every consumer |
| Version skew | a commit hash, resolved | two apps on two versions of the same module |
| Setup cost | one `git submodule add` | a server, auth, CI credentials |

Product modules change together and ship together. Submodules keep that cheap.

---

## 6. What isolation does *not* buy you

- **Not a security boundary.** Submodule access is repository permissions. Someone with a checkout has the source; this stops accidental coupling and casual reading, not a determined reader.
- **Not freedom from contracts.** A module still talks to others only through `core_di`. What changes is that breaking a contract is now visible as a cross-repository PR rather than a silent edit.
- **Not optional discipline.** Every guardrail that made partial checkouts possible — R8's optional lookups, R10's import ban, resolution by name — stops working the moment somebody adds a direct import. Which is why each one fails the build rather than a review.

---

## Related

- [Architecture overview — who owns what](../architecture/01_overview.md)
- [Tooling reference — `composer`](../reference/03_tooling.md)
- [Rules — feature removability](../reference/01_rules.md)
