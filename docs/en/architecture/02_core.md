# The Core Layer

This document answers **"what is inside `platform/*`, and which package should I reach for?"**. After reading it you should be able to pick the right core package for a task — and recognise when what you are about to add does *not* belong in core at all.

Core packages are **infrastructure**. They provide mechanisms; they never encode business rules, and they never know a feature exists.

---

## 0. The rules that govern every core package

Three rules apply to everything on this page.

**Core must not depend on features or data.** Three approved exceptions exist, listed in [the overview](01_overview.md#the-approved-exceptions). `tools/arch_check/check.dart` enforces the list on every PR.

**Core provides mechanism, not policy.** `core_storage` gives you `StorageValue<T>`; it does not decide that a key called `token` exists. `core_database` gives you a connection and a migration contract; it does not know your tables' business meaning. Whenever a core package starts naming a specific domain concept, that name belongs somewhere else.

**Every package keeps its constants in its own `utils/` folder.** One approved exception: design tokens in `core_base_ui/src/styles/` stay where they are — see [`core_base_ui`](#3-core_base_ui--design-system) below.

---

## 1. `platform_kernel` and `core_common` — shared primitives

The bottom of the infrastructure stack is two packages, split by one question: *does it need Flutter?*

**`platform_kernel`** is pure Dart — no `flutter` in its dependencies, enforced by `arch_check` R9. Its only workspace dependency is `domain_core`, for the `AppFailure` that `ErrorHandler` produces. Depend on it directly unless you need something Flutter-bound.

| Area | Path | Contents |
|:--|:--|:--|
| Service locator | `src/di/` | `getIt`, `getItOrNull`, `getAll`, `getAllOrEmpty` |
| Config | `src/config/` | `SslPinningConfig` |
| Enums | `src/enums/` | app-wide enums (`Flavor`, …) |
| Errors | `src/error/` | `ErrorHandler.handleError()`, exception types, and a re-export of `AppFailure` (declared in `domain_core` alongside `Result<T>`) |
| Extensions | `src/extensions/` | `bool`, `DateTime`, `Enum`, `List`, `num`, `String` |
| Utils **and constants** | `src/utils/` | `ApiStatusConstants`, `EnvConstants`, `MessageQueue`, `helpers/` (`TypeHelper`, `ValidationHelper`, `JsonConverters`) |

**`core_common`** is the Flutter-bound half. It declares two workspace dependencies — `platform_kernel`, which it re-exports wholesale so a `package:core_common/core_common.dart` import still resolves everything above, and `core_responsive`, used by the page-transition widgets in `src/routing/page_transitions/`.

| Area | Path | Contents |
|:--|:--|:--|
| Config | `src/config/` | `AppConfig` (flavor, design size, base URL, default locale), `AppInitializer` (HttpOverrides, logging, orientation, system UI) |
| Extensions | `src/extensions/` | `Dio` |
| Mixins | `src/mixins/` | `LifecycleMixin`, `NetworkMixin`, `LoadMoreControllerBinding` |
| Routing helpers | `src/routing/` | `GoRouteDataCustom`, `RouteAwareWidget`, page transitions |
| Utils | `src/utils/` | `AppUtils`, `Debounce`, `DownloadImage`, `formatters/`, `helpers/` (`AppInfoHelper`), `dialog/` |

### What does *not* belong here, and why

`core_common` has no `constants/` folder. A shared constants folder in the bottom package becomes a **god object** — one place, importable by every package, listing values that belong to individual domains:

| Kind of constant | Where it belongs | Why not here |
|:--|:--|:--|
| Storage keys (`TOKEN`, `AUTH_USER`, `LOCALE`, `THEME_MODE`, `VIEWED_ONBOARD`) | with the class that owns the value — see [the storage guide](../guides/06_storage.md) | Listed together, every package can read and overwrite every other feature's storage key. |
| REST endpoints (`/user/login`, `/user/refresh-token`) | the owning data package — [`modules/auth/data/lib/src/utils/auth_api_constants.dart`](../../../modules/auth/data/lib/src/utils/auth_api_constants.dart) | They belong solely to auth. Nothing else has any business naming them. |
| Subsystem constants (analytics event names, socket events such as `TYPING` / `USER_JOINED`, remote-config keys) | the package implementing that subsystem, if it exists | Chat-specific events sitting in a core package are a boundary leak, and constants for a subsystem the repo does not have are dead weight. |

Exactly two constants files live at the bottom of the stack, and both are genuinely global: `ApiStatusConstants` (HTTP status codes) and `EnvConstants` (`String.fromEnvironment` values). Both sit in `platform_kernel`'s `src/utils/`, the one place it keeps such values.

> [!CAUTION]
> Before adding a constant to `core_common`, ask: *would more than one unrelated domain read this?* If the answer is no, it belongs in the owning package's `utils/`.

**Firebase options are not here either.** They name one bundle ID, so they belong to one app: each app that uses Firebase owns a `lib/firebase/firebase_module.dart` registering its per-flavour `FirebaseOptions` (the sample's is [`apps/mobile/lib/firebase/firebase_module.dart`](../../../apps/mobile/lib/firebase/firebase_module.dart)). While that module sat in `core_common`, a second app would have inherited the mobile app's Firebase identity.

---

## 2. `core_di` — the DI Hub

Contracts only. No implementations, no business logic. It is the neutral ground where two packages that must not import each other can meet.

| Contract group | Path | Purpose |
|:--|:--|:--|
| Navigators | `src/navigators/` | `AuthNavigator`, `HomeNavigator` — declared here, implemented in the owning feature |
| Routing | `src/routing/` | `IFeatureRouteModule`, `INavDestinationModule`, `IAppEntryLocation`, `DashboardRouteModule`, `NavigatorKeys` |
| Action handlers | `src/actions/` | `IAuthActionHandler` — cross-feature UI actions (e.g. logout) |
| Agnostic streams | `src/agnostic_streams/` | `IAuthStatusStream` — state sharing between a Provider feature and a BLoC feature |
| Storage contracts | `src/theme/`, `src/language/` | `IThemeStorage`, `ILanguageStorage` — implemented in the app shell |
| Localization | `src/feature_localization.dart` | `IFeatureLocalization` — each feature contributes its own delegate |

**`NavigatorKeys`** lives in its own file, [`src/routing/navigator_keys.dart`](../../../platform/di/lib/src/routing/navigator_keys.dart), separate from the routing interfaces in `routing_interfaces.dart`. It exposes `rootKey`, `appKey`, and `nested(id)` for a module that needs its own back stack.

A `ShellRoute` and its child routes must share the **same** `GlobalKey` instance, but the shell is built by the app shell while the children are declared inside a feature. Neither side can host the key without creating a cycle, so the Hub — which both already depend on — holds it.

Keys are requested by id rather than declared: `NavigatorKeys.nested('auth')` returns the same instance every time. The DI Hub therefore names no feature, and a module needing its own back stack adds nothing here.

> [!NOTE]
> `core_di` depends on `go_router`. That is not a leak: `IFeatureRouteModule` returns `List<RouteBase>` and `INavDestinationModule` returns `List<RouteBase>` too. These *are* routing contracts, so they must speak GoRouter's vocabulary — but note `INavDestinationModule` describes its destination with the Hub's own `NavDestination`, never a `BottomNavigationBarItem`, so the contract does not commit to a bottom bar. Abstracting them further would add an adapter layer with no benefit.

**Not here:** anything with an implementation. If you write a `class …Impl` in `core_di`, it is in the wrong package.

---

## 3. `core_base_ui` — design system

Design tokens, themes, typography, global assets and the base localization bundle.

| Area | Path | Contents |
|:--|:--|:--|
| Design tokens | `src/styles/` | `AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows` |
| Theme | `src/theme/` | `ThemeProvider`, `ThemeSystemExtension`, `ThemeSystemInterface` |
| Language | `src/language/` | `LanguageProvider` |
| Extensions | `src/extensions/` | `context.colors`, key/locale extensions |
| Generated | `src/gen/` | `Assets`, `AppLocalizations` (global strings) |
| Constants | `src/utils/base_ui_constants.dart` | Non-token values: snackbar duration, dropdown geometry, app-bar font size |

### Zero Flutter widgets — verified

The package contains **no** `StatelessWidget`, `StatefulWidget`, `State<…>` or `InheritedWidget`. This is checked, not assumed. Reusable widgets belong in [`core_ui_kit`](#4-core_ui_kit--reusable-widgets); `core_base_ui` supplies only the values those widgets consume.

### Why design tokens stay in `styles/`, not `utils/`

They are an approved exception to the "constants live in `utils/`" rule:

- They are **public API** imported directly by many feature packages.
- `styles/` carries meaning — "this is the design system". `utils/` reads as "miscellaneous", which is exactly the wrong signal for tokens the whole app is expected to obey.

Non-token magic values live in `src/utils/base_ui_constants.dart`. The dividing line: if a designer would recognise it, it is a token and stays in `styles/`.

### `ThemeProvider` reacts to OS theme changes

`ThemeProvider` is a `@lazySingleton` that mixes in `WidgetsBindingObserver`. Under `ThemeMode.system` the OS brightness can change while the app runs, so it overrides `didChangePlatformBrightness()` and rebuilds — but only when the mode actually *is* `system`, so an explicit light/dark choice never triggers a wasted rebuild.

`WidgetsBindingObserver` was chosen over assigning `platformDispatcher.onPlatformBrightnessChanged`: that field is a **single** slot, so whoever assigns last silently wins. For an app-wide singleton competing with the framework and plugins, that is a real hazard.

The observer is removed in `dispose()`, which is annotated `@disposeMethod` so GetIt invokes it on container reset — without it, every `resetDependencies()` in a test would leave a stale observer registered.

---

## 4. `core_ui_kit` — reusable widgets

The shared widget library every feature may consume. It is **core, not a feature**: it lives at `platform/ui_kit` precisely so `modules/*/feature/` contains only removable product surfaces.

Flat layout (no `src/`): `buttons/`, `inputs/`, `dialogs/`, `feedback/`, `layout/`, `media/`, `navigation/`, `utils/`.

It depends on `core_common`, `core_base_ui`, `core_responsive` and `provider_state_management` — never on a feature or on `data_*`.

> [!NOTE]
> The dependency runs **one way**: `core_ui_kit -> provider_state_management`. The reverse edge would close a cycle inside the core ring, so `provider_state_management` ships its own `DefaultLoadingWidget` / `DefaultEmptyWidget` rather than borrowing branded ones from here.

### The UI-agnostic rule

Reusable widgets use their parameters **exactly as received** and must not scale them through `core_responsive`. Scaling is the caller's job, so by the time a value arrives it is already in device pixels — note `context.w(120)` on the calling side below. A widget still scales its *own* constants, or it would not be responsive at all:

```dart
// caller scales
CustomButton(width: context.w(120), height: context.h(44))

// widget scales its own parameter -- wrong
double _width(BuildContext context) => context.w(width);
```

Scaling inside means a caller who already scaled gets it applied twice, and a caller who wants a literal pixel value cannot get one.

> [!WARNING]
> **What this rule forbids.** An `AppBar` in `core_ui_kit` that carries:
>
> ```dart
> @override
> double? get leadingWidth => context.w(64);
> ```
>
> Two failures at once: it scales internally, and -- because it is a getter override -- it **silently discards the `leadingWidth` a caller passed to the constructor**. The parameter looks supported and does nothing.

### Constants

Defaults for these widgets live in `platform/ui_kit/lib/utils/shared_ui_constants.dart`:

```dart
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(milliseconds: 200);
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const Duration MEDIA_ERROR_TOAST_DURATION = Duration(seconds: 2);
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
```

They are defaults, not policy — a caller that needs a different value passes it through the constructor.

---

## 5. `core_responsive` — responsive sizing

The scaling mechanism every widget in the app resolves through. It lives at `platform/responsive` and depends on **nothing but `flutter`** — no workspace package, no third-party package.

| Piece | What it is |
|:--|:--|
| `ResponsiveInit` | `StatelessWidget` mounted once above `MaterialApp`. Params: `child`, `designSize` (default 360×690), `splitScreenMode`, `minTextAdapt`, `fontSizeResolver` |
| `ResponsiveScope` | `InheritedWidget` carrying the metrics — `maybeOf(context)` / `of(context)` |
| `ResponsiveMetrics` | Immutable value object computing `width`, `height`, `radius`, `diagonal`, `diameter`, `sp`, `spMin` |
| `ResponsiveContext` | Extension on `BuildContext` — `context.w/h/r/sp/spMin/dg/dm`, `edgeInsets`, `borderRadius`, `verticalSpace`, `horizontalSpace` |
| `ResponsiveConstants` | `SPLIT_SCREEN_MIN_HEIGHT = 700`, `DEFAULT_DESIGN_WIDTH = 360`, `DEFAULT_DESIGN_HEIGHT = 690` — in `src/utils/`, like every other package's constants |

`ResponsiveInit` is a `StatelessWidget` on purpose: it reads `MediaQuery.sizeOf(context)`, which registers a **size-only** dependency, so it rebuilds on resize and ignores brightness, text-scale and padding changes. No `WidgetsBindingObserver`, no `setState`.

### There is deliberately no `num` extension

`16.w` **does not compile**. A number carries no context, so such an extension could only read a global singleton — and a widget reading a global never learns the metrics changed. Requiring a `BuildContext` makes the correct thing the only writable thing; `arch_check` rule **R7** rejects the bare form in any file importing `core_responsive`.

There is no global instance, no imperative `init()`, no `setWidth()` helper and no rebuild flag — rebuild targeting is Flutter's job once the metrics live in an `InheritedWidget`.

> [!NOTE]
> `ResponsiveScope.of(context)` **asserts** — *"No ResponsiveInit found above this context."* — rather than falling back to unscaled values. A silent fallback would ship a layout that is wrong on every device. A widget test that scales must therefore wrap its subject in `ResponsiveInit`.

Configuration (design canvas, `fontSizeResolver`) is documented in [`../guides/11_design_system.md`](../guides/11_design_system.md).

---

## 6. `core_network` — HTTP client

Built on Dio, configured through the `NetworkConfig` contract so the package never touches storage or UI directly.

| Area | Path | Contents |
|:--|:--|:--|
| Client | `src/api_client.dart` | `ApiClient.createClient()` — Dio factory, assembles the interceptor chain |
| Contract | `src/network_config.dart` | `NetworkConfig` — `getToken`, `getLocale`, `onRetryCallback`, `onRefreshToken`, `onRefreshFailed`, `sslPinningHashes` |
| Interceptors | `src/interceptors/` | `AuthInterceptor`, `RefreshTokenInterceptor`, `RetryInterceptor`, `LoggingInterceptor` |
| Handlers | `src/handlers/` | `RefreshTokenHandler`, `RetryHandler` |
| Constants | `src/utils/network_constants.dart` | Timeouts, header names, `Bearer` prefix, extra keys, log tags |

`NetworkConfig` is implemented **in the app shell**, not here — that is what keeps `core_network` free of any storage dependency. Both refresh callbacks default to `null`, so a client with no refresh endpoint simply surfaces the `401` unchanged.

> [!CAUTION]
> **SSL pinning is only as good as its hash list.** `sslPinningHashes` currently returns `const []`, which disables pinning. `AppInitializer` logs an `ERROR` on non-dev flavors when the list is empty or the config is unregistered, so the gap is visible rather than silent — but it is still a gap until you populate it. See [the networking guide](../guides/08_networking.md).

Full detail on the interceptor chain, the recursion guards around token refresh, and header redaction lives in [`../guides/08_networking.md`](../guides/08_networking.md).

---

## 7. `core_storage` — encrypted key–value storage

Provides the **mechanism only**. It defines no keys and no presets.

| Export | Purpose |
|:--|:--|
| `StorageInterface` | Backend contract |
| `StorageManager` | `@singleton`; resolves a backend by `StorageType`, initializes all backends in parallel via `@PostConstruct(preResolve: true)` |
| `StorageValue<T>` | Reactive wrapper over one key — `ChangeNotifier` + broadcast `Stream`, in-memory cache, auto-persist on write |
| `StorageType` | `pref` (SharedPreferences) · `secure` (hardware-backed) |
| `ObfuscatedString` / `ObfuscatedBytes` | RAM obfuscation |
| `PrefStorageImpl` / `SecureStorageImpl` | Internal, resolved via `@Named('Pref')` / `@Named('Secure')` |

### RAM obfuscation is a real protection, not a label

Beyond encrypting data at rest (AES-256-CBC with a per-write random IV), `StorageValue` keeps its **in-memory** value XOR-masked with a random mask, and reveals it only for the moment a read needs it. The master key receives the same treatment. This raises the bar against memory-dump inspection — a layer most templates omit entirely.

`SecureStorageImpl` also self-heals: if the Keychain/KeyStore entry becomes unreadable, it clears and regenerates the master key rather than leaving the app permanently unable to start.

### Ownership

Each consuming package declares its own `StorageValue` instances through an injected `StorageManager`, with its keys in that package's `utils/`. Current owners:

| Owner | Package | Keys | Backend |
|:--|:--|:--|:--|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | secure |
| `ThemeStorageImpl` | `platform_app_shell` | `themeMode` | pref |
| `LanguageStorageImpl` | `platform_app_shell` | `locale` | pref |
| `AppBootStorage` | `platform_app_shell` | `viewed_onboard` | pref |

See [`../guides/06_storage.md`](../guides/06_storage.md) for the step-by-step.

---

## 8. `core_database` — relational storage (Drift + SQLite)

Runs on a background isolate via `NativeDatabase.createInBackground`. Depends on **no other workspace package**.

This package is the **mechanism only**: it owns no database, no table and no DAO, and its DI module registers nothing. Each package that persists relational data declares **its own** database next to its own tables, DAO and data source, and opens it with the pieces below. `data_core`'s `CacheDatabase` (`platform/data_core/lib/src/database/`) is the reference wiring.

| Area | Path | Contents |
|:--|:--|:--|
| Opening | `src/opening/` | `DriftDatabaseOpener` — opens any `GeneratedDatabase` on a background isolate, verifies it, quarantines a corrupt file |
| Connection | `src/connection/` | `DatabaseConnectionFactory` — file resolution, background executor |
| **Access** | `src/access/` | `IDatabaseHandle`, `DatabaseHandle` |
| **Migration** | `src/migration/` | `IDatabaseMigration`, `DatabaseMigrationRunner`, `driftMigrationStrategy` |
| Constants | `src/utils/database_constants.dart` | `DEFAULT_FILE_NAME`, `DEFAULT_READ_POOL`, `BUSY_TIMEOUT_MS` |

Drift resolves `@DriftDatabase(tables:)` at compile time and requires a DAO to be `part of` its database library, so a database declared here would have to name the tables of whichever package owns them. Keeping databases package-owned buys one property: deleting a package deletes its database with it, and no other package can reach its rows. The trade-off is that SQL cannot join across package boundaries — crossing a bounded context belongs at the repository layer, not inside a query.

### Two contracts keep packages out of each other's tables

**`IDatabaseMigration`** — a package that changes the schema implements this next to its own tables and registers it in its own DI module, exactly as features contribute routes. `version` is the schema version the step *produces*; steps replay in order so a device that skipped releases still lands correctly. Duplicate versions are rejected at startup rather than silently applying one.

**`IDatabaseHandle`** — a data source asks for the accessor it needs instead of receiving a database object with every DAO on it:

```dart
ProfileLocalDataSource(IDatabaseHandle handle)
  : _dao = handle.accessor(ProfileDao.new);
```

> [!NOTE]
> Within one database this is **API-surface isolation, not enforced isolation**: the factory callback still receives the database object, so a determined caller can reach any DAO on it. The value is that crossing that line becomes a deliberate, reviewable act rather than an ordinary constructor parameter. Isolation *between* packages is the real barrier, and it is enforced by the package graph — a package that does not declare `data_core` cannot name `CacheDatabase` at all.

Connection hardening (`foreign_keys = ON`, WAL journal mode, busy timeout) and the corruption-quarantine strategy are covered in [`../guides/07_database.md`](../guides/07_database.md).

---

## 9. `core_notifications` — push and local notifications

`PushNotificationService` wraps Firebase Messaging and `flutter_local_notifications`. Channel IDs and payload types live in `src/utils/notification_constants.dart`, with the package that consumes them — a notification channel ID has no business being readable by every package in the app.

The service is an eager `@singleton` that injects `FirebaseOptions`, which each app registers from its own `lib/firebase/firebase_module.dart`. That is why an app's manifest lists `core_notifications` in a `notifications` group with `phase: after` rather than in `core`: `before` runs ahead of the app's own registrations. An app without push notifications leaves the group out.

---

## 10. State management — two branches, **not at parity**

The template supports Provider and BLoC. Be aware before choosing: the two are not equally developed.

| | `provider_state_management` | `bloc_state_management` |
|:--|:--|:--|
| Base class | `BaseProvider<T>` — full implementation | `BaseBloc` / `BaseCubit` — *extension point only, adds nothing* |
| Async helper | `executeOperation(OperationConfig(...))` handles loading/success/failure automatically | **none** |
| State type | `ViewStateModel<T>` + `ViewState` (5 variants incl. `loadingMore`, data held on the model) | `BlocViewState<T>` (4 variants, carries its own payload) |
| Error shape | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — required |
| Extras | `StateManager`, `OperationExecutor`, `OperationGlobalConfig`, `LoadMoreMixin`, `ProviderStateListener`, `BaseViewWidget` | — |

> [!WARNING]
> On the BLoC branch you must unwrap `Result<T>`, map `AppFailure`, and emit loading/terminal states **by hand in every handler**. The Provider branch wraps all of that in `executeOperation`. `base_bloc.dart` documents this honestly and shows the manual pattern.

### `BlocViewState<T>`

The BLoC state type is `BlocViewState<T>`, **not** `ViewState`. Both packages export from public barrels, and the Provider branch exports a semantically different `ViewState`. The distinct name is what lets a file import both barrels without a compile-time collision.

`OperationGlobalConfig` exposes read-only getters; `setup()` **merges** rather than overwriting, so calling it twice keeps both sets of hooks, and `reset()` exists for tests.

Practical usage for both branches: [`../guides/03_state_management.md`](../guides/03_state_management.md).

---

## 11. Dependency map

Local (workspace) dependencies only — pub.dev packages omitted.

| Package | Depends on |
|:--|:--|
| `domain_core` | *(none)* |
| `core_database` | *(none)* |
| `core_di` | *(none)* |
| `core_responsive` | *(none)* |
| `platform_kernel` | `domain_core` *(approved exception — `ErrorHandler` produces `AppFailure`)* |
| `core_common` | `platform_kernel`, `core_responsive` |
| `core_network` | `platform_kernel` |
| `core_notifications` | `platform_kernel` |
| `core_storage` | `core_common` |
| `data_core` | `platform_kernel`, `core_database`, `domain_core` |
| `core_base_ui` | `core_common`, `core_di`, `core_responsive` |
| `bloc_state_management` | `domain_core` *(approved exception — `AppFailure` for `BlocViewState.error`)* |
| `provider_state_management` | `core_common`, `domain_core` *(approved exception)* |
| `core_ui_kit` | `core_common`, `core_base_ui`, `core_responsive`, `provider_state_management` |
| `platform_app_shell` | `core_base_ui`, `core_common`, `core_di`, `core_network`, `core_responsive`, `core_storage`, `core_ui_kit`, `provider_state_management` |

No arrow in this table points at `modules/*/feature` or `modules/*/data` — that is the invariant to preserve.
