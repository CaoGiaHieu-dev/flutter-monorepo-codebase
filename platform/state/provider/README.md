🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# Provider State Management

A micro-core package providing a standardized skeleton for UI state management built on `provider` and the **MVVM (Model-View-ViewModel)** architecture.

It removes the boilerplate of moving between Loading, Success and Error while calling a use case or running async logic, so UI code stays declarative. The package barrel re-exports `package:provider/provider.dart` (`ChangeNotifierProvider`, `Consumer`, `Selector`, `context.read`, …).

---

## 🌟 Core Features

- **`ViewStateModel<T>`**: An immutable (Freezed) UI state holding `state` (a `ViewState`), `data` (`T?`) and `message` (`String?`). `ViewState` has 5 variants: `initial`, `loading`, `success`, `error({ErrorState? error})`, `loadingMore`.
- **`BaseProvider<T>`**: The base ViewModel, with a built-in `executeOperation()` that automates the state changes around a `Result<R>`: loading → call the use case → `success` (with data) or `error` (with a `message` and an optional `ErrorState`).
- **`BaseViewWidget<TProvider, TData>`**: Builds the UI from the `ViewStateModel` (shows loading for you, hands over non-null data, shows an error UI if you pass `onErrorBuilder`).
- **`ProviderStateListener`** / **`MultiProviderStateListener`**: Widgets for side-effects (navigating, showing a toast) without hand-writing a StatefulWidget or a stream subscription.
- **`LoadMoreMixin` / `LoadMoreListView`**: Page bookkeeping for load-more lists, and a separated list that appends a spinner slot while `isLoadingMore` is true.
- **`DefaultLoadingWidget` / `DefaultEmptyWidget`**: Core's default widgets for the loading / empty states — core never borrows a widget from `core_ui_kit`.

---

## 🚀 1. Automation through `executeOperation`

A ViewModel does not toggle loading or map results by hand. It delegates that to `executeOperation`, built into `BaseProvider`:

```dart
import 'package:domain_auth/domain_auth.dart'; // LoginUseCase, LoginParams, UserEntity
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

import 'auth_error_state.dart';

@injectable
class LoginProvider extends BaseProvider<UserEntity> {
  LoginProvider(this._loginUseCase);

  final LoginUseCase _loginUseCase;

  Future<void> login(String email, String password) async {
    await executeOperation(
      OperationConfig(
        operation: () =>
            _loginUseCase(LoginParams(email: email, password: password)),
        // Defaults to true. Switches to `loading` only while the provider has
        // NO data yet — with data present the view keeps it instead of
        // flashing a spinner over it.
        showLoading: true,
        onSuccess: (user) async {
          // Handle success (e.g. logging, analytics).
        },
        // (Optional) map a Domain failure to a UI error (Custom Error State).
        errorStateBuilder: (failure) => failure.whenOrNull(
          // ErrorHandler: HTTP 401/403 → AuthFailure, other 4xx/5xx → ServerFailure.
          auth: (message, code, data) => code == 401
              ? const AuthErrorState.invalidCredentials()
              : AuthErrorState.serverError(message: message, code: code),
          server: (message, code, data) => code == 404
              ? const AuthErrorState.userNotFound()
              : AuthErrorState.serverError(message: message, code: code),
        ),
      ),
    );
  }
}
```

Behaviour worth knowing (`platform/state/provider/lib/src/management/operation_executor.dart`):

- **Success** → `ViewState.success()` with the data. When the result type `R` differs from the provider's state type `T`, pass `convert:` to `executeOperation`.
- **Failure** → `ViewState.error(error: errorStateBuilder?.call(failure))` with `message = failure.message`. This emission is **forced**, so two identical failures in a row (the user taps Retry while still offline) both reach listeners.
- **`none` / `cancel`** → the state is left untouched — including a `loading` state `showLoading` just set.
- `executeOperation` does **not** try-catch: it handles `Result.failure`, while an exception thrown by `operation` propagates to the caller. Catching exceptions is the job of `BaseRepository.execute()` in the Data layer.
- A local `onSuccess` / `onFailure` **replaces** the global callback installed through `OperationGlobalConfig.instance.setup(...)` for that call; the global `onStart` / `onFinish` always run.

---

## 🧩 2. Automated UI Rendering with `BaseViewWidget` & `LoadMoreListView`

Instead of hand-writing `if/else` blocks inside a `Consumer` for `loading`, `error`, `empty` and `success`, the package ships a standardized wrapper widget that keep your UI code short and declarative.

#### 2.1 `BaseViewWidget` (plain data)
`BaseViewWidget` is built on `Selector` (it rebuilds only when `viewState` changes) and listens to exactly the `ViewStateModel` of a `BaseProvider`.

```dart
BaseViewWidget<ProductProvider, ProductEntity>(
  // Called only with non-null data (success, loadingMore — and error when
  // no onErrorBuilder is given).
  builder: (context, product, child) {
    return Text(product.name);
  },

  // (Optional) Before the provider has run anything. Omitted → loadingWidget → DefaultLoadingWidget.
  initialWidget: (context, child) => const ProductPlaceholderWidget(),

  // (Optional) While loading. Omitted → DefaultLoadingWidget.
  loadingWidget: (context, child) => const CircularProgressIndicator(),

  // (Optional) When data == null outside initial/loading. Omitted → DefaultEmptyWidget.
  emptyWidget: (context, child) => Text(context.l10nProduct.productNotFound),

  // (Optional) On error — (context, previous data, message, child).
  onErrorBuilder: (context, data, message, child) =>
      Text(message ?? context.l10n.somethingWentWrong),
)
```

> Without `onErrorBuilder` the error state has **no** automatic error UI: the widget keeps drawing the normal branch (the previous data through `builder`, or `emptyWidget` when there is none). To report an error as a toast or dialog, use `ProviderStateListener` (section 3).

*(One `BaseViewWidget` observes one provider. A screen that combines several providers nests a `BaseViewWidget` per provider, or reads them with `context.select`.)*

#### 2.2 Paginated lists: `LoadMoreMixin` + `LoadMoreListView`
Mix `LoadMoreMixin` into the provider to track `currentPage` / `totalPage` / `isLoadingMore`, keep the page in a `BaseProvider<PaginatedEntity<T>>`, and render it with `LoadMoreListView<P>` inside `BaseViewWidget`. The list appends a spinner slot after the last item while the provider's `isLoadingMore` is true.

```dart
// class UsersProvider extends BaseProvider<PaginatedEntity<UserEntity>>
//     with LoadMoreMixin<UserEntity> { … }
BaseViewWidget<UsersProvider, PaginatedEntity<UserEntity>>(
  builder: (context, page, child) {
    final users = page.data; // List<UserEntity>; paging info in page.meta
    if (users.isEmpty) return Text(context.l10nUsers.noUsers);
    return LoadMoreListView<UsersProvider>(
      itemCount: users.length,
      itemBuilder: (context, index) => Text(users[index].name ?? users[index].id),
    );
  },
)
```

---

## 🎧 3. Listening for Side-effects & Showing Notifications (`ProviderStateListener`)

When the UI must react to a ViewModel state change (open a dialog, show an error toast, navigate on success), do not hand-manage a `StreamSubscription` in a `StatefulWidget`.
Use **`ProviderStateListener`** (or `MultiProviderStateListener` with a list of `ProviderStateListenerEntry` for several providers). The provider `P` must already be above it in the tree (the listener reads it with `context.read<P>()` in `initState`).

- Callbacks fire only when the state **actually changes** (not on rebuilds) — **except `onError`**, which fires for **every** failed operation, even one identical to the previous failure.
- `listenWhen: (previous, current) => …` filters further; `onStateChanged` fires before the specific callbacks; `onLoading` and `onLoadingMore` also exist.

```dart
@override
Widget build(BuildContext context) {
  return ProviderStateListener<AuthProvider, UserEntity>(
    // Catch and show feature-specific business errors
    onError: (context, error, message) {
      final l10n = context.l10n; // core_base_ui's global strings
      if (error is AuthErrorState) {
        error.maybeWhen(
          invalidCredentials: () =>
              AppOverlay.showToast(content: l10n.invalidCredentials),
          serverError: (serverMessage, code) =>
              AppOverlay.showToast(content: serverMessage),
          orElse: () =>
              AppOverlay.showToast(content: message ?? l10n.somethingWentWrong),
        );
      } else {
        AppOverlay.showToast(content: message ?? l10n.somethingWentWrong);
      }
    },
    // Fires on success. Do not navigate here: the app shell listens to the
    // session and changes route itself (see feature_auth's LoginPage).
    onSuccess: (context, user) {
      AppOverlay.showToast(content: context.l10nAuth.welcomeBack);
    },
    child: Scaffold(
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return MyLoginForm(
            isLoading: authProvider.isLoading,
            onSubmit: (email, password) => authProvider.login(email, password),
          );
        },
      ),
    ),
  );
}
```

> In this template `AuthProvider` is a global singleton, and the app shell (`NavigatorWrapperWidget`) **already** toasts sign-in failures through `ISessionState`. The snippet illustrates the API; applied verbatim to `AuthProvider` it would toast twice.

---

## 🔒 4. Feature-Specific Business Errors (Custom Error State)

When a call fails, the Domain layer returns an `AppFailure`. The UI layer should not depend on its internals, though. A **Custom Error State** names exactly the errors a feature can hit, so they are handled type-safely.

**`auth_error_state.dart` with Freezed** (the real file: `modules/auth/feature/lib/src/provider/auth_error_state.dart`):
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:provider_state_management/provider_state_management.dart';

part 'auth_error_state.freezed.dart';

@freezed
abstract class AuthErrorState extends CustomErrorState with _$AuthErrorState {
  const AuthErrorState._();

  const factory AuthErrorState.invalidCredentials() = _InvalidCredentials;
  const factory AuthErrorState.userNotFound() = _UserNotFound;
  const factory AuthErrorState.serverError({
    required String message,
    int? code,
  }) = _ServerError;
}
```

`CustomErrorState` is the `ErrorState.custom()` variant of `ErrorState` — extending it is how a feature attaches its own error to `ViewState.error`. *(Then map `AppFailure` to `AuthErrorState` through `OperationConfig`'s `errorStateBuilder`, as in section 1 — the real one is `AuthProvider.mapAuthFailure`.)*

---

## 🔗 5. Dependencies Between Providers

When `NewsProvider` must reload whenever the user changes language, recreate it at the routing layer, keyed by the value it depends on. `LanguageProvider` belongs to `core_base_ui` and is mounted at the app root (`AppMaterialWrapper`), so any feature may read it:

```dart
@TypedGoRoute<NewsRoute>(path: NewsPath.NEWS)
class NewsRoute extends GoRouteDataCustom with $NewsRoute {
  const NewsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final languageCode = context.select<LanguageProvider, String>(
      (language) => language.locale.languageCode,
    );
    return ChangeNotifierProvider(
      // A new key disposes the old NewsProvider and creates a fresh one —
      // only when the language really changes.
      key: ValueKey(languageCode),
      create: (_) => getIt<NewsProvider>(param1: languageCode),
      child: const NewsPage(),
    );
  }
}
```

> A route only depends on providers the feature is allowed to see: its own, or `core_*` ones. **Do not** read `AuthProvider` from another feature — importing `feature_auth` breaks module isolation. Sign-in state travels through `core_di`'s `ISessionStatusStream`.

---

## ⚠️ Critical Lifecycle Notes

1. **Route-level auto dispose**: A feature provider tied to one screen **must be `@injectable`** — never `@singleton` / `@lazySingleton`. (Global controllers such as `AuthProvider`, `ThemeProvider`, `LanguageProvider` are the deliberate exception and use `@lazySingleton`.)
2. **Create it in the router**: Always wrap `ChangeNotifierProvider(create: (_) => getIt<XProvider>())` in the route class's `build` (`go_router`), so the provider is disposed when the route leaves the widget tree. The page does not wrap itself in another provider.
3. **`initialize()`**: `BaseProvider` calls `initialize()` in a microtask after construction; override it (calling `super.initialize()`) for async setup, and `await provider.ensureInitialized()` when you need it finished.
