# Documentation

🌍 *Language:* **English** | [Tiếng Việt](../vi/README.md)

Everything you need to work in this Flutter monorepo, organised by **what you are trying to do** rather than by which package a topic happens to live in. Every code sample in these pages is quoted from real source with its file path, so you can always open the original.

---

## Where do I start?

| If you… | Go to |
|---|---|
| 🚀 **Just cloned the repo** and want it running | [`getting-started/`](getting-started/01_setup.md) |
| 🧭 **Want to understand the system** — layers, boundaries, why | [`architecture/`](architecture/01_overview.md) |
| 🔨 **Want to build something** — a screen, an API, a table | [`guides/`](guides/01_new_feature.md) |
| 📖 **Need a quick answer** — naming, a rule, a command | [`reference/`](reference/01_rules.md) |
| 🚢 **Need to build, sign or ship** | [`operations/`](operations/01_cicd.md) |

New to the project? Read in this order: **`getting-started/01` → `04` (the tutorial: your first feature, end to end) → `02` → `architecture/01` → the guide for whatever you are building.**

---

## 🚀 Getting started

Zero to a running app, and the daily rhythm afterwards.

| Page | Answers |
|---|---|
| [`01_setup.md`](getting-started/01_setup.md) | What do I need installed, and what exact commands take me from `git clone` to a running app? |
| [`02_project_tour.md`](getting-started/02_project_tour.md) | What is every folder for, which package owns what, and where do I go to change a given thing? |
| [`03_daily_workflow.md`](getting-started/03_daily_workflow.md) | Which command do I run, and when? What breaks if I skip it? |
| [`04_first_feature_tutorial.md`](getting-started/04_first_feature_tutorial.md) | How do I build, test and remove a small module end to end — in 30 minutes, every command verified? |

---

## 🧭 Architecture

How the system is laid out and why. Read these to place a new file correctly, or to settle whether an `import` is legal.

| Page | Answers |
|---|---|
| [`01_overview.md`](architecture/01_overview.md) | How is this monorepo laid out, and which package may depend on which? |
| [`02_core.md`](architecture/02_core.md) | What is inside `platform/*`, and which package should I reach for? |
| [`03_domain.md`](architecture/03_domain.md) | What business rules live in `modules/*/domain`, why is that code forbidden from touching Flutter, and what does `Result<T>` give you? |
| [`04_data.md`](architecture/04_data.md) | How does `modules/*/data` fulfil the repository contracts Domain declares — and which boundaries must it not leak across? |
| [`05_features.md`](architecture/05_features.md) | How is a screen-owning package organised, and how do features stay isolated while still composing into one app? |
| [`06_app_shell.md`](architecture/06_app_shell.md) | What happens between tapping the icon and seeing the first screen, and who wires everything together? |

---

## 🔨 Guides

Practical, step-by-step, with working code. This is the "how to use" section. Every guide has the same shape: **Goal → Prerequisites → numbered steps → Verify → Troubleshooting → Related**. The *why* behind each lives in `architecture/`.

| Page | Answers |
|---|---|
| [`01_new_feature.md`](guides/01_new_feature.md) | How do I add a new screen area to the app, end to end? |
| [`02_new_domain_data.md`](guides/02_new_domain_data.md) | How do I add a new business capability — entities, use cases, repository, data sources? |
| [`03_state_management.md`](guides/03_state_management.md) | Which state-management branch should I use for a screen, and how do I write a controller in it? |
| [`04_routing.md`](guides/04_routing.md) | How do I add a screen, and how do I navigate to one owned by another feature? |
| [`05_di.md`](guides/05_di.md) | Which annotation do I use, where does my module get registered, and why does the app throw "not registered" at startup? |
| [`06_storage.md`](guides/06_storage.md) | How do I persist a value so it survives restarts — without letting another package read or overwrite it? |
| [`07_database.md`](guides/07_database.md) | How do I store relational data so that deleting my package deletes its database with it? |
| [`08_networking.md`](guides/08_networking.md) | How do I call a new endpoint, opt a request out of auth or retry, plug in token refresh and turn on SSL pinning? |
| [`09_localization_theming.md`](guides/09_localization_theming.md) | How does a feature ship its own translations, and how do colours, fonts and dimensions stay consistent? |
| [`10_cross_feature.md`](guides/10_cross_feature.md) | Feature A needs something from feature B — how, without importing it? |
| [`11_design_system.md`](guides/11_design_system.md) | Where is every colour, font, spacing step and radius defined — which file do I edit to rebrand the app, and how does the UI scale and adapt on tablets, foldables and split screen? |
| [`12_module_isolation.md`](guides/12_module_isolation.md) | How does a team check out only its own module, build the whole app from it, and never see another team's source? |

---

## 📖 Reference

Short, dense, built for Ctrl+F.

| Page | Answers |
|---|---|
| [`01_rules.md`](reference/01_rules.md) | The rule registry — every rule once, as `RULE-NN`, with why, what enforces it and how to verify. |
| [`02_naming.md`](reference/02_naming.md) | What do I call this file, this class, this folder? |
| [`03_tooling.md`](reference/03_tooling.md) | Which script do I run, with what arguments, and when? |
| [`04_review_checklist.md`](reference/04_review_checklist.md) | What must hold before this PR merges? |

---

## 🚢 Operations

Building, signing and shipping.

| Page | Answers |
|---|---|
| [`01_cicd.md`](operations/01_cicd.md) | What pipelines exist, what secrets do they need, and what is currently broken in them? |
| [`02_fastlane_release.md`](operations/02_fastlane_release.md) | Which Fastlane lanes exist, how is the app signed, and what is the full release procedure? |

---

## I want to… → read this

| Task | Start here | Then |
|---|---|---|
| Add a new screen | [`guides/01_new_feature.md`](guides/01_new_feature.md) | [`guides/04_routing.md`](guides/04_routing.md) |
| Call a new API endpoint | [`guides/02_new_domain_data.md`](guides/02_new_domain_data.md) | [`guides/08_networking.md`](guides/08_networking.md) |
| Add a database table | [`guides/07_database.md`](guides/07_database.md) | [`architecture/04_data.md`](architecture/04_data.md) |
| Store a token or a flag | [`guides/06_storage.md`](guides/06_storage.md) | [`guides/05_di.md`](guides/05_di.md) |
| Add a translated string | [`guides/09_localization_theming.md`](guides/09_localization_theming.md) | — |
| Add a locale | [`guides/09_localization_theming.md`](guides/09_localization_theming.md) § 2 | — |
| Change theme, colours or spacing | [`guides/11_design_system.md`](guides/11_design_system.md) | [`architecture/02_core.md`](architecture/02_core.md) |
| Lay out a screen for tablets, foldables or split screen | [`guides/11_design_system.md`](guides/11_design_system.md) § 7 | [`architecture/05_features.md`](architecture/05_features.md) § dashboard |
| Share state between two features | [`guides/10_cross_feature.md`](guides/10_cross_feature.md) | [`guides/05_di.md`](guides/05_di.md) |
| Remove a feature from the app | [`guides/01_new_feature.md`](guides/01_new_feature.md) § removal | [`reference/01_rules.md`](reference/01_rules.md) |
| Choose Provider or BLoC | [`guides/03_state_management.md`](guides/03_state_management.md) | — |
| Fix "not registered" at startup | [`guides/05_di.md`](guides/05_di.md) | [`architecture/06_app_shell.md`](architecture/06_app_shell.md) |
| Fix a red CI run | [`operations/01_cicd.md`](operations/01_cicd.md) | [`reference/03_tooling.md`](reference/03_tooling.md) |
| Ship a release build | [`operations/02_fastlane_release.md`](operations/02_fastlane_release.md) | [`operations/01_cicd.md`](operations/01_cicd.md) |
| Review someone's PR | [`reference/04_review_checklist.md`](reference/04_review_checklist.md) | [`reference/01_rules.md`](reference/01_rules.md) |
| Know if an `import` is legal | [`reference/01_rules.md`](reference/01_rules.md) | [`architecture/01_overview.md`](architecture/01_overview.md) |

---

## Documentation contract

The full contract is in [`CONTRIBUTING.md` § 5](../../CONTRIBUTING.md#5-documentation-contract). In short:

1. **Source of truth, most authoritative first:** the code → the rule registry ([`reference/01_rules.md`](reference/01_rules.md)) → `docs/en/**` → `CLAUDE.md` / `.agents/AGENTS.md` / skills → `README.md` → `docs/vi/**`. When two disagree, fix the lower one.
2. **A rule is stated once**, in the registry. Everywhere else cites its `RULE-NN` and links there; `docs_check` fails on an id the registry does not define.
3. **`docs/vi` mirrors `docs/en`** — same files, headings, code blocks and table rows, in the same PR. After syncing a translation, stamp it: `dart tools/docs_check/check.dart --stamp-translations docs/vi/<file>.md`.
4. **Never document an intention.** Code samples are copied from real files; commands run against the tree in that commit; limitations are stated plainly.

History that is no longer current guidance lives in [`../history/`](../history/restructure-log.md), English only.

---

## Conventions in these pages

- **Every link is relative.** They work on GitHub, in an IDE preview, and on a local docs server alike.
- **Every code block names its source file** in a leading comment — open it to see the current version.
- Callouts carry weight: `> [!NOTE]` is context, `> [!WARNING]` is something that will bite you, `> [!CAUTION]` is something that can lose data or ship a broken build.
- Where a rule has an approved exception, the exception is written down with its reasoning — so a later audit does not "fix" it by mistake.

> [!NOTE]
> The feature, domain and data packages shipped here (auth, cache, home, settings, onboarding, splash, dashboard) are **reference sample code**. They demonstrate the wiring; they are patterns to copy or delete, not production logic. AI agents start from [`../../CLAUDE.md`](../../CLAUDE.md) or [`../../.agents/AGENTS.md`](../../.agents/AGENTS.md), which cite the registry rather than restate it.
