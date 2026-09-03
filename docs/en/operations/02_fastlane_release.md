# Fastlane & Release

This page answers: **how the Fastlane setup is wired, which lanes exist and what they take, how the app is signed, and what the full release procedure is.** After reading it you can configure `Config.yaml`, run any lane from the repository root, and ship a build to Firebase App Distribution, Google Play or TestFlight.

> [!IMPORTANT]
> Two traps in this setup are documented below — a **silent fallback to the committed dev keystore** ([§4](#4-signing)) and a **required `app/env.prod` file** without which a prod build hard-fails ([§6](#6-flavors-and-env-files)). Read both before your first store upload.

---

## 1. Why you can run it from anywhere

Fastlane normally forces you into the directory holding its `Fastfile`. This repo removes that constraint with a two-file proxy.

```
fastlane/Fastfile              ← root proxy
app/fastlane/Fastfile          ← real entry point
app/fastlane/modules/
    helpers.rb                 ← config loading + all shared logic
    android_lanes.rb           ← platform :android
    ios_lanes.rb               ← platform :ios
    flutter_lanes.rb           ← cross-platform lanes
app/fastlane/Config.yaml       ← YOUR config (gitignored, created by you)
app/fastlane/Config.example.yaml
```

`fastlane/Fastfile` at the root does two things:

```ruby
# Change directory to app/fastlane to align working directories with the app configuration
Dir.chdir("../app/fastlane")

import "../app/fastlane/modules/helpers.rb"
import "../app/fastlane/modules/ios_lanes.rb"
import "../app/fastlane/modules/android_lanes.rb"
import "../app/fastlane/modules/flutter_lanes.rb"
```

Paths inside the modules are then resolved **absolutely from the file's own location**, never from the caller's CWD (`app/fastlane/modules/helpers.rb`):

```ruby
CONFIG_FILE = File.expand_path("../Config.yaml", __dir__)
APP_DIR     = File.expand_path("../..", __dir__)
```

That is what makes `fastlane android build …` work identically from the repository root and from `app/`.

---

## 2. Configuration

`Config.yaml` is **required** — `helpers.rb` aborts immediately if it is missing:

```ruby
UI.user_error!("Configuration file not found at #{CONFIG_FILE}") unless File.exist?(CONFIG_FILE)
```

Create it once:

```bash
cp app/fastlane/Config.example.yaml app/fastlane/Config.yaml
```

`app/fastlane/.gitignore` ignores `*.yaml` with an explicit `!Config.example.yaml` exception, so your filled-in `Config.yaml` — and every `*.json` credential beside it — stays out of git.

### Fields to fill in

| Key | Meaning |
|:---|:---|
| `flutter.default_version` | Default answer to the "Flutter version" prompt. `stable` uses the system Flutter; anything else drives `fvm` |
| `default_app_version` | Default answer to the "app version" prompt |
| `valid_flavors` | Accepted flavor names. `none` is always accepted on top of this list |
| `app_bundle_ids.ios` / `.android` | **Base** bundle ID, without any flavor suffix |
| `firebase.app_ids.<platform>.<flavor>` | Firebase App ID per platform and flavor, plus a `default` key for flavor-less builds |
| `firebase.credentials_map.<flavor>` | Path to the Firebase service-account JSON per flavor |
| `app_store_connect.api_key_id` / `.issuer_id` | App Store Connect API key identifiers |
| `app_store_connect.username` / `.team_id` | Apple ID and team, fallback for actions that do not take an API key |
| `app_store_connect.apple_ids.<flavor>` | Numeric Apple ID per flavor — **required** by the TestFlight upload, which errors with *"Unknown flavor for apple-id mapping"* if the flavor is missing |
| `google_play.account_id` | Used only to build console links |
| `paths.firebase_testers_file` | Text file of tester emails for Firebase App Distribution |
| `paths.google_play_key_prod` / `_dev` | Google Play service-account JSON files |
| `paths.app_store_connect_key_filepath` | The `.p8` API key file |
| `paths.change_log_android` / `_ios` | Temp files Fastlane uses to pass the changelog between lanes |

Install the one required plugin:

```bash
fastlane add_plugin firebase_app_distribution
```

---

## 3. Lanes

Every lane is interactive: any parameter you omit is prompted for. Passing it on the command line skips the prompt, which is what makes the lanes CI-friendly.

### Android — `app/fastlane/modules/android_lanes.rb`

| Lane | What it does | Parameters |
|:---|:---|:---|
| `android build` | Build APK or AAB and distribute | `flavor`, `build_type` (`apk`/`aab`), `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log`, `skip_setup`, `skip_build` |
| `android upload` | Upload an **already-built** artifact to Play. Forces `skip_build:true`, `skip_setup:true`, `flutter_version:stable`, `distribute_store:true`, `distribute_firebase:false` | `flavor`, `build_type`, `version`, `track` |
| `android store` | Prod release to Play. Forces `flavor:prod`, `build_type:aab`, `distribute_store:true`, `distribute_firebase:false` | `version`, `build_number`, `track` |

### iOS — `app/fastlane/modules/ios_lanes.rb`

| Lane | What it does | Parameters |
|:---|:---|:---|
| `ios build` | Build IPA and distribute to TestFlight and/or Firebase | `flavor`, `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `change_log`, `skip_setup`, `skip_build` |
| `ios upload` | Upload an existing IPA to TestFlight, no rebuild | `flavor`, `version` |
| `ios store` | Prod release to TestFlight. Forces `flavor:prod`, `distribute_store:true` | `version`, `build_number` |

### Cross-platform — `app/fastlane/modules/flutter_lanes.rb`

| Lane | What it does | Parameters |
|:---|:---|:---|
| `flutter` | Prompts once for shared inputs, sets up the toolchain once, then shells out to `fastlane ios build` followed by `fastlane android build` | `flavor`, `version`, `build_number`, `build_type`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log` |
| `store` | Same orchestration but prod/store defaults: `fastlane ios store` then `fastlane android store` | `version`, `build_number`, `track`, `flutter_version`, `change_log` |

Both cross-platform lanes run **iOS first and abort the whole run if it fails**, so Android is never built against a release iOS could not produce. They also write the changelog to the two temp files up front so the child lanes read it instead of re-prompting, and delete those files in an `ensure` block.

Valid values enforced by `helpers.rb`:

- `VALID_TRACKS` = `production`, `internal`, `closed`
- `VALID_BUILD_TYPES` = `apk`, `aab`
- `VALID_FLAVORS` = whatever is in `Config.yaml`, plus `none`

### Examples

```bash
# Dev APK to Firebase testers
fastlane android build flavor:dev build_type:apk distribute_firebase:true change_log:"Fix login bug"

# Local build only — no distribution, no toolchain setup (fastest)
fastlane android build flavor:dev build_type:apk distribute_firebase:false distribute_store:false skip_setup:true

# Prod AAB to the Play internal track
fastlane android store version:1.2.0 build_number:45 track:internal

# Prod IPA to TestFlight
fastlane ios store version:1.2.0 build_number:45

# Both platforms, dev flavor, Firebase only
fastlane flutter flavor:dev version:1.2.0 build_number:auto distribute_firebase:true distribute_store:false

# Both platforms, prod, to both stores
fastlane store version:1.2.0 build_number:auto track:internal
```

### Build numbers

`build_number` accepts a literal number or the string `auto`. With `auto`, `determine_build_number` fetches the current highest and adds one — from **TestFlight** (iOS + store), **Google Play** for the given track (Android + store), or **Firebase App Distribution** otherwise. If you ask for `auto` with no distribution target at all, it falls back to querying Firebase.

`versionCode` and `versionName` are **not** read from `app/pubspec.yaml` during a Fastlane build. `app/android/app/build.gradle.kts` binds them to Flutter:

```kotlin
versionCode = flutter.versionCode
versionName = flutter.versionName
```

which means whatever `--build-number` / `--build-name` the lane passes wins. `version: 1.0.0+1` in `app/pubspec.yaml` is only the fallback for a plain `flutter build` with no flags.

---

## 4. Signing

`app/android/app/build.gradle.kts` declares three signing configs, each reading a different properties file from `app/android/`:

| Config | Properties file | Used by flavor |
|:---|:---|:---|
| `dev` | `key-dev.properties` | `dev` |
| `staging` | `key-stg.properties` | `staging` |
| `prod` | `key.properties` | `prod` |

### The fallback is silent — and dangerous

Each block loads its file **only if it exists**, otherwise it copies the dev properties wholesale:

```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile: File = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { fis -> keystoreProperties.load(fis) }
} else {
    keystoreProperties.putAll(keystoreDevProperties)   // ← falls back to DEV
}
```

> [!CAUTION]
> **If `key.properties` is absent, a prod build is signed with the committed dev keystore and the build still succeeds.** There is no warning. A release signed with the wrong key cannot be updated on the Play Store afterwards — the signature is permanent for that listing.
>
> Before any production build, verify the file exists and points where you expect:
> ```bash
> test -f app/android/key.properties && echo OK || echo "MISSING — prod would use the dev key"
> ```

### The committed dev keystore

`app/android/key-dev.properties` and `app/android/keystore-dev.jks` are **tracked in git** so a fresh clone builds and runs without any setup. That is deliberate for a template, and fine for `dev`.

> [!CAUTION]
> **Never ship a production release with the dev keystore.** It is public in the repository — anyone who clones it can sign an APK that the OS treats as an update to yours.

Generate your own release key:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `app/android/key.properties` (already covered by `.gitignore`):

```properties
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Keep the `.jks` outside the repository, and back it up somewhere durable — losing it means you can never publish an update to that Play listing again.

---

## 5. Bundle IDs

`helpers.rb` derives the bundle ID by appending a flavor suffix, and the suffixes match Gradle exactly:

```ruby
def get_bundle_id_with_suffix(base_bundle_id, flavor)
  return base_bundle_id if flavor.nil? || flavor.empty?
  case flavor
  when 'dev' then "#{base_bundle_id}.dev"
  when 'staging' then "#{base_bundle_id}.stg"
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

| Flavor | Gradle `applicationIdSuffix` | Fastlane bundle ID | Agree |
|:---|:---|:---|:---|
| `dev` | `.dev` | `<base>.dev` | ✅ |
| `staging` | `.stg` | `<base>.stg` | ✅ |
| `prod` | *(none)* | `<base>` | ✅ |

> [!NOTE]
> These two lists are maintained independently and nothing checks that they agree. If Fastlane computed `.staging` while Gradle produced `.stg`, a staging upload would look up a Play listing that does not match the artifact. If you add a flavor, change **both** sides in the same commit.

---

## 6. Flavors and env files

| Flavor | applicationId suffix | dart-define file expected by Fastlane | Present |
|:---|:---|:---|:---|
| `dev` | `.dev` | `app/env.dev` | ✅ |
| `staging` | `.stg` | `app/env.stg` | ✅ |
| `prod` | *(none)* | `app/env.prod` | ❌ **you must create it** |

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

and refuses to build when that file is missing:

```ruby
unless File.exist?("../#{dart_define_file}")
  UI.user_error!(
    "Dart define file 'app/#{dart_define_file}' not found for flavor "     "'#{flavor}'. Building without it would ship empty "     "String.fromEnvironment values (API base URL, keys), so this is "     "a hard failure. Create the file first."
  )
end
build_command += " --dart-define-from-file=#{dart_define_file}"
```

> [!IMPORTANT]
> **A prod release cannot be built until you create `app/env.prod`.** That is deliberate. The alternative — skipping the flag with a warning — lets a prod build *succeed* with every `String.fromEnvironment` in `packages/core/common/lib/src/utils/env_constants.dart` falling back to empty, producing an APK that points at empty API URLs and empty keys, signed and shipped with no warning. Failing loudly is the safer trade.
>
> Copy the key names from `app/env.dev`; `.vscode/launch.json` already points its Prod configuration at `env.prod`.

> [!WARNING]
> `.gitignore`'s `*.env` pattern does **not** match `env.dev` / `env.stg` / `env.prod` — the dot is on the wrong side — which is why `env.dev` and `env.stg` are currently tracked in git. Add explicit entries before putting real credentials in `env.prod`.

---

## 7. Toolchain setup inside a lane

Unless you pass `skip_setup:true`, every lane calls `setup_flutter_environment`, which either switches the system Flutter to stable and upgrades it, or activates `fvm` and pins the requested version. It then runs `install_dependencies`:

```ruby
sh "#{prefix}dart pub global activate flutterfire_cli"
sh "#{prefix}dart pub global activate flutter_gen"
sh "#{prefix}flutter clean"
sh "#{prefix}flutter pub get"
# ...then flutter gen-l10n for every packages/**/l10n.yaml
sh "#{prefix}dart run build_runner build -d --workspace"
```


Because this runs `flutter clean` and a full workspace `build_runner`, it is slow. Use `skip_setup:true` for iterative local builds.

---

## 8. Release procedure

1. **Pick the version.** Decide the `version` (build name). Use `build_number:auto` unless you need a specific code.
2. **Verify signing.** `test -f app/android/key.properties` — see the [§4](#4-signing) caution.
3. **Verify the env file exists for the flavor** — see [§6](#6-flavors-and-env-files). For prod you must create `app/env.prod` first; the lane hard-fails without it.
4. **Confirm `Config.yaml` is filled in**, particularly `firebase.app_ids`, `app_store_connect.apple_ids` and the credential paths.
5. **Dry run locally**, no distribution:
   ```bash
   fastlane android build flavor:prod build_type:aab \
     distribute_store:false distribute_firebase:false skip_setup:true
   ```
6. **Ship it.**
   ```bash
   # Testers first
   fastlane android build flavor:prod build_type:apk distribute_firebase:true \
     version:1.2.0 build_number:auto change_log:"…"

   # Then the stores
   fastlane store version:1.2.0 build_number:auto track:internal
   ```
7. **Promote** from `internal` to `production` in the Play Console once validated. The lane uploads with `release_status: 'draft'`, so nothing goes live without an explicit promotion.

### Pre-release checklist

- [ ] `app/android/key.properties` exists and points at your **release** keystore
- [ ] Release keystore is backed up outside the repository
- [ ] Env file for the target flavor exists (`app/env.prod` for prod — see [§6](#6-flavors-and-env-files))
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
- If `flutter build ipa` archives successfully but export fails, it retries `xcrun xcodebuild -exportArchive` up to three times.
- `distribute_to_app_store` bypasses Fastlane's `upload_to_testflight` and calls `xcrun altool --upload-app` directly, with a comment noting Fastlane's altool wrapper has compatibility problems with Xcode 26.

What is **not** wired up:

- iOS build and distribute steps in `azure-ci-cd.yml` are fully commented out.
- The iOS build in `.github/workflows/flutter_build.yml` is commented out; only Android is built and distributed.
- iOS builds require macOS, so the `self-hosted` option in `fastlane.yml` must actually be a Mac.

---

## See also

- [`01_cicd.md`](01_cicd.md) — pipelines, secrets, and the defects listed there
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — flavors, env files, Firebase bootstrap
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — the `tools/` scripts Fastlane invokes
