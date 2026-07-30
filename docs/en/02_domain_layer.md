# 02. Domain Layer (Pure Business Logic)

The Domain layer acts as "The Core Kernel" of the entire monorepo, containing all Business Rules, core processing logic, and abstract communication contracts.

In the Monorepo architecture, the entire Domain layer is divided into independent **Micro-packages** by business, located in the `packages/domain/` directory:

| Micro-Package | Package Name | Description |
|:---|:---|:---|
| `packages/domain/core` | `domain_core` | System-wide shared entities, repository interfaces, and result types (`Result<T>`, `BaseEntity<T>`) |
| `packages/domain/auth` | `domain_auth` | Entities, UseCases, and Repository interfaces for authentication business (Login, Register, Social Auth) |
| `packages/domain/language` | `domain_language` | Entities, UseCases for multi-language business (Get/Set Language) |

---

## 🏛️ 1. Absolute Independence Principle (Pure-Dart Mandate)

Every `packages/domain/*` package is a **Pure Dart Package**. To protect business durability and absolute Unit Testability:
- **No Flutter imports allowed**: Do not import `flutter/material.dart`, do not contain any UI Widgets or render operations.
- **No specific network / storage library dependencies allowed**: Do not import `dio`, `retrofit`, or `shared_preferences`.
- **Allowed libraries**: `dart:core`, `core_common` (constants, enums, AppFailure), `domain_core` (Result, BaseEntity), `freezed_annotation`, `json_annotation`, and `injectable`.

> [!CAUTION]
> **Static Compilation Rule**: If any file in `packages/domain/*` is found to contain an import line related to Flutter UI or Dio, the global static CI/CD reviewer will report a compilation error and refuse to run.

---

## 📂 2. Component Directory Structure

```text
packages/domain/<module_name>/
├── lib/
│   ├── domain_<module_name>.dart  # Main Barrel file (Exposes public APIs)
│   ├── di/
│   │   └── module.dart            # Local DI locator for Domain package
│   └── src/
│       ├── entities/              # Immutable Business Entities
│       ├── params/                # Input parameter structures for UseCases
│       ├── repositories/          # Abstract interfaces describing storage repositories
│       ├── usecases/              # Business logic packaged into single action blocks
│       └── services/              # (Optional) Specific business services
└── pubspec.yaml
```

---

## 💎 3. Implementing Business Components

### A. Immutable Business Entities (Entities)
Entities are clean data objects describing the app's real business (like `User`, `Transaction`). Every entity in the Domain inherits Immutability via `freezed`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_entity.freezed.dart';

@freezed
class UserEntity with _$UserEntity {
  const UserEntity._(); // Required to use getter / helper methods inside the class

  const factory UserEntity({
    required String id,
    required String email,
    required String fullName,
    required String avatarUrl,
  }) = _UserEntity;

  // Entity's internal business logic
  bool get hasAvatar => avatarUrl.isNotEmpty;
  String get displayName => fullName.trim().isEmpty ? 'User' : fullName;
}
```

### B. UseCase Parameters (Params)
When a UseCase requires multiple input parameters, we group them into a single immutable structure to maintain transparency:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_params.freezed.dart';
part 'login_params.g.dart';

@freezed
class LoginParams with _$LoginParams {
  const factory LoginParams({
    required String email,
    required String password,
  }) = _LoginParams;

  factory LoginParams.fromJson(Map<String, dynamic> json) =>
      _$LoginParamsFromJson(json);
}
```

### C. Repository Interfaces
Defines "Contracts" that the Data layer must comply with. Every result returned from a Repository is always wrapped safely via `Result<T>`:

```dart
import 'package:domain_core/domain_core.dart';
import '../entities/user_entity.dart';
import '../params/login_params.dart';

abstract class IAuthRepository {
  Future<Result<UserEntity>> login(LoginParams params);
  Result<void> logout();
}
```

> [!NOTE]
> `Result<T>` is a sealed Freezed class defined in `domain_core`, with 4 variants: `Success<T>`, `Failure<T>` (containing `AppFailure`), `None<T>`, `Cancel<T>`.

### D. Business Use Cases (UseCases)
Each UseCase solves exactly **one closed business action** (Single Responsibility Principle). ViewModels at Features only communicate with UseCases, absolutely never calling the Repository directly:

```dart
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';
import '../repositories/i_auth_repository.dart';
import '../params/login_params.dart';
import '../entities/user_entity.dart';

@injectable
class LoginUseCase {
  final IAuthRepository _authRepository;

  LoginUseCase(this._authRepository);

  Future<Result<UserEntity>> call(LoginParams params) async {
    // 1. Basic business validation at Domain (if needed)
    if (params.password.length < 6) {
      return const Result.failure(
        AppFailure.validation(message: 'Password must be 6 characters or more'),
      );
    }
    
    // 2. Trigger indirect data connection
    return _authRepository.login(params);
  }
}
```

---

## ⚡ 4. Dependency Injection Automation (DI Generation)

To help the Host App resolve UseCases declared with `@injectable`, the `domain` package automates exposing local DI registrations:
- The file `packages/domain/<module>/lib/di/module.dart` contains the initialization declaration:
  ```dart
  import 'package:injectable/injectable.dart';

  @InjectableInit.microPackage()
  void initMicroPackage() {}
  ```
- When compiled via `build_runner`, the module will generate a local dependency injection generated file `module.module.dart`, which is then smoothly integrated into the global DI container at the Host App.

> [!TIP]
> If a Domain micro-package depends on Repository interfaces that are not yet registered with DI (because they reside in the Data layer), add `ignoreUnregisteredTypes` to the declaration:
> ```dart
> @InjectableInit.microPackage(ignoreUnregisteredTypes: [ILanguageRepository])
> void initMicroPackage() {}
> ```

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
