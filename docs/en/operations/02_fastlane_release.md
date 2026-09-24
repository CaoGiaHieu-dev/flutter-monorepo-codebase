# Fastlane & Release

This page answers: **how the Fastlane setup is wired, which lanes exist and what they take, how the app is signed, and what the full release procedure is.** After reading it you can configure `Config.yaml`, run any lane from the repository root, and ship a build to Firebase App Distribution, Google Play or TestFlight.

> [!IMPORTANT]
> Two files you must supply yourself are documented below — a **release keystore** (`key.properties`, plus `key-stg.properties` for staging), without which a staging/prod release build refuses to start ([§4](#4-signing)), and **`apps/mobile/env.prod`**, without which a prod build hard-fails ([§6](#6-flavors-and-env-files)). Read both before your first store upload.

---

## 1. Why you can run it from anywhere

Fastlane normally forces you into the directory holding its `Fastfile`. This repo removes that constraint with a two-file proxy.

```
Gemfile                        ← root: fastlane + cocoapods, loads fastlane/Pluginfile
fastlane/Fastfile              ← root proxy
fastlane/Pluginfile            ← forwards to apps/mobile/fastlane/Pluginfile
apps/mobile/Gemfile            ← same gems, for running from apps/mobile/
apps/mobile/fastlane/Fastfile          ← real entry point
apps/mobile/fastlane/Pluginfile        ← the ONE plugin list
apps/mobile/fastlane/modules/
    helpers.rb                 ← config loading + all shared logic
    android_lanes.rb           ← platform :android
    ios_lanes.rb               ← platform :ios
    flutter_lanes.rb           ← cross-platform lanes
apps/mobile/fastlane/Config.yaml       ← YOUR config (gitignored, created by you)
apps/mobile/fastlane/Config.example.yaml
```

`fastlane/Fastfile` at the root only imports the real modules:

```ruby
ENV['FASTLANE_SKIP_DOCS'] = '1'

import "../apps/mobile/fastlane/modules/helpers.rb"
import "../apps/mobile/fastlane/modules/ios_lanes.rb"
import "../apps/mobile/fastlane/modules/android_lanes.rb"
import "../apps/mobile/fastlane/modules/flutter_lanes.rb"
```

It deliberately does **not** `Dir.chdir`. Fastlane parses a Fastfile inside its own `chdir` block and restores the directory afterwards, so a `chdir` there was undone before any lane ran — lanes run in `<root>/fastlane`, actions (`sh`, uploads) in `<root>` — and Ruby only warned `conflicting chdir during another chdir block`. Instead, every path inside the modules is resolved **absolutely from the file's own location**, never from the caller's CWD (`apps/mobile/fastlane/modules/helpers.rb`):

```ruby
FASTLANE_DIR = File.expand_path("..", __dir__)   # apps/mobile/fastlane
APP_DIR = File.expand_path("..", FASTLANE_DIR)   # apps/mobile
CONFIG_FILE = File.join(FASTLANE_DIR, "Config.yaml")
```

The dart-define file, `ExportOptions.plist`, the build artifacts, `ios/` for CocoaPods and every credential path from `Config.yaml` are built from `APP_DIR`, and `flutter build` runs inside `APP_DIR`. That is what makes `bundle exec fastlane android build …` work identically from the repository root and from `apps/mobile/`.

`ENV['FASTLANE_SKIP_DOCS'] = '1'` is set in both Fastfiles: without it fastlane rewrites `README.md` in the fastlane folder after every run — the tracked, hand-written `apps/mobile/fastlane/README.md`, or a stray one at the root. `fastlane/.gitignore` (root) and `apps/mobile/fastlane/.gitignore` ignore what a run writes (`report.xml`, …) and every credential file.

---

## 2. Configuration

`Config.yaml` is **required** — `helpers.rb` aborts immediately if it is missing:

```ruby
UI.user_error!("Configuration file not found at #{CONFIG_FILE}. Copy Config.example.yaml next to it and fill it in.") unless File.exist?(CONFIG_FILE)
```

Create it once:

```bash
cp apps/mobile/fastlane/Config.example.yaml apps/mobile/fastlane/Config.yaml
```

`apps/mobile/fastlane/.gitignore` ignores `*.yaml` with an explicit `!Config.example.yaml` exception, so your filled-in `Config.yaml` — and every `*.json` / `*.p8` credential beside it — stays out of git. In CI, `fastlane.yml` writes it from the `FASTLANE_CONFIG_YAML_B64` secret ([`01_cicd.md` §7](01_cicd.md#7-secrets)).

**Relative paths in `Config.yaml` are resolved against `apps/mobile/`** — whichever directory you run fastlane from — so the example's `fastlane/firebase-auth.json` lands in `apps/mobile/fastlane/`, next to `Config.yaml`. Absolute paths are used as is.

### Fields to fill in

| Key | Meaning |
|:---|:---|
| `flutter.default_version` | Default answer to the "Flutter version" prompt. `stable` = use the Flutter this machine resolves (the `.fvmrc` pin when fvm is installed, else the one on PATH); an exact version must match it — see [§7](#7-toolchain-setup-inside-a-lane) |
| `default_app_version` | Default answer to the "app version" prompt |
| `valid_flavors` | Accepted flavor names. `none` is always accepted on top of this list |
| `app_bundle_ids.ios` / `.android` | **Base** bundle ID, without any flavor suffix |
| `firebase.app_ids.<platform>.<flavor>` | Firebase App ID per platform and flavor, plus a `default` key for flavor-less builds. A flavor with no entry falls back to `default` with a warning — which uploads to the default app, so give every flavor you distribute its own entry |
| `firebase.credentials_map.<flavor>` | Path to the Firebase service-account JSON per flavor; a flavor with no entry falls back to `default` (the same fallback `fastlane.yml` uses when it writes the file) |
| `app_store_connect.api_key_id` / `.issuer_id` | App Store Connect API key identifiers |
| `app_store_connect.username` / `.team_id` | Apple ID and team, fallback for actions that do not take an API key |
| `app_store_connect.apple_ids.<flavor>` | Numeric Apple ID per flavor — **required** by the TestFlight upload, which errors with *"Unknown flavor for apple-id mapping"* if the flavor is missing |
| `google_play.account_id` | Used only to build console links |
| `paths.firebase_testers_file` | Text file of tester emails for Firebase App Distribution |
| `paths.google_play_key_prod` / `_dev` | Google Play service-account JSON files |
| `paths.app_store_connect_key_filepath` | The `.p8` API key file. Its name **must be `AuthKey_<app_store_connect.api_key_id>.p8`** — the name App Store Connect gives the download. The TestFlight upload runs `xcrun altool --apiKey <id>`, which takes no key path: it looks only for that file name, in `$API_PRIVATE_KEYS_DIR` (the lane sets it to this file's directory) or in `./private_keys`, `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys`. Locally, a differently named file still uploads, through a temporary renamed copy and a warning; `fastlane.yml` refuses it |

The former `paths.change_log_android` / `_ios` keys are gone (see [§3](#3-lanes)); if your `Config.yaml` still has them they are ignored.

### Gems and plugins

The one plugin, `fastlane-plugin-firebase_app_distribution`, is already listed in `apps/mobile/fastlane/Pluginfile`. Install everything once and always run through Bundler:

```bash
bundle install                         # from the repository root (or from apps/mobile/)
bundle exec fastlane android build …   # same from either directory
```

**Commit the `Gemfile.lock` files** that the first `bundle install` writes (one next to each Gemfile: the root one and the one in `apps/mobile/`) — the root `.gitignore` ignores `*.lock` but makes an exception for them, as for `pubspec.lock`. Without them every machine and every CI run resolves whatever fastlane, CocoaPods and plugin versions are newest that day. Generate them on the machine that cuts releases, and add the other platforms that run the lanes, e.g. `bundle lock --add-platform arm64-darwin x86_64-linux`, so `bundler-cache` on a GitHub runner does not reject the lockfile.

Do not run `fastlane add_plugin`: the plugin is already there, the command is interactive (it fails in CI), and it edits the Pluginfile of whichever fastlane folder it runs in. Add a new plugin by hand to `apps/mobile/fastlane/Pluginfile`; both Gemfiles load it — the root one through `fastlane/Pluginfile`, which fastlane requires in order to consider plugins set up.

---

## 3. Lanes

Every lane is interactive: any parameter you omit is prompted for. Passing it on the command line skips the prompt, which is what makes the lanes CI-friendly.

### Android — `apps/mobile/fastlane/modules/android_lanes.rb`

| Lane | What it does | Parameters |
|:---|:---|:---|
| `android build` | Build APK or AAB and distribute | `flavor`, `build_type` (`apk`/`aab`), `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log`, `change_log_file`, `skip_setup`, `skip_build`, `flutter_upgrade` |
| `android upload` | Upload an **already-built** artifact to Play. Forces `skip_build:true`, `skip_setup:true`, `flutter_version:stable`, `distribute_store:true`, `distribute_firebase:false` | `flavor`, `build_type`, `version`, `track` |
| `android store` | Prod release to Play. Forces `flavor:prod`, `build_type:aab`, `distribute_store:true`, `distribute_firebase:false` | `version`, `build_number`, `track` |

### iOS — `apps/mobile/fastlane/modules/ios_lanes.rb`

| Lane | What it does | Parameters |
|:---|:---|:---|
| `ios build` | Build IPA and distribute to TestFlight and/or Firebase | `flavor`, `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `change_log`, `change_log_file`, `skip_setup`, `skip_build`, `flutter_upgrade` |
| `ios upload` | Upload an existing IPA to TestFlight, no rebuild | `flavor`, `version` |
| `ios store` | Prod release to TestFlight. Forces `flavor:prod`, `distribute_store:true` | `version`, `build_number` |

### Cross-platform — `apps/mobile/fastlane/modules/flutter_lanes.rb`

| Lane | What it does | Parameters |
|:---|:---|:---|
| `flutter` | Prompts once for shared inputs, sets up the toolchain once, then shells out to `fastlane ios build` followed by `fastlane android build` | `flavor`, `version`, `build_number`, `build_type`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log`, `skip_setup`, `flutter_upgrade` |
| `store` | Same orchestration but prod/store defaults: `fastlane ios store` then `fastlane android store` | `version`, `build_number`, `track`, `flutter_version`, `change_log`, `skip_setup`, `flutter_upgrade` |

Both cross-platform lanes run **iOS first and abort the whole run if it fails**, so Android is never built against a release iOS could not produce. The child processes run from `apps/mobile/` (under `bundle exec` they inherit the same bundle).

### Change log

A lane takes its change log from, in this order:

1. `change_log:` — always wins;
2. `change_log_file:` — a file whose path is passed **explicitly**. The cross-platform lanes write the change log once to a temp directory **outside the repository**, pass it to both children as `change_log_file:`, and delete it in an `ensure` block whether the run succeeded or not;
3. an interactive prompt.

Nothing is read implicitly and nothing is written back. (The lanes used to read a fixed `change_log_<platform>.txt` *before* looking at `change_log:`, so a file left behind by an interrupted run silently replaced the change log you passed.)

Valid values enforced by `helpers.rb`:

- `VALID_TRACKS` = `internal`, `alpha` (closed testing), `beta` (open testing), `production` — the Play Console's built-in tracks. `closed` is not a track name the Play API accepts. A custom closed-testing track created in the Play Console is addressed by its own name: pass `track:<name>` on the command line, which the lanes accept as is; only the interactive prompt is limited to this list
- `VALID_BUILD_TYPES` = `apk`, `aab`
- `VALID_FLAVORS` = whatever is in `Config.yaml`, plus `none`

### Examples

```bash
# Dev APK to Firebase testers
bundle exec fastlane android build flavor:dev build_type:apk distribute_firebase:true change_log:"Fix login bug"

# Local build only — no distribution, no toolchain setup (fastest)
bundle exec fastlane android build flavor:dev build_type:apk distribute_firebase:false distribute_store:false skip_setup:true

# Prod AAB to the Play internal track
bundle exec fastlane android store version:1.2.0 build_number:45 track:internal

# Prod IPA to TestFlight
bundle exec fastlane ios store version:1.2.0 build_number:45

# Both platforms, dev flavor, Firebase only
bundle exec fastlane flutter flavor:dev version:1.2.0 build_number:auto distribute_firebase:true distribute_store:false

# Both platforms, prod, to both stores
bundle exec fastlane store version:1.2.0 build_number:auto track:internal
```

### Build numbers

`build_number` accepts a positive integer or `auto`; an **empty** value (`build_number:` — what a CI input left blank produces) also means `auto`. Anything else (`0`, `abc`) stops the lane: it used to become `"".to_i` = `0` and ship as `--build-number=0`. With `auto`, `determine_build_number` works it out:

| Distribution | `auto` resolves to |
|:---|:---|
| store, iOS | latest **TestFlight** build for that version + 1 |
| store, Android | highest **Google Play** version code on the track + 1 |
| Firebase only | latest **Firebase App Distribution** release + 1 |
| none (local build) | the build number in `apps/mobile/pubspec.yaml` (`version: 1.0.0+N` → `N`) — no credentials needed, nothing to collide with |

`fastlane.yml` sends `build_number:auto` when its input is left empty.

`versionCode` and `versionName` are **not** read from `apps/mobile/pubspec.yaml` during a Fastlane build. `apps/mobile/android/app/build.gradle.kts` binds them to Flutter:

```kotlin
versionCode = flutter.versionCode
versionName = flutter.versionName
```

which means whatever `--build-number` / `--build-name` the lane passes wins. `version: 1.0.0+1` in `apps/mobile/pubspec.yaml` is only the fallback for a plain `flutter build` with no flags.

---

## 4. Signing

`apps/mobile/android/app/build.gradle.kts` declares three signing configs, each reading a different properties file from `apps/mobile/android/`:

| Config | Properties file | Used by flavor |
|:---|:---|:---|
| `dev` | `key-dev.properties` | `dev` |
| `staging` | `key-stg.properties` | `staging` |
| `prod` | `key.properties` | `prod` |

### Release builds refuse the dev key

A missing `key-stg.properties` / `key.properties` is handled differently per build type:

| Build | Flavor `staging` / `prod` without its properties file |
|:---|:---|
| `--debug`, `--profile` | Signed with the committed dev key, so a fresh clone runs every flavor |
| `--release` (APK or AAB) | **Fails** in `pre<Flavor>ReleaseBuild`, early in the build and before anything is packaged or signed |

The failure names the missing file and points back here:

```text
Execution failed for task ':app:preProdReleaseBuild'.
> Refusing to build the prod release: …/apps/mobile/android/key.properties is missing.
  Without it this build would be signed with the committed, public dev keystore
  (keystore-dev.jks), and a Play listing's signing key can never change afterwards.
```

The guard sits at the bottom of `apps/mobile/android/app/build.gradle.kts`. It hangs off the `pre…ReleaseBuild` task that every release entry point runs — `flutter build apk|appbundle`, the Fastlane lanes, `./gradlew assemble…|bundle…` — so none of them can produce a release signed with the public key.

> [!NOTE]
> **Staging only** has an explicit escape hatch, for a pipeline that deliberately ships staging to testers with the dev key: the Gradle property `allowDevKeystoreForStaging=true`.
> ```bash
> flutter build apk --flavor staging -PallowDevKeystoreForStaging=true --dart-define-from-file=env.stg
> # or, for a whole CI job:
> export ORG_GRADLE_PROJECT_allowDevKeystoreForStaging=true
> ```
> Prod has none. Anyone can sign an update to a dev-key-signed staging app, so prefer a real `key-stg.properties` (a separate upload key, generated the same way as below).

`dev` releases keep using `key-dev.properties`: the dev flavor is never a store listing.

### The committed dev keystore

`apps/mobile/android/key-dev.properties` and `apps/mobile/android/keystore-dev.jks` are **tracked in git** so a fresh clone builds and runs without any setup. That is deliberate for a template, and fine for `dev`. `apps/mobile/android/.gitignore` ignores every other `*.jks`, `*.keystore`, `key.properties` and `key-*.properties` and un-ignores exactly these two; the root `.gitignore` repeats the same patterns (plus `google-services.json` / `GoogleService-Info.plist`) at any depth, with the same two exceptions.

> [!CAUTION]
> **Never ship a production release with the dev keystore.** It is public in the repository — anyone who clones it can sign an APK that the OS treats as an update to yours.

Generate your own release key:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `apps/mobile/android/key.properties` (already covered by `.gitignore`):

```properties
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Staging reads `key-stg.properties`, next to it and in the same format — ideally pointing at a second key, so a leaked staging key cannot sign prod.

Keep the `.jks` outside the repository, and back it up somewhere durable — losing it means you can never publish an update to that Play listing again.

---

## 5. Bundle IDs

`helpers.rb` derives the bundle ID by appending a flavor suffix. The staging suffix differs per platform — Gradle uses `.stg`, the Xcode project `.staging` — so the helper takes the platform and matches each native project exactly:

```ruby
def get_bundle_id_with_suffix(base_bundle_id, flavor, platform)
  return base_bundle_id if flavor.nil? || flavor.empty?
  case flavor
  when 'dev' then "#{base_bundle_id}.dev"
  when 'staging' then platform == :ios ? "#{base_bundle_id}.staging" : "#{base_bundle_id}.stg"
  else base_bundle_id
  end
end
```

```kotlin
create("staging") {
    dimension = "environment"
    applicationIdSuffix = ".stg"
    signingConfig = signingConfigs.getByName("staging")
}
```

| Flavor | Android: Gradle `applicationIdSuffix` | Android: Fastlane bundle ID | iOS: Xcode `PRODUCT_BUNDLE_IDENTIFIER` | iOS: Fastlane bundle ID | Agree |
|:---|:---|:---|:---|:---|:---|
| `dev` | `.dev` | `<base>.dev` | `com.example.codebase.dev` | `<base>.dev` | ✅ |
| `staging` | `.stg` | `<base>.stg` | `com.example.codebase.staging` | `<base>.staging` | ✅ |
| `prod` | *(none)* | `<base>` | `com.example.codebase` | `<base>` | ✅ |

`<base>` is `app_bundle_ids.android` / `app_bundle_ids.ios` from `Config.yaml`. The Xcode identifiers are set per build configuration (`Debug-<flavor>`, `Release-<flavor>`, `Profile-<flavor>`) in `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`, and `tools/firebase/firebase_config.dart` registers the same `.staging` iOS ID.

> [!NOTE]
> These lists are maintained independently and nothing checks that they agree. If Fastlane computed `.staging` while Gradle produced `.stg` — or `.stg` while Xcode produced `.staging`, as it did before the helper took the platform — a staging upload would look up a store listing that does not match the artifact. If you add a flavor or rename a suffix, change the helper, Gradle **and** Xcode in the same commit.

---

## 6. Flavors and env files

| Flavor | applicationId suffix | dart-define file expected by Fastlane | Present |
|:---|:---|:---|:---|
| `dev` | `.dev` | `apps/mobile/env.dev` | ✅ |
| `staging` | `.stg` | `apps/mobile/env.stg` | ✅ |
| `prod` | *(none)* | `apps/mobile/env.prod` | ❌ **you must create it** |

`helpers.rb` maps flavor to file:

```ruby
def get_dart_define_file(flavor)
  case flavor
  when 'dev' then "env.dev"
  when 'staging' then "env.stg"
  else "env.prod"
  end
end
```

and refuses to build when that file is missing — the path is absolute, built from `APP_DIR`, so it is the same file from either entry point:

```ruby
dart_define_file = File.join(APP_DIR, get_dart_define_file(flavor))
unless File.exist?(dart_define_file)
  UI.user_error!(
    "Dart define file '#{display_path(dart_define_file)}' not found for flavor " \
    "'#{flavor}'. Building without it would ship empty " \
    "String.fromEnvironment values (API base URL, keys), so this is " \
    "a hard failure. Create the file first."
  )
end
build_command += " --dart-define-from-file=#{dart_define_file.shellescape}"
```

> [!IMPORTANT]
> **A prod release cannot be built until you create `apps/mobile/env.prod`.** That is deliberate. The alternative — skipping the flag with a warning — lets a prod build *succeed* with every `String.fromEnvironment` in `platform/kernel/lib/src/utils/env_constants.dart` falling back to empty, producing an APK that points at empty API URLs and empty keys, signed and shipped with no warning. Failing loudly is the safer trade.
>
> Copy the key names from `apps/mobile/env.dev`; `.vscode/launch.json` already points its Prod configuration at `env.prod`.

> [!NOTE]
> `env.prod` is already ignored — `apps/mobile/.gitignore` lists it explicitly (the root `.gitignore`'s `*.env` pattern would not match it: the dot is on the wrong side). `env.dev` and `env.stg` are committed **deliberately**: they hold no secrets and a fresh clone must build. Keep real credentials out of them. In CI, prod builds get `env.prod` from the `ENV_PROD_B64` secret.

---

## 7. Toolchain setup inside a lane

Unless you pass `skip_setup:true`, every lane calls `setup_flutter_environment`. **FVM is optional**: it is used only when the workspace pins a version (`.fvmrc`) **and** `fvm` is installed — the same rule as `tools/shared/toolchain.dart`. `FASTLANE_USE_FVM=true|false` overrides the detection.

| `flutter_version` | With FVM | Without FVM |
|:---|:---|:---|
| `stable` (or empty) | `fvm install` — the `.fvmrc` pin | the `flutter` on PATH, as is |
| exact, e.g. `3.47.4` | must equal the `.fvmrc` pin, else the lane stops (switching would rewrite the tracked `.fvmrc`) | must equal `flutter --version`, else the lane stops |

Nothing is upgraded implicitly. `flutter_upgrade:true` (opt-in, non-FVM only) runs `flutter channel stable` + `flutter upgrade --force` first — it used to run on every `stable` build, silently moving the machine's toolchain. `flutter precache --ios` runs only for iOS builds on macOS.

It then runs `install_dependencies`, with `fvm ` in front of `dart` / `flutter` when FVM is in use:

```ruby
sh "#{dart_cmd} pub global activate flutterfire_cli"
sh "#{dart_cmd} pub global activate flutter_gen"
sh "#{flutter_cmd} clean"
sh "#{flutter_cmd} pub get --enforce-lockfile"
# ...then flutter gen-l10n for every l10n.yaml in the tree
sh "#{dart_cmd} run build_runner build --workspace"
# ...then, per package with a lib/ (apps skipped), from the workspace root:
sh "#{dart_cmd} tools/barrel_generator/generate.dart <package>/lib"
```

`--enforce-lockfile` builds from exactly the committed workspace `pubspec.lock`, and fails when it no longer matches the pubspecs instead of re-resolving.

The barrel pass comes last because a barrel also exports generated files, and the `lib/src/gen/gen.dart` barrels are gitignored — it mirrors step 6 of `tools/workspace_setup/configure.dart`.


Because this runs `flutter clean` and a full workspace `build_runner`, it is slow. Use `skip_setup:true` for iterative local builds.

---

## 8. Release procedure

1. **Pick the version.** Decide the `version` (build name). Use `build_number:auto` unless you need a specific code.
2. **Verify signing.** `test -f apps/mobile/android/key.properties` — without it the release build stops in `preProdReleaseBuild` ([§4](#4-signing)).
3. **Verify the env file exists for the flavor** — see [§6](#6-flavors-and-env-files). For prod you must create `apps/mobile/env.prod` first; the lane hard-fails without it.
4. **Confirm `Config.yaml` is filled in**, particularly `firebase.app_ids`, `app_store_connect.apple_ids` and the credential paths.
5. **Dry run locally**, no distribution:
   ```bash
   bundle exec fastlane android build flavor:prod build_type:aab \
     distribute_store:false distribute_firebase:false skip_setup:true
   ```
6. **Ship it.**
   ```bash
   # Testers first
   bundle exec fastlane android build flavor:prod build_type:apk distribute_firebase:true \
     version:1.2.0 build_number:auto change_log:"…"

   # Then the stores
   bundle exec fastlane store version:1.2.0 build_number:auto track:internal
   ```
7. **Promote** from `internal` to `production` in the Play Console once validated. The lane uploads with `release_status: 'draft'`, so nothing goes live without an explicit promotion.
8. **Archive the obfuscation symbols.** Every lane builds with `--obfuscate --split-debug-info=apps/mobile/obfuscate` and prints that path after the build. The symbol files are not inside the APK/AAB/IPA, and without them `flutter symbolize` cannot read a single crash stack trace from this release — keep them with the release (`fastlane.yml` uploads them as a workflow artifact). The next build overwrites them.

### Pre-release checklist

- [ ] `apps/mobile/android/key.properties` exists and points at your **release** keystore
- [ ] Release keystore is backed up outside the repository
- [ ] Env file for the target flavor exists (`apps/mobile/env.prod` for prod — see [§6](#6-flavors-and-env-files))
- [ ] `Config.yaml` complete; credential JSON/`.p8` files present at the configured paths
- [ ] `flutter analyze` clean and package tests pass — `pr_quality_check.yml` gates this on PRs, but the release pipelines do not (see [`01_cicd.md`](01_cicd.md#6-the-quality-gate))
- [ ] `sslPinningHashes` populated if this build faces production traffic — it defaults to `const []`, which disables pinning entirely
- [ ] Changelog written
- [ ] Build number does not collide with an existing release

---

## 9. iOS status

The iOS lanes are real and reasonably developed, not stubs:

- `run_flutter_build` deletes `Podfile.lock` and runs `pod deintegrate && pod install --repo-update` before every iOS build, forcing fresh dependency resolution.
- It picks `ios/flavors/<flavor>/ExportOptions.plist` when a flavor is set, `ios/ExportOptions.plist` otherwise, and warns rather than failing if neither exists.
- If `flutter build ipa` archives successfully but export fails, it retries `xcrun xcodebuild -exportArchive -exportOptionsPlist <that file>` up to three times — **only when that file exists**. Without it there is nothing to retry with, so the lane stops with an error naming the missing path. Create it next to the flavor (`ios/flavors/<flavor>/ExportOptions.plist`, or `ios/ExportOptions.plist` for flavor-less builds) with at least `method` (e.g. `app-store-connect`), `teamID` and, for manual signing, `provisioningProfiles`; the `ExportOptions.plist` inside a successful Xcode *Distribute App* export is a working starting point.
- `distribute_to_app_store` bypasses Fastlane's `upload_to_testflight` and calls `xcrun altool --upload-app` directly, with a comment noting Fastlane's altool wrapper has compatibility problems with Xcode 26. altool is spawned with `API_PRIVATE_KEYS_DIR` set to the directory of `paths.app_store_connect_key_filepath`, since it finds the key only by the name `AuthKey_<api_key_id>.p8` ([§2](#fields-to-fill-in)).

What is **not** wired up:

- iOS build and distribute steps in `azure-ci-cd.yml` are fully commented out.
- The iOS build in `.github/workflows/flutter_build.yml` is commented out; only Android is built and distributed.
- iOS builds require macOS, so the `self-hosted` option in `fastlane.yml` must actually be a Mac — one whose keychain already holds the signing certificates and profiles; no workflow installs them. Pick `platform: android` in `fastlane.yml` to build Android only.
- `ios/flavors/<flavor>/GoogleService-Info.plist` is gitignored; `fastlane.yml` restores it from `GOOGLE_SERVICE_INFO_<FLAVOR>_PLIST_B64` when that secret is set.

---

## See also

- [`01_cicd.md`](01_cicd.md) — pipelines, secrets, and the defects listed there
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — flavors, env files, Firebase bootstrap
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — the `tools/` scripts Fastlane invokes
