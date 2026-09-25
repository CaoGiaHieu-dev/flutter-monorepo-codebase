🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# 🤖 AI Code Review Tool - Flutter Clean Architecture

A code review tool powered by Gemini AI (model `gemini-3-flash-preview`, set in `lib/core/constants.dart`), built specifically for Flutter projects that follow Clean Architecture. The instructions given to the AI live in `review_prompt.md`.

## ✨ Key Features

- **🎯 Focused on real problems**: The prompt asks for real issues only (architecture, logic, performance), not style nitpicks, to keep the noise down.
- **🏗️ Architecture-focused**: Checks compliance with the Clean Architecture layers, SOLID principles and the project's patterns.
- **🚀 Performance & security analysis**: Finds bottlenecks, memory leaks and security holes.
- **📊 Consolidated report**: Per-file analysis with a score table (`Project Rules`, `Architecture`, `SOLID/Code` and `Overall`, on an X/10 scale) and prioritised actions.
- **🌐 Multi-language**: Reports in 8 languages (`en`, `vi`, `ja`, `ko`, `zh`, `fr`, `de`, `es`).
- **⚡ Batch mode**: With more than one file, the tool asks for Batch (the default) or Individual. Batch reviews the files of a batch in parallel, pauses between batches, and retries files that hit the API rate limit or time out.

## 🚀 Quick Start

### 1. Get an API key
Get a free Gemini API key at: https://aistudio.google.com/app/apikey

### 2. Set up the API key
**Option 1: Environment variable (recommended)**
```bash
export GEMINI_API_KEY="your_api_key_here"
```

**Option 2: Let the tool ask**
Run the tool without a key: it asks for one and offers to save it to `tools/code_review/.gemini_api_key` — the file is gitignored, so the key never lands in a commit. (`--api-key "<key>"` also works for a single run.)

Key lookup order: `--api-key` → `GEMINI_API_KEY` → `tools/code_review/.gemini_api_key` → a prompt on the terminal.

### 3. Run a review
**Interactive mode (easiest for newcomers)** — run it without any file selection (or with `-i`):
```bash
dart tools/code_review/code_review.dart
```

**Review every file** (every `lib/` under `apps/`, `modules/`, `platform/`)
```bash
dart tools/code_review/code_review.dart --all
```

**Review files changed against the current commit** (`git diff HEAD`: staged + unstaged; untracked files are not included)
```bash
dart tools/code_review/code_review.dart --changed
```

## 📖 Detailed Usage

### Common commands

- **Review specific files** (repeat `--file` for several):
  ```bash
  dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart
  ```
- **Review a folder**:
  ```bash
  # Only the domain layer (the most important one)
  dart tools/code_review/code_review.dart --folder modules/auth/domain
  ```
- **Review the files staged for commit**:
  ```bash
  dart tools/code_review/code_review.dart --staged
  ```
- **Focus on specific aspects**:
  ```bash
  # Security only
  dart tools/code_review/code_review.dart --all --focus security

  # Several aspects
  dart tools/code_review/code_review.dart --all --focus security,performance,bugs
  ```
  *Valid `focus` values: `architecture`, `security`, `performance`, `bugs`, `style`, `testing`. Anything else is refused.*

- **Excluding files**:
  ```bash
  # Exclude more by glob
  dart tools/code_review/code_review.dart --all --exclude "**/routing/**"
  ```
  Generated files (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`, `*.mocks.dart`, anything under `gen/` / `generated/`, `firebase_options_*.dart`), test files (`/test/`) and every gitignored file are **always** excluded, with or without `--exclude`.

- **Language & format options**:
  ```bash
  # Report in Vietnamese
  dart tools/code_review/code_review.dart --all --language vi
  ```
  `--language` applies to that run only — it is not written to `code_review_config.json`; change the default with `--config`.
  Reports are always Markdown (`code_review_reports/code_review_report_<date>_<time>.md`; change the folder with `--output-dir`, skip the report file with `--no-summary`). `--format` accepts only `markdown` — it is kept so scripts passing `--format markdown` keep working. `-v` / `--verbose` prints more detail.

### An effective workflow

1.  **Before committing**:
    ```bash
    # Review the staged files before you commit
    dart tools/code_review/code_review.dart --staged
    ```
2.  **Layer by layer (weekly)**:
    ```bash
    # Monday: the domain layer
    dart tools/code_review/code_review.dart --folder modules/auth/domain --focus architecture

    # Wednesday: the data layer
    dart tools/code_review/code_review.dart --folder modules/auth/data
    ```
3.  **Before a release**:
    ```bash
    # Security and performance across the whole project
    dart tools/code_review/code_review.dart --all --focus security,performance
    ```

## 🔧 Configuration

- **Show the current settings**:
  ```bash
  dart tools/code_review/code_review.dart --show-config
  ```
- **Change settings (interactive)**:
  ```bash
  dart tools/code_review/code_review.dart --config
  ```
- **Settings in `code_review_config.json`** (committed values: `vi`, `3`, `1000`):
  - `reportLanguage`: Report language (`en`, `vi`, `ja`, `ko`, `zh`, `fr`, `de`, `es`).
  - `batchSize`: Files reviewed in parallel per batch (1-20; `5` when absent).
  - `delayBetweenBatches`: Pause (ms) between batches to stay under the API limits (`2000` when absent).
  - `includeTimestamps`: Write the generation time into the report.

## 🔗 CI/CD Integration

The real workflow is [`.github/workflows/code_review.yml`](../../.github/workflows/code_review.yml): on every pull request (into `main`, `develop`, `master`) touching Dart files in `apps/*/lib`, `modules/` or `platform/` (except `*.g.dart`, `*.freezed.dart`, `*.module.dart`), it runs the tool with one `--file` per changed file (`--language vi`), uploads the report as an artifact and posts a review with inline suggestions on the PR. It can also be run by hand (`workflow_dispatch`) with a `changed` / `all` / `domain` / `data` / `platform` / `presentation` scope. Required secret: `GEMINI_API_KEY`. This workflow does not block a merge.

## 🐛 Troubleshooting

- **"Gemini API key not found"**:
  - Set the `GEMINI_API_KEY` environment variable, pass `--api-key`, or run the tool and agree to save the key when asked.

- **"Rate limit exceeded"** (HTTP 429 / 503):
  - In Batch mode the tool waits (per `Retry-After`, 60 seconds by default) and retries, up to 3 times. Individual mode does not retry.
  - If it keeps happening, raise the delay: `dart tools/code_review/code_review.dart --config` and set `delayBetweenBatches` to `2000`-`3000` ms, or lower `batchSize`.

- **"Timeout" or "Failed to parse successful API response"**:
  - A timeout (60 seconds per request) is retried by Batch mode after 30 / 60 / 90 seconds. A response that fails to parse is not retried.
  - Usually the file is too large or the response was blocked/truncated. If it still fails, review that file on its own (`--file`).

---

## 📚 Appendix A: Quick Review Checklist

Use this checklist to self-review your code.

### 🏛️ Architecture
- [ ] **Dependency rule**: Does the code break `Presentation → Domain ← Data`?
- [ ] **Pure Domain layer**: Does the Domain layer import `flutter`, `dart:ui`, `dio`, `retrofit` or any `core_*` package? (Forbidden.)

### 🧬 Per layer
- **Core**: No direct `SharedPreferences` (go through `core_storage`'s `StorageManager` + `StorageValue<T>`). `platform/*` must NOT depend on `feature_*`, `data_*` or `domain_*` — except the three approved edges to `domain_core` (arch_check R1).
- **Domain**: An `Entity` stays pure (no `statusCode`, `message`). A `Repository` returns `Future<Result<T>>`.
- **Data**: A `RepositoryImpl` `implements` the Domain interface and wraps every call in `BaseRepository`'s `execute()` / `executeSync()` (`data_core`).
- **Presentation**: A `Provider` must NOT hold UI controllers. Async calls go through `executeOperation`.

### 💅 Naming & style
- **Constants**: `static const` fields are `UPPER_SNAKE_CASE`.
- **Private members**: Start with `_`.
- **`final`**: Variables that are never reassigned are `final`.
