---
name: implement_provider_ui
description: Guide for UI state management using Provider (BaseProvider, executeOperation, BaseViewWidget, ProviderStateListener).
---

# 🧠 Skill: UI State Management with Provider (Implement Provider UI)

Use this skill when requested to: "implement screen logic using Provider", "automate loading/error UI states", "listen to state changes to display warnings/dialogs", etc.

---

## 📋 Core Components

### 1. State Type Parameter of BaseProvider
- **Core Rule**: `BaseProvider<T>` is directly parameterized using the **Domain Entity** `T` (e.g., `UserEntity` for authentication, or `List<ProductEntity>` for a list of products).
- **Avoid Anti-pattern**: Do not create custom state classes inside the Presentation layer (such as `ProductListState`) to perform redundant `copyWith` operations. The `BaseProvider` mechanism automatically wraps the entity `T` inside a `ViewStateModel<T>` to manage `loading`, `success`, `error`, and `loadingMore` states globally.

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

### 3. Rendering UI: `BaseViewWidget`
Use `BaseViewWidget` in the Screen/Page class to automate the rendering of different UI states (Loading, Error, Empty, Success) based on the Domain data type:
```dart
class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BaseViewWidget<ProductListProvider, List<ProductEntity>>(
        builder: (context, products, child) {
          // Focus exclusively on building the success UI with loaded data
          // Loading and Error states are automatically overlaid by BaseViewWidget
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
