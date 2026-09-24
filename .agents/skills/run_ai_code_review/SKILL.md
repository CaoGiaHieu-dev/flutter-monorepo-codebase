---
name: run_ai_code_review
description: Guide for running the AI Code Review tool (Gemini) to automatically audit codebase architecture against Clean Architecture standards.
---

# 🤖 Run AI Code Review

The codebase contains an AI-powered Code Review tool that automatically audits the quality and architecture of your changes.

## Execution Instructions

When a task involves "review code", "audit codebase", "verify architecture", etc., the Agent should execute the CLI script:

1. To review all uncommitted changes (staged/unstaged - recommended):
   ```bash
   dart tools/code_review/code_review.dart --changed
   ```

2. To review specific **files** (repeatable):
   ```bash
   dart tools/code_review/code_review.dart --file <path> --file <path>
   ```

3. To review a **folder** (use `--folder`, not `--file`):
   ```bash
   dart tools/code_review/code_review.dart --folder modules/home/feature/lib
   ```

4. To review only what is staged for commit:
   ```bash
   dart tools/code_review/code_review.dart --staged
   ```

5. To review the entire codebase (Warning: Takes a long time):
   ```bash
   dart tools/code_review/code_review.dart --all
   ```

Useful extras: `--focus <area>` (repeatable, restricted to the tool's allowed focus areas),
`--exclude <glob>` (repeatable), `--verbose`, `--output-dir <dir>`, `--language <code>`.

- Generated files (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`,
  `*.mocks.dart`, `lib/src/gen/**`, `firebase_options_*.dart`), tests and git-ignored files are
  **always** excluded; `--exclude` only adds to that.
- `--language` applies to that run only and is not written to `code_review_config.json`
  (change the default with `--config`). The report is always Markdown — `--format` accepts only
  `markdown`.

Requires a Gemini API key — `--api-key`, the `GEMINI_API_KEY` environment variable, or the
gitignored `tools/code_review/.gemini_api_key` the tool writes when the user agrees to save one.
Never put a key in the tracked `code_review_config.json`. With no key and no terminal to ask on
(an agent's shell, CI), the tool prints where to set one on stderr and exits `1` — set
`GEMINI_API_KEY` rather than expecting a prompt.

Run the commands above in the shell, from the repository root. After execution, analyze the summary output printed to the terminal and advise the user on how to resolve any architectural violations.

## Key rules to check while reviewing

**Presentation**
- UI Controllers (ViewModel, Bloc, Cubit) must be `@injectable`, never singletons.
- Instantiation happens at the **route** via `ChangeNotifierProvider` / `BlocProvider`; the
  `Page` must not wrap itself a second time.
- All sizing goes through `BuildContext`: `context.w(x)` / `context.h(x)` / `context.sp(x)` /
  `context.r(x)`. The bare receiver form (`16.h`) is forbidden — it returns the same number but
  skips the InheritedWidget dependency, so it never rebuilds on rotation or resize.
  `arch_check` rule R7 blocks it, so flag it as a hard error, not a nit.
- Design tokens take context: `AppSpacing.lg(context)`, `AppRadius.md(context)`,
  `AppTextStyles.bodyMediumStyle(context)`. Never double-scale an already-scaled token.
- Reusable widgets in `core_ui_kit` use parameters **as received** — the caller scaled them — and scale
  only their own constants. `context.w(widget.width)` is a double-scale bug; `context.h(10)` as that
  widget's own default is correct.

**Layering**
- `platform/*` must not depend on `feature_*`, `data_*` or product `domain_*` packages. Approved exceptions only:
  `platform_kernel → domain_core`, `provider_state_management → domain_core`,
  `bloc_state_management → domain_core`. Three, and nothing else.
- Domain stays pure — no `flutter` / `dio` / `retrofit` / `drift` import *and* no such entry
  in its pubspec.
- Feature A never imports Feature B (only `core_ui_kit`).
- DataSources return Models, not Entities, and never expose Drift/Retrofit generated types.

**Conventions**
- Every package keeps its constants in `lib/src/utils/` (exception: design tokens in
  `core_base_ui/src/styles/`).
- Errors are converted with `ErrorHandler.handleError(e)`; nothing throws out of the Data layer.
- Cross-feature access goes through a `core_di` contract resolved with `getItOrNull` /
  `getAllOrEmpty` + fallback, so any feature can be deleted without breaking the app.
- Dependencies are declared explicitly in `pubspec.yaml` — Pub Workspaces hide missing ones.

See `docs/{en,vi}/reference/04_review_checklist.md` for the full checklist.
