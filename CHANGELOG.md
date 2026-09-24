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
- `platform_app_shell` (`platform/shell/app_shell`): boot, dynamic router, material wrapper and
  app state, shared by every app instead of copied into each; its storage adapters and
  `NetworkConfigImpl` live beside it in `platform_shell_adapters` (`platform/shell/adapters`).
- `platform_kernel` (`platform/foundation/kernel`): a pure-Dart foundation (`getIt` helpers,
  `ErrorHandler`, `AppException`, extensions) that non-Flutter packages depend on.
- Composer: each app is generated from `apps/<id>/app_manifest.yaml` (`composer sync`,
  `composer verify`), plus `tools/composer/bootstrap.dart` for partial checkouts.
- Sample management: `tools/sample_manifest.yaml` and `tools/sample_cleanup/remove_sample.dart`
  delete a sample bundle safely — keeping a module API package that another package still
  imports, and saying so.
- Module API packages, `modules/<id>/api` → `<id>_api`: a module's contracts for other features
  (`auth_api`: `AuthNavigator`, `IAuthActionHandler`; `home_api`: `HomeNavigator`). Composed as
  the manifest layer `api` — a workspace member with no DI group and no app dependency.
- `core_di` location contracts `ISignInLocation` / `IPostSignInLocation`: where the app shell
  sends a signed-out / signed-in user (contributed by `feature_auth` / `feature_home`; with none,
  no sign-in redirect / `AppRouter.fallbackLocation`).
- `arch_check` **R11** — platform group direction, read from `platform/<group>/<package>`,
  `dependencies:` only; R3 extended to module API packages (foundation + Flutter only; features
  may import another module's API, never its feature), R1/R8/R10 cover them too.
- CI merge gate `pr_quality_check.yml`: composer verify, `arch_check` (rules R1–R15, including
  R8 optional contract lookup, R10 app-level removability and R11 platform group direction),
  analyze, per-package tests,
  catalog sync, `docs_check`, an unused-dependency advisory, and a debug APK build job.
- `core_responsive`: window size classes and breakpoints, a per-window-class scale policy
  (down by default, up on opt-in), and adaptive widgets (`AdaptiveLayout`, `AdaptiveSplitView`,
  `AdaptiveContent`, fold postures).
- `DisposeGuard` mixin; `DefaultLoadingWidget` / `DefaultEmptyWidget` in
  `provider_state_management`.
- Bilingual documentation hub (`docs/en`, `docs/vi`) grouped as getting-started, architecture,
  guides, reference and operations; English + Vietnamese READMEs for the state-management,
  responsive and tooling packages; agent skills under `.claude/skills/`.
- Tests in 16 packages; the Plus Jakarta Sans font bundled so bold text uses the bold face.

### Changed

- Documentation restructure: `docs/en/reference/01_rules.md` (and its `docs/vi` twin) is now the
  single rule registry — 65 rules with stable ids `RULE-01`…`RULE-79`, each with its reason, what
  enforces it (`arch_check` R1–R15, analyzer, a test, a CI gate, `composer verify`, `docs_check` or
  review) and a command to verify it. New rules for testing, logging, error reporting and
  accessibility. Every other document cites ids instead of restating rules, and `docs_check`
  fails on an undefined id. Drift fixed on the way: DI ordering is proven by each app's
  `test/di_smoke_test.dart` (CI Gate 3), not by reading `injection.config.dart`; navigators and
  action handlers live in the owning module's `<id>_api`, not `core_di`; the BLoC branch has
  `emitResult`.
- `CLAUDE.md` is a ~200-line agent brief (was 938 lines) — top rules by id first, layout,
  essential commands, where to look; `.agents/AGENTS.md` is a short pointer for other AI tools.
- Agent skills moved from .agents/skills/ to `.claude/skills/`, where Claude Code discovers
  them; every description starts with "Use when…", each skill links its guide and cites rule ids;
  `run_ai_code_review`, `run_barrel_generator`, `run_dependency_sync` and `run_unused_checker`
  merged into `run_repo_tooling`.
- The documentation contract moved to `CONTRIBUTING.md` § 5; the restructure runbook moved from
  .agents/RESTRUCTURE.md to `docs/history/restructure-log.md`.
- `tools/code_review/review_prompt.md` checks against the registry (ids + one-liners), now
  including BLoC, database, optional lookups, ARB casing, double-wrapping, accessibility and testing.

- Repository layout: `packages/core/*` → `platform/*`, product packages → vertical slices
  `modules/<name>/{domain,data,feature}`, `app/` → `apps/mobile/` (package `mobile_app`).
- `platform/` regrouped into six role folders — `foundation/` (`kernel`, `contracts` = `core_di`,
  `common`), `layers/` (`domain` = `domain_core`, `data` = `data_core`), `infra/` (`network`,
  `storage`, `database`, `notifications`), `ui/` (`responsive`, `design_system` = `core_base_ui`,
  `ui_kit`), `state/` (`provider`, `bloc` = the two `*_state_management` packages) and `shell/`
  (`app_shell`). Package names are unchanged, so imports and manifests are untouched; a fork
  updates its own relative `path:` dependencies and any hard-coded `platform/<pkg>` path.
  `module_generator` types 4/5 take `--group` (default `infra`). The allowed direction between
  groups is documented in `docs/en/architecture/02_core.md` § 0 and enforced by `arch_check` R11.
- The platform package graph now follows that group direction with no exception (stage 2):
  `LoadMoreListView` / `LoadingMoreWidget` moved from `core_ui_kit` to
  `provider_state_management` (`core_ui_kit` no longer depends on a state package);
  `BottomTransitionPage` moved from `core_common` to `core_ui_kit` (`navigation/`), and
  `AppInitializer`'s portrait threshold became a private constant, so `core_common` no longer
  depends on `core_responsive`; `core_storage` depends on `platform_kernel` instead of
  `core_common`; `data_auth` drops its unused `flutter` dependency. Imports through the package
  barrels resolve unchanged except for code that imported these two widgets' old file paths.
- `ErrorHandler` (`platform_kernel`) no longer imports Dio. The `DioException` → `AppFailure`
  mapping moved, unchanged, to `core_network`'s `DioFailureClassifier`, which registers itself
  through the new `ErrorClassifier` / `ErrorHandler.registerClassifier` seam while the `core` DI
  group initialises. A unit test that classifies `DioException`s without running DI must call
  `DioFailureClassifier.ensureRegistered()` first.
- `platform_app_shell` split (stage 3): its infrastructure adapters — `NetworkConfigImpl`,
  `NetworkBindingModule`, `LanguageStorageImpl`, `ThemeStorageImpl`, `AppBootStorage` and their
  storage-key classes — moved to the new `platform_shell_adapters` (`platform/shell/adapters`),
  listed first in every app's `shell` DI group. `platform_app_shell` keeps boot, router,
  wrappers and app state, and depends on the adapters. Storage keys are unchanged, so stored
  values survive the update. A fork adds `platform_shell_adapters` to the `shell` group of each
  `app_manifest.yaml` and runs `composer sync`.
- Flutter 3.47 / Dart 3.13 toolchain, pinned in `.fvmrc`; FVM is optional everywhere.
- `core_database` and `core_storage` are mechanism only: each package owns its own Drift database
  and its own storage keys. The Drift cache example moved to the `cache` sample module.
- `core_di` contracts carry their own value types (`SessionPrincipal`) instead of domain entities;
  domain packages depend only on `domain_core`, and `AppFailure` lives there.
- **Breaking — the shell no longer knows the auth/home flow (stage 4).** The shell-facing
  contracts in `core_di` are product-neutral and renamed, semantics unchanged: `AuthPrincipal` →
  `SessionPrincipal`, `IAuthStatusStream` → `ISessionStatusStream` (`authStatusStream` →
  `sessionStatusStream`), `IAuthSessionState` → `ISessionState`, `AuthSessionFailure` →
  `SessionFailure` (variants `Session{InvalidCredentials,UserNotFound,Server,Unknown}Failure`),
  `IAuthRefreshListenable` → `ISessionRefreshListenable`, `IAuthSessionGateway` →
  `ISessionGateway`; they moved from `lib/src/agnostic_streams/` to `lib/src/session/`.
  `NavigatorWrapperWidget` routes through `ISignInLocation` / `IPostSignInLocation` instead of
  `AuthNavigator` / `HomeNavigator`. `AuthNavigator`, `IAuthActionHandler` and `HomeNavigator`
  left `core_di` for `auth_api` / `home_api`: a fork renames the session types, adds `<id>_api`
  to each consumer's `dependencies:` and imports it, and adds `api` to the module's `layers:` in
  every `app_manifest.yaml`.
- Every module is removable: the shell reaches features only through `core_di` contracts with
  `getItOrNull` / `getAllOrEmpty` fallbacks.
- Each app owns its Firebase configuration; tools take `--app` instead of assuming one app.
- Sample code trimmed to what teaches the patterns (single-screen auth; the language
  domain/data packages removed); unused utilities, colour slots and assets dropped.
- The workspace `pubspec.lock` is committed and enforced in CI; versions come from the
  `pubspec_dependencies.yaml` catalog.
- Fastlane runs through Bundler, from the repository root or `apps/mobile`.
- `data_core` no longer depends on Flutter.
- The analyzer runs strict: `strict-casts`, `strict-inference` and `strict-raw-types`, plus
  `unawaited_futures`, `cancel_subscriptions`, `close_sinks`, `avoid_dynamic_calls` and
  `empty_catches` (`analysis_options.yaml`, whose header now explains each). Code built on the
  template may need explicit type arguments and casts to pass Gate 2. The phantom type parameter
  of `InitialWidgetBuilder` / `LoadingWidgetBuilder` / `EmptyWidgetBuilder` is gone, and
  `CustomButton`'s `T` is bounded by `Object?` so plain buttons need no type argument.
- `flutter_secure_storage` 10.3.1 → 11.2.0 (`flutter_secure_storage_darwin` 0.4.x: iOS 13+,
  Android minSdk 24). Values written by 10.x are read unchanged — same pinned RSA-OAEP + AES-GCM
  pair; see `docs/en/guides/06_storage.md` § 3 for apps that once shipped 9.x.

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
