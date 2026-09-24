# The Core Layer

This document answers **"what is inside `platform/*`, and which package should I reach for?"**. After reading it you should be able to pick the right core package for a task — and recognise when what you are about to add does *not* belong in core at all.

Core packages are **infrastructure**. They provide mechanisms; they never encode business rules, and they never know a feature exists.

---

## 0. The rules that govern every core package

Three rules apply to everything on this page.

**Core must not depend on features or data.** Three approved exceptions exist, listed in [the overview](01_overview.md#the-approved-exceptions). `tools/arch_check/check.dart` enforces the list on every PR.

**Core provides mechanism, not policy.** `core_storage` gives you `StorageValue<T>`; it does not decide that a key called `token` exists. `core_database` gives you a connection and a migration contract; it does not know your tables' business meaning. Whenever a core package starts naming a specific domain concept, that name belongs somewhere else.

**Every package keeps its constants in its own `utils/` folder.** One approved exception: design tokens in `core_base_ui/src/styles/` stay where they are — see [`core_base_ui`](#3-core_base_ui--design-system) below.

### Where a package lives — the six groups

`platform/` is split into six group folders by role. Only the folder says which group a package is in — every package **name** is unchanged (`core_di` is still `core_di`, now at `platform/foundation/contracts`), so imports, `app_manifest.yaml` and the dependency names in each `pubspec.yaml` do not mention groups at all.

| Group | Folder | Packages (folder) | What belongs here | May depend on |
|:--|:--|:--|:--|:--|
| **foundation** | `platform/foundation/` | `platform_kernel` (`kernel/`), `core_di` (`contracts/`), `core_common` (`common/`) | What every other package builds on: the service locator and error handling, the cross-module DI contracts, Flutter-bound helpers. No I/O, no widgets, no transport type | foundation, `domain_core` |
| **layers** | `platform/layers/` | `domain_core` (`domain/`), `data_core` (`data/`) | The base contracts of the domain and data layers — `Result<T>`, `AppFailure`, `BaseEntity`, `IBaseRepository` — that `modules/*/domain` and `modules/*/data` extend | `domain_core`: nothing. `data_core`: foundation, `domain_core` |
| **infra** | `platform/infra/` | `core_network`, `core_storage`, `core_database`, `core_notifications` (`network/`, `storage/`, `database/`, `notifications/`) | Mechanisms that reach outside the process — HTTP, key–value storage, SQLite, push. Mechanism only: no product module's keys, tables or endpoints. The default group of `generate.dart 4` / `5` | foundation, layers — never another infra package |
| **ui** | `platform/ui/` | `core_responsive` (`responsive/`), `core_base_ui` (`design_system/`), `core_ui_kit` (`ui_kit/`) | Scaling and adaptive layout, design tokens, themes and global strings, the shared widget library | foundation, ui — never state, infra or shell |
| **state** | `platform/state/` | `provider_state_management` (`provider/`), `bloc_state_management` (`bloc/`) | The state-management bases, and the widgets bound to them (`LoadMoreListView`); a feature picks one | foundation, layers, ui |
| **shell** | `platform/shell/` | `platform_shell_adapters` (`adapters/`), `platform_app_shell` (`app_shell/`) | The infrastructure adapters every app registers (`NetworkConfigImpl`, the storage adapters, `AppBootStorage`); the app shell every app composes: boot, router assembly, material wrapper, app state | every platform group (`app_shell → adapters`, never the reverse) |

The direction, with each arrow pointing at the side that is depended on: `domain_core ← foundation ← data_core ← infra`, `foundation ← ui ← state`, `layers ← state`, `shell ← all of platform/`. `platform_kernel → domain_core` is part of the design, not an exception to it: `ErrorHandler` produces an `AppFailure` (the approved R1 edge). And, unchanged, nothing under `platform/` depends on `modules/` (`arch_check` R1). `arch_check` **R11** enforces the group direction: it reads a package's group from its folder (`platform/<group>/<package>`; a package outside a known group folder is itself a violation) and checks every `dependencies:` entry that is a platform package against the table above. Dev dependencies are not checked — they never ship; `platform_app_shell`'s tests use `core_storage` for fakes. An edge into `domain_core` / `data_core` also needs R1's approved list.

The package graph obeys the direction **with no exception**. Three edges used to run against it; each was removed, not approved:

- `core_common` (foundation) → `core_responsive` (ui). `BottomTransitionPage`, the one widget that scaled through it, moved to `core_ui_kit` (`navigation/`); `AppInitializer`'s phone-sized portrait lock compares against a private 600 px constant (the Material 3 `medium` breakpoint).
- `core_ui_kit` (ui) → `provider_state_management` (state). `LoadMoreListView` / `LoadingMoreWidget` — the only kit widgets bound to `LoadMoreMixin` — moved into `provider_state_management` (`src/base_view/loading_more_widget.dart`), which may depend on `ui`. The kit now declares no state-management package.
- `platform_kernel` → `dio`. The Dio → `AppFailure` mapping moved to `core_network` as `DioFailureClassifier`, registered into `ErrorHandler` (§ 1, § 6).

Two lighter edges went with them: `core_storage` now takes `TypeHelper` from `platform_kernel` instead of the whole of `core_common`, and `data_auth` no longer declares an unused `flutter`.

Group-level graph (arrow = "depends on"; every package edge falls on one of these):

```text
layers/domain  -> (nothing)
foundation     -> foundation, layers/domain
layers/data    -> foundation, layers/domain
infra          -> foundation, layers/domain            (no infra -> infra)
ui             -> foundation, ui
state          -> foundation, layers/domain, ui
shell          -> foundation, infra, ui, state, shell
```

A new mechanism package goes in `infra` — `dart tools/module_generator/generate.dart 4 <name>` puts it there; pass `--group <group>` for another group.

---

## 1. `platform_kernel` and `core_common` — shared primitives

The bottom of the infrastructure stack is two packages, split by one question: *does it need Flutter?*

**`platform_kernel`** is pure Dart — no `flutter` in its dependencies, enforced by `arch_check` R9, and no transport either: it names no `dio` type. Its only workspace dependency is `domain_core`, for the `AppFailure` that `ErrorHandler` produces. Depend on it directly unless you need something Flutter-bound.

| Area | Path | Contents |
|:--|:--|:--|
| Service locator | `src/di/` | `getIt`, `getItOrNull`, `getAll`, `getAllOrEmpty` |
| Config | `src/config/` | `SslPinningConfig` |
| Enums | `src/enums/` | app-wide enums (`Flavor`, …) |
| Errors | `src/error/` | `ErrorHandler.handleError()`, exception types, and a re-export of `AppFailure` (declared in `domain_core` alongside `Result<T>`). `ErrorClassifier` + `ErrorHandler.registerClassifier` let the package that owns an exception type map it — `core_network` registers `DioFailureClassifier` (§ 6). `ErrorHandler.onUnclassifiedError` is a plain callback for the exceptions it cannot classify — the app shell points it at the optional `IErrorReporter` ([`06_app_shell.md`](06_app_shell.md#errors-and-crash-reporting)) |
| Extensions | `src/extensions/` | `bool`, `Enum`, `List`, `String` — no `DateTime` or `num` formatting: dates, times and currency are locale-dependent, so format them with `intl`'s `DateFormat` / `NumberFormat` and the current locale |
| Utils **and constants** | `src/utils/` | `EnvConstants`, `ErrorCodes`, `MessageQueue`, `helpers/` (`TypeHelper`, `ValidationHelper`, `JsonConverters`) |

**`core_common`** is the Flutter-bound half. It declares two workspace dependencies — `platform_kernel`, which it re-exports wholesale so a `package:core_common/core_common.dart` import still resolves everything above; and `core_di`, for the optional `IAnalytics` that `RouteAwareWidget` reports screen views to. It depends on nothing in the `ui` group: `BottomTransitionPage` now lives in `core_ui_kit`.

| Area | Path | Contents |
|:--|:--|:--|
| Config | `src/config/` | `AppConfig` (flavor, design size, base URL, default locale), `AppInitializer` (HttpOverrides, logging, orientation — portrait lock on phone-sized displays only, system UI) |
| Mixins | `src/mixins/` | `LifecycleMixin`, `NetworkMixin`, `LoadMoreControllerBinding` |
| Routing helpers | `src/routing/` | `GoRouteDataCustom`, `RouteAwareWidget` |
| Utils | `src/utils/` | `AppUtils`, `Debounce`, `formatters/`, `helpers/` (`AppInfoHelper`), `dialog/` |

### What does *not* belong here, and why

`core_common` has no `constants/` folder. A shared constants folder in the bottom package becomes a **god object** — one place, importable by every package, listing values that belong to individual domains:

| Kind of constant | Where it belongs | Why not here |
|:--|:--|:--|
| Storage keys (`TOKEN`, `AUTH_USER`, `LOCALE`, `THEME_MODE`, `VIEWED_ONBOARD`) | with the class that owns the value — see [the storage guide](../guides/06_storage.md) | Listed together, every package can read and overwrite every other feature's storage key. |
| REST endpoints (`/user/login`, `/user/refresh-token`) | the owning data package — [`modules/auth/data/lib/src/utils/auth_api_constants.dart`](../../../modules/auth/data/lib/src/utils/auth_api_constants.dart) | They belong solely to auth. Nothing else has any business naming them. |
| Subsystem constants (analytics event names, socket events such as `TYPING` / `USER_JOINED`, remote-config keys) | the package implementing that subsystem, if it exists | Chat-specific events sitting in a core package are a boundary leak, and constants for a subsystem the repo does not have are dead weight. |

Two constants files live at the bottom of the stack, because they are genuinely global — both in `platform_kernel`'s `src/utils/`: `EnvConstants` (`String.fromEnvironment` values) and `ErrorCodes` ([`error_codes.dart`](../../../platform/foundation/kernel/lib/src/utils/error_codes.dart) — the failure codes `ErrorHandler` and `IBaseRepository` assign when there is no HTTP status, e.g. `REQUEST_CANCELLED`, `RESPONSE_REJECTED`, `UNKNOWN`, all outside the HTTP range so a 5xx is always a real one).

> [!CAUTION]
> Before adding a constant to `core_common`, ask: *would more than one unrelated domain read this?* If the answer is no, it belongs in the owning package's `utils/`.

**Firebase options are not here either.** They name one bundle ID, so they belong to one app: each app that uses Firebase owns a `lib/firebase/firebase_module.dart` registering its per-flavour `FirebaseOptions` (the sample's is [`apps/mobile/lib/firebase/firebase_module.dart`](../../../apps/mobile/lib/firebase/firebase_module.dart)). While that module sat in `core_common`, a second app would have inherited the mobile app's Firebase identity.

---

## 2. `core_di` — the DI Hub

Contracts only. No implementations, no business logic. It is the neutral ground where the platform meets the modules — and every contract in it is **product-neutral**: named for what the platform needs (a session, a location), never for the module that happens to provide it.

| Contract group | Path | Purpose |
|:--|:--|:--|
| Routing | `src/routing/` | `IFeatureRouteModule`, `INavDestinationModule`, `IAppEntryLocation`, `ISignInLocation` / `IPostSignInLocation` (where the shell sends a signed-out / signed-in user), `DashboardRouteModule`, `NavigatorKeys` |
| Session | `src/session/` | `SessionPrincipal`, `SessionFailure`, `ISessionState` (shell-facing), `ISessionStatusStream` (feature-facing: state shared between a Provider and a BLoC feature), `ISessionRefreshListenable`, `ISessionGateway` (transport) — implemented by whichever module owns sign-in |
| Storage contracts | `src/theme/`, `src/language/` | `IThemeStorage`, `ILanguageStorage` — implemented in the app shell's adapters package (`platform_shell_adapters`) |
| Localization | `src/feature_localization.dart` | `IFeatureLocalization` — each feature contributes its own delegate |
| Observability | `src/observability/` | `IErrorReporter`, `IAnalytics` — optional, implemented by the app (Crashlytics, Sentry, Firebase Analytics, …); see [`06_app_shell.md`](06_app_shell.md#errors-and-crash-reporting) |

**`NavigatorKeys`** lives in its own file, [`src/routing/navigator_keys.dart`](../../../platform/foundation/contracts/lib/src/routing/navigator_keys.dart), separate from the routing interfaces in `routing_interfaces.dart`. It exposes `rootKey`, `appKey`, and `nested(id)` for a module that needs its own back stack.

A `ShellRoute` and its child routes must share the **same** `GlobalKey` instance, but the shell is built by the app shell while the children are declared inside a feature. Neither side can host the key without creating a cycle, so the Hub — which both already depend on — holds it.

Keys are requested by id rather than declared: `NavigatorKeys.nested('auth')` returns the same instance every time. The DI Hub therefore names no feature, and a module needing its own back stack adds nothing here.

> [!NOTE]
> `core_di` depends on `go_router`. That is not a leak: `IFeatureRouteModule` returns `List<RouteBase>` and `INavDestinationModule` returns `List<RouteBase>` too. These *are* routing contracts, so they must speak GoRouter's vocabulary — but note `INavDestinationModule` describes its destination with the Hub's own `NavDestination`, never a `BottomNavigationBarItem`, so the contract does not commit to a bottom bar. Abstracting them further would add an adapter layer with no benefit.

**Not here:** anything with an implementation. If you write a `class …Impl` in `core_di`, it is in the wrong package. Nor a contract that exists so one feature can reach *one other module* — `AuthNavigator`, `IAuthActionHandler`, `HomeNavigator`: those live in the owning module's API package (`modules/auth/api` → `auth_api`, `modules/home/api` → `home_api`), which may depend on the foundation and Flutter only (`arch_check` R3).

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

The shared widget library every feature may consume. It is **core, not a feature**: it lives at `platform/ui/ui_kit` precisely so `modules/*/feature/` contains only removable product surfaces.

Flat layout (no `src/`): `buttons/`, `inputs/`, `dialogs/`, `feedback/`, `layout/`, `media/`, `navigation/`, `utils/`.

It depends on `core_common`, `core_base_ui` and `core_responsive` — never on a state-management package, on infra, on a feature or on `data_*`. `navigation/` also holds `BottomTransitionPage`, a `Page` that shows a go_router route as a modal bottom sheet (it moved here from `core_common` because its corner radius scales through `core_responsive`).

> [!NOTE]
> The dependency runs **one way**: `state -> ui`. `provider_state_management` may depend on the ui group (its `LoadMoreListView` scales through `core_responsive`); `core_ui_kit` depends on no state-management package. A widget bound to `LoadMoreMixin` or `ViewState` therefore lives in `provider_state_management`, not here — which is where `LoadMoreListView` / `LoadingMoreWidget` moved. `provider_state_management` also keeps its own `DefaultLoadingWidget` / `DefaultEmptyWidget` rather than borrowing branded ones from here.

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

Defaults for these widgets live in `platform/ui/ui_kit/lib/utils/shared_ui_constants.dart`:

```dart
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(milliseconds: 200);
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
```

They are defaults, not policy — a caller that needs a different value passes it through the constructor.

---

## 5. `core_responsive` — responsive sizing and adaptive layout

The scaling mechanism every widget in the app resolves through, and the window size classes and adaptive widgets that choose a layout. It lives at `platform/ui/responsive` and depends on **nothing but `flutter`** — no workspace package, no third-party package, and no `material` import either.

| Export | Path | What it is |
|:--|:--|:--|
| `ResponsiveInit` | `src/responsive_init.dart` | `StatelessWidget` mounted **once** above `MaterialApp`. Params: `child` (required), `designSize` (default 360×690), `scaleBounds` and `textScaleBounds` (both default `ScaleBounds.downOnly()`), `profiles`, `breakpoints` (default `ResponsiveBreakpoints.material3()`), `splitScreenMode`, `minTextAdapt`, `fontSizeResolver`. Asserts that `designSize` and every profile's `designSize` are positive and finite |
| `ResponsiveScope` | `src/responsive_scope.dart` | `InheritedWidget` carrying `ResponsiveMetrics`; `maybeOf(context)` returns nullable, `of(context)` asserts when missing |
| `ResponsiveMetrics` | `src/responsive_metrics.dart` | Immutable value object computing `width`, `height`, `radius`, `diagonal`, `diameter`, `sp`, `spMin`; exposes the resolved `activeProfile` / `effectiveDesignSize` / `effectiveScaleBounds` / `effectiveTextScaleBounds` / `effectiveMinTextAdapt`, plus `windowSizeClass`, `windowHeightClass`, `orientation`, and the static `isValidDesignSize(size)` |
| `FontSizeResolver` | `src/responsive_metrics.dart` | `typedef double Function(num fontSize, ResponsiveMetrics metrics)` — its result is not clamped by any bounds |
| `ScaleBounds` | `src/scaling/scale_bounds.dart` | The range a scale factor may take: `downOnly()` (the default — shrink, never grow), `fixed()`, `unbounded()`, or `ScaleBounds(min:, max:)`; `clamp` reads a NaN factor as 1 |
| `ResponsiveProfile` | `src/scaling/responsive_profile.dart` | Overrides `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` for one `WindowSizeClass` (`null` inherits); `resolve` picks the exact class, else the nearest smaller one |
| `WindowSizeClass` / `WindowHeightClass` / `ResponsiveBreakpoints` | `src/adaptive/window_size_class.dart` | The window's width class (`compact` < 600 ≤ `medium` < 840 ≤ `expanded` < 1200 ≤ `large` < 1600 ≤ `extraLarge`) and height class, and where they begin |
| `ResponsiveContext` | `src/context_extension.dart` | Extension on `BuildContext` — the **only** way to scale ([table below](#the-buildcontext-extension)); plus `responsive`, `windowSizeClass`, `windowHeightClass` |
| `AdaptiveContext` | `src/adaptive/adaptive_context_extension.dart` | Extension on `BuildContext` — `adaptive(compact:, medium:, …)`, `isCompactWindow`, `isExpandedOrWider`, `separatingDisplayFeature`, `foldPosture` |
| `AdaptiveBuilder` / `AdaptiveLayout` | `src/adaptive/adaptive_builder.dart` | A builder, or one builder per window class |
| `AdaptiveSplitView` | `src/adaptive/adaptive_split_view.dart` | Master–detail: two panes at a fold, hinge or from `splitAt`, one pane otherwise; an optional `divider` laid out `dividerExtent` wide (default 1). `primary` is capped so the divider and `secondary` always fit, and a `primaryWidth` that would leave `secondary` nothing falls back to one pane. `AdaptiveSplitView.isSplit(context)` tells the list which of the two it is |
| `AdaptiveContent` | `src/adaptive/adaptive_content.dart` | Caps content at a readable width (640, not scaled) |
| `FoldPosture` | `src/adaptive/fold_posture.dart` | `flat` / `book` / `tabletop` |
| Constants | `src/utils/` | `ResponsiveConstants`: `SPLIT_SCREEN_MIN_HEIGHT` (700), `DEFAULT_DESIGN_WIDTH` (360), `DEFAULT_DESIGN_HEIGHT` (690), `DESIGN_SCALE_FACTOR` (1), the `BREAKPOINT_*` values; `AdaptiveConstants`: `SPLIT_PRIMARY_FRACTION` (0.4), `SPLIT_DIVIDER_EXTENT` (1), `CONTENT_MAX_WIDTH` (640) — in `src/utils/`, like every other package's constants |

Every factor is clamped, and by default only downward: a window smaller than the artboard shrinks the design, a larger one draws it 1:1 and leaves the extra room to the layout. Growth is opt-in and capped, per window class.

Degenerate input never collapses a layout. An empty window — Android reports 0×0 for the first frame — scales by 1, not 0; a NaN factor clamps as 1; an unusable artboard (a zero or infinite side) asserts in debug and scales by 1 in release.

### Why metrics go through an `InheritedWidget`

`core_responsive` publishes its metrics through an `InheritedWidget`, so every read **registers a dependency** and rebuilding exactly the right widgets is Flutter's job. The alternative — hanging the scale values on a global singleton — produces the same numbers but registers nothing, so a widget reading them never learns the metrics changed (rotation, split screen, resize).

`ResponsiveInit` is a `StatelessWidget` on purpose: it reads `MediaQuery.sizeOf(context)`, which registers a **size-only** dependency, so it rebuilds on resize and ignores brightness, text-scale and padding changes. No `WidgetsBindingObserver`, no `setState`.

`ResponsiveScope.of(context)` **asserts** — *"No ResponsiveInit found above this context."* — rather than falling back to unscaled values. Failing loudly is deliberate: a silent "no scaling" fallback would ship a layout that is wrong on every device. The layout members — `context.windowSizeClass` and everything adaptive — are the exception: choosing a layout is a question about the window, so without a `ResponsiveInit` they classify it with the Material 3 defaults.

### The `BuildContext` extension

| Call | Axis |
|:--|:--|
| `context.responsive` | returns the `ResponsiveMetrics` |
| `context.w(n)` | width — also for anything that must stay square |
| `context.h(n)` | height |
| `context.r(n)` | smaller axis — radii, borders, strokes |
| `context.sp(n)` | font size (or `fontSizeResolver`, when set) |
| `context.spMin(n)` | `sp` capped at the design value — text may shrink, never grow; equal to `sp` under the default bounds |
| `context.dg(n)` | both axes |
| `context.dm(n)` | larger axis |
| `context.edgeInsets({all, horizontal, vertical, left, top, right, bottom})` | `horizontal` by `w`, `vertical` by `h`, `all` by `w` — physical sides |
| `context.edgeInsetsDirectional({all, horizontal, vertical, start, top, end, bottom})` | same axes; `start`/`end` flip with the text direction |
| `context.borderRadius({all, topLeft, topRight, bottomLeft, bottomRight})` | `r` |
| `context.verticalSpace(n)` / `context.horizontalSpace(n)` | a `SizedBox`, by `h` / `w` |
| `context.windowSizeClass` / `context.windowHeightClass` | window classes — work without a `ResponsiveInit` |

> [!CAUTION]
> **There is deliberately no `num` extension.** `16.w` **does not compile**. A number carries no context, so such an extension could only read a global singleton — and a widget reading a global never learns the metrics changed. Requiring a `BuildContext` makes the correct thing the only writable thing. There is no global instance, no imperative `init()`, no `setWidth()` helper and no rebuild flag — rebuild targeting is Flutter's job once the metrics live in an `InheritedWidget`.

`dart tools/arch_check/check.dart` rule **R7** rejects the bare form — the pattern `[\d)]\.(spMin|sp|dg|dm|w|h|r)\b(?!\s*\()` — in any file importing `core_responsive`, and is Gate 1 of `pr_quality_check.yml`.

> [!NOTE]
> A widget test that scales **must** wrap its subject in `ResponsiveInit`, or `ResponsiveScope.of` asserts. The package's own tests live in `platform/ui/responsive/test/`.

The assembly at the root of the tree (`_ResponsiveWrapper` in `platform/shell/app_shell/lib/main_scope.dart`) is described in [the app shell](06_app_shell.md#_responsivewrapper); choosing an axis, changing the design canvas, the scale policy and the adaptive widgets are in [`../guides/11_design_system.md`](../guides/11_design_system.md) (§4–§7).

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
| Error mapping | `src/error/dio_failure_classifier.dart` | `DioFailureClassifier` — `DioException` → `AppFailure` (timeouts → `NetworkFailure` 1003, `badResponse` → `AuthFailure` 401/403 or `ServerFailure` with the status, cancel → `ErrorCodes.REQUEST_CANCELLED`, …) |

`DioFailureClassifier` is how the kernel's `ErrorHandler` learns about Dio without importing it: an eager `@singleton` of this package's DI module whose `@PostConstruct` calls `ErrorHandler.registerClassifier`. The module runs in the `core` DI group, so the classifier is registered before any Dio client exists (all are lazy) and before any repository runs; `ApiClient`'s constructor registers it again, idempotently, for a client built outside DI. A unit test that drives a repository into a `DioException` without DI calls `DioFailureClassifier.ensureRegistered()` first. The apps' DI smoke tests assert the registration.

`NetworkConfig` is implemented **in the app shell's adapters package** (`platform_shell_adapters`), not here — that is what keeps `core_network` free of any storage dependency. Both refresh callbacks default to `null`, so a client with no refresh endpoint simply surfaces the `401` unchanged.

> [!CAUTION]
> **SSL pinning is only as good as its hash list.** `sslPinningHashes` currently returns `const []`, which disables pinning. `AppInitializer` logs an `ERROR` whenever the list is empty or the config is unregistered on any build that does not bypass validation — that is, everything but a debug build that explicitly declared `--flavor dev`, a missing or unknown flavor included (treated as `prod` for TLS), so the gap is visible rather than silent — but it is still a gap until you populate it. See [the networking guide](../guides/08_networking.md).

Full detail on the interceptor chain, the recursion guards around token refresh, and header redaction lives in [`../guides/08_networking.md`](../guides/08_networking.md).

---

## 7. `core_storage` — encrypted key–value storage

Provides the **mechanism only**. It defines no keys and no presets.

| Export | Purpose |
|:--|:--|
| `StorageInterface` | Backend contract |
| `StorageManager` | `@singleton`; resolves a backend by `StorageType`, initializes the secure backend, then the others, via `@PostConstruct(preResolve: true)` — secure first because its first-launch wipe shares a keystore namespace with the pref backend's master key |
| `StorageValue<T>` | Reactive wrapper over one key — `ChangeNotifier` + broadcast `Stream`, in-memory cache, auto-persist on write. Notifying after `dispose` is a no-op (`isDisposed`). The package's only workspace dependency is `platform_kernel` (`TypeHelper`) |
| `StorageType` | `pref` (SharedPreferences) · `secure` (hardware-backed) |
| `ObfuscatedString` / `ObfuscatedBytes` | RAM obfuscation |
| `PrefStorageImpl` / `SecureStorageImpl` | Internal, resolved via `@Named('Pref')` / `@Named('Secure')` |

### RAM obfuscation is a real protection, not a label

Beyond encrypting data at rest (AES-256-CBC with a per-write random IV), `StorageValue` keeps its **in-memory** value XOR-masked with a random mask, and reveals it only for the moment a read needs it. The master key receives the same treatment. This raises the bar against memory-dump inspection — a layer most templates omit entirely.

`SecureStorageImpl` never wipes the store on a platform error: a master-key read that fails (a locked Keychain before first unlock, a busy KeyStore) is retried and then rethrown with nothing deleted; only a master key that is present but unusable is replaced, and only an undecryptable value is dropped. `PrefStorageImpl` applies the same rule to its own master key: it falls back to a key in SharedPreferences only when that key opens the stored preferences or there are none to lose, and otherwise rethrows with every preference intact. See [the storage guide](../guides/06_storage.md).

### Ownership

Each consuming package declares its own `StorageValue` instances through an injected `StorageManager`, with its keys in that package's `utils/`. Current owners:

| Owner | Package | Keys | Backend |
|:--|:--|:--|:--|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | secure |
| `ThemeStorageImpl` | `platform_shell_adapters` | `themeMode` | pref |
| `LanguageStorageImpl` | `platform_shell_adapters` | `locale` | pref |
| `AppBootStorage` | `platform_shell_adapters` | `viewed_onboard` | pref |

See [`../guides/06_storage.md`](../guides/06_storage.md) for the step-by-step.

---

## 8. `core_database` — relational storage (Drift + SQLite)

Runs on a background isolate via `NativeDatabase.createInBackground`. Depends on **no other workspace package**.

This package is the **mechanism only**: it owns no database, no table and no DAO, and its DI module registers nothing. Each package that persists relational data declares **its own** database next to its own tables, DAO and data source, and opens it with the pieces below. The `cache` sample module's `CacheDatabase` (`modules/cache/data/lib/src/database/`) is the reference wiring.

| Area | Path | Contents |
|:--|:--|:--|
| Opening | `src/opening/` | `DriftDatabaseOpener` — opens any `GeneratedDatabase` on a background isolate, verifies it, quarantines a corrupt file |
| Connection | `src/connection/` | `DatabaseConnectionFactory` — file resolution, background executor |
| **Access** | `src/access/` | `IDatabaseHandle`, `DatabaseHandle` |
| **Migration** | `src/migration/` | `IDatabaseMigration`, `DatabaseMigrationRunner`, `driftMigrationStrategy` |
| Constants | `src/utils/database_constants.dart` | `DEFAULT_READ_POOL`, `BUSY_TIMEOUT_MS`, `CORRUPT_FILE_SUFFIX`, corruption / environment error markers |

Drift resolves `@DriftDatabase(tables:)` at compile time and requires a DAO to be `part of` its database library, so a database declared here would have to name the tables of whichever package owns them. Keeping databases package-owned buys one property: deleting a package deletes its database with it, and no other package can reach its rows. The trade-off is that SQL cannot join across package boundaries — crossing a bounded context belongs at the repository layer, not inside a query.

### Two contracts keep packages out of each other's tables

**`IDatabaseMigration`** — a package that changes the schema implements this next to its own tables and registers it in its own DI module, exactly as features contribute routes. `version` is the schema version the step *produces*; steps replay in order so a device that skipped releases still lands correctly. Duplicate versions are rejected at startup rather than silently applying one.

**`IDatabaseHandle`** — a data source asks for the accessor it needs instead of receiving a database object with every DAO on it:

```dart
ProfileLocalDataSource(IDatabaseHandle<ProfileDatabase> handle)
  : _dao = handle.accessor(ProfileDao.new);
```

> [!NOTE]
> Within one database this is **API-surface isolation, not enforced isolation**: the factory callback still receives the database object, so a determined caller can reach any DAO on it. The value is that crossing that line becomes a deliberate, reviewable act rather than an ordinary constructor parameter. Isolation *between* packages is the real barrier, and it is enforced by the package graph — a package that does not declare `data_cache` cannot name `CacheDatabase` at all.

Connection hardening (`foreign_keys = ON`, WAL journal mode, busy timeout) and the corruption-quarantine strategy are covered in [`../guides/07_database.md`](../guides/07_database.md).

---

## 9. `core_notifications` — push and local notifications

`PushNotificationService` wraps Firebase Messaging and `flutter_local_notifications`. Channel IDs and payload types live in `src/utils/notification_constants.dart`, with the package that consumes them — a notification channel ID has no business being readable by every package in the app.

Boot never waits on the user or the network: `init()` (awaited inside `configureDependencies()`) sets up Firebase, the channels, the listeners and the local-notifications plugin only. The permission prompts and FCM token registration run afterwards, un-awaited, and log failures instead of throwing — read the token from `tokenStream`, since `fcmToken` can still be `null` right after boot. Blocked payload types (`addBlockedTypes`) match case-insensitively. The grouped-inbox summary and title are app-supplied (`inboxSummaryBuilder` / `inboxTitleBuilder`, both `null` by default) so the text comes from the app's own localizations.

The service is an eager `@singleton` that injects `FirebaseOptions`, which each app registers from its own `lib/firebase/firebase_module.dart`. That is why an app's manifest lists `core_notifications` in a `notifications` group with `phase: after` rather than in `core`: `before` runs ahead of the app's own registrations. An app without push notifications leaves the group out.

---

## 10. State management — two branches, **not at parity**

The template supports Provider and BLoC. Be aware before choosing: both automate the core load → settle path now, but the Provider branch still ships far more around it.

| | `provider_state_management` | `bloc_state_management` |
|:--|:--|:--|
| Base class | `BaseProvider<T>` — full implementation | `BaseBloc` / `BaseCubit` — *extension point only, adds nothing* |
| Async helper | `executeOperation(OperationConfig(...))` handles loading/success/failure automatically | `emitResult` from `BlocResultMixin<T>` / `CubitResultMixin<T>` — the same, for a `BlocViewState<T>` state only; it also catches an operation that throws |
| State type | `ViewStateModel<T>` + `ViewState` (5 variants incl. `loadingMore`, data held on the model) | `BlocViewState<T>` (4 variants, carries its own payload) |
| Error shape | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — required |
| Extras | `StateManager`, `OperationExecutor`, `OperationGlobalConfig`, `LoadMoreMixin`, `ProviderStateListener`, `BaseViewWidget` | — |

> [!WARNING]
> `emitResult` (`platform/state/bloc/lib/src/result_emitter.dart`) covers a Bloc or Cubit whose state is `BlocViewState<T>`: loading, `Result` unwrap, `none`/`cancel` undoing its own loading, exceptions through `ErrorHandler`. A Bloc with its **own Freezed state** still unwraps `Result<T>` and emits loading/terminal states by hand in every handler, and the BLoC branch has no counterpart for `OperationGlobalConfig`, `errorStateBuilder` or `LoadMoreMixin`. `bloc_state_management` depends on `platform_kernel` for `ErrorHandler` — a platform → platform edge, not one of the `→ domain_core` exceptions.

### `BlocViewState<T>`

The BLoC state type is `BlocViewState<T>`, **not** `ViewState`. Both packages export from public barrels, and the Provider branch exports a semantically different `ViewState`. The distinct name is what lets a file import both barrels without a compile-time collision.

`OperationGlobalConfig` exposes read-only getters, and `setup()` merges hook by hook: a hook the second call omits (or passes as `null`) keeps its earlier value, while one it passes **replaces** the earlier one — each hook holds one callback, and two calls never chain. `null` therefore cannot clear a hook; `reset()` clears them all, and exists for tests.

Practical usage for both branches: [`../guides/03_state_management.md`](../guides/03_state_management.md).

---

## 11. Web builds — honest status

Measured with `flutter build web` on `apps/admin` after scaffolding `web/` (`flutter create --platforms=web .` — neither app ships a `web/` folder), then loading the release build in headless Chromium.

| App | Compiles (dart2js; the Wasm dry run passes too) | Boots |
|:--|:--|:--|
| `apps/admin` (auth + settings) | yes | yes — to the sign-in screen, with `flutter_secure_storage`'s WebCrypto store and `shared_preferences` working (the page must be a secure context: `https` or `localhost`) |
| `apps/mobile` (every sample module) | **no** — `core_database` imports `package:drift/native.dart`, which pulls `sqlite3`'s `dart:ffi` | — |

What makes the shared boot path web-safe:

- `dart:io` **compiles** on the web; only *calling* most of it fails. The shell never calls it there: `runShellApp` checks `kIsWeb` before `Platform.isIOS`, `GoRouteDataCustom.buildPage` returns before its `Platform.isIOS` branch, and `core_network` uses `dart:io` only for header-name constants and `is SocketException` checks — Dio itself switches to the browser adapter.
- `AppInitializer` installs **no** `HttpOverrides` on the web and logs once, at `INFO`, that the browser validates certificates. The browser owns TLS, so neither pinning nor the dev-flavor bypass can apply; installing one anyway was harmless but suggested otherwise, and the "not pinned" `ERROR` it logged described a misconfiguration the web cannot fix.

Known gaps, none fixed here:

- `apps/mobile` needs a web database before it can even compile: drift's `WasmDatabase` (the `sqlite3.wasm` + drift worker assets), opened through a conditional import in `core_database`'s connection factory.
- `MainScope` calls `FlutterNativeSplash.remove()` on every platform; on the web it throws `PlatformException(… removeSplashFromWeb …)` unless `flutter_native_splash` generated web assets for that app. The error is uncaught but not fatal — the app still boots — and it reaches the crash reporter on every web start.
- `AppInfoHelper.getDeviceInfo` / `getDeviceString` / `platformName` branch on `Platform.isAndroid`, which **throws** on the web. Nothing calls them during boot; a screen that does needs a `kIsWeb` guard first.
- `core_notifications` (`apps/mobile` only) initialises Firebase with the app's per-flavor options, which describe no web app.

---

## 12. Dependency map

Local (workspace) dependencies only — pub.dev packages omitted. Which group each package sits in, and which direction the groups may depend in: [§ 0](#where-a-package-lives--the-six-groups).

| Package | Depends on |
|:--|:--|
| `domain_core` | *(none)* |
| `core_database` | *(none)* |
| `core_di` | *(none)* |
| `core_responsive` | *(none)* |
| `platform_kernel` | `domain_core` *(approved exception — `ErrorHandler` produces `AppFailure`)* |
| `core_common` | `platform_kernel`, `core_di` |
| `core_network` | `platform_kernel` |
| `core_notifications` | `platform_kernel` |
| `core_storage` | `platform_kernel` |
| `data_core` | `platform_kernel`, `domain_core` |
| `core_base_ui` | `core_common`, `core_di`, `core_responsive` |
| `bloc_state_management` | `platform_kernel`, `domain_core` *(approved exception — `AppFailure` for `BlocViewState.error`)* |
| `provider_state_management` | `core_common`, `core_responsive`, `domain_core` *(approved exception)* |
| `core_ui_kit` | `core_common`, `core_base_ui`, `core_responsive` |
| `platform_shell_adapters` | `core_common`, `core_di`, `core_network`, `core_storage`, `core_ui_kit` (`RetryDialog` only) |
| `platform_app_shell` | `core_base_ui`, `core_common`, `core_di`, `core_responsive`, `core_ui_kit`, `provider_state_management`, `platform_shell_adapters` |

No arrow in this table points at `modules/*/feature` or `modules/*/data` — that is the invariant to preserve.
