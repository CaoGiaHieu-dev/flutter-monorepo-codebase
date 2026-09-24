## Summary

<!-- What does this change and why? Link the issue it closes: "Closes #123". -->

## Type of change

- [ ] `fix` — bug fix
- [ ] `feat` — new capability
- [ ] `refactor` — no behaviour change
- [ ] `docs` — documentation only
- [ ] `chore` / `build` / `ci` — tooling, dependencies, pipelines
- [ ] **Breaking** — projects built on the template must change code or layout (MAJOR bump)

## Checklist

Full list: [`docs/en/reference/04_review_checklist.md`](../docs/en/reference/04_review_checklist.md).
Tick what applies; delete lines that do not.

**Gates** — the commands are in [CONTRIBUTING.md § 3](../CONTRIBUTING.md#3-checks-to-run-before-opening-a-pr).

- [ ] The `pr_quality_check.yml` gates pass locally: composer verify, `arch_check`, `flutter analyze`, tests in every package with a `test/`, `dependency_sync --check`, `docs_check`
- [ ] `flutter build apk --flavor dev --debug` passes (analyze does not cover generated code)

**Architecture**

- [ ] Domain stays pure Dart — no Flutter, Dio, Retrofit or `core_*` imports; zero `core_*` deps
- [ ] No feature depends on a data package or another feature; no `platform/*` depends on `feature_*` / `data_*` / `domain_*` beyond the approved `domain_core` edges
- [ ] Feature controllers are `@injectable` (never singleton) and created at the route, not inside the page
- [ ] Routes and cross-feature calls go through `core_di` contracts — nothing hardcoded in `app_router.dart`
- [ ] The feature is still removable: optional lookups use `getItOrNull` / `getAllOrEmpty`
- [ ] All sizing goes through `context.w/h/sp/r`; layouts pick by window size class, not by device
- [ ] All user-facing strings are translated (feature ARBs, `lowerCamelCase` keys)
- [ ] A new `StorageValue` / table is owned by its package and registered as a singleton

**Hygiene**

- [ ] Every imported package is declared in `dependencies`; versions changed only in `pubspec_dependencies.yaml`
- [ ] No hand edits to composer-managed regions, generated files or barrel exports; barrels regenerated after codegen
- [ ] Docs updated in **both** `docs/en` and `docs/vi` (and `README.md` / `README.vi.md` if touched)
- [ ] `CHANGELOG.md` has an `Unreleased` entry for a user-visible change

## Notes for reviewers

<!-- Anything non-obvious: trade-offs, follow-ups, screenshots for UI changes. -->
