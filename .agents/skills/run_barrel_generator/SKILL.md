---
name: run_barrel_generator
description: Guide for running the barrel file generator script to automatically update export entrypoints.
---

# 📦 Run Barrel Generator

The project automatically generates `*.dart` exports at the root of packages to manage monorepo entrypoints.

## Execution Instructions

When a developer adds, deletes, or renames files under a package's `lib` directory, or when requested to "generate barrel files", "update exports", etc.:

1. Run the generator script using Dart:
   ```bash
   dart tools/barrel_generator/generate.dart <path_to_lib_directory>
   ```
   *Example: `dart tools/barrel_generator/generate.dart packages/features/home/lib`*

Use the `run_command` tool to execute the command and report the status.
