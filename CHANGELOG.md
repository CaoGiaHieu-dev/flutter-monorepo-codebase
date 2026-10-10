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
apps composed from a manifest, and the architecture rules enforced by CI instead of review alone.
The step-by-step record of how it got here is `docs/history/restructure-log.md`.

### Added

- A signed-in user whose session expires sees a translated "session expired" toast (`SessionExpiredFailure`, the global key `sessionExpired`, en and vi); the Settings theme row shows the current mode.
- Tests: database upgrades in `modules/cache/data` and `core_database`, a palette contrast test, the modal overlay and the shared widgets' states, and the notification permission flow.
- **`composer reconcile`** declares `absent` every optional capability whose last provider is gone (the V3 scan, not a list); `remove_sample --apply` runs it and then `sync`, so `composer verify` stays green for every bundle and for all bundles together. A fully stripped template keeps `modules/.gitkeep`.
- **V15 checks native flavors.** On a committed Android or iOS runner it requires a `productFlavor` per declared flavor and an Xcode scheme plus `Debug-`/`Release-`/`Profile-<flavor>` configurations; the failure names the flavor and the recipe in guide 13.
- **CI `generator-smoke-compose`** generates a Provider feature, its API package, a domain/data pair and a new app with `composer new`, then holds them to verify, analyze, arch_check, the new tests and the apps' DI smoke tests.
- Docs: a "native flavors for a new mobile runner" recipe, "a fully stripped template" section, "what you will see on the first run" and the sample sign-in contract (en and vi).
- Docs: the "make it yours" rename and placeholder checklist (`01_setup` § 8), the first-feature tutorial (`04_first_feature_tutorial`, a module end to end) and the iOS `CFBundleLocalizations` step for a new locale (guide 09).
- **`NetworkProfile.authorizedHosts`** (hosts besides the API base URL that may receive the bearer token, default none), **`NetworkConstants.EXTRA_IDEMPOTENT`** (opt a POST or PATCH into replay after a timeout) and `runBootFailure` / `bootFailureCode` (the boot failure screen, code `B01`).
- **`arch_check` R21** holds every ARB to the keys of `en.arb` in `lowerCamelCase` (RULE-34, RULE-35); `composer verify` V13 also fails on code outside the two generated regions of `lib/di/injection.dart`.
- `ExportOptions.example.plist` for the iOS lanes (`apps/mobile/fastlane/`) and admin launch configurations in `.vscode/launch.json`.
- Tests for `check_unused_assets`, `check_unused_translate` and `check_script`, rendered-output tests for the module generator, and a CI generator smoke that also covers a feature without state management or route, a data package without a domain, and core and custom packages.
- Tests for the lifecycle and network mixins, `BaseViewWidget`, `UndefinedRouteWidget`, `TextScaleDown`, `BottomTransitionPage`, `BaseUseCase`, `ErrorClassifier`, `TypeHelper`, `EncryptedStorage` and the `GoRouteDataCustom` pages; the app profile tests read the display name from the manifest.
- **Apps layer.** Every app is `apps/<id>/`: an `app_manifest.yaml` (manifest v2) that says what the
  app is — `app.name`, `flavors` (with an `ssl_pinning` decision per flavor: `pins` or `disabled`
  with a reason), `env` keys, `platforms` (`runner: committed | scaffold`, plus `splash`, `push`,
  `deep_links`, `orientation`, `window`), `capabilities` (every optional contract the shell resolves
  is `provided` or `absent` with a reason) and a `why` per DI group — and what it composes. From it
  `composer sync` generates the root `workspace:` list, the app's path dependencies, the `imports` and
  `modules` regions of `lib/di/injection.dart`, the `facts` region of `lib/app/app_profile.dart` and a `report` region in the
  app's `README.md`. `apps/mobile` and `apps/admin` (auth + settings only, to prove that modules compose
  per app) are the two shipped apps.
- `AppProfile` / `AppFacts` in `platform_kernel` and typed tuning in each app's `lib/app/app_profile.dart`:
  `display` (`DisplayProfile`: design artboard, scale policy per window class, the OS font-size cap),
  `router` (`RouterProfile`: `EntryPolicy`, fallback path), `locale` (`LocaleProfile`, `LanguageSet`),
  `theme` (`ThemeProfile`: first-launch mode, palette overrides) and `network` (`NetworkProfile`:
  timeouts, headers, redirects). `ShellHooks` in `lib/app/app_hooks.dart` (`onError`, `onNonFatalError`,
  `beforeDependencies`, `afterBoot`, `navigatorObservers`, `redirect`, `configureWindow`);
  `runShellApp(profile:, hooks:, configureDependencies:)` boots it, and an app started on a platform or
  flavor its manifest does not declare stops at a boot-error screen before dependency injection
  (problems `P01`–`P05`).
- The shell contract catalog `SHELL_CONTRACTS` (`platform_app_shell`; 21 rows, 7 required and 14
  optional) and `checkAppContract` (problems `C01`–`C12`), which each app's DI smoke test runs for
  every declared flavor.
- `composer describe [--app <id>] [--catalog]` prints an app's report or every manifest key, shell
  contract and check; `composer new <id> --platforms <a,b> [--modules <x,y>]` renders
  `tools/composer/app_template/` into a whole new app (manifest, profile, hooks, entry point, smoke and
  profile tests), derives its `capabilities:` and runs `sync` and `verify`, never `flutter create`;
  `composer list`; `tools/composer/bootstrap.dart` for partial checkouts.
- Rules RULE-80 (everything per-app is declared in `apps/<id>/`), RULE-81 (every optional shell contract
  has a declared state) and RULE-82 (a platform difference is an app decision), and `arch_check` **R16**
  (the shell catalog is complete) and **R17** (platform forks only in an allow-list, each with a reason).
  Guide `docs/en/guides/13_app_composition.md` and skill `configure_app`.
- Module API packages, `modules/<id>/api` → `<id>_api`: a module's contracts for other features
  (`auth_api`: `AuthNavigator`, `IAuthActionHandler`; `home_api`: `HomeNavigator`), composed as the
  manifest layer `api` — a workspace member with no DI group and no app dependency.
  `generate.dart 6 <name>` creates one.
- Session and location contracts in `core_di`: `ISessionState`, `ISessionStatusStream`,
  `ISessionRefreshListenable`, `ISessionGateway`, `SessionPrincipal`, and `ISignInLocation` /
  `IPostSignInLocation` — where the shell sends a signed-out / signed-in user (contributed by
  `feature_auth` / `feature_home`; with none, no sign-in redirect / `AppRouter.fallbackLocation`).
- `platform_app_shell` (`platform/shell/app_shell`: boot, router, material wrapper, app state) and
  `platform_shell_adapters` (`platform/shell/adapters`: storage adapters, `NetworkConfigImpl`), shared by
  every app instead of copied into each; `platform_kernel` (`platform/foundation/kernel`), a pure-Dart
  foundation (`getIt` helpers, `ErrorHandler`, `AppException`, extensions).
- Sample management: `tools/sample_manifest.yaml` and `tools/sample_cleanup/remove_sample.dart` delete a
  sample bundle safely — keeping a module API package another package still imports, and saying so —
  and run `composer sync` after `--apply`.
- **Gates, hardened.** `arch_check` rules R1–R21 are all blocking: **R11** platform group direction;
  **R18** `on<Event>` handlers are `async`; **R19** no `print` / `debugPrint` in `lib/`; **R20** no raw
  numeric literal in layout and paint constructors; R1–R3, R5, R9 and R10 read imports with a lexer,
  classify a package by its workspace location, and also hold `dev_dependencies:` and test imports;
  R7 and R8 read every `lib/` file and every spelling of a `getIt` lookup. `composer verify` fails on drift
  in any generated region, on a package under `modules/` or `platform/` that no app composes, on a
  second `workspace:` node (V17) and on a smoke test that does not build every factory (V12).
  `dependency_sync --check` also fails on a hosted dependency missing from the catalog.
  `pr_quality_check.yml` gains a barrel-drift step (RULE-75), a blocking unused-dependency audit
  (RULE-06), a generator smoke job and an advisory coverage report. Each app's DI smoke test builds every
  lazy singleton and every `@injectable` factory, one by one, and names the one that fails.
- `core_responsive`: window size classes and breakpoints, a per-window-class scale policy (down by
  default, up on opt-in), and adaptive widgets (`AdaptiveLayout`, `AdaptiveSplitView`, `AdaptiveContent`,
  fold postures).
- `AppLocalizations.failureMessage(code)` (`core_base_ui`) words a failure by its code for the user;
  `DisposeGuard`, `DefaultLoadingWidget` / `DefaultEmptyWidget` in `provider_state_management`.
- Bilingual documentation hub (`docs/en`, `docs/vi`) grouped as getting-started, architecture, guides,
  reference and operations, with a rule registry (68 rules, `RULE-01`…`RULE-82`); English + Vietnamese
  READMEs for the state-management, responsive, ui_kit and tooling packages; agent skills under
  `.claude/skills/`; `docs_check` (paths, en↔vi parity, RULE-ID citations, translation stamps).
- Tests across the platform, module and app packages and for the gate tools in `tools/test/`; the Plus
  Jakarta Sans font bundled so bold text uses the bold face.

### Changed

- Lock files (`pubspec.lock`, `Gemfile.lock`, `Podfile.lock`) are git-ignored and no longer committed; CI resolves with plain `flutter pub get`.
- `composer` with no command exits 64; its help lists V13, V15, V16 and V17; `16kb_check.sh` exits 1 when `zipalign` verification fails.
- CI workflows run with `contents: read`; the fastlane workflow reads the Flutter version from `.fvmrc`; `code_review` defaults to English with no author in the footer.
- Generated package descriptions say what the layer is, and five shipped pubspecs got real descriptions; the freezed constraint is `^4.0.1`; `LoadMoreListView` takes its spinner padding from `AppSpacing`.
- **Layout.** `packages/core/*` → `platform/*`, product packages → vertical slices
  `modules/<name>/{api,domain,data,feature}`, `app/` → `apps/mobile/` (package `mobile_app`).
  `platform/` is regrouped into six role folders — `foundation/` (`kernel`, `contracts` = `core_di`,
  `common`), `layers/` (`domain` = `domain_core`, `data` = `data_core`), `infra/` (`network`, `storage`,
  `database`, `notifications`), `ui/` (`responsive`, `design_system` = `core_base_ui`, `ui_kit`), `state/`
  (`provider`, `bloc` = the two `*_state_management` packages) and `shell/` (`adapters`, `app_shell`).
  Package names are unchanged; a fork updates its own relative `path:` dependencies and any hard-coded
  `platform/<pkg>` path. `module_generator` types 4/5 take `--group` (default `infra`); the direction
  between groups is `docs/en/architecture/02_core.md` § 0 and `arch_check` R11. Core packages follow that
  direction with no exception: `LoadMoreListView` moved to `provider_state_management`,
  `BottomTransitionPage` to `core_ui_kit`, `core_storage` depends on `platform_kernel`, `core_common` no
  longer on `core_responsive`.
- **One barrel per package**: `lib/<package_name>.dart`, regenerated by
  `dart tools/barrel_generator/generate.dart <package>/lib`, which exports every library file under
  `lib/` and deletes directory barrels and hand-added exports. Inside a package files import concrete
  files, never a barrel. There is no `lib/src/src.dart` and no `lib/src/gen/gen.dart`; setup is
  `pub get`, `gen-l10n`, `build_runner` and the barrel pass (`configure.dart`).
- **Breaking, for forks of the template — the shell no longer knows the auth/home flow.** The shell-facing
  contracts in `core_di` are product-neutral and renamed: `AuthPrincipal` → `SessionPrincipal`,
  `IAuthStatusStream` → `ISessionStatusStream`, `IAuthSessionState` → `ISessionState`,
  `AuthSessionFailure` → `SessionFailure`, `IAuthRefreshListenable` → `ISessionRefreshListenable`,
  `IAuthSessionGateway` → `ISessionGateway`. `NavigatorWrapperWidget` routes through `ISignInLocation` /
  `IPostSignInLocation`. `AuthNavigator`, `IAuthActionHandler` and `HomeNavigator` left `core_di` for
  `auth_api` / `home_api`: a fork renames the session types, adds `<id>_api` to each consumer's
  `dependencies:` and adds `api` to the module's `layers:` in every `app_manifest.yaml`.
- **Breaking, for forks — the app declares itself.** `runShellApp` requires `profile:` and no longer takes
  `onError:` (pass `hooks: ShellHooks(onError: ...)`); `app.kind` is refused and `app.name`, `flavors`,
  `platforms` and `capabilities` are required in every manifest (`composer verify` prints the YAML to
  paste). `AppShellUiConstants` is gone (the cap is `DisplayProfile.textScaleMax`);
  `BaseUiConstants.FALLBACK_LANGUAGE_CODE` and the `NetworkConstants` timeouts moved to `LocaleProfile`
  and `NetworkProfile`; `ThemeSystemExtension.withMode` is replaced by `ThemeProvider.paletteFor`.
  `AppInitializer.initBeforeRunApp` and `init` require `platform` and `flavor`. `APP_NAME` is not
  `required_in`: the title falls back to `app.name`. A non-debug build with an empty required
  `--dart-define` stops at the boot-error screen.
- **Breaking, for forks — certificate pinning.** The decision is the app's, per flavor
  (`flavors.<f>.ssl_pinning`), installed by `AppInitializer` from the profile before dependency injection
  starts; the `SslPinningConfig` supertype, its `@module` binding and `NetworkConfig.sslPinningHashes`
  are gone, so a missing registration can no longer switch pinning off. The template ships a stated
  placeholder decision for staging and prod, listed under *decisions to revisit* in each app's report.
- `ErrorHandler` (`platform_kernel`) no longer imports Dio: the `DioException` → `AppFailure` mapping is
  `core_network`'s `DioFailureClassifier`, registered through `ErrorClassifier` /
  `ErrorHandler.registerClassifier` while the `core` DI group initialises. `AppFailure.message` is an
  English diagnostic, never shown to users — the UI words a failure by its code.
- `core_database` and `core_storage` are mechanism only: each package owns its own Drift database and its
  own storage keys. `core_storage` writes are serialized and logged (`StorageValue.save` returns
  `Future<void>`, `delete()` became `remove()`), with one encryption base, `EncryptedStorage`.
- `core_di` contracts carry their own value types (`SessionPrincipal`) instead of domain entities; domain
  packages depend only on `domain_core` and their own module's domain, and `AppFailure` lives in
  `domain_core`. `data_core` no longer depends on Flutter.
- Design system: one palette-built `ColorScheme` (every slot), one language source (`AppLanguages`),
  shadow and scrim tokens; the dialog and overlay systems merged into `AppOverlay` in `core_ui_kit`;
  `CustomButton` is rectangle-only and non-generic; default design size 375×812.
- App shell internals: `lib/src/` layout, `AppRouter.destinations` computed once,
  `IDashboardRouteModule.builder` takes the destinations, `AppBootStorage.viewedOnboard`. Notifications:
  the permission prompt is opt-in (`PushNotificationService.requestPermission()`) and the background
  handler initialises Firebase without DI.
- `DioFailureClassifier` maps an unknown error caused by bad JSON to `ParseFailure` and one caused by a TLS error or a pin mismatch to a certificate failure (`BAD_CERTIFICATE`) that the retry policy does not retry.
- Samples follow the rules they teach: a simpler auth sample (a `session/` folder for its session
  contributions), `lib/di/` holds the DI module only, settings reads `LanguageProvider` /
  `ThemeProvider` from the tree, the module generator's templates match.
- The sample modules are much smaller (`modules/*/{api,domain,data,feature}/lib`, without generated
  files and barrels, about 2,640 → 1,720 lines; their tests about 3,750 → 1,310): auth is one login use case, a token-only local data source and one inline
  login form (ARB keys 13 → 5); the splash is a logo and a spinner with no strings; onboarding keeps one
  route-module file; `domain_cache` is an entity and a repository contract; the cache database tests are
  one old-file upgrade test and one repository round trip; the Home title, the settings row icons and
  the dashboard's RTL special case are gone; a 404 on sign-in is a server failure with its code
  (`SessionServerFailure`); an app started offline opens on the login screen (the token stays stored).
- Flutter 3.47 / Dart 3.13 toolchain, pinned in `.fvmrc`; FVM is optional everywhere. Lock files are
  generated and git-ignored (see above); versions come from the `pubspec_dependencies.yaml`
  catalog. Fastlane runs through Bundler, from the repository root or `apps/mobile`.
- The analyzer runs strict: `strict-casts`, `strict-inference` and `strict-raw-types`, plus
  `unawaited_futures`, `cancel_subscriptions`, `close_sinks`, `avoid_dynamic_calls` and `empty_catches`
  (`analysis_options.yaml`, whose header explains each). Code built on the template may need explicit type
  arguments and casts to pass Gate 2.
- `flutter_secure_storage` 10.3.1 → 11.2.0 (iOS 13+, Android minSdk 24). Values written by 10.x are read
  unchanged; an app that once shipped 9.x must ship a 10.x release first — see
  `docs/en/architecture/02_core.md` § 7.
- Tooling: one workspace discovery walk (`tools/shared/workspace.dart`); `unused_checker` has no blanket
  allowlist and does not treat a barrel export as a use; the 16 KB check is `16kb_check.{sh,bat}`; the
  unused root `build.yaml` is gone; `.vscode/launch.json` runs from `apps/mobile`.
- Documentation restructure: `docs/en/reference/01_rules.md` (and its `docs/vi` twin) is the single rule
  registry — every rule once, with its reason, what enforces it and a command to verify it; every other
  document cites ids, and `docs_check` fails on an undefined id. `CLAUDE.md` is a short agent brief and
  `.agents/AGENTS.md` a pointer; skills moved to `.claude/skills/` and merged; the
  documentation contract is `CONTRIBUTING.md` § 5.

### Removed

- Sample code: `UserRole`, `LogoutUseCase`, `RestoreSessionUseCase` with `IAuthRepository.restoreSession`,
  `AuthFormWidget`, `AuthHeaderWidget`, `AuthUiConstants`, `AuthValidationConstants`, the stored user
  (`AuthLocalDataSource.saveUserData` / `getUserData`; `clearAllAuthData` is now `clearUserToken`),
  `isTransientFailure` (now a private `_isTransient` in `AuthSessionGatewayImpl`), the auth ARB keys
  `email`, `password`, `invalidEmail`, `passwordTooShort`, `signInSubtitle`, `showPassword`,
  `hidePassword`, `emailIsRequired` and `passwordIsRequired` (replaced by `fieldRequired`), the splash
  ARBs, `CacheEntryParams` and the cache use cases, `AppGradients.liquidOnboarding` and the
  `liquidOnboardingColors` palette token.
- Dead and duplicated code across the platform packages: `BaseViewWidget2`…`6`, `PaginatedViewWidget`,
  `BaseProxyWidget`, `ErrorStateRegistry`, `AppProvider`, `AppRouter.currentContext` / `push` /
  `replace` / `back`, `ThemeSystemInterface`, the `ContextExtension` getters `core_responsive` already
  answers, `AppDialogController`, `ErrorDialog`, `WarningDialog`, `KeepAliveWidget`, `BaseResult`,
  `ExtraRequest`, `LoadMoreControllerBinding`, `MessageQueue`, `device_info_plus` and other unused
  dependencies (`get_it` from 14 packages, `json_annotation`, `cupertino_icons`), the per-package
  `.gitignore` files, and the language domain/data sample packages.
- The unused `dev/` and `staging/` `MainActivity.kt` files (the manifest resolves `.MainActivity` under the namespace).
- Unread fastlane keys (`app_store_connect.username` / `team_id`, `google_play.account_id`) and the ineffective bundler Dependabot block.
- The unused `package_rename` dev dependency and the unused `APP_ID` Android resource.
- The unused `BottomTransitionPage.useRootNavigator`.

### Fixed

- Gate 5 no longer fails on a fresh checkout: the fastlane guide names the git-ignored `Gemfile.lock` files, which are now allowlisted with a reason.
- The generated feature navigator keeps its imports sorted whatever the feature is called (a name sorting before `injectable` used to trip `directives_ordering`).
- The `code_review` workflow parses the report in any language, so the default English report is posted.
- `GoRouteDataCustom` reports screen views on the web and honours `canPop` / `pageKey` on every platform.
- The generator-smoke unused-dependency step matches the generated app's package; `check_unused_translate` no longer flags bare getters inside `extension on AppLocalizations`.
- Xcode scheme comments are in English; 14 files end with a newline; the `LoadingWidget` doc example compiles.
- `docs_check` accepts a glob over an empty directory (e.g. `modules/*/feature` in a fully stripped template); a glob over a non-empty directory must still match.
- Networking: token-refresh deadlocks and recursion (a `401` from login or refresh no longer starts a
  refresh; a late `401` for an old token replays), retry decisions that could lose an error, and
  retry/refresh failures reported accurately to the UI.
- Boot: TLS overrides installed before the first widget; returning users skip onboarding; the route
  observer is attached; boot crashes in apps without onboarding or home; no artificial two-second splash.
- Storage: no key wipe on first launch or on a transient secure-store error.
- Localization: the Material wrapper wires `material_ui`'s own localization delegates, so an app in
  Vietnamese (or any non-English locale) no longer lacks `MaterialLocalizations`.
- Database: the cache database opens after its own migrations register; read-pool connections get a busy
  timeout.
- UI: dark-mode colours in `ui_kit`, theme text scaling, split-view overflow, responsive edge cases.
- Tooling: dozens of silent failures, hangs and hazards across the module generator, composer,
  `dependency_sync`, `docs_check`, the unused checker and Fastlane lanes; tool output in English.
- Stopped tracking the committed Gradle, iOS and tools build output (about 160 MB uncompressed, two copies of a large `kernel_blob.bin` among it).
- Boot no longer freezes on a splash or blank window when `configureDependencies`, an initializer or a hook throws: a boot error screen with Retry appears and the error is still reported.
- Certificate pinning no longer overflows the stack on the first request when pins are declared; the pinning tests verify the installed client and real pin matching.
- The splash waits (up to the connect timeout) for the stored-session restore, so a returning user does not see the signed-out home.
- The retry handler recovers when its prompt callback throws and no longer replays timed-out POST and PATCH requests (opt in with `EXTRA_IDEMPOTENT`).
- `CustomButton` keeps a 48 dp tap target, the toast is announced by screen readers and spinners are labelled (new global `loading` string, en and vi).
- The sample auth keeps the signed-in session when a certificate or pin is rejected on renewal (`BAD_CERTIFICATE` counts as "no verdict from the server", like a lost network), instead of signing the user out; at app start only a 401/403 from the server drops the stored token.
- A throwing `executeOperation` leaves loading for the error state; a sign-in or refresh answer without a token no longer wipes the stored credential; the login email is trimmed.
- A database upgrade runs all its steps in one transaction: a failing step no longer leaves a half-migrated file that fails every launch; the file keeps its old version and the next launch retries.
- `ThemeProvider` applies the palette's text colours to every text style (it used to leave Material's defaults on all of them).
- The sample login button's label reads on the brand fill in both themes, and Done on the keyboard no longer sends a second sign-in (`AuthProvider.login` ignores a call while one is pending).
- `CustomButton` has a distinct disabled fill with a readable label, `CustomInputField` has contrast-safe resting, focused, error and disabled borders and is at least 48 dp tall, and `showDropDown` rows are at least 48 dp (RULE-39).
- `AppOverlay` dialogs and the loading layer hide the page behind them from assistive technology and keyboard focus.
- Onboarding and home scroll instead of overflowing on short or square windows with large text; the dashboard bottom bar keeps its labels from the fourth tab.
- A throwing `convert` settles on the error state in `BaseProvider` and `BaseBloc` instead of leaving `loading`.
- Deep links keep repeated query keys, fragments and `myapp:///path`; `BaseEntity.isSuccess` accepts any 2xx; `ValidationHelper` dates and `isValidEmail` (any-length TLD, `+`); `EncryptedStorage.encryptData('')` no longer throws.
- The toast pill is near-opaque (alpha 0.92); the light palette's `error`, `info` and `primaryContainer` are darker so their on-colours reach WCAG AA; `PushNotificationService.requestPermission()` returns whether notifications are allowed and no longer uses `dart:io` `Platform`.
- The iOS runner uses the UIScene lifecycle (the first iOS build no longer rewrites tracked files) and each flavored Xcode configuration uses its own icon set.
- `code_review.yml` stubs Firebase like the other workflows; the generated Provider page renders a translated error and ships a failing-load test; a rolled-back generator or `remove_sample` run restores each app's README report and `app_profile.dart` facts; `firebase_config.dart` refuses to run without terminals.
- The `code_review` workflow skips its review and comment steps, with a notice, when `GEMINI_API_KEY` is not set (a fresh adopter, a fork PR) instead of failing every pull request that touches Dart.
- CI no longer installs `flutterfire_cli` on stubbed runs (`configure.dart --stub-firebase` skips it; a run without the flag still activates it); the quality job timeout is 45 minutes; the PR template's APK command is complete (from `apps/mobile`, with the env file).
- The CI step that annotated critical review findings was named "Fail on Critical Issues" but never failed; it is now named as advisory.

### Security

- Certificate validation is bypassed only in a debug build that explicitly declared `--flavor dev`; a
  missing or unknown flavor is treated as prod.
- `LoggingInterceptor` redacts credentials in bodies as well as headers and logs only in debug.
- The AI code-review tool sends the Gemini key in a header, redacts it from errors, and stores it in a
  gitignored file instead of tracked config.
- The bearer token is sent only to the API base-URL host or `NetworkProfile.authorizedHosts`; a request refused the token is also marked not refreshable.
- Debug logs redact more credential keys and URL query values and no longer print the FCM token; the storage encryption docs state confidentiality only, no integrity.
- Release keystores, `key*.properties` (except the public dev key) and `env.prod` are ignored by broad
  patterns; see [SECURITY.md](SECURITY.md).

[Unreleased]: https://github.com/CaoGiaHieu-dev/flutter-monorepo-codebase/commits/main
