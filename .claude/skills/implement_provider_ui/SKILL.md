---
name: implement_provider_ui
description: Use when a screen's logic is written with Provider — "implement screen logic using Provider", "automate loading/error states", "show a toast or dialog when state changes", "paginate with load-more". Covers BaseProvider<T> with executeOperation, BaseViewWidget rendering, ProviderStateListener side effects, LoadMoreMixin + LoadMoreListView, translated errors and the controller's tests; the route creates the provider. For the translated text itself (ARB key, getter) use localize_feature.
---

# Skill: Screen logic with Provider

Use this skill to give a screen a `BaseProvider<T>` controller: load data through a use case, render
loading / success / empty / error, react to failures, page through a list.

> **Use [`localize_feature`](../localize_feature/SKILL.md) for** the text a toast, dialog or error state shows (ARB key, getter,
> `failureMessage`); this skill decides when it appears.

**Guide:** [`docs/en/guides/03_state_management.md`](../../../docs/en/guides/03_state_management.md) —
the long form; the package README is `platform/state/provider/README.md`.
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-10, RULE-21, RULE-30, RULE-34,
RULE-35, RULE-36, RULE-50, RULE-61. Cite them; do not restate them.

The BLoC branch is [`implement_bloc_ui`](../implement_bloc_ui/SKILL.md): it has `emitResult` for
`BlocViewState<T>` but no counterpart of the `OperationGlobalConfig` hooks, `errorStateBuilder` or
`LoadMoreMixin` — pick the branch deliberately.

## 1. What the generator gave you

`generate.dart 1 <name> "" 1 <route>` writes `provider/<name>_provider.dart`
(`BaseProvider<Object>` whose `initialize()` settles a placeholder `Result.success(Object())`),
`pages/<name>_page.dart` (`BaseViewWidget<<Name>Provider, Object>` with an `onErrorBuilder` that shows the translated
`somethingWentWrong`), the route that creates the
provider, and tests that pass as generated (`test/<name>_page_test.dart`, `test/<name>_provider_test.dart`).
Everything below **replaces those placeholders**; keep the file names.

## 2. Declare the dependencies

Declare every package your code imports under `dependencies:` (`arch_check` R5). The generated feature
already lists `provider_state_management`, `domain_core`, `core_base_ui` (`context.l10n`, tokens) and
`core_responsive`. Add:

- `domain_<name>` — the use case and entity you inject (a feature never imports `data_<name>`, RULE-04);
- `core_ui_kit` — `LoadingWidget`, `EmptyWidget`, `AppOverlay` (toast / dialog host). The feature does
  not get it for a Provider screen; `provider_state_management` cannot depend on it, so its own defaults
  are minimal (see Step 4).

Path entries only, no versions. Then `flutter pub get`, before codegen.

## 3. The controller

`BaseProvider<T>` is parameterised directly with the **Domain entity** `T` (`List<ProductEntity>`):
`executeOperation` wraps it in a `ViewStateModel<T>` and drives `loading` / `success` / `error` /
`loadingMore`. No hand-written `ProductListState` with `copyWith`. `ViewState` here is non-generic,
carries no payload and takes a nullable `ErrorState` — it is **not** the BLoC branch's
`BlocViewState<T>`.

```dart
import 'package:domain_core/domain_core.dart';
import 'package:domain_product/domain_product.dart'; // GetProductsUseCase, ProductEntity
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

@injectable
class ProductListProvider extends BaseProvider<List<ProductEntity>> {
  ProductListProvider(this._getProducts);

  final GetProductsUseCase _getProducts;

  // BaseProvider schedules initialize() once after construction. It must be this override: a method
  // named anything else (init()) never runs and the page shows its loading state forever.
  // ensureInitialized() resolves only after this Future completes.
  @override
  Future<void> initialize() async {
    await super.initialize();
    await load();
  }

  Future<void> load() => executeOperation(
    OperationConfig(
      operation: () => _getProducts(const NoParams()), // FutureOr<Result<List<ProductEntity>>>
      errorStateBuilder: ProductErrorState.fromFailure,
    ),
  );
}
```

- A use case returning another type than `T` passes `convert:` to `executeOperation` (a named argument
  of the method, not of `OperationConfig`); without it a release build ends in `success` with `null` data. A `convert` that throws settles on `error`
  like a failing operation (never a stuck `loading`).
- `showLoading` is conditional: `OperationExecutor.execute` emits `loading` only while `data == null`
  (`platform/state/provider/lib/src/management/operation_executor.dart`). A **refresh** on a populated
  screen shows no spinner and there is no flag; call `updateState(state: const ViewState.loading())` first
  when one is needed, as `AuthProvider.initialize` does.
- An operation that *throws* is a bug (repositories return `Result.failure`), but it does not leave the screen on `loading`: the
  executor reports it (`FlutterError.reportError`) and settles on `error` through `ErrorHandler.handleError`, with `onFailure` and
  `errorStateBuilder` applied as for a `Result.failure`. It is not rethrown, so do not wrap `executeOperation` in a try/catch.
- `AppFailure.message` is an English diagnostic and never reaches the screen (RULE-34). To word a failure
  carry its `code` in a feature error state — a Freezed union that extends `CustomErrorState` — and map it
  with `errorStateBuilder`. `ProductErrorState.fromFailure` above is a static you write; model the union on
  `modules/auth/feature/lib/src/provider/auth_error_state.dart` and the mapping on
  `AuthProvider.mapAuthFailure`: one variant per case the screen words differently, plus
  `failed({int? code})` for "anything else".

## 4. Render with `BaseViewWidget`

What it renders (`platform/state/provider/lib/src/base_view/base_view_widget.dart`):

| State | Renders |
| :--- | :--- |
| `initial` | `initialWidget` → else `loadingWidget` → else `DefaultLoadingWidget` |
| `loading` | `loadingWidget` → else `DefaultLoadingWidget` |
| `error` | `onErrorBuilder(context, data, message, child)`; **without one it falls through** to the success / empty branch, so the last good data stays and a first-load error is a blank screen |
| `success` / `loadingMore` | `data == null` → `emptyWidget` → else `DefaultEmptyWidget` (`SizedBox.shrink()`, renders **nothing**); otherwise `builder(context, data, child)` |

"Empty" means `data == null` only: an empty list arrives in `builder`. So on every user-facing screen pass
`loadingWidget`, `emptyWidget` and `onErrorBuilder`, and handle `isEmpty` yourself:

```dart
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10nProduct.title)),
      body: BaseViewWidget<ProductListProvider, List<ProductEntity>>(
        loadingWidget: (context, child) => const LoadingWidget(),
        emptyWidget: (context, child) => const EmptyWidget(),
        // The error text comes from the failure's code, never from `message` (RULE-34).
        onErrorBuilder: (context, products, message, child) =>
            Center(child: Text(context.l10n.somethingWentWrong)),
        builder: (context, products, child) {
          if (products.isEmpty) return const EmptyWidget();
          return ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) => Text(products[index].name),
          );
        },
      ),
    );
  }
}
```

Sizes, colours and text styles come from the tokens through `context` (RULE-30, RULE-33); the generated
page shows the shape (`AdaptiveContent`, `AppSpacing.lg(context)`, `AppTextStyles.bodyMediumStyle(context)`).
`core_ui_kit`'s `EmptyWidget` and `LoadingWidget` take already-scaled values (RULE-31).

## 5. Side effects: `ProviderStateListener`

One-off reactions (a toast, navigation) are not rendered in `build`. The listener fires on real
transitions; a repeated identical error is passed through, so a `listenWhen` must let errors through
(`|| current.isError`):

```dart
ProviderStateListener<ProductListProvider, List<ProductEntity>>(
  onError: (context, error, message) {
    // Word it from the code the error state carries (RULE-34); `message` is a diagnostic.
    final text = error is ProductErrorState
        ? error.maybeWhen(
            failed: (code) => context.l10n.failureMessage(code),
            orElse: () => context.l10n.somethingWentWrong,
          )
        : context.l10n.somethingWentWrong;
    AppOverlay.showToast(content: text);
  },
  child: const ProductListContent(),
)
```

`AppOverlay.showToast` and its queued `AppOverlay.showDialog` come from `core_ui_kit`; a dialog is its own
widget class extending `OverlayDialogWidget` (`*_dialog.dart`, RULE-36 — `RetryDialog` is the example),
never an inline builder. `MultiProviderStateListener` nests several listeners.

## 6. Paginate with `LoadMoreMixin`

Mix `LoadMoreMixin<T>` into the provider for `currentPage`, `totalPage`, `nextPage`, `isLoadingMore`,
`canLoadMore`; render with `LoadMoreListView<P>` inside `BaseViewWidget`, which appends a spinner slot while
`isLoadingMore` is true. The mixin holds paging state only — the screen's `ScrollController` decides
when to call `loadMore()`. The complete provider + list sample, built on `PaginatedEntity<T>` from
`domain_core`, is in [guide 03 § 3](../../../docs/en/guides/03_state_management.md#page-through-a-list-with-loadmoremixin).

## 7. Translated text

Every user-facing string is translated (RULE-34, RULE-35): add the keys to the feature's
`assets/language/en.arb` **and** `vi.arb` (`lowerCamelCase`), then `cd modules/<name>/feature && flutter gen-l10n`
and read them through `context.l10n<Name>`. Steps: [`localize_feature`](../localize_feature/SKILL.md). A
generic fault uses `context.l10n.failureMessage(code)` from `core_base_ui`.

## 8. Lifecycle and registration

A screen-scoped provider is an `@injectable` factory (RULE-10), created **at the route** and never inside
the `Page`, which must not wrap itself in a second `ChangeNotifierProvider` (RULE-21). The route snippet and the
`@injectable` vs `@lazySingleton` choice live once each: [`implement_navigation_route`](../implement_navigation_route/SKILL.md)
and [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md).

## 9. Update the tests

The generated tests build `ProductListProvider()` with no argument, so they stop compiling once the
constructor takes a use case, and the provider test asserts the placeholder `initialize()`.

- **Provider test** — build it from the use case over a **hand-written fake** repository (RULE-61), as
  `modules/auth/feature/test/auth_provider_test.dart` does: `ProductListProvider(GetProductsUseCase(FakeProductRepository()))`,
  `await provider.ensureInitialized()`, assert `provider.isSuccess` and `provider.data`.
- **Page test** — pump the page under `ResponsiveInit` with a provider that already holds data
  (`ChangeNotifierProvider.value`), because the page renders its body only then. The generated assertion
  `find.text(title)` `findsNWidgets(2)` counts the app bar **and** the body, so update it when the body no longer repeats the title.
- **Failing-load case** — the generated page test also declares `_FailingProvider extends <Name>Provider` and asserts that a
  failed first load shows `somethingWentWrong`, never the diagnostic. Once the constructor takes a use case, give
  `_FailingProvider` a constructor that passes one to `super`, and keep the case.

## Related

- [`implement_domain_data_flow`](../implement_domain_data_flow/SKILL.md) — the use case this provider calls
- [`implement_navigation_route`](../implement_navigation_route/SKILL.md) — where the provider is created

## Verify

```bash
cd modules/<name>/feature && flutter gen-l10n            # after ARB edits
dart run build_runner build --workspace                  # the provider's constructor changed
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R5 declared deps, R7 / R20 no raw sizes
dart tools/composer/composer.dart verify
cd modules/<name>/feature && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # the provider factory builds from the real graph
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77, after a DI or dependency change
```

Barrels: [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator) says when to regenerate them.
