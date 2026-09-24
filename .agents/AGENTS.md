# AGENTS.md

Entry point for AI coding agents (Codex, Gemini, Copilot, Cursor, …) working in this repository.
It is deliberately short: it points at the files that hold the substance.

## The repository

A Flutter **Pub Workspaces monorepo template** — Clean Architecture + SOLID + MVVM, Provider and
BLoC, GetIt/injectable DI, go_router. Three territories: `apps/<id>/` (composition roots generated
from `app_manifest.yaml`), `modules/<id>/{api,domain,data,feature}` (one vertical slice per bounded
context — the shipped ones are sample code) and `platform/<group>/<package>` (infrastructure, six
groups). `tools/` holds the CI gates and generators.

## Where things are

| You need | Read |
|:--|:--|
| **The rules** — every one, once, with why, what enforces it and how to verify | [`docs/en/reference/01_rules.md`](../docs/en/reference/01_rules.md) (registry, ids `RULE-NN`; Vietnamese: [`docs/vi/reference/01_rules.md`](../docs/vi/reference/01_rules.md)) |
| The agent brief — layout, essential commands, workflows | [`CLAUDE.md`](../CLAUDE.md) |
| Architecture and how-to guides | [`docs/en/README.md`](../docs/en/README.md) |
| Every tool in `tools/` | [`docs/en/reference/03_tooling.md`](../docs/en/reference/03_tooling.md) |
| Task recipes (skills) | [`.claude/skills/`](../.claude/skills/) — each `SKILL.md` is plain Markdown any agent can follow |
| Documentation contract, commits, PR checks | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |

## Top rules

Cite these by id; the registry has the full text and the reason.

- **RULE-30** — size through `context.w/h/sp/r`; no raw doubles, no `16.w` (arch_check R7).
- **RULE-05** — only `apps/<id>/lib/di/injection.dart` imports a module; the shell imports none (arch_check R10, R1).
- **RULE-12** — module-owned contracts resolve with `getItOrNull` / `getAllOrEmpty` (arch_check R8).
- **RULE-01 / RULE-04 / RULE-03** — platform never depends on modules; features never import features or data; domain is pure Dart (arch_check R1, R3, R2).
- **RULE-13** — no eager `@Singleton` on a later-registered type (`apps/*/test/di_smoke_test.dart`).
- **RULE-10 / RULE-21** — screen controllers are `@injectable`, created at the route, never double-wrapped.
- **RULE-51 / RULE-52** — private Freezed BLoC events; `async (event, emit)` handlers.
- **RULE-34 / RULE-35** — every string translated; ARB keys `lowerCamelCase`.
- **RULE-36** — dialogs and bottom sheets are their own widget classes.
- **RULE-16 / RULE-75 / RULE-76** — never hand-edit `composer:managed` regions, barrel exports or generated files.
- **RULE-71 / RULE-72 / RULE-40 / RULE-78** — no lint suppressions, no `.ps1`, `data_sources/`, `I` prefix for interfaces only (arch_check R13, R12, R14, R15).
- **RULE-77** — a clean `flutter analyze` is not a build; finish with a debug APK build.
- **RULE-79** — docs change with the code, in `docs/en` and `docs/vi`; cite rules by id, never restate them.

## Before you finish

```bash
dart tools/composer/composer.dart verify
dart tools/arch_check/check.dart
flutter analyze
dart tools/docs_check/check.dart
```

Plus `flutter test` in every package you touched that has a `test/` directory.
