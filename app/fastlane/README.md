# CI/CD Documentation
Để xem tài liệu chi tiết về hệ thống CI/CD, vui lòng truy cập: [**docs/FASTLANE_GUIDE.md**](../docs/FASTLANE_GUIDE.md)

---

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### flutter

```sh
[bundle exec] fastlane flutter
```



### store

```sh
[bundle exec] fastlane store
```



----


## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build and distribute iOS app (interactive)

### ios store

```sh
[bundle exec] fastlane ios store
```

Build and distribute iOS app to TestFlight (Prod flavor)

----


## Android

### android build

```sh
[bundle exec] fastlane android build
```

Build and distribute Android app (interactive)

### android store

```sh
[bundle exec] fastlane android store
```

Build and distribute Android app to Play Store (Prod flavor, AAB)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
