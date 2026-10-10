---
name: implement_domain_data_flow
description: Use when wiring a new business flow end to end — "integrate a new API endpoint", "load X from the server and show it", "add a use case / repository / model". Builds it domain first (entity, repository interface, use case) then data (model, Retrofit data source, RepositoryImpl with execute()), replaces the generated ping() stubs, declares the dependencies, and hands the use case to a Provider or BLoC consumer with its tests.
---

# Skill: Implement a domain and data flow

Use this skill to put a new business operation behind a use case: "load products from the server and
show them", "integrate a new endpoint", "add a use case / repository / model".

**Guide:** [`docs/en/guides/02_new_domain_data.md`](../../../docs/en/guides/02_new_domain_data.md) (the
long form), [`08_networking.md`](../../../docs/en/guides/08_networking.md) (Retrofit, interceptors).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-03, RULE-06, RULE-09, RULE-40,
RULE-41, RULE-42, RULE-43, RULE-49, RULE-61, RULE-74, RULE-77. Cite them; do not restate them.

The examples use a `product` module; substitute yours.

## Order of work

Each step only depends on the ones above it: **domain first** (entity, repository interface, use case),
**then data** (model, data source, RepositoryImpl), then the consumer.

### Step 0: Generate the packages, domain first

```bash
dart tools/module_generator/generate.dart 2 product   # domain_product
dart tools/module_generator/generate.dart 3 product   # data_product (implements the domain's interface)
```

Without `--apps` both join every `apps/<id>/app_manifest.yaml`. Each run also composes the package,
resolves dependencies, runs `build_runner` and writes the package barrel. The generator leaves **one
stub each** — `I<Product>Repository` with a placeholder `ping()` and `ProductRepositoryImpl extends
BaseRepository` — so **replace `ping()`**, never create a second interface or implementation.
Details: [`create_feature_module`](../create_feature_module/SKILL.md).

### Step 1: Entity (domain)

`modules/<module>/domain/lib/src/entities/product_entity.dart`. Freezed, with `const Class._()`
(RULE-49). The first entity brings `freezed_annotation:` under `dependencies:` and `freezed:` under
`dev_dependencies:` (versions stay empty — see Step 8).

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_entity.freezed.dart';

@freezed
abstract class ProductEntity with _$ProductEntity {
  const ProductEntity._();

  const factory ProductEntity({
    required int id,
    required String name,
    required double price,
  }) = _ProductEntity;
}
```

The domain stays pure Dart (RULE-03): no Flutter, Dio, Retrofit, `core_*`. A use case with no input
takes `NoParams` from `domain_core`; with input, add a Freezed params class under `src/params/`.

### Step 2: Repository interface (domain)

Edit the generated `modules/<module>/domain/lib/src/repositories/i_product_repository.dart` — drop
`ping()`, declare the real operations. Every method returns `Result<T>`:

```dart
import 'package:domain_core/domain_core.dart';

import '../entities/product_entity.dart';

abstract class IProductRepository {
  Future<Result<List<ProductEntity>>> getProducts();
}
```

### Step 3: Use case (domain)

`modules/<module>/domain/lib/src/usecases/get_products_usecase.dart`. `@injectable`, one operation,
returns `Result<T>` (RULE-49):

```dart
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../entities/product_entity.dart';
import '../repositories/i_product_repository.dart';

@injectable
class GetProductsUseCase extends BaseUseCase<List<ProductEntity>, NoParams> {
  GetProductsUseCase(this._repository);

  final IProductRepository _repository;

  @override
  Future<Result<List<ProductEntity>>> call(NoParams params) =>
      _repository.getProducts();
}
```

### Step 4: Model (data)

`modules/<module>/data/lib/src/models/product_model.dart`. Freezed + `json_serializable`,
`implements BaseModel<Entity>` with `toEntity()` (RULE-41). Declare `domain_product` (the generator
already did when the domain existed first), `freezed_annotation:` and `json_annotation:` under
`dependencies:`, `freezed:` and `json_serializable:` under `dev_dependencies:`.

```dart
import 'package:data_core/data_core.dart';
import 'package:domain_product/domain_product.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_model.freezed.dart';
part 'product_model.g.dart';

@freezed
abstract class ProductModel with _$ProductModel implements BaseModel<ProductEntity> {
  const ProductModel._();

  const factory ProductModel({
    @JsonKey(name: 'id') required int id,
    @JsonKey(name: 'name') required String name,
    @JsonKey(name: 'price') required double price,
  }) = _ProductModel;

  factory ProductModel.fromJson(Map<String, dynamic> json) =>
      _$ProductModelFromJson(json);

  @override
  ProductEntity toEntity() => ProductEntity(id: id, name: name, price: price);
}
```

A database-backed source wraps the Drift row instead of JSON and converts it at the boundary:
`CacheEntryModel.fromRow` in `modules/cache/data/lib/src/models/cache_entry_model.dart` —
[`implement_package_database`](../implement_package_database/SKILL.md).

### Step 5: Endpoint constants (data)

Endpoints live in the owning package's `utils/` (RULE-09), `modules/<module>/data/lib/src/utils/product_api_constants.dart`
(shape of `AuthApiConstants` in `modules/auth/data/lib/src/utils/auth_constants.dart`, which also holds that
package's storage keys in the same file):

```dart
class ProductApiConstants {
  ProductApiConstants._();

  static const String PRODUCTS = '/products';
}
```

### Step 6: Retrofit data source and its registration (data)

Add `dio:` and `retrofit:` under `dependencies:` and `retrofit_generator:` under `dev_dependencies:`,
each with an empty value (Step 8 fills the versions). A data source returns Models, wrapped in the
`BaseEntity<T>` envelope, and exposes no other generated type (RULE-41). Directory is
`data_sources/remote/` (RULE-40). Import a type the generated code names — `BaseEntity` — from its real
home, `package:domain_core/domain_core.dart` (RULE-77). Modelled on
`modules/auth/data/lib/src/data_sources/remote/auth_remote_data_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:domain_core/domain_core.dart';
import 'package:retrofit/retrofit.dart';

import '../../models/product_model.dart';
import '../../utils/product_api_constants.dart';

part 'product_remote_data_source.g.dart';

@RestApi()
abstract class ProductRemoteDataSource {
  factory ProductRemoteDataSource(Dio dio, {String? baseUrl}) =
      _ProductRemoteDataSource;

  @GET(ProductApiConstants.PRODUCTS)
  Future<BaseEntity<List<ProductModel>>> getProducts();
}
```

A Retrofit class is a factory constructor, not an `@injectable` class, so register it through a
`@module` in the **existing** `modules/<module>/data/lib/di/module.dart`, beside the generated
`@InjectableInit.microPackage()` marker (as `modules/auth/data/lib/di/module.dart` does):

```dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../src/data_sources/remote/product_remote_data_source.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class ProductDataDiModule {
  @lazySingleton
  ProductRemoteDataSource productRemoteDataSource(Dio dio) =>
      ProductRemoteDataSource(dio);
}
```

The `Dio` is `core_network`'s client with the interceptor chain; the package needs no `core_network`
dependency for that unless it imports its types (`NetworkConstants`, `ApiClient`).

### Step 7: RepositoryImpl (data)

Edit the generated `modules/<module>/data/lib/src/repositories_impl/product_repository_impl.dart`:
inject the data source, drop `ping()`, wrap every call in `execute()` (async) or `executeSync()`
(RULE-42). `R` is what the request returns — here the whole envelope — and `T` the entity.
`successCondition` turns a 200 with an error body into a `Failure`; `mapper` unwraps the envelope.
Same shape as `_authenticate` in `modules/auth/data/lib/src/repositories_impl/auth_repository_impl.dart`:

```dart
import 'package:data_core/data_core.dart';
import 'package:domain_core/domain_core.dart';
import 'package:domain_product/domain_product.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/remote/product_remote_data_source.dart';
import '../models/product_model.dart';

@LazySingleton(as: IProductRepository)
class ProductRepositoryImpl extends BaseRepository implements IProductRepository {
  ProductRepositoryImpl(this._remote);

  final ProductRemoteDataSource _remote;

  @override
  Future<Result<List<ProductEntity>>> getProducts() {
    return execute<BaseEntity<List<ProductModel>>, List<ProductEntity>>(
      _remote.getProducts,
      successCondition: (response) =>
          response.isSuccess && response.data != null,
      mapper: (response) => response.data!.map((m) => m.toEntity()).toList(),
    );
  }
}
```

Errors are classified by `ErrorHandler.handleError(e)` (RULE-43), never an invented
`AppFailure.fromException()`. `ErrorHandler` has no Firebase branch: a flow on Firebase registers an
`ErrorClassifier` first ([guide 02 § 9](../../../docs/en/guides/02_new_domain_data.md#9-implement-the-repository)).

### Step 8: Dependencies and codegen

Write every third-party entry with an empty value (`dio:`); versions live only in the catalog
(RULE-74), so `dart tools/dependency_sync.dart` fills them in and runs `pub get`. `pubspec.lock` is generated and
git-ignored: never commit it. Add a dependency **as your code starts importing it**: `arch_check`
R5 fails an import that is not declared, `check_unused_packages` a declaration nothing imports.

The data package's models and repository import `domain_<name>` types (the entity, `I<Name>Repository`) through
the domain barrel, which is stale after Steps 1-3 — so regenerate the domain and data barrels **before**
`build_runner`, then the data barrel once more after it (the generated files are exported too):

```bash
dart tools/dependency_sync.dart
dart tools/barrel_generator/generate.dart modules/<module>/domain/lib
dart tools/barrel_generator/generate.dart modules/<module>/data/lib
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<module>/data/lib
```

Skipped, `flutter analyze` reports `non_type_as_type_argument` on the entity in the models and repository
implementation. [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator) states the general order.

### Step 9: Consume it

The feature declares `domain_product` and `domain_core` under `dependencies:` **before** codegen, takes
the use case through its controller's constructor, and never imports `data_product` (RULE-04, `arch_check`
R3). `executeOperation` unwraps the `Result` for Provider
(`OperationConfig(operation: () => _useCase(const NoParams()))`), `emitResult` for a BLoC — see
[`implement_provider_ui`](../implement_provider_ui/SKILL.md) and [`implement_bloc_ui`](../implement_bloc_ui/SKILL.md).
Then rerun `build_runner`: the controller's constructor, and so its DI registration, changed. Regenerate
the domain barrel before it if the feature imports a type you added in this flow, and the feature barrel after
(`dart tools/barrel_generator/generate.dart modules/<module>/feature/lib`).

### Step 10: Tests

- Controller: the generated `test/<name>_provider_test.dart` / `<name>_bloc_test.dart` and
  `<name>_page_test.dart` build the controller with no argument and stop compiling. Rebuild it from the
  use case over a **hand-written fake** of `IProductRepository` (RULE-61), as
  `modules/auth/feature/test/auth_provider_test.dart` does.
  The page test's generated `expect(find.text(title), findsNWidgets(2))` counts the placeholder body too: once
  the real body replaces it, assert the title once in the app bar and the fake's data instead.
- Repository: a fake data source — one test maps models to entities, one where the data source throws and
  the repository returns a `Failure`.

## Related

- [`docs/en/architecture/03_domain.md`](../../../docs/en/architecture/03_domain.md) and [`04_data.md`](../../../docs/en/architecture/04_data.md)
- [`implement_package_storage`](../implement_package_storage/SKILL.md) — key-value persistence;
  [`implement_package_database`](../implement_package_database/SKILL.md) — Drift tables
- [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md) — "not registered" at boot

## Verify

```bash
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R2 pure domain, R3 no feature -> data, R5 declared deps
dart tools/composer/composer.dart verify                 # the new packages are composed
dart tools/unused_checker/check_unused_packages.dart     # no declared-but-unused dependency
cd modules/<module>/feature && flutter test               # and every package you added a test to
cd apps/mobile && flutter test test/di_smoke_test.dart   # use case, repository and data source resolve
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77
```
