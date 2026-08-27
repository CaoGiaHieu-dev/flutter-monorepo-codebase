---
name: implement_provider_ui
description: Guide for UI state management using Provider (BaseProvider, executeOperation, BaseViewWidget, ProviderStateListener).
---

# 🧠 Skill: UI State Management with Provider (Implement Provider UI)

Use this skill when requested to: "implement screen logic using Provider", "automate loading/error UI states", "listen to state changes to display warnings/dialogs", etc.

> [!NOTE]
> This is the more complete of the two state-management branches: `BaseProvider` ships
> `executeOperation`, `StateManager`, `LoadMoreMixin` and `ensureInitialized`. The BLoC
> branch (`implement_bloc_ui`) has no equivalent automation — pick deliberately.

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
import 'package:provider_state_management/provider_state_management.dart';
import 'package:domain_*/domain_*.dart';
import 'package:injectable/injectable.dart';

@injectable
class ProductListProvider extends BaseProvider<List<ProductEntity>> {
  final GetProductsUseCase _getProductsUseCase;

  ProductListProvider(this._getProductsUseCase);

  // AUTOMATIC INITIALIZATION LIFECYCLE:
  // BaseProvider schedules initialize() via Future.microtask after construction.
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
        operation: () => _getProductsUseCase(), // Returns Result<List<ProductEntity>>
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
> (`packages/core/provider_state_management/lib/src/management/operation_executor.dart`)
>
> So a **refresh** on an already-populated screen shows no spinner, and there is no flag to
> override that. When you do need one, set it yourself before the call — this is exactly
> what `AuthProvider.login` does:
> ```dart
> updateState(state: const ViewState.loading());
> await executeOperation(OperationConfig(...));
> ```

### 3. Rendering UI: `BaseViewWidget`
Use `BaseViewWidget` in the Screen/Page class to automate the rendering of different UI states (Loading, Error, Empty, Success) based on the Domain data type:
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
          // Focus exclusively on building the success UI with loaded data
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
> **Pass `emptyWidget` or you get a blank screen.** `core/*` must never depend on
> `core_ui_kit`, so `provider_state_management` no longer borrows its branded widgets.
> The built-in fallbacks live in `src/base_view/default_state_widgets.dart` and are
> deliberately minimal:
> - `DefaultLoadingWidget` → `Center(child: CircularProgressIndicator.adaptive())`
> - `DefaultEmptyWidget` → **`SizedBox.shrink()`** — renders *nothing*
>
> An empty list with no `emptyWidget` therefore shows an empty screen with no explanation.

### 4. Listening for Side-effects: `ProviderStateListener`
To handle one-off side-effects (e.g., displaying a Dialog, Toast, or navigating to another page), wrap the content with `ProviderStateListener`.
Use the specialized callback parameters for each state:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: ProviderStateListener<ProductListProvider, List<ProductEntity>>(
      // Triggered on error
      onError: (context, error, message) {
        AppDialog.showError(context, message: message);
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
> Never register a screen-scoped ViewModel as a singleton, and never wrap the `Page` in a
> second `ChangeNotifierProvider` — both cause duplicate instances and leaks.

---

## 🔗 Related

- `docs/{en,vi}/guides/03_state_management.md` — full comparison of both branches
- `implement_bloc_ui` — the BLoC branch
- `implement_navigation_route` — route-level instantiation
