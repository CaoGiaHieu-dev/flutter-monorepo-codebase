# Domain Layer

**What this answers:** what business rules live in `packages/domain/*`, why that code is forbidden from touching Flutter, and what `Result<T>` actually gives you.

**After reading you can:** read any use case in the repo, know which types you may import inside a domain package, and add a new entity / params / use case without breaking the layer boundary.

---

## 1. What the Domain layer is for

Domain is the centre of the dependency rule: it depends on nobody, and everybody depends on it through interfaces.

```
Feature (UI) ──→ Domain ←── Data
```

A domain package holds four things and nothing else:

| Component | Directory | Responsibility |
|:---|:---|:---|
| **Entities** | `entities/` | Immutable business objects (Freezed) |
| **Params** | `params/` | Typed inputs for use cases |
| **Repository interfaces** | `repositories/` | Contracts the Data layer must satisfy |
| **Use cases** | `usecases/` | One business operation each, returns `Result<T>` |

No widgets, no HTTP, no SQL, no `SharedPreferences`. If a use case needs any of that, it declares an *interface* and lets `packages/data/*` implement it.

---

## 2. The Pure-Dart mandate

### Forbidden imports

```dart
import 'package:flutter/...';    // ❌
import 'package:dio/...';        // ❌
import 'package:retrofit/...';   // ❌
import 'package:drift/...';      // ❌
```

### Allowed imports

| Package | Why it is allowed |
|:---|:---|
| `dart:core`, `dart:async` | Language basics |
| `domain_core` | `Result<T>`, `AppFailure`, `BaseEntity<T>`, `BaseUseCase`, `NoParams` |
| `freezed_annotation`, `json_annotation` | Codegen annotations only |
| `injectable`, `get_it` | DI annotations |

### Verification

The rule holds in the source. Run it yourself:

```bash
grep -rn "import 'package:flutter\|import 'package:dio\|import 'package:retrofit" \
  --include="*.dart" packages/domain/
# → no output
```

> [!NOTE]
> **The package graph enforces this, not just review.** No domain pubspec lists `flutter` under `dependencies`, and none declares a `core_*` package:
>
> ```yaml
> # packages/domain/auth/pubspec.yaml
> dependencies:
>   domain_core:
>     path: ../core
>   get_it: ^9.2.1
>   injectable: ^3.0.0
>   freezed_annotation: ^3.1.0
>   json_annotation: ^4.12.0
> ```
>
> `domain_core` itself has **no** workspace dependency at all. An `import 'package:flutter/…'` added to a domain file therefore fails to resolve rather than quietly compiling. Keep it that way: never add `flutter` or a `core_*` package to a domain pubspec.
>
> One caveat, so the claim is not oversold: every domain pubspec still carries a `flutter:` constraint under `environment:`. That is a minimum-SDK assertion, not a dependency — it pulls no Flutter code into the package graph, and the purity check above still passes. It does mean pub wants the Flutter SDK present to resolve these packages, so they are not consumable from a Dart-only runtime as they stand. Drop the `environment: flutter:` line if you ever need to share a domain package with a pure Dart server.

### Why UI state bypasses Domain entirely

`ThemeMode` and `Locale` are `flutter/material.dart` types. A domain package cannot name them, so routing theme/locale through a use case is impossible by construction. Those two flows deliberately skip Domain and persist through an interface owned by `core_di` instead. See [Cross-feature communication](../guides/10_cross_feature.md).

---

## 3. `domain_core` — the shared vocabulary

`packages/domain/core/` is depended on by every other domain package.

### `Result<T>` — the return type of every use case

Defined in `packages/domain/core/lib/src/repositories/result.dart`, with `AppFailure` alongside it in `src/failures/`:

```dart
@freezed
sealed class Result<T> with _$Result<T> {
  const Result._();

  const factory Result.success([T? data]) = Success<T>;
  const factory Result.failure(AppFailure error) = Failure<T>;
  const factory Result.none() = None<T>;
  const factory Result.cancel() = Cancel<T>;
```

Because it is `sealed`, Dart 3 pattern matching is exhaustive:

```dart
switch (result) {
  case Success(:final data): print('Data: $data');
  case Failure(:final error): print('Error: ${error.message}');
  case None(): print('No result');
  case Cancel(): print('Cancelled');
}
```

> [!NOTE]
> **`None` and `Cancel` are unused reserve variants.** Grep the repo: no repository or use case ever returns `Result.none()` or `Result.cancel()` — they appear only in `packages/core/provider_state_management/test/base_provider_test.dart`. So the honest answer to *"when does `Cancel` happen?"* is: **it does not, today.** They exist so the union can grow without a breaking change. You still have to handle them in exhaustive `switch` / `whenAsync`, which is the cost of keeping them.

#### API surface

| Member | Kind | Notes |
|:---|:---|:---|
| `isSuccess` / `isFailure` | getter | Type test |
| `dataOrNull` | getter | Data on `Success`, else `null` |
| `errorOrNull` | getter | `AppFailure` on `Failure`, else `null` |
| `when` / `whenOrNull` / `maybeWhen` | Freezed-generated | Synchronous branches |
| `whenAsync` | hand-written | Use when **any** branch does async work |
| `mapData<R>` | hand-written | Transform `Success` data, pass other variants through |
| `flatMap<R>` | hand-written | Chain another `Result`-returning call |
| `getOrElse(default)` | hand-written | Data or fallback |
| `getOrThrow()` | hand-written | Data, or throws the `AppFailure` |

`whenAsync` exists because Freezed's generated `when` is synchronous:

```dart
Future<R> whenAsync<R>({
  required FutureOr<R> Function(T? data) success,
  required FutureOr<R> Function(AppFailure error) failure,
  required FutureOr<R> Function() none,
  required FutureOr<R> Function() cancel,
}) async { ... }
```

Two aliases are provided for wrapped server payloads:

```dart
typedef BaseResult<T> = Result<BaseEntity<T>>;
typedef BasePaginateResult<T> = Result<BaseEntity<PaginatedEntity<T>>>;
```

### `BaseEntity<T>` — standard server envelope

`packages/domain/core/lib/src/entities/base/base_entity.dart`:

```dart
@Freezed(genericArgumentFactories: true)
abstract class BaseEntity<T> with _$BaseEntity<T> {
  const BaseEntity._();

  const factory BaseEntity({
    @JsonKey(name: 'statusCode') @Default(200) int statusCode,
    @JsonKey(name: 'data') T? data,
    @JsonKey(name: 'message') String? message,
  }) = _BaseEntity<T>;

  bool get isSuccess => statusCode == DomainConstants.SUCCESS_STATUS_CODE;
  bool get hasError => !isSuccess;
```

### `PaginatedEntity<T>` + `MetaPaginate`

`packages/domain/core/lib/src/entities/base/paginate_entity.dart` — items land in `data` (JSON key `items`), page info in `meta` (`totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`).

### `BaseUseCase<RType, Params>`

```dart
abstract class BaseUseCase<RType, Params> {
  FutureOr<Result<RType>> call(Params params);
}
```

`FutureOr` is deliberate: a use case reading local storage can be fully synchronous (see `GetLanguageUseCase` below) while a network one returns a `Future`.

Use `NoParams()` when an operation takes no input.

### Cache sample

`domain_core` also ships a working cache slice — `CacheEntryEntity`, `CacheEntryParams`, `ICacheEntryRepository`, and `GetCacheEntryUseCase` / `SaveCacheEntryUseCase` / `GetAllCacheEntriesUseCase`. It is the domain half of the Drift example described in [the database guide](../guides/07_database.md).

---

## 4. `domain_auth`

| File | Contents |
|:---|:---|
| `entities/user/user_entity.dart` | `UserEntity` (Freezed) |
| `entities/user/user_role.dart` | `UserRole` enum — `customer`, `owner`, `none`, `unknown` |
| `params/auth_params/login_params.dart` | `LoginParams` |
| `params/auth_params/complete_login_flow_params.dart` | `CompleteLoginFlowParams` |
| `repositories/i_auth_repository.dart` | `IAuthRepository` |
| `usecases/auth/` | `LoginUseCase`, `LogoutUseCase`, `RefreshTokenUseCase` |

### A use case, in full

`packages/domain/auth/lib/src/usecases/auth/login_usecase.dart`:

```dart
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) {
    // Params are already validated at construction - no need to validate here
    // Repository returns Result<UserEntity> directly - no unwrapping needed
    return _authRepository.login(params);
  }
}
```

Three things to copy from this:

1. **`@injectable`** — a use case is a factory, never a singleton.
2. **Constructor injection** — the repository interface arrives through the constructor. Never call `getIt<T>()` inside a use case.
3. **No re-validation, no unwrapping** — params validate themselves at construction; the repository already returns `Result<T>`.

A synchronous use case looks the same minus the `Future`:

```dart
@injectable
class LogoutUseCase extends BaseUseCase<void, NoParams> {
  LogoutUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Result<void> call(NoParams params) {
    return _authRepository.logout();
  }
}
```

### `UserRole` has an `unknown` member on purpose

```dart
enum UserRole {
  @JsonValue('customer') customer,
  @JsonValue('owner') owner,
  @JsonValue('none') none,
  unknown,
}
```

`unknown` carries no `@JsonValue`; it is the landing slot for `@JsonKey(unknownEnumValue: UserRole.unknown)` in `UserModel`, so a role the server adds later deserialises instead of throwing.

---

## 5. `domain_language` — a stub, and why it stays

`domain_language` is complete but **not wired to any screen**:

| File | Contents |
|:---|:---|
| `repositories/i_language_repository.dart` | `ILanguageRepository` — `getLanguage()`, `setLanguage()` |
| `params/set_language_params.dart` | `SetLanguageParams` |
| `usecases/get_language_usecase.dart` | `GetLanguageUseCase` |
| `usecases/set_language_usecase.dart` | `SetLanguageUseCase` |

```dart
abstract class ILanguageRepository {
  Result<void> setLanguage(String languageCode);
  Result<String> getLanguage();
}
```

> [!IMPORTANT]
> **The Settings screen does not call these use cases.** Language switching goes through `LanguageProvider` in `core_base_ui`, which persists via `ILanguageStorage` — bypassing Domain entirely.
>
> That is not an oversight. `Locale` is a Flutter type, so a pure-Dart domain package cannot express "the current locale" without inventing a parallel `String` representation and translating at every boundary. For a value that never leaves the UI, the ceremony buys nothing.
>
> `domain_language` is kept as the template for the day locale becomes a *business* concern — user preference synced to a server, per-tenant defaults — at which point the use cases already exist. Until then, read it as reference, and do not add screens that depend on it.

Note it has no entity: it exchanges a plain `String` language code.

---

## 6. Package layout and naming

```
packages/domain/<name>/
├── lib/
│   ├── domain_<name>.dart          # public barrel
│   ├── di/
│   │   ├── module.dart             # @InjectableInit.microPackage()
│   │   └── di.dart
│   └── src/
│       ├── entities/
│       ├── params/
│       ├── repositories/
│       ├── usecases/
│       ├── services/               # optional
│       ├── utils/                  # package-owned constants (if any)
│       └── src.dart
└── pubspec.yaml
```

| Component | File suffix | Class suffix | Example |
|:---|:---|:---|:---|
| Entity | `_entity.dart` | `Entity` | `UserEntity` |
| Params | `_params.dart` | `Params` | `LoginParams` |
| Repository interface | `i_<name>_repository.dart` | prefix `I` | `IAuthRepository` |
| Use case | `_usecase.dart` | `UseCase` | `LoginUseCase` |

The `I` prefix is reserved for interfaces. Never name an implementation `IFoo`. Constants are `UPPER_SNAKE_CASE` and live in the package's own `utils/` — see [rules](../reference/01_rules.md).

### Entities use Freezed with a private constructor

```dart
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();          // ← required to add getters/methods

  const factory UserEntity({
    required String id,
    String? email,
    // …
  }) = _UserEntity;

  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);
}
```

The `const Class._()` line is mandatory. Without it Freezed cannot generate a class you can extend with custom getters (`BaseEntity.isSuccess` depends on this).

---

## 7. Adding to the Domain layer

```bash
# 1. Scaffold the package (creates dirs + registers the workspace member)
dart tools/module_generator/generate.dart 2 payment

# 2. Write entity → params → repository interface → use case

# 3. Refresh the barrel files
dart tools/barrel_generator/generate.dart packages/domain/payment/lib

# 4. Generate Freezed + injectable code
dart run build_runner build -d --workspace
```

Checklist before you open a PR:

- [ ] No `flutter` / `dio` / `retrofit` / `drift` import anywhere in the package
- [ ] Entities are Freezed with `const Class._()`
- [ ] Use cases are `@injectable` (never singleton) and return `Result<T>`
- [ ] Dependencies arrive by constructor — no `getIt<T>()` in the body
- [ ] Constants sit in the package's own `utils/`
- [ ] The package is declared in the root `pubspec.yaml` workspace list with `resolution: workspace`

---

## Related

- [Data layer](04_data.md) — who implements these repository interfaces
- [Feature layer](05_features.md) — who calls these use cases
- [Guide: new domain + data package](../guides/02_new_domain_data.md)
- [Rules and conventions](../reference/01_rules.md)
