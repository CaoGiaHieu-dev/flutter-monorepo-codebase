---
name: implement_bloc_ui
description: Use when a screen's logic is written with BLoC — "create a bloc", "implement UI logic using BLoC", "listen to bloc state to show a toast or dialog". Covers BaseBloc with private Freezed events (part / part of), BlocViewState<T> settled by emitResult or a custom Freezed state, BlocBuilder / BlocListener with translated errors, the route-level BlocProvider and the bloc's tests. Cubit only when events are unnecessary. For the translated text itself (ARB key, getter) use localize_feature.
---

# Skill: Screen logic with BLoC

Use this skill to give a screen a `BaseBloc` controller: load data through a use case, render
loading / success / error, react to failures.

> **Use [`localize_feature`](../localize_feature/SKILL.md) for** the text a toast, dialog or error state shows (ARB key, getter,
> `failureMessage`); this skill decides when it appears.

**Guide:** [`docs/en/guides/03_state_management.md`](../../../docs/en/guides/03_state_management.md) § 6–9
(the long form); the package README is `platform/state/bloc/README.md`.
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-10, RULE-21, RULE-34, RULE-35,
RULE-36, RULE-50, RULE-51, RULE-52, RULE-53, RULE-61. Cite them; do not restate them.

Default is `BaseBloc` + Freezed events. `BaseCubit` only when events are unnecessary (one method, no
concurrent intents) — say why in a comment; the file stays `*_cubit.dart` / `*Cubit`.

> `BaseBloc` and `BaseCubit` are extension points only. The counterpart of Provider's `executeOperation`
> is **opt-in**: mix in `BlocResultMixin<T>` (`CubitResultMixin<T>`) when the state is `BlocViewState<T>`
> and call `emitResult(emit, () => useCase(params))`. A bloc with its own Freezed state unwraps the
> `Result` by hand (§ 5). Read `platform/state/bloc/lib/src/result_emitter.dart` for the exact rules.

## 1. What the generator gave you

`generate.dart 1 <name> "" 2 <route>` writes, under `modules/<name>/feature/lib/src/`:

- `bloc/<name>_bloc.dart` — an `@injectable` `<Name>Bloc extends BaseBloc<<Name>Event, BlocViewState<<Name>StateData>>
  with BlocResultMixin<<Name>StateData>`, with `part` lines for the event, the state and `.freezed.dart`;
- `bloc/<name>_event.dart` (`part of`) — a Freezed event whose subclasses are private (`= _<Name>Started`);
- `bloc/<name>_state.dart` (`part of`) — `<Name>StateData`, a Freezed placeholder payload;
- `pages/<name>_page.dart` — a `BlocBuilder` over `BlocViewState<<Name>StateData>`;
- the route that creates the bloc **and dispatches `started`** (§ 7), and tests that pass as generated
  (`test/<name>_page_test.dart`, `test/<name>_bloc_test.dart`).

Everything below **replaces those placeholders**; keep the file names and the `part` structure.

## 2. Declare the dependencies

Declare every package your code imports under `dependencies:` (`arch_check` R5). The generated feature
already lists `bloc_state_management` (it re-exports `flutter_bloc`), `domain_core`, `core_ui_kit`
(`LoadingWidget`, `AppOverlay`), `core_base_ui` and `core_responsive`. Add `domain_<name>` for the use case
and entity you inject — a feature never imports `data_<name>` (RULE-04). Path entries only, no versions;
then `flutter pub get`, before codegen.

## 3. Events: private Freezed subclasses

```dart
// product_event.dart
part of 'product_bloc.dart';

@freezed
abstract class ProductEvent with _$ProductEvent {
  const factory ProductEvent.started() = _ProductStarted;
  const factory ProductEvent.refreshed() = _ProductRefreshed;
}
```

The bloc file holds `part 'product_event.dart';`, `part 'product_state.dart';` and
`part 'product_bloc.freezed.dart';` (RULE-51). Handlers are `async (event, emit)` method references
(RULE-52, `arch_check` R18); a sync closure that starts async work ends in "emit was called after an
event handler completed normally".

## 4. A bloc that loads through a use case

`BlocViewState<T>` (`platform/state/bloc/lib/src/bloc_view_state.dart`) has `initial`, `loading`,
`success(T data)` and `error(AppFailure)`, plus `T? get data`; it is **not** the Provider branch's
`ViewState`. `emitResult` emits `loading` (skipped once a `success` is on screen), settles the
`Result` into `success` / `error`, restores the previous state on `none` / `cancel` and turns a thrown
error into `error(ErrorHandler.handleError(e))` (RULE-53).

```dart
@injectable
class ProductBloc
    extends BaseBloc<ProductEvent, BlocViewState<List<ProductEntity>>>
    with BlocResultMixin<List<ProductEntity>> {
  ProductBloc(this._getProducts) : super(const BlocViewState.initial()) {
    on<_ProductStarted>(_load);
    on<_ProductRefreshed>(_load);
  }

  final GetProductsUseCase _getProducts;

  Future<void> _load(
    ProductEvent event,
    Emitter<BlocViewState<List<ProductEntity>>> emit,
  ) async => emitResult(emit, () async => _getProducts(const NoParams()));
}
```

When the use case returns another type than the state's payload, pass `convert:` (the payload `R` to `T`).
Use the generated `<Name>StateData` as the payload only while it is a placeholder: replace it with your
entity or view data and delete `<name>_state.dart` with its `part` line. Generic code writes the type
argument (`BlocViewState<T>.loading()`, never `const BlocViewState.loading()`), or the state is
`BlocViewState<Never>` and never compares equal.

Reference sample: `modules/home/feature/lib/src/bloc/home_profile_bloc.dart` — a **stream-mapping** bloc
with no use case; it emits `BlocViewState.success` by hand and reads a nullable
`@factoryParam ISessionStatusStream?` that its route passes with `getItOrNull`.

## 5. A custom Freezed state, unwrapped by hand

For forms, wizards and filters declare a state in the feature and extend `BaseBloc<Event, YourState>`. The
state carries the failure's **code**, not its text (`AppFailure.message` is developer text, RULE-34):

```dart
@freezed
abstract class CheckoutState with _$CheckoutState {
  const factory CheckoutState({
    @Default([]) List<CartLine> lines,
    @Default(false) bool isSubmitting,
    int? failureCode,
  }) = _CheckoutState;
}
```

Every handler emits a loading state before the async work, unwraps `Result<T>` (`success` / `failure` /
`none` / `cancel` — `when` is exhaustive) and ends in a terminal state:

```dart
Future<void> _onSubmitted(
  _CheckoutSubmitted event,
  Emitter<CheckoutState> emit,
) async {
  emit(state.copyWith(isSubmitting: true, failureCode: null));
  final result = await _submit(SubmitParams(lines: state.lines));
  result.when(
    success: (_) => emit(state.copyWith(isSubmitting: false)),
    failure: (f) => emit(state.copyWith(isSubmitting: false, failureCode: f.code)),
    none: () => emit(state.copyWith(isSubmitting: false)),
    cancel: () => emit(state.copyWith(isSubmitting: false)),
  );
}
```

## 6. Render and react

```dart
BlocBuilder<ProductBloc, BlocViewState<List<ProductEntity>>>(
  builder: (context, state) => state.when(
    initial: () => const Center(child: LoadingWidget()),
    loading: () => const Center(child: LoadingWidget()),
    success: (products) => ProductList(products: products),
    // `failure.message` is an English diagnostic, never shown (RULE-34): word the failure from its code.
    error: (failure) => Center(child: Text(context.l10n.failureMessage(failure.code))),
  ),
)
```

`LoadingWidget` is `core_ui_kit`'s; `context.l10n.failureMessage` is `core_base_ui`'s. For a side effect
(a toast, navigation) use a `BlocListener` — never `build`:

```dart
BlocListener<ProductBloc, BlocViewState<List<ProductEntity>>>(
  listenWhen: (previous, current) => current.maybeWhen(error: (_) => true, orElse: () => false),
  listener: (context, state) => state.maybeWhen(
    error: (failure) => AppOverlay.showToast(content: context.l10n.failureMessage(failure.code)),
    orElse: () {},
  ),
  child: const ProductListContent(),
)
```

A dialog is its own widget class (`*_dialog.dart`, extending `OverlayDialogWidget`, shown with
`AppOverlay.showDialog` — RULE-36); `RetryDialog` in `core_ui_kit` is the example. Dispatch events with
`context.read<ProductBloc>().add(const ProductEvent.refreshed())`.

## 7. Create it at the route, and dispatch the first event in one place

The route creates the bloc; the `Page` never wraps itself in a second `BlocProvider` (RULE-21). The
generated route already dispatches the first event:

```dart
create: (context) => getIt<ProductBloc>()..add(const ProductEvent.started()),
```

Dispatch `started` **either** there **or** in the bloc's constructor (`HomeProfileBloc` does, its route
does not) — never both. The route snippet, factory parameters and the `@injectable` rule (RULE-10) live
once: [`implement_navigation_route`](../implement_navigation_route/SKILL.md) and
[`implement_dependency_injection`](../implement_dependency_injection/SKILL.md).

## 8. Translated text

Every user-facing string is translated (RULE-34, RULE-35): add the keys to the feature's
`assets/language/en.arb` **and** `vi.arb` (`lowerCamelCase`), then `cd modules/<name>/feature && flutter gen-l10n`
and read them through `context.l10n<Name>`. Steps: [`localize_feature`](../localize_feature/SKILL.md).

## 9. Update the tests

Once the bloc takes a use case, the generated tests (`<Name>Bloc()` with no argument) stop compiling and the
page test shows a bloc that never settles. Build the bloc from the use case over a **hand-written fake**
repository (RULE-61), as `modules/home/feature/test/home_profile_bloc_test.dart` builds its bloc from a fake
stream. The fake keeps its data `const`, so the expected state is a `const` too (without it,
`prefer_const_constructors` fails the 0-issues gate):

```dart
class FakeProductRepository implements IProductRepository {
  static const products = [ProductEntity(id: 1, name: 'Pen', price: 2)];

  @override
  Future<Result<List<ProductEntity>>> getProducts() async =>
      const Result.success(products);
}

test('started emits loading, then success', () async {
  final bloc = ProductBloc(GetProductsUseCase(FakeProductRepository()));
  addTearDown(bloc.close);

  bloc.add(const ProductEvent.started());

  await expectLater(
    bloc.stream,
    emitsInOrder([
      const BlocViewState<List<ProductEntity>>.loading(),
      const BlocViewState<List<ProductEntity>>.success(
        FakeProductRepository.products,
      ),
    ]),
  );
});
```

The page test provides a bloc built the same way, above the page under `ResponsiveInit`, as `Route.build` does.
Change its assertions too: the generated `expect(find.text(title), findsNWidgets(2))` counts the title in the
app bar **and** in the placeholder body, so it fails once the success body shows your data. Assert the app bar
title once and the fake's data instead (`expect(find.text('Pen'), findsOneWidget)`).

## Related

- [`implement_provider_ui`](../implement_provider_ui/SKILL.md) — the Provider branch, with `executeOperation`
- [`implement_domain_data_flow`](../implement_domain_data_flow/SKILL.md) — the use case this bloc calls

## Verify

```bash
cd modules/<name>/feature && flutter gen-l10n            # after ARB edits
dart run build_runner build --workspace                  # events, state and the DI registration
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R5 declared deps, R18 async handlers, R7 / R20 no raw sizes
dart tools/composer/composer.dart verify
cd modules/<name>/feature && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # the bloc factory builds from the real graph
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77, after a DI or dependency change
```

Barrels: [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator) says when to regenerate them.
