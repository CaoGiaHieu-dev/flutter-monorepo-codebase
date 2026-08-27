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
   dart tools/code_review/code_review.dart --folder packages/features/home/lib
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
`--exclude <glob>` (repeatable), `--verbose`, `--output-dir <dir>`.

Requires a Gemini API key — either `--api-key` or the `GEMINI_API_KEY` environment variable
(`tools/code_review/code_review_config.json` ships empty on purpose).

Use the `run_command` tool to run the commands above. After execution, analyze the summary output printed to the terminal and advise the user on how to resolve any architectural violations.

## Key rules to check while reviewing

**Presentation**
- UI Controllers (ViewModel, Bloc, Cubit) must be `@injectable`, never singletons.
- Instantiation happens at the **route** via `ChangeNotifierProvider` / `BlocProvider`; the
  `Page` must not wrap itself a second time.
- All sizing goes through `flutter_screenutil` (`.w` / `.h` / `.sp` / `.r`); reusable widgets
  in `core_ui_kit` take **unscaled** values and never scale internally.

**Layering**
- `core/*` must not depend on `feature_*` or `data_*`. Approved exceptions only:
  `core_di → domain_auth`, `provider_state_management → domain_core`,
  `core_common → domain_core`.
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
