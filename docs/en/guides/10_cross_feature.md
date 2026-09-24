# Guide: Cross-Feature Communication

This guide answers **"feature A needs something from feature B — how, without importing it?"**.
Feature packages may never import each other — no exception; shared widgets come from the core package `core_ui_kit` — so every
interaction goes through a contract that a *neutral* package owns.

By the end you will know which of the six models fits your case, and how to wire it so that
deleting either feature leaves the app running.

---

## The rule

```
feature_a  ──✗──>  feature_b        forbidden, always
feature_a  ──✓──>  core_di          contract lives here
feature_b  ──✓──>  core_di          implementation registers against it
```

`core_di` is the **DI Hub**: it holds interfaces, not logic. Both sides depend on it, neither
depends on the other. That is what makes a feature removable.

---

## Decision table

| I need to… | Use | Model |
| :-- | :-- | :-- |
| Run the same business operation as another feature | Shared **UseCase** from `domain_*` | 1 |
| Read/write storage, call an API, log | **Core service** (`core_storage`, `core_network`…) | 2 |
| React continuously to another feature's state (login/logout…) | **Agnostic stream** on `core_di` | 3 |
| Persist a pure-UI preference (theme, locale) | **Bypass Domain** via a `core_di` storage interface | 4 |
| Embed a widget that only another feature can build | **Widget builder interface** on `core_di` | 5 |
| Trigger a one-shot UI action another feature owns (logout…) | **Action handler** on `core_di` | 6 |
| Just navigate to another feature's screen | **Navigator interface** — see [`04_routing.md`](04_routing.md) | — |

---

## Model 1 — Shared Domain UseCase

**Use when** two features perform the same business operation.
**Don't use when** the thing you need is UI state rather than business logic.

Both features inject the same use case from the domain package. Neither knows the other exists:

```dart
// In any feature's controller
class CheckoutProvider extends BaseProvider<PaymentEntity> {
  CheckoutProvider(this._loginUseCase);

  final LoginUseCase _loginUseCase;
}
```

The use case lives in `domain_auth`; both `feature_auth` and `feature_checkout` depend on
`domain_auth`, never on each other. This is the cheapest model — reach for it first.

---

## Model 2 — Core Service

**Use when** the capability is infrastructure, not business logic.
**Don't use when** the behaviour belongs to a specific feature.

Inject `StorageManager`, `Dio`, `IDatabaseHandle<TDb>` and friends directly from the relevant `core_*`
package. Nothing feature-specific is involved, so there is no coupling to break.

See [`06_storage.md`](06_storage.md), [`08_networking.md`](08_networking.md),
[`07_database.md`](07_database.md).

---

## Model 3 — Agnostic Stream (dual registration)

**Use when** feature A must react *continuously* to state owned by feature B — and the two may use
different state-management libraries.
**Don't use when** you need a one-shot action (use model 6) or a plain value read (use model 4).

This is the most important pattern in the codebase. `feature_auth` uses Provider;
`feature_home` uses BLoC. Neither may import the other, and neither should learn the other's
state-management tool.

### Step 1 — neutral interface in `core_di`

Real code from
[`platform/foundation/contracts/lib/src/agnostic_streams/i_auth_status_stream.dart`](../../../platform/foundation/contracts/lib/src/agnostic_streams/i_auth_status_stream.dart):

```dart
abstract class IAuthStatusStream {
  /// Emits on every authentication state change; `null` means signed out.
  Stream<AuthPrincipal?> get authStatusStream;

  /// The currently signed-in principal, or `null` when signed out.
  ///
  /// Read this for the state at subscription time — [authStatusStream] is a
  /// broadcast stream and does not replay its last value to new listeners.
  AuthPrincipal? get currentUser;
}
```

Two deliberate design decisions worth understanding:

**Why `AuthPrincipal` and not `UserEntity`.** A `core_di` contract may not name a type from a
`domain_*` package (`.agents/AGENTS.md` §8.4): the import would make every consumer depend on
`domain_auth` at compile time, which `getItOrNull` cannot soften. So `core_di` owns a small value
type,
[`AuthPrincipal`](../../../platform/foundation/contracts/lib/src/agnostic_streams/auth_principal.dart), and the auth
feature narrows its entity to it at the boundary (`toPrincipal` in step 2). The contract is
deliberately smaller than the entity — a consumer that only asks *who is signed in* never sees the
rest.

**Why `currentUser` exists alongside the stream.** `authStatusStream` is a *broadcast* stream: it
does not replay its last value to new listeners. A consumer subscribing after login would sit blind
until the next change, so it reads `currentUser` for the state at subscription time.

### Step 2 — concrete implementation in the owning feature

Real code from
[`modules/auth/feature/lib/src/services/auth_status_stream_impl.dart`](../../../modules/auth/feature/lib/src/services/auth_status_stream_impl.dart):

```dart
/// Implementation of [IAuthStatusStream] provided by `feature_auth`.
@singleton
class AuthStatusStreamImpl implements IAuthStatusStream {
  final _controller = StreamController<AuthPrincipal?>.broadcast();
  AuthPrincipal? _currentUser;

  @override
  Stream<AuthPrincipal?> get authStatusStream => _controller.stream;

  @override
  AuthPrincipal? get currentUser => _currentUser;

  /// Called by `feature_auth` when the session settles.
  void updateAuthStatus(UserEntity? user) {
    final principal = toPrincipal(user);
    _currentUser = principal;
    _controller.add(principal);
  }

  /// The one place `UserEntity` is narrowed for the outside world.
  static AuthPrincipal? toPrincipal(UserEntity? user) {
    if (user == null) return null;
    return AuthPrincipal(
      id: user.id,
      displayName: user.name,
      email: user.email,
      roles: {if (user.role != null) user.role!.name},
    );
  }
}
```

### Step 3 — bind the interface to that same instance

Real code from
[`modules/auth/feature/lib/di/module.dart`](../../../modules/auth/feature/lib/di/module.dart):

```dart
@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDiModule {
  @singleton
  IAuthStatusStream bindIAuthStatusStream(AuthStatusStreamImpl impl) => impl;
}
```

**Why register twice.** The concrete class is registered so `feature_auth` can inject
`AuthStatusStreamImpl` directly and call the writer method `updateAuthStatus` — no `getIt` lookup,
no `as` cast. The `@module` binding then exposes the *same instance* under the read-only interface
for everyone else. Owner writes, consumers read.

### Step 4 — consume from another feature

Real code from
[`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`](../../../modules/home/feature/lib/src/bloc/home_profile_bloc.dart):

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<AuthPrincipal?>> {
  HomeProfileBloc(@factoryParam this._authStatusStream)
    : super(const BlocViewState.initial()) {
    // …
  }

  final IAuthStatusStream? _authStatusStream;
  StreamSubscription<AuthPrincipal?>? _subscription;
```

`feature_home` depends on `core_di` alone — not on `feature_auth`, and not on `domain_auth` either: the contract carries `AuthPrincipal`, a type `core_di` owns, so no domain package crosses the boundary.

The stream is **optional** on purpose. `IAuthStatusStream` is registered by `feature_auth`, which an app may leave out, so the bloc takes it as an `@factoryParam` and the route supplies it — real code from [`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

```dart
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no IAuthStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<IAuthStatusStream>(),
      ),
      child: const HomePage(),
    );
```

A required constructor parameter would compile just as well — and then DI could not build `HomeProfileBloc` at all in a build without auth. The constructor still receives its dependency (no lookup in business logic); only the *optional* lookup moves to the route.

> [!CAUTION]
> Always cancel the subscription in `close()` / `dispose()`. A broadcast stream will happily keep a
> disposed controller alive.

---

## Model 4 — Bypass Domain for pure-UI state

**Use when** the value is a UI preference that never leaves the device — theme mode, locale.
**Don't use when** the value has business meaning or is sent to a server.

The chain skips the domain layer entirely:

```
ThemeProvider  →  IThemeStorage (core_di)  →  ThemeStorageImpl (app shell)  →  StorageValue
```

The interface — real code from
[`platform/foundation/contracts/lib/src/theme/i_theme_storage.dart`](../../../platform/foundation/contracts/lib/src/theme/i_theme_storage.dart):

```dart
import 'package:material_ui/material_ui.dart';

/// Interface for theme storage, decoupling ThemeProvider from the actual storage implementation.
abstract class IThemeStorage {
  /// Gets the current ThemeMode from storage.
  ThemeMode getThemeMode();

  /// Saves the given ThemeMode to storage.
  void saveThemeMode(ThemeMode mode);
}
```

**Why bypass Domain here.** A use case would have to accept and return `ThemeMode`, which is a
`package:flutter/material.dart` type. The domain layer is pure Dart and **cannot import Flutter**,
so routing theme through it is impossible by construction — not a shortcut, a hard constraint.

The implementation lives in the app shell (`platform/shell/adapters/lib/src/theme_storage_impl.dart`) because that is
where `core_base_ui`'s provider and `core_storage`'s mechanism meet without creating a cycle.


---

## Model 5 — Widget Builder interface

**Use when** feature A must render a widget whose content only feature B knows how to build.
**Don't use when** the widget is generic UI — that belongs in `core_ui_kit`.

Declare the builder contract in `core_di`:

```dart
// platform/foundation/contracts/lib/src/builders/i_profile_card_builder.dart
import 'package:flutter/widgets.dart';

abstract class IProfileCardBuilder {
  Widget build(BuildContext context, {required String userId});
}
```

Implement it in the owning feature and register with `@Injectable(as: IProfileCardBuilder)`.
Consumers resolve it defensively so the app survives the feature being removed:

```dart
final builder = getItOrNull<IProfileCardBuilder>();
return builder?.build(context, userId: id) ?? const SizedBox.shrink();
```

---

## Model 6 — Action Handler

**Use when** feature A must trigger a one-shot, UI-bound action that feature B owns — logout being
the canonical case.
**Don't use for** plain navigation (use a Navigator interface) or for domain logic (use a UseCase).

The interface — real code from
[`platform/foundation/contracts/lib/src/actions/i_auth_action_handler.dart`](../../../platform/foundation/contracts/lib/src/actions/i_auth_action_handler.dart):

```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```

The implementation — real code from
[`modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart`](../../../modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';

@Injectable(as: IAuthActionHandler)
class AuthActionHandlerImpl implements IAuthActionHandler {
  @override
  void logout(BuildContext context) {
    context.read<AuthProvider>().logout();
  }
}
```

`feature_settings` calls `getItOrNull<IAuthActionHandler>()?.logout(context)` — it never learns
that logout is a Provider call, or that `AuthProvider` exists.

Handler implementations live in the owning feature's `handlers/` directory and are named
`*ActionHandlerImpl`.

---

## Safe fallback — the rule that makes features removable

Every consumer of a cross-feature contract must tolerate the contract being **absent**. The app
shell already does this for routing:

```dart
// platform/shell/app_shell/lib/presentation/navigation/app_router.dart
List<RouteBase> get _featureRoutes {
  return [
    for (final module in getAllOrEmpty<IFeatureRouteModule>())
      ...module.routes,
  ];
}
```

Apply the same discipline everywhere:

| Situation | Use | Not |
| :-- | :-- | :-- |
| Zero or more implementations | `getAllOrEmpty<T>()` | `getIt.getAll<T>()` |
| Optional single implementation | `getItOrNull<T>()` + fallback | `getIt<T>()` |

`getIt<T>()` **throws** when nothing is registered. Every bare `getIt<T>()` pointing at a
feature-owned type is a crash waiting for the day that feature is deleted.

```dart
// Good — degrades quietly
getItOrNull<IAuthActionHandler>()?.logout(context);

// Good — falls back to the bare branch widget rather than crashing
// (platform/shell/app_shell/lib/presentation/navigation/app_router.dart)
builder: (context, state, navigationShell) {
  return getItOrNull<DashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      navigationShell;
},
```

`navigationShell` is itself the widget showing the current branch, so an app composed without
`feature_dashboard` still renders its destinations — just without chrome. An empty `SizedBox` here
would open that app on a blank screen.

> [!NOTE]
> `apps/mobile/lib/di/injection.dart` naming feature packages is the composition root's one intentional
> hard reference — it must name what it composes. No other app file imports a module (R10), and the
> shared shell in `platform/shell/app_shell/` cannot (R1); everything else reaches features through `core_di` contracts with
> `getAllOrEmpty` / `getItOrNull` fallbacks. The `core_ui_kit` imports in the shell are not
> exceptions — that is a core package, not a removable feature.
>
> Verify with `grep -rn "package:feature_" apps/mobile/lib --include="*.dart"` — every hit should be in
> `injection.dart` or the generated `injection.config.dart`.

---

## Anti-patterns

| Don't | Why | Instead |
| :-- | :-- | :-- |
| `import 'package:feature_b/...'` from feature A | Hard couples two features; neither is removable | A `core_di` contract |
| Expose a `Bloc` or `ChangeNotifier` across features | Forces the other feature to adopt your state library | Model 3 — neutral stream |
| `getIt<FeatureOwnedType>()` | Throws when that feature is gone | `getItOrNull<T>()` + fallback |
| Action Handler for navigation | Wrong tool; loses type-safe routes | Navigator interface |
| Put shared business logic in `core_ui_kit` | It is a UI package | A domain UseCase |
| A `core_di` contract naming a `domain_*` entity | Every consumer then depends on that domain package; contradicts AGENTS.md §8.4 | A contract-owned value type (`AuthPrincipal`) |

---

## Related

- [`04_routing.md`](04_routing.md) — Navigator interfaces and route contracts
- [`05_di.md`](05_di.md) — registration scopes, `@module` bindings, ordering
- [`03_state_management.md`](03_state_management.md) — Provider and BLoC
- [`../architecture/05_features.md`](../architecture/05_features.md) — feature boundary rules
- [`../architecture/02_core.md`](../architecture/02_core.md) — what `core_di` is for
