# Domain Layer

**What this answers:** what business rules live in `modules/*/domain`, why that code is forbidden from touching Flutter, and what `Result<T>` actually gives you.

**After reading you can:** read any use case in the repo, know which types you may import inside a domain package, and add a new entity / params / use case without breaking the layer boundary.

---

## 1. What the Domain layer is for

Domain is the centre of the dependency rule: it depends on nothing but `domain_core`, and everybody depends on it through interfaces.

```
Feature (UI) ──→ Domain ←── Data
```

A domain package holds four things:

| Component | Directory | Responsibility |
|:---|:---|:---|
| **Entities** | `entities/` | Immutable business objects (Freezed) |
| **Params** | `params/` | Typed inputs for use cases |
| **Repository interfaces** | `repositories/` | Contracts the Data layer must satisfy |
| **Use cases** | `usecases/` | One business operation each, returns `Result<T>` |

No widgets, no HTTP, no SQL, no `SharedPreferences`. If a use case needs any of that, it declares an *interface* and lets `modules/*/data` implement it.

---

## 2. The Pure-Dart mandate

Registry: RULE-03 — `arch_check` R2 reads domain imports, `dependencies:`, `dev_dependencies:` and test imports, so the list below is checked, not a convention.

### Forbidden

```dart
import 'package:flutter/...';    // ❌ Flutter, or any package that needs the Flutter SDK
import 'package:dio/...';        // ❌ transport
import 'package:retrofit/...';   // ❌ transport
import 'package:drift/...';      // ❌ persistence
import 'package:platform_kernel/...';  // ❌ any core_* / platform_* package
```

Also out: `data_*`, `feature_*`, another module's domain, and engine-only `dart:` libraries such as `dart:ui`.

### Allowed imports

| Package | Why it is allowed |
|:---|:---|
| `dart:core`, `dart:async` | Language basics |
| `domain_core` | `Result<T>`, `AppFailure`, `BaseEntity<T>`, `PaginatedEntity<T>`, `BaseUseCase`, `NoParams` |
| `freezed_annotation` | Codegen annotation only |
| `injectable` | DI annotations |

### Verification

The rule holds in the source. Run it yourself:

```bash
grep -rn "import 'package:flutter\|import 'package:dio\|import 'package:retrofit" \
  --include="*.dart" modules/*/domain/
# → no output
```

> [!NOTE]
> **The package graph and `arch_check` enforce this, not just review.** No domain pubspec lists `flutter` under `dependencies`, and none declares a `core_*` package:
>
> ```yaml
> # modules/auth/domain/pubspec.yaml
> dependencies:
>   domain_core:
>     path: ../../../platform/layers/domain
>   injectable: ^3.0.0
>   freezed_annotation: "^3.1.0"
> ```
>
> `domain_core` itself has **no** workspace dependency at all. An `import 'package:flutter/…'` added to a domain file therefore fails to resolve rather than quietly compiling, and a `core_*` dependency fails Gate 1. A domain test runs on `package:test`, not `flutter_test`.
>
> One caveat, so the claim is not oversold: every domain pubspec still carries a `flutter:` constraint under `environment:`. That is a minimum-SDK assertion, not a dependency — it pulls no Flutter code into the package graph, and the purity check above still passes. It does mean pub wants the Flutter SDK present to resolve these packages, so they are not consumable from a Dart-only runtime as they stand. Drop the `environment: flutter:` line if you ever need to share a domain package with a pure Dart server.

### Why UI state bypasses Domain entirely

`ThemeMode` and `Locale` are `flutter/material.dart` types. A domain package cannot name them, so routing theme/locale through a use case is impossible by construction. Those two flows deliberately skip Domain and persist through an interface owned by `core_di` instead. See [Cross-feature communication](../guides/10_cross_feature.md).

---

## 3. `domain_core` — the shared vocabulary

`platform/layers/domain/` is depended on by every other domain package.

### `Result<T>` — the return type of every use case

Defined in `platform/layers/domain/lib/src/result/result.dart`, with `AppFailure` in `src/failures/app_failure.dart`:

```dart
@freezed
sealed class Result<T> with _$Result<T> {
  const Result._();

  const factory Result.success([T? data]) = Success<T>;
  const factory Result.failure(AppFailure<dynamic> error) = Failure<T>;
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
> **`None` and `Cancel` are unused reserve variants.** Grep the repo: no repository or use case ever returns `Result.none()` or `Result.cancel()` — outside `result.dart` they appear only in `platform/layers/domain/test/result_test.dart`. So the honest answer to *"when does `Cancel` happen?"* is: **it does not, today.** They exist so the union can grow without a breaking change. You still have to handle them in exhaustive `switch` / `whenAsync`, which is the cost of keeping them.

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
  required FutureOr<R> Function(AppFailure<dynamic> error) failure,
  required FutureOr<R> Function() none,
  required FutureOr<R> Function() cancel,
}) async { ... }
```

### `BaseEntity<T>` — standard server envelope

`platform/layers/domain/lib/src/entities/base_entity.dart`:

```dart
@Freezed(genericArgumentFactories: true)
abstract class BaseEntity<T> with _$BaseEntity<T> {
  const BaseEntity._();

  const factory BaseEntity({
    @JsonKey(name: 'statusCode') @Default(200) int statusCode,
    @JsonKey(name: 'data') T? data,
    @JsonKey(name: 'message') String? message,
  }) = _BaseEntity<T>;

  bool get isSuccess =>
      statusCode >= DomainConstants.SUCCESS_STATUS_CODE &&
      statusCode < DomainConstants.SUCCESS_STATUS_CEILING;
  bool get hasError => !isSuccess;
```

`isSuccess` is any 2xx (`200` ≤ `statusCode` < `300`), so a `201` or a `204` envelope is a success.

### `PaginatedEntity<T>` + `MetaPaginate`

`platform/layers/domain/lib/src/entities/paginated_entity.dart` — items land in `data` (JSON key `items`), page info in `meta` (`totalItems`, `itemCount`, `itemsPerPage`, `totalPages`, `currentPage`).

### `BaseUseCase<RType, Params>`

```dart
abstract class BaseUseCase<RType, Params> {
  FutureOr<Result<RType>> call(Params params);
}
```

`FutureOr` is deliberate: a use case that only reads local state may return a plain `Result<T>`, while a network one returns a `Future`. The shipped use cases all return `Future`s.

Use `NoParams()` when an operation takes no input.

### Cache sample

The second sample domain package, `domain_cache` (`modules/cache/domain`), is a smaller slice — `CacheEntryEntity`, `CacheEntryParams`, `ICacheEntryRepository`, and `GetCacheEntryUseCase` / `SaveCacheEntryUseCase`. It is the domain half of the Drift example described in [the database guide](../guides/07_database.md).

---

## 4. `domain_auth`

| File | Contents |
|:---|:---|
| `entities/user_entity.dart` | `UserEntity` (Freezed) |
| `entities/user_role.dart` | `UserRole` enum — `customer`, `owner`, `none`, `unknown` |
| `params/login_params.dart` | `LoginParams` |
| `repositories/i_auth_repository.dart` | `IAuthRepository` — `login`, `logout`, `refreshToken`, `restoreSession` |
| `usecases/` | `LoginUseCase`, `LogoutUseCase`, `RestoreSessionUseCase` |

### A use case, in full

`modules/auth/domain/lib/src/usecases/login_usecase.dart`:

```dart
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) {
    return _authRepository.login(params);
  }
}
```

Three things to copy from this:

1. **`@injectable`** — a use case is a factory, never a singleton.
2. **Constructor injection** — the repository interface arrives through the constructor. Never call `getIt<T>()` inside a use case.
3. **No validation, no unwrapping** — a use case passes its params straight through. `LoginParams` does not validate itself either; it only carries the input, which the login form (`AuthFormWidget` in `feature_auth`) validated before building it. A rule that must hold whatever the caller is belongs in the use case, returned as a `Failure` — the repository already returns `Result<T>`, so there is nothing to unwrap.

A use case with no input takes `NoParams` and looks the same:

```dart
@injectable
class LogoutUseCase extends BaseUseCase<void, NoParams> {
  LogoutUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<void>> call(NoParams params) {
    return _authRepository.logout();
  }
}
```

### `UserRole` has an `unknown` member on purpose

```dart
enum UserRole { customer, owner, none, unknown }
```

The enum is plain Dart: how a backend spells a role on the wire is a transport concern, so the domain names no JSON value. `unknown` is the landing slot `UserModel` (in `data_auth`) maps an unrecognised role string to, so a role the server adds later is read instead of throwing.

---

## 5. Package layout and naming

```
modules/<name>/domain/
├── lib/
│   ├── domain_<name>.dart          # the package's one barrel (generated)
│   ├── di/
│   │   ├── module.dart             # @InjectableInit.microPackage()
│   │   └── module.module.dart      # generated by injectable
│   └── src/
│       ├── entities/
│       ├── params/
│       ├── repositories/
│       ├── usecases/
│       ├── services/               # optional
│       └── utils/                  # package-owned constants (if any)
└── pubspec.yaml
```

| Component | File suffix | Class suffix | Example |
|:---|:---|:---|:---|
| Entity | `_entity.dart` | `Entity` | `UserEntity` |
| Params | `_params.dart` | `Params` | `LoginParams` |
| Repository interface | `i_<name>_repository.dart` | prefix `I` | `IAuthRepository` |
| Use case | `_usecase.dart` | `UseCase` | `LoginUseCase` |

The `I` prefix marks interfaces only (RULE-78); constants live in the package's own `utils/` (RULE-09) — see [the rules](../reference/01_rules.md).

### Entities use Freezed with a private constructor

```dart
@freezed
abstract class UserEntity with _$UserEntity {
  const UserEntity._();          // ← required to add getters/methods

  const factory UserEntity({
    required String id,
    String? email,
    String? name,
    UserRole? role,
  }) = _UserEntity;
}
```

Keep the `const Class._()` line: without it Freezed cannot generate a class you can extend with custom getters (`BaseEntity.isSuccess` depends on this).

---

## 6. Adding to the Domain layer

```bash
# 1. Scaffold the package (adds it to every app manifest, then runs `composer sync`)
dart tools/module_generator/generate.dart 2 payment

# 2. Write entity → params → repository interface → use case

# 3. Generate Freezed + injectable code
dart run build_runner build --workspace

# 4. Regenerate the package barrel — after codegen, since the barrel exports generated files too
dart tools/barrel_generator/generate.dart modules/payment/domain/lib
```

Checklist before you open a PR:

- [ ] No `flutter` / `dio` / `retrofit` / `drift` / `core_*` import or dependency in the package (`dart tools/arch_check/check.dart`)
- [ ] Entities are Freezed with `const Class._()`
- [ ] Use cases are `@injectable` (never singleton) and return `Result<T>`
- [ ] Dependencies arrive by constructor — no `getIt<T>()` in the body
- [ ] Constants sit in the package's own `utils/`
- [ ] An app composes the package (`app_manifest.yaml` → `composer sync`) and its pubspec has `resolution: workspace`

---

## Related

- [Data layer](04_data.md) — who implements these repository interfaces
- [Feature layer](05_features.md) — who calls these use cases
- [Guide: new domain + data package](../guides/02_new_domain_data.md)
- [Rules and conventions](../reference/01_rules.md)
