---
name: implement_provider_ui
description: Use when a screen's logic is written with Provider — "implement screen logic using Provider", "automate loading/error states", "show a dialog when state changes", pagination with load-more. Covers BaseProvider<T> with executeOperation, BaseViewWidget rendering, ProviderStateListener side-effects and route-level ChangeNotifierProvider.
---

# 🧠 Skill: UI State Management with Provider (Implement Provider UI)

Use this skill when requested to: "implement screen logic using Provider", "automate loading/error UI states", "listen to state changes to display warnings/dialogs", etc.

> [!NOTE]
> This is the more complete of the two state-management branches: `BaseProvider` ships
> `executeOperation`, `StateManager`, `LoadMoreMixin` and `ensureInitialized`. The BLoC branch
> (`implement_bloc_ui`) has `emitResult` for `BlocViewState<T>`, but no counterpart of
> `OperationGlobalConfig` hooks, `errorStateBuilder` or `LoadMoreMixin` — pick deliberately.
>
> **Guide:** [`docs/en/guides/03_state_management.md`](../../../docs/en/guides/03_state_management.md).
> **Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-10, RULE-21, RULE-30,
> RULE-34, RULE-36, RULE-50.

---

## 📋 Core Components

### 1. State Type Parameter of BaseProvider
- **Core Rule**: `BaseProvider<T>` is directly parameterized using the **Domain Entity** `T` (e.g., `UserEntity` for authentication, or `List<ProductEntity>` for a list of products).
- **Avoid Anti-pattern**: Do not create custom state classes inside the Presentation layer (such as `ProductListState`) to perform redundant `copyWith` operations. The `BaseProvider` mechanism automatically wraps the entity `T` inside a `ViewStateModel<T>` to manage `loading`, `success`, `error`, and `loadingMore` states globally.

> [!IMPORTANT]
> The `ViewState` exported by `provider_state_management` is **not** the BLoC branch's
> `BlocViewState<T>`. This one is non-generic, has a `loadingMore` variant, takes a nullable
> `ErrorState`, and holds no payload — the data lives on `ViewStateModel<T>`.

### 2. BaseProvider (ViewModel)
ViewModels managing UI state must inherit directly from `BaseProvider<T>` where `T` is the Domain entity type:
```dart
import 'package:domain_<name>/domain_<name>.dart'; // GetProductsUseCase, ProductEntity
import 'package:domain_core/domain_core.dart'; // NoParams, Result
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

@injectable
class ProductListProvider extends BaseProvider<List<ProductEntity>> {
  final GetProductsUseCase _getProductsUseCase;

  ProductListProvider(this._getProductsUseCase);

  // AUTOMATIC INITIALIZATION LIFECYCLE:
  // BaseProvider schedules initialize() via Future.microtask after construction.
  // It must be an @override of initialize() — a method with any other name (e.g. init())
  // never runs, and the page shows its loading state forever. The module generator's
  // Provider template scaffolds exactly this override.
  // Await ALL setup here. ensureInitialized() resolves only after this Future completes.
  // UI / shell: await provider.ensureInitialized() before relying on data.
  @override
  Future<void> initialize() async {
    await super.initialize();
    await loadProducts();
  }

  Future<void> loadProducts() async {
    // executeOperation automatically handles isLoading = true and catches AppFailure.
    // The Result<List<ProductEntity>> returned from the UseCase aligns with the provider's T type.
    await executeOperation(
      OperationConfig(
        // BaseUseCase.call takes its Params — `const NoParams()` when there is no input.
        operation: () => _getProductsUseCase(const NoParams()), // Result<List<ProductEntity>>
        onSuccess: (products) {
          // Extra success side-effect logic (products is List<ProductEntity>?)
        },
      ),
    );
  }
}
```

> [!WARNING]
> **`showLoading` is conditional.** `OperationExecutor.execute` only emits the loading state
> when data is still absent:
> ```dart
> if (config.showLoading && _stateManager.data == null) {
>   _stateManager.setState(state: const ViewState.loading());
> }
> ```
> (`platform/state/provider/lib/src/management/operation_executor.dart`)
>
> So a **refresh** on an already-populated screen shows no spinner, and there is no flag to
> override that. When you do need one, set it yourself before the call — this is exactly
> what `AuthProvider.login` does:
> ```dart
> updateState(state: const ViewState.loading());
> await executeOperation(OperationConfig(...));
> ```

### 3. Rendering UI: `BaseViewWidget`
Use `BaseViewWidget` in the Screen/Page class to automate the rendering of the UI states based on the Domain data type. What it actually does (`platform/state/provider/lib/src/base_view/base_view_widget.dart`):

| State | Renders |
| :--- | :--- |
| `initial` | `initialWidget` → else `loadingWidget` → else `DefaultLoadingWidget` |
| `loading` | `loadingWidget` → else `DefaultLoadingWidget` |
| `error` | `onErrorBuilder(context, data, message, child)` → **without one it falls through** to the success/empty branch below, so the last good data stays on screen |
| `success` / `loadingMore` | `data == null` → `emptyWidget` → else `DefaultEmptyWidget`; otherwise `builder(context, data, child)` |

"Empty" means **`data == null` only**. An empty list is non-null data, so it goes to `builder` —
handle `products.isEmpty` there.
```dart
class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BaseViewWidget<ProductListProvider, List<ProductEntity>>(
        loadingWidget: (context, child) => const MyBrandedLoader(),
        emptyWidget: (context, child) => const MyBrandedEmptyState(),
        builder: (context, products, child) {
          // An empty list arrives here, not in emptyWidget — handle it yourself.
          if (products.isEmpty) return const MyBrandedEmptyState();
          return ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              return Text(products[index].name);
            },
          );
        },
      ),
    );
  }
}
```

> [!CAUTION]
> **Pass `emptyWidget` or null data gives a blank screen.** `provider_state_management` must never
> depend on `core_ui_kit` (a cycle — `core_ui_kit` depends on it), so it cannot use its branded widgets.
> The built-in fallbacks live in `src/base_view/default_state_widgets.dart` and are
> deliberately minimal:
> - `DefaultLoadingWidget` → `Center(child: CircularProgressIndicator.adaptive())`
> - `DefaultEmptyWidget` → **`SizedBox.shrink()`** — renders *nothing*
>
> Null data with no `emptyWidget` — including an error before any data loaded, when there is
> no `onErrorBuilder` — therefore shows an empty screen with no explanation. Pass
> `onErrorBuilder` too if the error must be visible in the page rather than only as a
> `ProviderStateListener` side-effect.

### 4. Listening for Side-effects: `ProviderStateListener`
To handle one-off side-effects (e.g., displaying a Dialog, Toast, or navigating to another page), wrap the content with `ProviderStateListener`.
Use the specialized callback parameters for each state:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: ProviderStateListener<ProductListProvider, List<ProductEntity>>(
      // Triggered on error. `error` is the optional ErrorState, `message` a String?.
      onError: (context, error, message) {
        // `core_ui_kit`'s AppDialog: static, no BuildContext, both strings required.
        AppDialog.showErrorDialog(
          title: context.l10nProduct.errorTitle,             // your feature's ARB keys —
          message: message ?? context.l10nProduct.genericError, // never raw strings
        );
      },
      // Triggered on success
      onSuccess: (context, data) {
        // e.g., display success banner or navigate
      },
      // Triggered on loading state
      onLoading: (context) {
        // Extra loading actions (if necessary)
      },
      child: const ProductListContent(),
    ),
  );
}
```

### 5. Lifecycle & registration

| Controller | Annotation | Why |
| :--- | :--- | :--- |
| Screen-scoped ViewModel | `@injectable` (factory) | disposed with the route |
| App-wide controller (`AuthProvider`, `ThemeProvider`, …) | `@lazySingleton` | lives for the process |

Instantiate at the **route**, never inside the `Page`:

```dart
@override
Widget build(BuildContext context, GoRouterState state) {
  return ChangeNotifierProvider(
    create: (context) => getIt<ProductListProvider>(),
    child: const ProductListPage(),
  );
}
```

> [!CAUTION]
> Screen-scoped means `@injectable` (RULE-10), and the `Page` never wraps itself in a second
> `ChangeNotifierProvider` (RULE-21).

---

## 🔗 Related

- `docs/{en,vi}/guides/03_state_management.md` — full comparison of both branches
- `implement_bloc_ui` — the BLoC branch
- `implement_navigation_route` — route-level instantiation
