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

2. To review a specific file or directory:
   ```bash
   dart tools/code_review/code_review.dart --file <path_to_file_or_directory>
   ```

3. To review the entire codebase (Warning: Takes a long time):
   ```bash
   dart tools/code_review/code_review.dart --all
   ```

Use the `run_command` tool to run the commands above. After execution, analyze the summary output printed to the terminal and advise the user on how to resolve any architectural violations.

Key rules to pay attention to during code review (especially the Presentation layer):
- UI Controllers (ViewModel, Bloc, Cubit) must be annotated with `@injectable` instead of Singletons.
- Instantiation must happen at the Router layer using `ChangeNotifierProvider` or `BlocProvider` to ensure auto-dispose.
