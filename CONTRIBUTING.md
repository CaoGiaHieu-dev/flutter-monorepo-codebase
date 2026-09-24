# Contributing

Thanks for helping improve this template. This page is the short version of what a pull request
needs; the full rules are in [`docs/en/reference/01_rules.md`](docs/en/reference/01_rules.md) and
the review checklist in [`docs/en/reference/04_review_checklist.md`](docs/en/reference/04_review_checklist.md).

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go
through [SECURITY.md](SECURITY.md), never a public issue.

## 1. Set up

Follow [`docs/en/getting-started/01_setup.md`](docs/en/getting-started/01_setup.md) (Vietnamese:
[`docs/vi/getting-started/01_setup.md`](docs/vi/getting-started/01_setup.md)). In short:

```bash
dart tools/workspace_setup/configure.dart   # pub get → gen-l10n → build_runner → barrels
```

`flutter pub get` + `build_runner` alone is not enough — the gitignored `lib/src/gen/gen.dart`
barrels only exist after the barrel pass. Building the app also needs the gitignored Firebase
files (setup guide § 3 has compile-only stubs). FVM is optional: write commands bare and add
`fvm ` yourself if you use it.

## 2. Branches and commits

- Branch from `main`; name the branch `<type>/<short-topic>` (e.g. `fix/refresh-deadlock`).
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/), as the history does:
  `<type>(<scope>): <summary>` — lowercase, imperative or descriptive, no trailing period.
  - Types in use: `feat`, `fix`, `refactor`, `docs`, `chore`, `build`, `ci`, `style`.
  - Scope is the package or area touched: `network`, `app_shell`, `base_ui`, `tools`, `composer`,
    `module_generator`, `fastlane`, `ci`, `docs_check`, … Omit it for cross-cutting changes.
  - The body says **why**, and lists each distinct change as a bullet when there are several.
- Keep a PR to one concern. Fill in the [PR template](.github/pull_request_template.md).
- User-visible changes get a line under `Unreleased` in [CHANGELOG.md](CHANGELOG.md).

## 3. Checks to run before opening a PR

These mirror [`.github/workflows/pr_quality_check.yml`](.github/workflows/pr_quality_check.yml)
in its order. Run them from the repository root after `configure.dart`:

```bash
flutter pub get --enforce-lockfile                   # CI fails if pubspec.lock is stale
dart tools/composer/composer.dart verify             # Gate 0 — composition matches app_manifest.yaml
dart tools/arch_check/check.dart                     # Gate 1 — layering rules R1–R10
flutter analyze                                      # Gate 2 — static analysis
# Gate 3 — flutter test in every package that has a test/ directory
for p in $(find . -name pubspec.yaml -not -path './.git/*' -not -path '*/build/*' \
             -not -path '*/.dart_tool/*' | sort); do
  d=$(dirname "$p"); [ -d "$d/test" ] || continue
  (cd "$d" && flutter test) || echo "FAILED: $d"
done
dart tools/dependency_sync.dart --check              # Gate 4 — version catalog in sync
dart tools/docs_check/check.dart                     # Gate 5 — every repo path the docs name exists
dart tools/unused_checker/check_unused_packages.dart # advisory — declared but never imported

# The separate `build` job — the only proof generated code compiles
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

A clean `flutter analyze` does not mean the app builds: `analysis_options.yaml` excludes every
generated file. The debug APK build is what catches a broken `.freezed.dart` or
`injection.config.dart`.

## 4. House rules that trip people up

- **Composer-managed regions are generated.** The root `workspace:` list, each app's
  `composer:managed:deps` block in `pubspec.yaml` and `lib/di/injection.dart` are written by
  `dart tools/composer/composer.dart sync` from `apps/<id>/app_manifest.yaml`. Edit the manifest,
  never the region — Gate 0 fails on drift. `tools/module_generator/generate.dart` does this for you.
- **Dependency versions live in the catalog.** Change [`pubspec_dependencies.yaml`](pubspec_dependencies.yaml),
  then run `dart tools/dependency_sync.dart`; never hand-edit a version in a member pubspec. The
  workspace `pubspec.lock` is committed — commit its changes with the PR that caused them.
- **Generated files.**
  - Not committed (gitignored per package): `*.g.dart`, `*.freezed.dart`, `*.config.dart`,
    `*.module.dart`, `lib/src/gen/**`. Regenerate with `dart run build_runner build --workspace`
    (no `-d` flag) and `flutter gen-l10n`; never hand-edit them.
  - Committed: barrel files. Re-run `dart tools/barrel_generator/generate.dart <package>/lib`
    after adding, renaming or deleting a file — **after** codegen — and commit the result. The
    generator deletes hand-written `export` lines; put deliberate re-exports in a normal source file.
- **The analyzer is strict.** `strict-casts`, `strict-inference` and `strict-raw-types` are on,
  with `unawaited_futures`, `cancel_subscriptions`, `close_sinks`, `avoid_dynamic_calls` and
  `empty_catches`; `flutter analyze` must report 0 issues, and `// ignore:` is not a fix. What
  each asks of your code: [`docs/en/reference/01_rules.md` § 16](docs/en/reference/01_rules.md).
- **Docs stay in parity.** Every page under `docs/en/` has a twin under `docs/vi/`, and
  `README.md` / `README.vi.md`, `tools/README*.md` and the package `README.vi.md` files likewise.
  Change both in the same PR. If you change a rule, update `docs/*/reference/01_rules.md`,
  [`.agents/AGENTS.md`](.agents/AGENTS.md) and [`CLAUDE.md`](CLAUDE.md) together.
- **Tools** in `tools/` print with `stdout.writeln` / `stderr.writeln`, never `print()`; no
  PowerShell scripts; no lint suppressions.
- **Sample modules** (auth, home, settings, …) are reference code. Fix them when they teach the
  wrong pattern; do not grow them into product features.

## 5. Reporting bugs and proposing features

Use the [issue forms](.github/ISSUE_TEMPLATE). Questions about how to do something are usually
answered in the [docs hub](docs/en/README.md) — please check there first.

## License

Contributions are accepted under the repository's [BSD 3-Clause License](LICENSE).
