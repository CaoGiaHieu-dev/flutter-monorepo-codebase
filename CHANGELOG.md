# Changelog

All notable changes to this template are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

**Versioning.** The template as a whole follows [Semantic Versioning](https://semver.org/):
a MAJOR bump means a project built on the template must change code or layout to take the update
(a package moved or renamed, a contract changed, a rule tightened so existing code fails a gate);
MINOR adds a capability without breaking what exists; PATCH is fixes and documentation. Releases
are git tags of the form `vX.Y.Z` on `main`, and each one moves the entries below into a dated
section. The `version:` in each app's `pubspec.yaml` is that app's store version and is
independent of the template's.

## [Unreleased]

The first large refactor of the template: a Pub Workspaces monorepo organised by bounded context,
with the architecture rules enforced by CI instead of review alone.

### Added

- `apps/admin`, a second app composing only auth + settings, to prove that modules compose per app.
- `platform_app_shell` (`platform/app_shell`): boot, dynamic router, material wrapper, storage
  adapters and `NetworkConfigImpl`, shared by every app instead of copied into each.
- `platform_kernel` (`platform/kernel`): a pure-Dart foundation (`getIt` helpers,
  `ErrorHandler`, `AppException`, extensions) that non-Flutter packages depend on.
- Composer: each app is generated from `apps/<id>/app_manifest.yaml` (`composer sync`,
  `composer verify`), plus `tools/composer/bootstrap.dart` for partial checkouts.
- Sample management: `tools/sample_manifest.yaml` and `tools/sample_cleanup/remove_sample.dart`
  delete a sample bundle safely.
- CI merge gate `pr_quality_check.yml`: composer verify, `arch_check` (rules R1–R10, including
  R8 optional contract lookup and R10 app-level removability), analyze, per-package tests,
  catalog sync, `docs_check`, an unused-dependency advisory, and a debug APK build job.
- `core_responsive`: window size classes and breakpoints, a per-window-class scale policy
  (down by default, up on opt-in), and adaptive widgets (`AdaptiveLayout`, `AdaptiveSplitView`,
  `AdaptiveContent`, fold postures).
- `DisposeGuard` mixin; `DefaultLoadingWidget` / `DefaultEmptyWidget` in
  `provider_state_management`.
- Bilingual documentation hub (`docs/en`, `docs/vi`) grouped as getting-started, architecture,
  guides, reference and operations; English + Vietnamese READMEs for the state-management,
  responsive and tooling packages; agent skills under `.agents/skills/`.
- Tests in 16 packages; the Plus Jakarta Sans font bundled so bold text uses the bold face.

### Changed

- Repository layout: `packages/core/*` → `platform/*`, product packages → vertical slices
  `modules/<name>/{domain,data,feature}`, `app/` → `apps/mobile/` (package `mobile_app`).
- Flutter 3.47 / Dart 3.13 toolchain, pinned in `.fvmrc`; FVM is optional everywhere.
- `core_database` and `core_storage` are mechanism only: each package owns its own Drift database
  and its own storage keys. The Drift cache example moved to the `cache` sample module.
- `core_di` contracts carry their own value types (`AuthPrincipal`) instead of domain entities;
  domain packages depend only on `domain_core`, and `AppFailure` lives there.
- Every module is removable: the shell reaches features only through `core_di` contracts with
  `getItOrNull` / `getAllOrEmpty` fallbacks.
- Each app owns its Firebase configuration; tools take `--app` instead of assuming one app.
- Sample code trimmed to what teaches the patterns (single-screen auth; the language
  domain/data packages removed); unused utilities, colour slots and assets dropped.
- The workspace `pubspec.lock` is committed and enforced in CI; versions come from the
  `pubspec_dependencies.yaml` catalog.
- Fastlane runs through Bundler, from the repository root or `apps/mobile`.
- `data_core` no longer depends on Flutter.

### Fixed

- Networking: token-refresh deadlocks and recursion (a `401` from login or refresh no longer
  starts a refresh; a late `401` for an old token replays), and retry/refresh failures reported
  accurately to the UI.
- Boot: TLS overrides installed before the first widget; returning users skip onboarding; the
  route observer is attached; boot crashes in apps without onboarding or home.
- Storage: no key wipe on first launch or on a transient secure-store error.
- Database: the cache database opens after its own migrations register; read-pool connections
  get a busy timeout.
- UI: dark-mode colours in `ui_kit`, theme text scaling, split-view overflow, responsive edge cases.
- Tooling: dozens of silent failures, hangs and hazards across the module generator, composer,
  `dependency_sync`, `docs_check`, the unused checker and Fastlane lanes; tool output in English.
- Stopped tracking 163 MB of build output.

### Security

- Certificate validation is bypassed only in a debug build that explicitly declared
  `--flavor dev`; a missing or unknown flavor is treated as prod.
- `SslPinningConfig` is bound in its own right, so pinning no longer silently no-ops once hashes
  are configured.
- `LoggingInterceptor` redacts credentials in bodies as well as headers and logs only in debug.
- The AI code-review tool sends the Gemini key in a header, redacts it from errors, and stores
  it in a gitignored file instead of tracked config.
- Release keystores, `key*.properties` (except the public dev key) and `env.prod` are ignored by
  broad patterns; see [SECURITY.md](SECURITY.md).

[Unreleased]: https://github.com/CaoGiaHieu-dev/flutter-monorepo-codebase/commits/main
