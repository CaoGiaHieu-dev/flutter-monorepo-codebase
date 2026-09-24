# Contributing

Thanks for helping improve this template. This page is the short version of what a pull request
needs. Every rule is stated once, with a stable `RULE-NN` id, in the registry at
[`docs/en/reference/01_rules.md`](docs/en/reference/01_rules.md); the review checklist is
[`docs/en/reference/04_review_checklist.md`](docs/en/reference/04_review_checklist.md).

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
dart tools/arch_check/check.dart                     # Gate 1 — layering and hygiene rules R1–R15
(cd tools && dart test)                              # Gate 1 — the gate tools' own tests
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

Each is a registry row — read it there; this list only says where people trip.

- **Composer-managed regions are generated** (RULE-16). Edit `apps/<id>/app_manifest.yaml`, run
  `dart tools/composer/composer.dart sync`; `tools/module_generator/generate.dart` does it for you.
- **Versions live in the catalog** (RULE-74). The workspace `pubspec.lock` is committed — commit its
  changes with the PR that caused them.
- **Generated files** (RULE-76). Not committed: `*.g.dart`, `*.freezed.dart`, `*.config.dart`,
  `*.module.dart`, `lib/src/gen/**`. Committed: barrel files, regenerated after codegen (RULE-75).
- **The analyzer is strict** (RULE-70) and `// ignore:` is not a fix (RULE-71).
- **DI changes are proven by the smoke test** (RULE-13, RULE-63), and a clean analyze is not a
  build (RULE-77).
- **Tools** print with `stdout.writeln` / `stderr.writeln` (RULE-65); no PowerShell (RULE-72).
- **Sample modules** (auth, home, settings, …) are reference code. Fix them when they teach the
  wrong pattern; do not grow them into product features.

## 5. Documentation contract

The docs are unusually complete, which means they go stale unusually fast. These rules keep them
true (RULE-79):

1. **Docs ship in the same PR as the code.** A change is not done when only the code has landed.
2. **Source of truth, most authoritative first:** the code → the rule registry
   (`docs/en/reference/01_rules.md`) → `docs/en/**` → `CLAUDE.md`, `.agents/AGENTS.md` and
   `.claude/skills/` → `README.md` → `docs/vi/**`. When two disagree, the lower one is the one to fix.
3. **State a rule once.** A rule lives in the registry, with its why, what enforces it, how to
   verify it and a link to its explanation. Everywhere else — `CLAUDE.md`, `AGENTS.md`, guides,
   skills, the review checklist, `tools/code_review/review_prompt.md` — cites `RULE-NN` and links
   there; keep the guide-specific *how*, drop the restated *what*. `docs_check` fails on an id the
   registry does not define. Ids are stable: never renumber or reuse one; retire it in place.
4. **When a rule becomes machine-checked, say so** — update its **Enforced by** column and name
   the check (`arch_check Rn`, a test file, a CI gate), so a reader knows whether CI or review holds it.
5. **`docs/vi/**` mirrors `docs/en/**` 1:1**: same filenames, headings, fenced code blocks and table
   rows, in the same PR — `README.md` / `README.vi.md`, `tools/README*.md` and package
   `README.vi.md` files likewise. `docs_check` enforces the shape; intentional differences go in
   `tools/docs_check/parity_allowlist.txt` with a reason. After syncing a translation, commit the
   English change, then stamp it:
   `dart tools/docs_check/check.dart --stamp-translations docs/vi/<file>.md`
   (`--stale-translations` lists the ones behind).
6. **Never document an intention.** Every code fence runs against the tree in that commit; code
   samples are copied from real files, not written from memory; known limitations are stated plainly.
7. **Numbers get re-measured, not copied.** Counts of packages, dependencies, rules or tests in prose
   are re-derived each time they are touched.
8. **History is not guidance.** A record of how the repo got here belongs in `docs/history/`
   (English only, outside the parity check) — see `docs/history/restructure-log.md`.

## 6. Reporting bugs and proposing features

Use the [issue forms](.github/ISSUE_TEMPLATE). Questions about how to do something are usually
answered in the [docs hub](docs/en/README.md) — please check there first.

## License

Contributions are accepted under the repository's [BSD 3-Clause License](LICENSE).
