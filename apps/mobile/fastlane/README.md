# CI/CD Documentation
Full CI/CD and release documentation: [**docs/en/operations/02_fastlane_release.md**](../../../docs/en/operations/02_fastlane_release.md) (Tiếng Việt: [docs/vi/operations/02_fastlane_release.md](../../../docs/vi/operations/02_fastlane_release.md))

---

# Installation

Make sure you have the latest version of the Xcode command line tools installed (iOS builds only):

```sh
xcode-select --install
```

Install the gems once, from the repository root or from `apps/mobile/` — both Gemfiles list the same gems and load the plugins from `fastlane/Pluginfile` here:

```sh
bundle install
```

Then copy `Config.example.yaml` to `Config.yaml` in this folder and fill it in. Every lane runs identically from the repository root and from `apps/mobile/`. Pass every parameter on the command line in CI: without a terminal an omitted one takes its default (distribution: off) and an omitted `flavor:` stops the lane.

# Available Actions

### flutter

```sh
bundle exec fastlane flutter
```

Build both platforms (iOS, then Android) with one set of inputs. Needs macOS.

### store

```sh
bundle exec fastlane store
```

Prod release of both platforms to TestFlight and Google Play. Needs macOS.

----


## iOS

Every iOS lane needs macOS with Xcode; elsewhere it stops at once with an error saying so.

### ios build

```sh
bundle exec fastlane ios build
```

Build and distribute iOS app (interactive)

### ios upload

```sh
bundle exec fastlane ios upload
```

Upload existing IPA to store (skip build)

### ios store

```sh
bundle exec fastlane ios store
```

Build and distribute iOS app to TestFlight (Prod flavor)

----


## Android

### android build

```sh
bundle exec fastlane android build
```

Build and distribute Android app (interactive)

### android upload

```sh
bundle exec fastlane android upload
```

Upload existing artifact to store (skip build)

### android store

```sh
bundle exec fastlane android store
```

Build and distribute Android app to Play Store (Prod flavor, AAB)

----

This README.md is maintained by hand. Both Fastfiles set `FASTLANE_SKIP_DOCS`, so fastlane no longer regenerates it after a run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).
