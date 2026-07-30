# 12. Advanced Fastlane CI/CD Guide Technical Manual (Workspace Root Execution)

This document provides the most detailed, comprehensive guide to the continuous integration and continuous delivery (CI/CD) system built with **Fastlane** for the Monorepo structure. Specially, this system has been upgraded to a **CWD-Independent** (Current Working Directory Independent) architecture, allowing execution of all compilation tasks right from the project's Root Workspace without manually changing directories (`cd`).

---

## 🏛️ 1. Proxy Assembly Architecture From Workspace Root

The CI/CD system is divided into two parts: **Proxy Gate at Root** and **Modular Execution Core at App**. This architecture ensures all actual Fastlane source code is neatly encapsulated inside the `app/` directory but can still be activated transparently at the Root:

```text
/ (Workspace Root)
├── Gemfile                      # [ROOT PROXY] Calls eval_gemfile "app/Gemfile"
├── fastlane/
│   ├── Pluginfile               # [ROOT PROXY] Calls eval_gemfile "../app/fastlane/Pluginfile"
│   └── Fastfile                 # [ROOT PROXY] Shifts CWD to app/fastlane and imports modular core
└── app/                         # Host Application
    ├── Gemfile                  # Defines dependencies (fastlane, dotenv, cocoapods)
    └── fastlane/
        ├── Pluginfile           # Loads plugins (e.g., firebase_app_distribution)
        ├── Config.yaml          # Aggregates all static configuration parameters of the project
        └── modules/             # Modular core broken down by function
            ├── helpers.rb       # Central run_build function & Intensive parameter processing logic
            ├── android_lanes.rb # Android compilation/distribution lanes
            ├── ios_lanes.rb     # iOS compilation/distribution lanes
            └── flutter_lanes.rb # Cross-platform combined lanes
```

### CWD Shifting Mechanism
The `fastlane/Fastfile` at the root directory acts as a smart proxy:
```ruby
# Safely shift Fastlane's working directory to the app/fastlane subdirectory
Dir.chdir("../app/fastlane")

# Import all actual business modules from the app directory
import "../app/fastlane/modules/helpers.rb"
import "../app/fastlane/modules/ios_lanes.rb"
import "../app/fastlane/modules/android_lanes.rb"
import "../app/fastlane/modules/flutter_lanes.rb"
```
*Thanks to this CWD shifting mechanism, Fastlane always sees the `app/` directory as the root working context when compiling Flutter source code, completely resolving missing file or incorrect relative path errors.*

---

## 🧭 2. Resolving Fixed Absolute Paths (CWD-Independent Paths)

Inside the execution core `app/fastlane/modules/helpers.rb`, instead of using `../` relative paths which are very prone to errors if CWD changes, we define a fixed absolute constant based on the location of the `helpers.rb` file:

```ruby
# Statically locate the APP directory 100% accurately regardless of where you stand to run the terminal command
APP_DIR = File.expand_path("../..", __dir__)
```

All directory references throughout the Fastlane system use this constant:
- Android output path: `#{APP_DIR}/build/app/outputs/flutter-apk`
- Configuration loading path: `#{APP_DIR}/fastlane/Config.yaml`
- Keystore file path, Firebase credentials, etc.

---

## 🏎️ 3. Execution Commands List (Lanes Directory)

You can trigger these commands directly at the monorepo root directory using the syntax:
`fastlane <platform> <command_name> <parameters>`

### A. Android Support Lanes (Android Lanes)

| Command Syntax | Role | Key Parameters |
| :--- | :--- | :--- |
| `fastlane android build` | Automatically compile APK or AAB | `flavor`, `build_type` (apk/aab), `distribute_store` (true/false) |
| `fastlane android store` | Compile AAB and push directly to CH Play | `version`, `build_number`, `track` (internal/closed/production) |

### B. iOS Support Lanes (iOS Lanes)

| Command Syntax | Role | Key Parameters |
| :--- | :--- | :--- |
| `fastlane ios build` | Compile IPA and distribute TestFlight/Firebase | `flavor`, `distribute_store`, `distribute_firebase` |
| `fastlane ios store` | Compile Prod IPA and push to App Store | `version`, `build_number` |

### C. Cross-Platform Support Lanes (Flutter Lanes)

| Command Syntax | Role | Key Parameters |
| :--- | :--- | :--- |
| `fastlane flutter` | Compile & distribute both Android + iOS simultaneously | `flavor`, `version`, `build_number` |
| `fastlane store` | Push Production build to both Stores simultaneously | `version`, `build_number` |

---

## 💎 4. Execution Parameters Details (Run Build Arguments Map)

The central `run_build` function is extremely flexibly configured to support both modes: **Interactive Prompt (Interactive)** and **Unattended Auto-Run (Non-interactive CLI)**.

| Parameter | Data Type | Default Value | Details & Effect |
| :--- | :--- | :--- | :--- |
| `flavor` | String | *Prompts user* | Select environment: `dev`, `staging`, `prod`. |
| `flutter_version` | String | `stable` | Flutter SDK version to compile . |
| `version` | String | `1.0.0` | Display version number (Version Name). |
| `build_number` | String | `auto` | If `auto`, system auto-connects to Store/Firebase to get largest number + 1. |
| `build_type` | String | `apk` | Export format for Android (`apk` or `aab`). |
| `distribute_store` | Boolean | `false` | Whether to push to Google Play / App Store TestFlight. |
| `distribute_firebase`| Boolean | `true` | Whether to push to Firebase App Distribution for testing. |
| `skip_setup` | Boolean | `false` | If `true`, skips cleanup, library downloading, code generation to speed up build. |
| `change_log` | String | *Prompts user* | Release Notes content shown to Testers. |

---

## 📘 5. Practical Terminal Usage Guide

Ensure you are at the **Monorepo root directory** (no need to `cd app/`):

### Example 1: Compile dev APK and push to Firebase for quick Testing
```powershell
fastlane android build flavor:dev build_type:apk distribute_firebase:true change_log:"Fix login bug"
```

### Example 2: Only compile locally to check for errors, skip entire distribution and setup phase (Max speed)
```powershell
fastlane android build flavor:dev build_type:apk distribute_firebase:false distribute_store:false skip_setup:true
```

### Example 3: Push Production AAB build to Google Play Console (Internal Track)
```powershell
fastlane android store version:1.2.0 build_number:45 track:internal
```

---

## ⚠️ 6. Special Automated Mechanisms (Automated Logic Gate)

1. **Auto-Select Flutter Version**:
   If the `flutter_version` parameter is passed a specific version (e.g., `3.22.0`), the system automatically uses the corresponding version management tool. If passed `stable` or empty, the system uses the Flutter SDK installed directly on the OS.
2. **Xcode Export IPA Auto-Retry**:
   For macOS environments when building iOS, if the IPA packaging process encounters an error due to temporary Provisioning Profile cache conflicts, Fastlane automatically triggers a retry mechanism (Auto-Retry) directly using pure `xcodebuild` commands up to **3 times** consecutively before reporting an error.
3. **Dynamic Firebase App IDs Fetching**:
   Depending on the passed `flavor` parameter, the system automatically maps the configuration in `Config.yaml` to get the exactly corresponding App ID on the Firebase Console, completely eliminating the error of accidentally pushing a dev build to the production environment.
4. **Localization & Code Generation Checklist**:
   Before compiling, the system automatically scans the entire `packages/` directory in the workspace to find `l10n.yaml` files. If present, it will automatically run `flutter gen-l10n` for each corresponding package. Then, the system will trigger the `dart run build_runner build --workspace` command at the root directory to synchronously generate code for all Micro-packages.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
