# The Core Layer

This document answers **"what is inside `platform/*`, and which package should I reach for?"**. After reading it you should be able to pick the right core package for a task — and recognise when what you are about to add does *not* belong in core at all.

Core packages are **infrastructure**. They provide mechanisms; they never encode business rules, and they never know a feature exists.

---

## 0. The rules that govern every core package

Three rules apply to everything on this page — RULE-01, RULE-44 / RULE-46 (mechanism, not policy) and RULE-09 in the [registry](../reference/01_rules.md#rule-registry).

**Core must not depend on features or data.** Three approved exceptions exist, listed in [the overview](01_overview.md#the-approved-exceptions). `tools/arch_check/check.dart` enforces the list on every PR.

**Core provides mechanism, not policy.** `core_storage` gives you `StorageValue<T>`; it does not decide that a key called `token` exists. `core_database` gives you a connection and a migration contract; it does not know your tables' business meaning. Whenever a core package starts naming a specific domain concept, that name belongs somewhere else.

**Every package keeps its constants in its own `utils/` folder.** One approved exception: design tokens in `core_base_ui/src/styles/` stay where they are — see [`core_base_ui`](#3-core_base_ui--design-system) below.

### Where a package lives — the six groups

`platform/` is split into six group folders by role. Only the folder says which group a package is in — every package **name** is unchanged (`core_di` is still `core_di`, now at `platform/foundation/contracts`), so imports, `app_manifest.yaml` and the dependency names in each `pubspec.yaml` do not mention groups at all.

| Group | Folder | Packages (folder) | What belongs here | May depend on |
|:--|:--|:--|:--|:--|
| **foundation** | `platform/foundation/` | `platform_kernel` (`kernel/`), `core_di` (`contracts/`), `core_common` (`common/`) | What every other package builds on: the service locator and error handling, the cross-module DI contracts, Flutter-bound helpers. No I/O, no widgets, no transport type | foundation, `domain_core` |
| **layers** | `platform/layers/` | `domain_core` (`domain/`), `data_core` (`data/`) | The base contracts of the domain and data layers — `Result<T>`, `AppFailure`, `BaseEntity`, `BaseRepository` — that `modules/*/domain` and `modules/*/data` extend | `domain_core`: nothing. `data_core`: foundation, `domain_core` |
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

Two constants files live at the bottom of the stack, because they are genuinely global — both in `platform_kernel`'s `src/utils/`: `EnvConstants` (`String.fromEnvironment` values) and `ErrorCodes` ([`error_codes.dart`](../../../platform/foundation/kernel/lib/src/utils/error_codes.dart) — the failure codes `ErrorHandler` and `BaseRepository` assign when there is no HTTP status, e.g. `REQUEST_CANCELLED`, `RESPONSE_REJECTED`, `UNKNOWN`, all outside the HTTP range so a 5xx is always a real one).

> [!CAUTION]
> Before adding a constant to `core_common`, ask: *would more than one unrelated domain read this?* If the answer is no, it belongs in the owning package's `utils/`.

**Firebase options are not here either.** They name one bundle ID, so they belong to one app: each app that uses Firebase owns a `lib/firebase/firebase_module.dart` registering its per-flavour `FirebaseOptions` (the sample's is [`apps/mobile/lib/firebase/firebase_module.dart`](../../../apps/mobile/lib/firebase/firebase_module.dart)). While that module sat in `core_common`, a second app would have inherited the mobile app's Firebase identity.

---

## 2. `core_di` — the DI Hub

Contracts only. No implementations, no business logic. It is the neutral ground where the platform meets the modules — and every contract in it is **product-neutral**: named for what the platform needs (a session, a location), never for the module that happens to provide it.

| Contract group | Path | Purpose |
|:--|:--|:--|
| Routing | `src/routing/` | `IFeatureRouteModule`, `INavDestinationModule`, `IAppEntryLocation`, `ISignInLocation` / `IPostSignInLocation` (where the shell sends a signed-out / signed-in user), `IDashboardRouteModule`, `NavigatorKeys` |
| Session | `src/session/` | `SessionPrincipal`, `SessionFailure`, `ISessionState` (shell-facing), `ISessionStatusStream` (feature-facing: state shared between a Provider and a BLoC feature), `ISessionRefreshListenable`, `ISessionGateway` (transport) — implemented by whichever module owns sign-in |
| Storage contracts | `src/theme/`, `src/language/` | `IThemeStorage`, `ILanguageStorage` — implemented in the app shell's adapters package (`platform_shell_adapters`) |
| Localization | `src/i_feature_localization.dart` | `IFeatureLocalization` — each feature contributes its own delegate |
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

### Why the colour and font-size rules are review-held

They were considered and deliberately left to review. A check for `Colors.<name>` would have to allow the places a literal colour is *correct* — `AppShadows`, which is the token file, and every modal scrim, where Flutter's own `ModalBarrier` is a fixed black and a theme-aware value would *lighten* the screen in dark mode. On this tree that is seven approved uses against two real ones, and a rule whose exception list outweighs its findings teaches people to skim it.

The repo also forbids suppression comments, so there is no honest escape hatch for the legitimate cases. Review it is — which is exactly why three dark-mode bugs survived in `core_ui_kit` until they were audited for, and worth knowing when you copy a widget out of it.

### `ThemeProvider` reacts to OS theme changes

`ThemeProvider` is a `@lazySingleton` that mixes in `WidgetsBindingObserver`. Under `ThemeMode.system` the OS brightness can change while the app runs, so it overrides `didChangePlatformBrightness()` and rebuilds — but only when the mode actually *is* `system`, so an explicit light/dark choice never triggers a wasted rebuild.

`WidgetsBindingObserver` was chosen over assigning `platformDispatcher.onPlatformBrightnessChanged`: that field is a **single** slot, so whoever assigns last silently wins. For an app-wide singleton competing with the framework and plugins, that is a real hazard.

The observer is removed in `dispose()`, which is annotated `@disposeMethod` so GetIt invokes it on container reset — without it, every `resetDependencies()` in a test would leave a stale observer registered.

The override, in `platform/ui/design_system/lib/src/theme/theme_provider.dart`:

```dart
// platform/ui/design_system/lib/src/theme/theme_provider.dart
/// Called by the framework when the OS switches between Light and Dark.
///
/// Only [ThemeMode.system] derives its appearance from the platform, so an
/// explicit light/dark choice is left untouched — no wasted rebuild.
@override
void didChangePlatformBrightness() {
  super.didChangePlatformBrightness();
  if (_themeMode != ThemeMode.system) return;

  // Refresh the status/navigation bar styling for the new brightness…
  setSystemTheme();
  // …and rebuild consumers, because `currentTheme` now resolves differently.
  notifyListeners();
}
```

Cleanup is wired into DI:

```dart
@disposeMethod
@override
void dispose() {
  if (_isObservingPlatform) {
    WidgetsBinding.instance.removeObserver(this);
```

The persisted preference is read through `IThemeStorage` — see [`../guides/06_storage.md`](../guides/06_storage.md#9-share-the-value-across-a-package-boundary).

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

How to declare a service, opt a request out, add a second client or turn pinning on: [`../guides/08_networking.md`](../guides/08_networking.md). What happens inside the client follows.

### `ApiClient` defaults

`core_network` never hard-codes credentials or UI. It takes everything through `NetworkConfig` (below), which the app shell implements.

```dart
// platform/infra/network/lib/src/api_client.dart
@lazySingleton
class ApiClient {
  final NetworkConfig _config;

  ApiClient(this._config);

  /// Default base options for Dio.
  BaseOptions get _defaultOptions => BaseOptions(
    baseUrl: EnvConstants.BASE_URL,
    connectTimeout: NetworkConstants.CONNECT_TIMEOUT,
    receiveTimeout: NetworkConstants.RECEIVE_TIMEOUT,
    sendTimeout: NetworkConstants.SEND_TIMEOUT,
    followRedirects: false,
    headers: {HttpHeaders.contentTypeHeader: ContentType.json.value},
  );
```

### The interceptor chain

Dio runs interceptors in the order they were added — for `onRequest` **and** for `onError`. The real order in `createClient()` is:

```
1. AuthInterceptor            → attaches Authorization + language headers
2. RefreshTokenInterceptor    → catches 401, renews the session, replays  (only if configured)
3. RetryInterceptor           → catches timeout / connection errors
4. LoggingInterceptor         → structured logs (debug builds only)
```

```dart
// platform/infra/network/lib/src/api_client.dart
dio.interceptors.add(
  AuthInterceptor(
    getToken: _config.getToken,
    getLocale: _config.getLocale,
  ),
);

// Renewing an expired session must happen before the retry pass,
// otherwise a 401 would be replayed with the same stale token.
// Only wired when the app supplies a refresh callback; without one a
// 401 surfaces to the caller unchanged.
final onRefreshToken = _config.onRefreshToken;
if (onRefreshToken != null) {
  final onRefreshFailed = _config.onRefreshFailed;
  dio.interceptors.add(
    RefreshTokenInterceptor(
      RefreshTokenHandler(
        dio: dio,
        currentToken: _config.getToken,
        onRefreshToken: onRefreshToken,
        onRefreshFailed: onRefreshFailed ?? () async {},
      ),
    ),
  );
}

dio.interceptors.addAll([
  RetryInterceptor(
    handleRetry: retryHandler.handleRetry,
    retryWhen: retryHandler.retryWhen,
  ),
  LoggingInterceptor(tag: NetworkConstants.CLIENT_LOG_TAG),
]);
```

Auth runs first so the token is attached before anything else; refresh sits ahead of retry so a 401 is *renewed* rather than replayed with the same dead token.

#### `AuthInterceptor`

Adds an upper-cased `language` header (falling back to the device locale, then to `vi`), and the bearer token when the request wants auth:

```dart
// platform/infra/network/lib/src/interceptors/auth_interceptor.dart
if (needAuthentication) {
  final token = getToken() ?? '';
  if (token.isNotEmpty) {
    options.headers.addAll({
      HttpHeaders.authorizationHeader:
          '${NetworkConstants.BEARER_PREFIX} $token',
    });
  }
}
```

> [!NOTE]
> The language header key is the non-standard `'language'`, not `Accept-Language`. Match it on the server side.

#### `RetryInterceptor`

Only transport failures qualify — **not** HTTP status codes:

```dart
// platform/infra/network/lib/src/handlers/retry_handler.dart
bool retryWhen(DioExceptionType type) {
  return type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout;
}
```

Concurrent failures are collected into one queue — one entry per caller — and a **single** retry dialog is raised through `NetworkConfig.onRetryCallback`. If no callback is supplied, every queued request is cancelled instead of hanging. "Retry" takes every queued request out of the queue and replays it through the same `Dio`, marked `canRetry: false`: the auth and refresh interceptors run again (fresh token, a 401 is refreshed), a timeout re-queues the caller for the next dialog, and any other failure reaches the caller as *that* error, not the original timeout.

#### `LoggingInterceptor`

All three hooks are behind `kDebugMode`, and credential headers are masked even in debug:

```dart
// platform/infra/network/lib/src/interceptors/logging_interceptor.dart
Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) {
  const redactedKeys = {
    HttpHeaders.authorizationHeader,
    HttpHeaders.cookieHeader,
    HttpHeaders.setCookieHeader,
    HttpHeaders.proxyAuthorizationHeader,
  };

  return {
    for (final entry in headers.entries)
      entry.key: redactedKeys.contains(entry.key.toLowerCase())
          ? '***REDACTED***'
          : entry.value,
  };
}
```

Bodies are masked too, at any depth: a value under `password`, `token`, `access_token` / `accessToken`, `refresh_token`, `id_token`, `secret` or `client_secret` prints as `***REDACTED***` — a login request carries the password in its body and the response returns the token in its body.

### How the app supplies `NetworkConfig`

```dart
// platform/infra/network/lib/src/network_config.dart
abstract class NetworkConfig implements SslPinningConfig {
  String? Function() get getToken;
  String? Function() get getLocale;

  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  });

  Future<String?> Function()? get onRefreshToken => null;
  Future<void> Function()? get onRefreshFailed => null;

  @override
  List<String> get sslPinningHashes;
}
```

The two refresh getters default to `null`, so in an app with no refresh endpoint a `401` reaches the caller untouched.

The implementation delegates each value to whoever actually owns it, rather than reading storage itself:

```dart
// platform/shell/adapters/lib/src/network_config_impl.dart
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  NetworkConfigImpl(this._languageStorage);

  final ILanguageStorage _languageStorage;

  /// Null in a build that composes no auth module.
  ISessionGateway? get _session => getItOrNull<ISessionGateway>();

  @override
  String? Function() get getToken => () => _session?.readToken();

  @override
  String? Function() get getLocale =>
      () => _languageStorage.getLanguage().languageCode;

  /// Whether an auth module is composed — without resolving it: resolving
  /// the gateway while `Dio` is being built closes a dependency cycle.
  bool get _hasSession => getIt.isRegistered<ISessionGateway>();

  @override
  Future<String?> Function()? get onRefreshToken =>
      _hasSession ? _refreshSession : null;

  @override
  Future<void> Function()? get onRefreshFailed =>
      _hasSession ? _clearSession : null;
```

> [!IMPORTANT]
> `NetworkConfigImpl` imports no module. It reads the token through `ISessionGateway`, resolved with `getItOrNull` at call time rather than injected, so it constructs whether or not an auth module is in the build and no DI ordering can break it. With no gateway registered, `onRefreshToken` returns null — and `ApiClient` installs `RefreshTokenInterceptor` **only** when that is non-null, so a build without auth gets no refresh interceptor rather than one that can never succeed. `arch_check` R1 keeps it that way: it lives in `platform_shell_adapters`, and a `platform/` package may not import a module. See [`../guides/05_di.md`](../guides/05_di.md).

### The refresh-token flow

`_refreshSession` hands the work to `ISessionGateway`, which `data_auth` implements: the repository refreshes and persists the credentials, and the gateway re-reads the token from its owner. The config never persists anything itself:

```dart
// platform/shell/adapters/lib/src/network_config_impl.dart
Future<String?> _refreshSession() async => await _session?.refreshToken();

// modules/auth/data/lib/src/services/auth_session_gateway_impl.dart
@override
Future<String?> refreshToken() async {
  final result = await _repository.refreshToken();
  if (result.isSuccess) return _local.getUserToken();
  final failure = result.errorOrNull;
  if (isTransient(failure)) {
    throw StateError(
      'Session renewal did not reach the server: '
      '${failure?.message}',
    );
  }
  return null;
}

/// Whether [failure] says nothing about the session's validity — the
/// renewal never got an answer — so the session must be kept.
///
/// Exposed for tests: this predicate decides whether a user is signed out.
static bool isTransient(AppFailure? failure) {
  if (failure is NetworkFailure) return true;
  if (failure is! ServerFailure) return false;
  final code = failure.code;
  if (code == null) return false;
  return (code >= 500 && code < 600) || code == ErrorCodes.REQUEST_CANCELLED;
}
```

#### Rejected vs. unreachable

The gateway's answer decides what happens to the session:

| `refreshToken()` | Meaning | `RefreshTokenHandler` |
| :-- | :-- | :-- |
| a token | renewed | replays the request and every one waiting on it |
| `null` | the server **refused** (401/403, any 4xx, or a 200 whose envelope reports an error — `ErrorCodes.RESPONSE_REJECTED`) | calls `onRefreshFailed` once, rejects them all |
| throws | never got an answer (no network, a real HTTP 5xx, cancelled) — only these | rejects them all, **keeps the session** |

`onRefreshFailed` is `NetworkConfigImpl._clearSession`: the gateway drops the stored credentials, then `ISessionState.onSessionLost()` drops the owner to signed-out — the change `NavigatorWrapperWidget` routes to login on. Clearing storage alone would leave the user on screen, "signed in", with no token.

A `401` that arrives *after* a refresh finished — a request sent with the old token — does not start another one: `RefreshTokenHandler` compares the request's `Authorization` header with `NetworkConfig.getToken` and, when they differ, just replays it. With rotating refresh tokens a redundant refresh could otherwise invalidate the session it just renewed.

#### One refresh for N concurrent 401s

`RefreshTokenHandler` serialises everything behind a `Completer`. The first 401 performs the refresh; the rest wait on the same future:

```dart
// platform/infra/network/lib/src/handlers/refresh_token_handler.dart
// If a refresh is already in progress, wait for it to complete.
if (_completer != null) {
  final String? newToken = await _completer!.future;
  if (newToken != null) {
    // The token was successfully refreshed, retry the original request.
    return _retryRequest(err, handler);
  } else {
    // The token refresh failed, reject the original request.
    return handler.reject(err);
  }
}
```

The retry is `await`-ed deliberately:

```dart
// `await` keeps the refresh lock (`_completer`) held until the retry
// finishes; releasing it earlier would let a concurrent 401 start a
// second, redundant refresh.
return await _retryRequest(err, handler);
```

`FormData` bodies are rebuilt before replay, because a form stream can only be consumed once.

#### Three guards against infinite recursion

```dart
// platform/infra/network/lib/src/interceptors/refresh_token_interceptor.dart
/// Three guards keep the flow from looping:
/// 1. Requests that opted out of auth
///    ([NetworkConstants.EXTRA_NEED_AUTHENTICATION] `= false`) or out of
///    refresh ([NetworkConstants.EXTRA_CAN_REFRESH_TOKEN] `= false`) are
///    ignored, so the login and refresh calls never trigger a refresh.
/// 2. A request already replayed after a refresh is marked with
///    [NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] and is not refreshed a
///    second time.
/// 3. [RefreshTokenHandler] serialises concurrent `401`s behind a single
///    `Completer`, so N failing requests cause exactly one refresh.
```

Guard 2 is subtle — the flag is set **before** handing over, because the replay goes back through this same interceptor:

```dart
// Mark the options *before* handing over: `RefreshTokenHandler` replays
// this same RequestOptions through `dio.fetch`, which re-enters this
// interceptor. The flag makes that second pass fall through to `super`.
err.requestOptions.extra[NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] = true;
```

> [!NOTE]
> The sample's refresh *is* an HTTP call through this same client (`AuthRemoteDataSource.refreshToken`), so it and `login` carry `@Extra({NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false})` (guard 1); the refresh call also sets `EXTRA_CAN_RETRY: false`, because it runs at boot and inside another request's 401 and must fail fast rather than wait on a retry dialog. With no stored token `AuthRepositoryImpl.refreshToken` answers without a network call at all. Without it, a `401` from the refresh call enters `RefreshTokenHandler` while that handler's own refresh is still in flight, and waits on itself forever. Any endpoint of yours whose `401` means something other than "session expired" needs the same flag.

### When pinning is installed, and when it is skipped

When the hash list is empty, the initializer refuses to fail silently:

```dart
// platform/foundation/common/lib/src/config/app_initializer.dart
if (hashes != null && hashes.isNotEmpty) {
  HttpOverrides.global = _MyHttpSecurityPinningHttpOverrides(hashes);
} else {
  // Never fail silently here: without pinning the app still talks to the
  // server over plain TLS, so a proxy with a trusted root can read every
  // request. Surfacing it keeps a misconfiguration from shipping unnoticed.
  DynamicLogger.log(
    config == null
        ? 'SSL pinning skipped: no SslPinningConfig registered in GetIt. ...'
        : 'SSL pinning skipped: sslPinningHashes is empty. ...',
    tag: 'Security',
    level: LogLevel.ERROR,
  );
}
```

`_setupHttpOverrides` runs from `AppInitializer.initBeforeRunApp()`, which `runShellApp` calls right after `configureDependencies()` and **before** `MainScope` builds the splash. Timing is the whole point: the splash is already wrapped in every feature's `IAppTreeWrapper`, so a controller created there — auth restoring its session with a token refresh — can make the first request at once, and Dio's `IOHttpClientAdapter` keeps the `HttpClient` it created first for the life of the `Dio`. An override installed later, in `initService`, would never reach that client. `AppInitializer.init` calls `initBeforeRunApp()` again for a host that skipped it; the second call installs nothing. `platform/shell/app_shell/test/boot_order_test.dart` fails if the order regresses.

Certificate validation is bypassed (for local self-signed servers) **only in a debug build that explicitly declared the `dev` flavor** — `AppConfig.bypassesCertificateValidation`. Everything else goes through the pinning path: `staging`, `prod`, a `dev` profile or release build, and a build with a **missing or unknown** flavor, which is treated as `prod` and logged as an ERROR. This fails closed on purpose: `AppConfig.appFlavor` used to fall back to `dev`, so a build made without `--flavor` — release included — accepted every certificate. `appFlavor` itself (the DI environment) now falls back to `dev` in a debug build and to `prod` otherwise.

---

## 7. `core_storage` — encrypted key–value storage

Provides the **mechanism only**. It defines no keys and no presets.

| Export | Purpose |
|:--|:--|
| `StorageInterface` | Backend contract; also hosts the AES helpers and the reserved-key guard |
| `StorageManager` | `@singleton`; resolves a backend by `StorageType`, initializes the secure backend, then the others, via `@PostConstruct(preResolve: true)` — secure first because its first-launch wipe shares a keystore namespace with the pref backend's master key |
| `StorageValue<T>` | Reactive wrapper over one key — `ChangeNotifier` + broadcast `Stream`, in-memory cache, auto-persist on write. Notifying after `dispose` is a no-op (`isDisposed`). The package's only workspace dependency is `platform_kernel` (`TypeHelper`) |
| `StorageType` | `pref` (SharedPreferences) · `secure` (hardware-backed) |
| `ObfuscatedString` / `ObfuscatedBytes` | RAM obfuscation |
| `PrefStorageImpl` / `SecureStorageImpl` | Internal, resolved via `@Named('Pref')` / `@Named('Secure')` |

`core_storage` deliberately declares **zero keys**. It ships the machinery; every package declares its own values.

```dart
// platform/infra/storage/lib/core_storage.dart
/// Core Storage — encrypted key-value persistence layer.
///
/// Provides only the storage MECHANISM — no package/feature-specific keys
/// or presets are defined here. Each consumer (data layer, app shell, ...)
/// must declare its own [StorageValue] instances with its own keys via
/// [StorageManager], so no other feature can see or touch its data.
```

> [!NOTE]
> There is no shared preset object and no central key registry — no `StorageValuePresets`, no `StorageKeyConstants`. A single object holding every domain's keys would let any injector read and write another feature's data, so the mechanism deliberately offers no such object to reach for.

### Two encryption layers, plus RAM masking

**Layer 1 — software AES-256-CBC with a fresh IV per write.** Implemented once on `StorageInterface` so both backends inherit it:

```dart
// platform/infra/storage/lib/src/contracts/storage_interface.dart
/// Encrypt [data] using AES-CBC with a random IV.
///
/// Returns `"iv_base64:ciphertext_base64"`.
String encryptData(String data) {
  final rawBytes = _obfuscatedMasterKey!.reveal();
  final key = encrypter.Key(rawBytes);
  final aes = encrypter.AES(key, mode: encrypter.AESMode.cbc);
  final enc = encrypter.Encrypter(aes);

  final iv = encrypter.IV.fromSecureRandom(16);
  final encrypted = enc.encrypt(data, iv: iv);

  // Zero out key buffers immediately
  rawBytes.fillRange(0, rawBytes.length, 0);
  key.bytes.fillRange(0, key.bytes.length, 0);

  return '${iv.base64}:${encrypted.base64}';
}
```

A random IV per write means writing the same value twice produces different ciphertext — an observer cannot tell that a value was unchanged.

**Layer 2 — hardware.** The 256-bit master key lives in Keychain/KeyStore under `_internal_master_key`, generated on first launch:

```dart
// platform/infra/storage/lib/src/impl/secure_storage_impl.dart
if (masterKey == null) {
  // Generate a new 32-byte (256-bit) random key for AES
  final newKey = encrypter.Key.fromSecureRandom(_MASTER_KEY_BYTES).base64;
  await _storage.write(key: _MASTER_KEY_ID, value: newKey); // rethrows on failure
  masterKey = newKey;
}
```

**Layer 3 (not advertised elsewhere) — RAM masking.** Neither the master key nor a cached value sits in memory as readable bytes. Both are XOR-masked with a random mask, and revealed only for the instant they are used:

```dart
// platform/infra/storage/lib/src/contracts/storage_interface.dart
/// Container that obfuscates bytes in RAM using dynamic XOR masking.
class ObfuscatedBytes {
  ObfuscatedBytes(Uint8List originalBytes)
    : _mask = _generateRandomMask(originalBytes.length),
      _maskedBytes = Uint8List(originalBytes.length) {
    for (int i = 0; i < originalBytes.length; i++) {
      _maskedBytes[i] = originalBytes[i] ^ _mask[i];
    }
  }
```

`ObfuscatedString` (in `storage_value.dart`) does the same for cached values. This raises the bar for a memory-dump attack; it is not a substitute for the layers above.

#### When the Keychain misbehaves — retry, never wipe

Reading the master key can fail for reasons that pass: the Keychain before the first unlock after a reboot (a background launch), a busy KeyStore. `SecureStorageImpl` used to treat *any* such failure as corruption and call `deleteAll()` — which destroyed every secure value, including `PrefStorageImpl`'s master key, which lives in the same store. Now:

```dart
// platform/infra/storage/lib/src/impl/secure_storage_impl.dart
Future<String?> _readMasterKey() async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await _storage.read(key: _MASTER_KEY_ID);
    } catch (e) {
      final lastAttempt = attempt >= _MASTER_KEY_READ_ATTEMPTS;
      // … logged: WARNING while retrying, ERROR on the last attempt …
      if (lastAttempt) rethrow; // nothing deleted, no new key generated
      await Future<void>.delayed(_retryDelay * attempt);
    }
  }
}
```

| Failure | What happens |
| :-- | :-- |
| Platform error reading the master key | retried (3 attempts); if it persists, `init` **rethrows** with the store untouched — generating a fresh key would orphan every value sealed with the unreadable one |
| Master key present but unusable (not a 256-bit base64 key) | only that key is replaced; values sealed with it fail to decrypt and are dropped one by one by `read()` |
| Corruption of the plugin's own storage | handled natively: on Android `AndroidOptions.resetOnError` (on by default) resets what it cannot decrypt before the call returns |
| Platform error in `read(key)` | returns `null` **and keeps the value** — it is still there for the next read |
| A value that fails to decrypt or decode in `read(key)` | that one key is deleted and `null` returned, so one bad row cannot fail every launch |

#### The pref backend's master key — the same rule

`PrefStorageImpl` seals SharedPreferences values with a master key of its own, `_internal_pref_master_key`, kept in the same secure store. It used to fall back on *any* read error to a brand-new key in SharedPreferences — after a single transient Keychain error every stored preference (theme, locale, the onboarding flag) failed to decrypt and was deleted on its next read, and the next healthy launch orphaned whatever that session wrote. Now it never replaces a key that may still be good:

| Situation | What `PrefStorageImpl.init` does |
| :-- | :-- |
| Platform error reading the key | retried (3 attempts) before anything else is decided |
| Still failing, no stored preferences | a new key is kept in SharedPreferences — there is nothing it could orphan |
| Still failing, and a key in SharedPreferences opens the stored preferences | that key is used (a device where secure storage is unavailable) |
| Still failing, and the stored preferences depend on the unreadable key | **rethrows**, nothing written or deleted — the values open again once the platform recovers |
| Readable again while a SharedPreferences key exists | whichever key decrypts the stored values wins; a winning SharedPreferences key is moved into secure storage and removed from SharedPreferences |
| Key absent or unusable (not a 256-bit base64 key) | a new key is generated — in secure storage, or in SharedPreferences if secure storage refuses the write; values sealed with a lost key drop one by one in `read()` |

`StorageManager.initialize` runs the secure backend first, so a persistent Keychain failure normally surfaces there before the pref backend is asked. The tests (`platform/infra/storage/test/storage_test.dart`) drive both backends through a flaky `FlutterSecureStorage` fake.

#### The plugin's cipher options are pinned

Both backends open `flutter_secure_storage` (11.x) with the same explicit Android pair — `KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding` and `StorageCipherAlgorithm.AES_GCM_NoPadding` — and `KeychainAccessibility.first_unlock` on iOS. On Android the plugin records the pair it wrote with and, when the configured pair differs, re-encrypts the store (`migrateOnAlgorithmChange`, on by default) or, failing that, resets it (`resetOnError`, also on). Leave both options alone unless you mean to migrate every user's secure data.

This pair is what the template has written since its first release (10.x) and it is still the 11.x default, so the 10 → 11 upgrade reads existing values unchanged: same KeyStore alias, same wrapped key, no migration step. What 11.x dropped is the pre-10 ciphers (RSA-PKCS1, AES-CBC, EncryptedSharedPreferences). An app that ever shipped `flutter_secure_storage` 9.x or older must ship a 10.x release first — a device going straight from 9 to 11 loses its secure values, tokens and `PrefStorageImpl`'s master key included. On Android, `FlutterSecureStorage.checkUpgradeStatus()` (11.1+), called before the first read, reports whether that happened.

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

App-shell key classes live in `platform/shell/adapters/lib/src/utils/`. See [`../guides/06_storage.md`](../guides/06_storage.md) for the step-by-step.

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

How to give a package its own database, contribute a migration and test it: [`../guides/07_database.md`](../guides/07_database.md). The design behind it follows.

### The rule: `core_database` owns no database

`core_database` provides the **mechanism** only. It declares no database, no table and no DAO — its DI module registers literally nothing:

```dart
// platform/infra/database/lib/di/module.dart
/// `core_database` registers nothing on its own.
///
/// It provides the persistence MECHANISM — [DriftDatabaseOpener],
/// [driftMigrationStrategy], [IDatabaseMigration], [IDatabaseHandle] — and
/// deliberately owns no database, no table and no DAO. Registering a database
/// here would mean this package had to name the tables of whichever package
/// owns them.
@InjectableInit.microPackage()
void initMicroPackage() {}
```

**Each package that owns persisted data declares its own database**, next to its own tables, DAO and data source. The `cache` sample module's `CacheDatabase` (package `data_cache`, in `modules/cache/data`) is the reference wiring.

### Why — this is forced by Drift, not a preference

Two Drift facts drive the whole design:

1. `@DriftDatabase(tables: [...])` is resolved at **compile time**. There is no runtime table registration.
2. A DAO must be a **`part of`** its database library — Drift generates `_$XDaoMixin` and `$XTable` into that same library.

Put together: whichever package declares the database must name every table on it, and every DAO must live in that same library. A single shared `AppDatabase` would therefore force one package to know the tables of all the others — the same "one object knows everything" coupling the storage and constants ownership rules exist to prevent.

> [!NOTE]
> Moving a shared `AppDatabase` up into `apps/mobile/` does not solve this — it only relocates the god object, and the owning package still could not hold a usable DAO. Giving each package its own database is what actually removes the coupling.

### What you gain, and what you pay

| | |
|---|---|
| **Gain** | Deleting a package deletes its database with it. No other package references it, so nothing else breaks. |
| **Gain** | No package can reach another's rows — there is no shared object to reach through. |
| **Cost** | **SQL cannot join across package boundaries.** |

That cost is deliberate. Crossing a bounded context belongs at the repository layer — compose two repositories in a use case — not inside a single query.

### What `core_database` exports

| Export | Kind | What it does |
|---|---|---|
| `DriftDatabaseOpener` | `abstract final class` | Opens any `GeneratedDatabase` on a background isolate, **verifies** the connection, quarantines a corrupt file |
| `DatabaseConnectionFactory` | `abstract final class` | Resolves the file path in app documents, builds the background executor, quarantines files |
| `IDatabaseMigration` | abstract class | Contract a package implements to contribute **one** schema step |
| `DatabaseMigrationRunner` | class | Sorts, validates and replays those steps |
| `driftMigrationStrategy(...)` | function | The shared `MigrationStrategy`: migration dispatch + the per-connection `PRAGMA`s |
| `IDatabaseHandle<TDb>` / `DatabaseHandle<TDb>` | abstract class / class | How a data source reaches its database without holding every DAO |
| `DatabaseConstants` | class | Read-pool size, busy timeout, corruption/environment error markers, `.corrupt` suffix |

Notice every one of these is generic over `GeneratedDatabase`. `core_database` never names a concrete database class — that is the whole point.

### How the migration runner replays

```dart
// platform/infra/database/lib/src/migration/database_migration_runner.dart
Future<void> run(Migrator m, int from, int to) async {
  if (from == to) return;

  if (to > from) {
    for (final migration in _migrations) {
      if (migration.version > from && migration.version <= to) {
        await migration.upgrade(m);
      }
    }
    return;
  }

  // A downgrade from a schema this build has no step for is refused.
  final newestKnown = _migrations.isEmpty ? null : _migrations.last.version;
  if (newestKnown == null || newestKnown < from) {
    throw UnsupportedError('Cannot downgrade the schema from version $from …');
  }

  for (final migration in _migrations.reversed) {
    if (migration.version > to && migration.version <= from) {
      await migration.downgrade(m);
    }
  }
}
```

Three properties worth naming:

1. **A plain `if`, not `else if`.** A device that skipped several releases replays *every* intermediate step instead of jumping straight to the newest shape.
2. **Upgrades ascend, downgrades descend.** Order matters in both directions.
3. **Gaps are legal.** A release may ship no schema change, leaving that version number unused.
4. **A downgrade needs explicit steps.** Going from `from` down to `to` throws `UnsupportedError` unless a step is registered for `from` or above — the runner must know the schema it is leaving. Without that check it did nothing, and drift stamped the lower `user_version` over tables that still had the newer shape; reinstalling the newer build then replayed its upgrades against them (a duplicate column) and failed on every launch. The throw leaves the file and its version untouched, and `DriftDatabaseOpener` surfaces it as a startup error rather than quarantining the file. In practice an older build only has such steps if they shipped ahead of the change they reverse — otherwise installing an older build over a newer schema is unsupported.

Validation happens once, at construction — not mid-migration. Discovering a wiring mistake halfway through would leave the schema partially migrated.

> [!WARNING]
> **Drift 2.x has no `onDowngrade`** (the lockfile resolves 2.35.0). `MigrationStrategy` exposes only `onCreate`, `onUpgrade` and `beforeOpen`; Drift's own documentation notes that "schema version upgrades and downgrades will both be run here". `IDatabaseMigration.downgrade` is real and tested, but it rides on that single entry point via a `from`/`to` comparison. Implement it when the change is reversible; **throw a descriptive error when it is not**, so the failure is explicit instead of leaving a schema that no longer matches the running code.

### The `PRAGMA` settings, and why they are centralised

`PRAGMA` settings are **per-connection and are not stored in the file**, so they must be reapplied on every open. That is why they live in `beforeOpen`:

```dart
// platform/infra/database/lib/src/migration/drift_migration_strategy.dart
beforeOpen: (OpeningDetails details) async {
  // SQLite ships with foreign key enforcement OFF. Without this any
  // `references()` declared on a table is silently ignored, so broken
  // relations are only discovered as corrupt data much later.
  await database.customStatement('PRAGMA foreign_keys = ON');

  // Write-Ahead Logging lets readers run concurrently with a writer,
  // which a read pool (readPool > 0) requires, and avoids "database is locked"
  // under contention.
  await database.customStatement('PRAGMA journal_mode = WAL');

  // Wait for a held lock instead of failing instantly with SQLITE_BUSY.
  await database.customStatement('PRAGMA busy_timeout = $busyTimeoutMs');
},
```

| Pragma | Why it matters |
|---|---|
| `foreign_keys = ON` | **SQLite defaults this OFF.** Every `references()` you declare is silently ignored without it — a silent trap that surfaces much later as corrupt relations. |
| `journal_mode = WAL` | Readers run concurrently with a writer. Required by any read pool (`readPool > 0`; the default is `1`); avoids "database is locked" under contention. |
| `busy_timeout = 5000` | Waits for a held lock instead of failing instantly with `SQLITE_BUSY`. Default is `0`. |

`beforeOpen` runs on the **writer** connection only. The read pool — one more connection per reader, each on its own isolate — never sees it, so `DatabaseConnectionFactory` also passes drift a `setup` callback that applies `busy_timeout` to every connection it opens (`platform/infra/database/test/database_connection_factory_test.dart` reads it back through a reader). `journal_mode` needs no such help: WAL is stored in the file. `foreign_keys` is only enforced on writes, which never reach a reader.

WAL adds `-wal` and `-shm` sidecar files next to the database. SQLite converts an existing file automatically and reversibly. In-memory databases (tests) ignore this and stay in `memory` journal mode — which is exactly why the WAL test in `data_cache` runs against a **real file**.

This is centralised for one reason: a package that wrote its own `MigrationStrategy` and forgot `foreign_keys = ON` would lose referential integrity without any error.

### Corruption recovery: quarantine, never delete

Opening is registered with `@preResolve`, so anything thrown there aborts `configureDependencies()` and the app cannot start. A damaged file would mean a permanent crash loop.

`DriftDatabaseOpener.open` handles this — and the design leans hard towards *not* touching user data:

```dart
// platform/infra/database/lib/src/opening/drift_database_opener.dart
static Future<T> open<T extends GeneratedDatabase>(
  DriftDatabaseBuilder<T> build, {
  required String fileName,
  int readPool = DatabaseConstants.DEFAULT_READ_POOL,
}) async {
  try {
    return await _openVerified(build, fileName: fileName, readPool: readPool);
  } catch (error, stackTrace) {
    if (!isCorruptionError(error)) rethrow;
    // ... quarantine, then reopen empty
  }
}
```

Three deliberate decisions:

**The connection is verified, not assumed.** `createBackgroundExecutor` is lazy — it does not touch the file until the first statement. `_openVerified` runs a `SELECT 1` probe so a broken database fails *here* rather than at some unrelated call site later.

**The file is renamed, never deleted.**

```dart
// platform/infra/database/lib/src/connection/database_connection_factory.dart
/// The file is **renamed, never deleted** — if the corruption check ever
/// misfires the user's bytes are still recoverable from
/// `<fileName><CORRUPT_FILE_SUFFIX>`. Only one quarantined copy is kept;
/// an older one is replaced so repeated failures cannot fill the disk.
```

The `-wal` / `-shm` sidecars move with it, to `<fileName>.corrupt-wal` / `.corrupt-shm`: they belong to the quarantined database and must not be applied to the new one, and the WAL holds committed transactions not yet checkpointed — deleting it would lose the newest data.

**An environment marker vetoes a corruption match.**

```dart
@visibleForTesting
static bool isCorruptionError(Object error) {
  final message = error.toString().toLowerCase();

  final looksLikeEnvironment = DatabaseConstants.ENVIRONMENT_ERROR_MARKERS
      .any(message.contains);
  if (looksLikeEnvironment) return false;

  return DatabaseConstants.CORRUPTION_ERROR_MARKERS.any(message.contains);
}
```

| Treated as corruption → quarantine | Treated as environment → rethrow untouched |
|---|---|
| `database disk image is malformed` | `unable to open database file` |
| `file is not a database` | `disk i/o error` |
| `file is encrypted or is not a database` | `database or disk is full` |
| `malformed database schema` | `attempt to write a readonly database` |
| | `access denied` / `permission denied` / `operation not permitted` |

The predicate matches on message strings rather than a typed `SqliteException`. `sqlite3` *is* a declared dependency of `core_database` (the connection factory imports it), so the type is available — but it is not what reaches the opener. The connection runs on a background isolate (`NativeDatabase.createInBackground`), and drift hands an error raised there back as a `DriftRemoteException` whose `remoteCause` holds the original; `on SqliteException` would never match it. `DriftRemoteException.toString()` returns the cause's message, so matching the message covers an error from either side of the isolate boundary. A typed check is possible — unwrap `remoteCause` and test for `SqliteException` and its `extendedResultCode` — but it would still need the message fallback for anything else. Because string matching is fragile, the predicate is **biased towards not recovering**: if an environment marker appears, the database is left alone even when a corruption marker also matched.

Losing user data is worse than surfacing a startup error.

---

## 9. `core_notifications` — push and local notifications

`PushNotificationService` wraps Firebase Messaging and `flutter_local_notifications`. Channel IDs and payload types live in `src/utils/notification_constants.dart`, with the package that consumes them — a notification channel ID has no business being readable by every package in the app.

Boot never waits on the user or the network: `init()` (awaited inside `configureDependencies()`) sets up Firebase, the channels, the listeners and the local-notifications plugin only. The permission prompts and FCM token registration run afterwards, un-awaited, and log failures instead of throwing — read the token from `tokenStream`, since `fcmToken` can still be `null` right after boot. Blocked payload types (`addBlockedTypes`) match case-insensitively. The grouped-inbox summary and title are app-supplied (`inboxSummaryBuilder` / `inboxTitleBuilder`, both `null` by default) so the text comes from the app's own localizations.

The service is an eager `@singleton` that injects `FirebaseOptions`, which each app registers from its own `lib/firebase/firebase_module.dart`. That is why an app's manifest lists `core_notifications` in a `notifications` group with `phase: after` rather than in `core`: `before` runs ahead of the app's own registrations. An app without push notifications leaves the group out.

---

## 10. State management — two branches, **not at parity**

The template supports Provider and BLoC. Be aware before choosing: both automate the core load → settle path now, but the Provider branch still ships far more around it. Picking one without knowing where they differ is the most common source of frustration.

| | `provider_state_management` | `bloc_state_management` |
|:--|:--|:--|
| Base class | `BaseProvider<T>` — full implementation | `BaseBloc<Event, State>` / `BaseCubit<State>` — *extension point only, adds nothing over `Bloc` / `Cubit`* |
| Lines of shared machinery | Full: `StateManager`, `OperationExecutor`, `LoadMoreMixin`, `ensureInitialized` | `BlocResultMixin` / `CubitResultMixin` (`emitResult`) — nothing else |
| Async helper / `Result<T>` unwrapping | `executeOperation(OperationConfig(...))` handles loading/success/failure automatically | `emitResult` from `BlocResultMixin<T>` / `CubitResultMixin<T>` — the same, **for a `BlocViewState<T>` state only**; by hand for a custom state |
| `AppFailure` → UI error mapping | `errorStateBuilder` hook | None — `error(AppFailure)` carries it as-is; map it in the view, or by hand into a custom state |
| Loading state | Set automatically (skipped once data is loaded) | `emitResult` emits it (skipped while a `success` is on screen) |
| An operation that **throws** | Propagates — the repository's `execute()` is what turns exceptions into `Result.failure` | `emitResult` catches it: `ErrorHandler.handleError` → `error(...)`, and the raw error goes to `addError` (`BlocObserver.onError`) |
| Global hooks | `OperationGlobalConfig` (`onStart`/`onSuccess`/`onFailure`/`onFinish`) | None |
| Pagination | `LoadMoreMixin` | None |
| State type | `ViewStateModel<T>` wrapping `ViewState` (5 variants incl. `loadingMore`, data held on the model) | `BlocViewState<T>` (optional; 4 variants, carries its own payload) or your own Freezed state |
| Error shape | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — required |
| Rendering | `BaseViewWidget` … `BaseViewWidget6`, `PaginatedViewWidget*` | `BlocBuilder` (from `flutter_bloc`) |
| Declarative side effects | `ProviderStateListener` / `MultiProviderStateListener` | `BlocListener` (from `flutter_bloc`) |

> [!WARNING]
> `emitResult` (`platform/state/bloc/lib/src/result_emitter.dart`) covers a Bloc or Cubit whose state is `BlocViewState<T>`: loading, `Result` unwrap, `none`/`cancel` undoing its own loading, exceptions through `ErrorHandler`. A Bloc with its **own Freezed state** still unwraps `Result<T>` and emits loading/terminal states by hand in every handler, and the BLoC branch has no counterpart for `OperationGlobalConfig`, `errorStateBuilder` or `LoadMoreMixin`. `bloc_state_management` depends on `platform_kernel` for `ErrorHandler` — a platform → platform edge, not one of the `→ domain_core` exceptions.

### `BlocViewState<T>`

The BLoC state type is `BlocViewState<T>`, **not** `ViewState`. Both packages export from public barrels, and the Provider branch exports a semantically different `ViewState`. The distinct name is what lets a file import both barrels without a compile-time collision. The two are genuinely different:

| | Provider `ViewState` | `BlocViewState<T>` |
|---|---|---|
| Generic | No | Yes |
| Variants | 5 (adds `loadingMore`) | 4 |
| Carries data | No — data sits on `ViewStateModel<T>` | Yes — `success(T data)` |
| Error payload | `error({ErrorState? error})`, nullable | `error(AppFailure error)`, required |

`BlocViewState` is **optional**. A screen with richer needs declares its own Freezed state and uses `BaseBloc<Event, CustomState>`.

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
- `AppInitializer` installs **no** `HttpOverrides` on the web and logs once, at `INFO`, that the browser validates certificates. The browser owns TLS, so neither pinning nor the dev-flavor bypass can apply; installing one anyway was harmless but suggested otherwise, and the "not pinned" `ERROR` it logged described a misconfiguration the web cannot fix. Tests stand in for `kIsWeb` with `AppInitializer.debugIsWebOverride`.

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
