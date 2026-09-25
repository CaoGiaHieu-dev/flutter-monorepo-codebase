# Guide: Cross-Feature Communication

## Goal

Feature A needs something from feature B, and may not import it (RULE-04). You pick the right one of the six sanctioned models (RULE-25) and wire it so that deleting either feature leaves the app running.

## Prerequisites

- **Why contracts live where they do** — in module B's API package or, when product-neutral, in `core_di` — and the anti-patterns to reject: [`../architecture/05_features.md` § 9](../architecture/05_features.md#9-cross-feature-communication--why-it-is-shaped-this-way).
- Two features to connect — [`01_new_feature.md`](01_new_feature.md). A module with no API package yet needs one: [`12_module_isolation.md` § 4](12_module_isolation.md#4-create-a-module-api-package).

---

## 1. Pick a model

| I need to… | Use | Model |
| :-- | :-- | :-- |
| Run the same business operation as another feature | Shared **UseCase** from `domain_*` | 1 |
| Read/write storage, call an API, log | **Core service** (`core_storage`, `core_network`…) | 2 |
| React continuously to another feature's state (login/logout…) | **Agnostic stream** — on `core_di` when product-neutral (the session), else the owner's `<id>_api` | 3 |
| Persist a pure-UI preference (theme, locale) | **Bypass Domain** via a `core_di` storage interface | 4 |
| Embed a widget that only another feature can build | **Widget builder interface** in the owner's `<id>_api` | 5 |
| Trigger a one-shot UI action another feature owns (logout…) | **Action handler** in the owner's `<id>_api` | 6 |
| Just navigate to another feature's screen | **Navigator interface** in the owner's `<id>_api` — see [`04_routing.md`](04_routing.md) | — |

Reach for model 1 first: it is the cheapest.

## 2. Share a business operation through a use case (model 1)

**Use when** two features perform the same business operation. **Don't use when** the thing you need is UI state rather than business logic.

Both features inject the same use case from the domain package. Neither knows the other exists:

```dart
// In any feature's controller
class CheckoutProvider extends BaseProvider<PaymentEntity> {
  CheckoutProvider(this._loginUseCase);

  final LoginUseCase _loginUseCase;
}
```

The use case lives in `domain_auth`. Both `feature_auth` and `feature_checkout` depend on `domain_auth`, never on each other.

## 3. Use a core service (model 2)

**Use when** the capability is infrastructure, not business logic. **Don't use when** the behaviour belongs to a specific feature.

Inject `StorageManager`, `Dio`, `IDatabaseHandle<TDb>` and friends directly from the relevant `core_*` package. Nothing feature-specific is involved, so there is no coupling to break. See [`06_storage.md`](06_storage.md), [`08_networking.md`](08_networking.md), [`07_database.md`](07_database.md).

## 4. Share continuous state through an agnostic stream (model 3)

**Use when** feature A must react *continuously* to state owned by feature B — and the two may use different state-management libraries. **Don't use when** you need a one-shot action (model 6) or a plain value read (model 4).

This is the most important pattern in the codebase. `feature_auth` uses Provider; `feature_home` uses BLoC. Neither may import the other, and neither should learn the other's state-management tool (RULE-54).

### Declare a neutral interface in `core_di`

Real code from [`platform/foundation/contracts/lib/src/session/i_session_status_stream.dart`](../../../platform/foundation/contracts/lib/src/session/i_session_status_stream.dart):

```dart
abstract class ISessionStatusStream {
  /// Emits on every session change; `null` means signed out.
  Stream<SessionPrincipal?> get sessionStatusStream;

  /// The currently signed-in principal, or `null` when signed out.
  ///
  /// Read this for the state at subscription time — [sessionStatusStream] is a
  /// broadcast stream and does not replay its last value to new listeners.
  SessionPrincipal? get currentUser;
}
```

The contract carries [`SessionPrincipal`](../../../platform/foundation/contracts/lib/src/session/session_principal.dart), a value type `core_di` owns, never a `domain_*` entity (RULE-08). `currentUser` exists because a broadcast stream does not replay its last value. Both decisions are explained in [`../architecture/05_features.md` § 9](../architecture/05_features.md#9-cross-feature-communication--why-it-is-shaped-this-way).

### Implement it in the owning feature

Real code from [`modules/auth/feature/lib/src/services/auth_status_stream_impl.dart`](../../../modules/auth/feature/lib/src/services/auth_status_stream_impl.dart):

```dart
/// Implementation of [ISessionStatusStream] provided by `feature_auth`.
@singleton
class AuthStatusStreamImpl implements ISessionStatusStream {
  final _controller = StreamController<SessionPrincipal?>.broadcast();
  SessionPrincipal? _currentUser;

  @override
  Stream<SessionPrincipal?> get sessionStatusStream => _controller.stream;

  @override
  SessionPrincipal? get currentUser => _currentUser;

  /// Called by `feature_auth` when the session settles.
  void updateAuthStatus(UserEntity? user) {
    final principal = toPrincipal(user);
    _currentUser = principal;
    _controller.add(principal);
  }

  /// The one place `UserEntity` is narrowed for the outside world.
  static SessionPrincipal? toPrincipal(UserEntity? user) {
    if (user == null) return null;
    return SessionPrincipal(
      id: user.id,
      displayName: user.name,
      email: user.email,
      roles: {if (user.role != null) user.role!.name},
    );
  }
}
```

### Bind the interface to that same instance

Real code from [`modules/auth/feature/lib/di/module.dart`](../../../modules/auth/feature/lib/di/module.dart):

```dart
@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDiModule {
  @singleton
  ISessionStatusStream bindISessionStatusStream(AuthStatusStreamImpl impl) => impl;
}
```

The owner injects `AuthStatusStreamImpl` and writes through `updateAuthStatus`. Everyone else reads the same instance through the read-only interface (RULE-14).

### Consume it from another feature

Real code from [`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`](../../../modules/home/feature/lib/src/bloc/home_profile_bloc.dart):

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<SessionPrincipal?>> {
  HomeProfileBloc(@factoryParam this._sessionStatusStream)
    : super(const BlocViewState.initial()) {
    // …
  }

  final ISessionStatusStream? _sessionStatusStream;
  StreamSubscription<SessionPrincipal?>? _subscription;
```

`feature_home` depends on `core_di` alone — not on `feature_auth`, and not on `domain_auth` either. The contract carries `SessionPrincipal`, a type `core_di` owns, so no domain package crosses the boundary.

The stream is **optional** on purpose. `ISessionStatusStream` is registered by `feature_auth`, which an app may leave out. So the bloc takes it as an `@factoryParam`, and the route supplies it — real code from [`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

```dart
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no ISessionStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<ISessionStatusStream>(),
      ),
      child: const HomePage(),
    );
```

A required constructor parameter would compile just as well — and then DI could not build `HomeProfileBloc` at all in a build without auth. The constructor still receives its dependency (no lookup in business logic); only the *optional* lookup moves to the route.

> [!CAUTION]
> Always cancel the subscription in `close()` / `dispose()`. A broadcast stream will happily keep a
> disposed controller alive.

## 5. Persist a UI preference without Domain (model 4)

**Use when** the value is a UI preference that never leaves the device — theme mode, locale. **Don't use when** the value has business meaning or is sent to a server.

The chain skips the domain layer entirely, because Domain cannot import Flutter's `ThemeMode` (RULE-03):

```
ThemeProvider  →  IThemeStorage (core_di)  →  ThemeStorageImpl (app shell)  →  StorageValue
```

The interface — real code from [`platform/foundation/contracts/lib/src/i_theme_storage.dart`](../../../platform/foundation/contracts/lib/src/i_theme_storage.dart):

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

The implementation lives in the shell adapters, `platform/shell/adapters/lib/src/theme_storage_impl.dart`. How to write one like it: [`06_storage.md` § 9](06_storage.md#9-share-the-value-across-a-package-boundary).

## 6. Embed a widget another feature builds (model 5)

**Use when** feature A must render a widget whose content only feature B knows how to build. **Don't use when** the widget is generic UI — that belongs in `core_ui_kit`.

Declare the builder contract in the owning module's API package (feature A adds `profile_api` to its `dependencies:`):

```dart
// modules/profile/api/lib/src/builders/i_profile_card_builder.dart
import 'package:flutter/widgets.dart';

abstract class IProfileCardBuilder {
  Widget build(BuildContext context, {required String userId});
}
```

Implement it in the owning feature and register it with `@Injectable(as: IProfileCardBuilder)`. Consumers resolve it defensively, so the app survives the feature being removed:

```dart
final builder = getItOrNull<IProfileCardBuilder>();
return builder?.build(context, userId: id) ?? const SizedBox.shrink();
```

## 7. Trigger another feature's UI action (model 6)

**Use when** feature A must trigger a one-shot, UI-bound action that feature B owns — logout is the canonical case. **Don't use for** plain navigation (use a Navigator interface) or for domain logic (use a UseCase).

The interface — real code from the auth module's API package, [`modules/auth/api/lib/src/actions/i_auth_action_handler.dart`](../../../modules/auth/api/lib/src/actions/i_auth_action_handler.dart) (`feature_settings` depends on `auth_api`, never on `feature_auth`):

```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  void logout(BuildContext context);
}
```

The implementation — real code from [`modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart`](../../../modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart):

```dart
import 'package:auth_api/auth_api.dart';
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

`feature_settings` calls `getItOrNull<IAuthActionHandler>()?.logout(context)`. It never learns that logout is a Provider call, or that `AuthProvider` exists.

Handler implementations live in the owning feature's `handlers/` directory and are named `*ActionHandlerImpl` (RULE-78).

## 8. Make every lookup survive the owner's removal

Every consumer of a cross-feature contract must tolerate the contract being **absent** (RULE-12). The app shell already does this for routing:

```dart
// platform/shell/app_shell/lib/src/navigation/app_router.dart
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

`getIt<T>()` **throws** when nothing is registered. Every bare `getIt<T>()` pointing at a feature-owned type is a crash waiting for the day that feature is deleted.

```dart
// Good — degrades quietly
getItOrNull<IAuthActionHandler>()?.logout(context);

// Good — falls back to the bare branch widget rather than crashing
// (platform/shell/app_shell/lib/src/navigation/app_router.dart)
builder: (context, state, navigationShell) {
  return getItOrNull<IDashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      navigationShell;
},
```

`navigationShell` is itself the widget showing the current branch. So an app composed without `feature_dashboard` still renders its destinations — just without chrome. An empty `SizedBox` here would open that app on a blank screen.

> [!NOTE]
> `apps/mobile/lib/di/injection.dart` naming feature packages is the composition root's one intentional
> hard reference — it must name what it composes. No other app file imports a module (R10), and the
> shared shell in `platform/shell/app_shell/` cannot (R1); everything else reaches features through `core_di` contracts with
> `getAllOrEmpty` / `getItOrNull` fallbacks. The `core_ui_kit` imports in the shell are not
> exceptions — that is a core package, not a removable feature.

---

## Verify

```bash
dart tools/arch_check/check.dart     # ✅ … R3 (feature/API imports), R8 (optional lookups), R10 (app imports)
grep -rn "package:feature_" apps/mobile/lib --include="*.dart"   # hits only in injection.dart / injection.config.dart
cd apps/mobile && flutter test test/di_smoke_test.dart            # contracts resolve from the real graph
```

Then prove the removal works: drop the owning module from a manifest with `dart tools/sample_cleanup/remove_sample.dart <bundle>` (a dry run, for a sample) or by editing the manifest in a scratch branch, and run `flutter analyze` plus the smoke test. The consumer must still compile and boot.

Review checklist:

- [ ] No `import 'package:feature_*'` from another feature
- [ ] The contract lives in the owner's `<id>_api` (or, if product-neutral, in `core_di`), never naming a `domain_*` entity
- [ ] Owner-written, consumer-read state is exposed as a neutral stream, not as a Bloc or `ChangeNotifier`
- [ ] Every consumer resolves with `getItOrNull` / `getAllOrEmpty` and has a fallback
- [ ] Subscriptions are cancelled in `close()` / `dispose()`
- [ ] Action handlers live in `handlers/` as `*ActionHandlerImpl`; navigation uses a navigator, not a handler

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `arch_check` R3 fails on a feature import | Feature A imports feature B or `data_*` | Depend on `b_api` (or a `core_di` contract) instead (step 1) |
| `arch_check` R8 fails | A module-owned contract is resolved with `getIt` / `getAll` outside its module | Use `getItOrNull` / `getAllOrEmpty` with a fallback (step 8) |
| The app crashes at boot after a feature was removed | A bare `getIt<T>()` or a required constructor parameter needs the removed type | Resolve it optionally, at the route, as a factory param (step 4) |
| A consumer sees no state until the next change | It subscribed to a broadcast stream after the last event | Read `currentUser` first, then listen (step 4) |
| Every consumer now depends on `domain_auth` | The `core_di` contract names a domain entity | Give the contract its own value type, like `SessionPrincipal` (step 4) |
| A disposed screen keeps reacting | The subscription was never cancelled | Cancel it in `close()` / `dispose()` (step 4) |

## Related

- Rules: RULE-04 (no feature → feature import), RULE-08 (`core_di` is product-neutral), RULE-12 (optional lookups), RULE-25 (the six models), RULE-54 (state through neutral streams) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/05_features.md` § 9](../architecture/05_features.md#9-cross-feature-communication--why-it-is-shaped-this-way) — why the contracts look this way, and the anti-patterns
- [`04_routing.md`](04_routing.md) — Navigator interfaces and route contracts
- [`05_di.md`](05_di.md) — registration scopes, `@module` bindings, ordering
- [`03_state_management.md`](03_state_management.md) — Provider and BLoC
- [`../architecture/02_core.md`](../architecture/02_core.md) — what `core_di` is for
