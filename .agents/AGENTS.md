# AGENTS.md

Entry point for AI coding agents (Codex, Gemini, Copilot, Cursor, …) working in this repository.
It is a pointer, not a copy: it holds no rule and no command list of its own, so it cannot go stale.

## The repository

A Flutter **Pub Workspaces monorepo template** — Clean Architecture + SOLID + MVVM, Provider and
BLoC, GetIt/injectable DI, go_router. Three territories: `apps/<id>/` (composition roots: an
`app_manifest.yaml` that declares what the app is and composes, a typed profile and hooks in
`lib/app/`, generated DI), `modules/<id>/{api,domain,data,feature}` (one vertical slice per bounded
context — the shipped ones are sample code) and `platform/<group>/<package>` (infrastructure, six
groups). `tools/` holds the CI gates and generators.

## Where things are

| You need | Read |
|:--|:--|
| **The rules** — every one, once, with why, what enforces it and how to verify | [`docs/en/reference/01_rules.md`](../docs/en/reference/01_rules.md) (registry, ids `RULE-NN`; Vietnamese: [`docs/vi/reference/01_rules.md`](../docs/vi/reference/01_rules.md)) |
| The agent brief — the rules that get violated, layout, commands, workflows, the task → guide table | [`CLAUDE.md`](../CLAUDE.md) |
| Architecture and how-to guides | [`docs/en/README.md`](../docs/en/README.md) |
| Every tool in `tools/`, its arguments and exit codes | [`docs/en/reference/03_tooling.md`](../docs/en/reference/03_tooling.md) |
| Configuring an app — platforms, flavors, pins, languages, hooks, capabilities; a third app | [`docs/en/guides/13_app_composition.md`](../docs/en/guides/13_app_composition.md), skill `configure_app` |
| Task recipes (skills) | [`.claude/skills/`](../.claude/skills/) — each `SKILL.md` is plain Markdown any agent can follow |
| Documentation contract, commits, PR checks | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |

## Before you finish

Run the gates `CLAUDE.md` lists under **Commands** for what you touched, and the debug APK build after
a DI, dependency or type-location change (RULE-77). Docs change in the same PR as the code, in
`docs/en` and `docs/vi` (RULE-79).
