# 03. Data Layer (Execution & Integration)

The Data Layer acts as "The Integration Gateway". It receives clean business requests from the Domain layer, connects to the outside world (the Internet, local disk database, secure memory), retrieves raw data, then translates and transforms the raw data into clean entities (`Entities`) and sends them back to the Domain.

In the monorepo, all these integration logics are divided into independent **Micro-packages** by business, located in the `packages/data/` directory:

| Micro-Package | Package Name | Description |
|:---|:---|:---|
| `packages/data/core` | `data_core` | `IBaseRepository` with `execute()` and `executeSync()` wrapper functions for automatic error handling |
| `packages/data/auth` | `data_auth` | RepositoryImpl, Models/DTOs, DataSources for authentication business |
| `packages/data/language` | `data_language` | RepositoryImpl for multi-language business (read/write Storage) |

---

## 📂 1. Data Package Directory Structure

```text
packages/data/<module_name>/
├── lib/
│   ├── data_<module_name>.dart    # Barrel file exposing implementation classes
│   ├── di/
│   │   └── module.dart            # Local DI registration of the Data Layer
│   └── src/
│       ├── data_sources/          # Direct connection to API or Cache
│       │   ├── remote/            # Remote DataSource (Retrofit)
│       │   └── local/             # Local DataSource (Storage/DB)
│       ├── models/                # DTOs (Data Transfer Objects) - Reflects JSON structure
│       └── repositories_impl/    # Specific implementation classes of Domain Interfaces
└── pubspec.yaml
```

---

## 🧬 2. Component Classes & Data Transformation Process

### A. Data Transfer Objects (Models / DTOs)
Models are classes that accurately reflect the physical data structure (JSON) returned from the Server or local storage.
- **Rule**: Every Model MUST be created using `freezed` and `json_serializable` to automate the data serialization process (`fromJson`/`toJson`).
- **Mapper Method**: The Domain layer strictly forbids the use of Models. Therefore, every Model must declare a `.toEntity()` function to transform raw data into a clean Domain entity.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:domain_auth/domain_auth.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

@freezed
class UserModel with _$UserModel {
  const UserModel._(); // Allows declaring extension functions inside the class

  const factory UserModel({
    @JsonKey(name: 'id') required String id,
    @JsonKey(name: 'email') required String email,
    @JsonKey(name: 'full_name', defaultValue: '') required String fullName,
    @JsonKey(name: 'avatar_url', defaultValue: '') required String avatar,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);

  // Map to clean Entity of the Domain layer
  UserEntity toEntity() {
    return UserEntity(
      id: id,
      email: email,
      fullName: fullName,
      avatarUrl: avatar,
    );
  }
}
```

### B. Data Sources (DataSources)
This is the lowest communication layer, responsible for firing HTTP requests or performing disk read/write operations:
- **Remote DataSources**: Built on the duo `dio` (from `core_network`) and `retrofit`. We declare the Interface and let the code generator write the actual API calling logic.
- **Local DataSources**: Wrap reactive secure storage (`core_storage`) for key-value data, or Drift DAOs (`core_database`) for relational SQL. See [14. Database System](./14_database_system.md) for the `CacheEntryLocalDataSource` example in `data_core`.

*Note: DataSources are only allowed to return `Models`, NEVER return `Entities`. DataSources also do not worry about handling errors but allow Exceptions (like `DioException`) to be freely thrown outwards for the RepositoryImpl to catch.*

```dart
import 'package:core_common/core_common.dart';
import 'package:dio/dio.dart';
import 'package:domain_core/domain_core.dart';
import 'package:retrofit/retrofit.dart';

import '../models/user_model.dart';

part 'auth_remote_data_source.g.dart';

@RestApi()
abstract class AuthRemoteDataSource {
  factory AuthRemoteDataSource(Dio dio, {String? baseUrl}) = _AuthRemoteDataSource;

  @POST(ApiConstants.LOGIN)
  Future<BaseEntity<UserModel>> login(@Body() Map<String, dynamic> body);
}
```

### C. IBaseRepository (from `data_core`)

The `data_core` package provides the `IBaseRepository` abstract class with three automatic error handling wrapper functions:

| Function | Purpose | Return Type |
|:----|:---------|:------------|
| `execute<R,T>()` | Asynchronous operation (Call API, Local DB, Firebase...), receives `R`, maps to Entity `T` | `Future<Result<T>>` |
| `executeSync<R,T>()` | Synchronous operation, receives `R`, maps to `T` | `Result<T>` |

Both functions automatically catch Exceptions and convert them into `AppFailure` via `ErrorHandler.handleError(e)`.

### D. Repository Implementations
This is the bone marrow of the Data layer, inheriting the Interface from the Domain layer, implementing the safe error handling flow and data type mapping:

> [!IMPORTANT]
> **Strict Handling Process in `RepositoryImpl`**:
> 1. Inherit `IBaseRepository` from `data_core` to utilize the error handling wrapper.
> 2. Call the DataSource inside the corresponding wrapper function (`execute` or `executeSync`).
> 3. **If successful**: Use `mapper` to map DTO → Entity, automatically wraps `Result.success(entity)`.
> 4. **If Exception**: The wrapper automatically converts it into `Result.failure(AppFailure)` via `ErrorHandler.handleError(e)`.

```dart
import 'package:core_common/core_common.dart';
import 'package:data_core/data_core.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/remote/auth_remote_data_source.dart';
import '../models/user_model.dart';

@Injectable(as: IAuthRepository)
class AuthRepositoryImpl extends IBaseRepository implements IAuthRepository {
  final AuthRemoteDataSource _remoteDataSource;

  AuthRepositoryImpl(this._remoteDataSource);

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    return execute<UserModel, UserEntity>(
      () => _remoteDataSource.login({
        'email': params.email,
        'password': params.password,
      }),
      mapper: (model) => model.toEntity(),
    );
  }
}
```

**Example of synchronous RepositoryImpl using `executeSync` (no API call):**
```dart
import 'package:core_common/core_common.dart';
import 'package:core_storage/core_storage.dart';
import 'package:data_core/data_core.dart';
import 'package:domain_core/domain_core.dart';
import 'package:domain_language/domain_language.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ILanguageRepository)
class LanguageRepositoryImpl extends IBaseRepository implements ILanguageRepository {
  LanguageRepositoryImpl(this._storage);

  final StorageValuePresets _storage;

  @override
  Result<String> getLanguage() {
    return executeSync<String, String>(() {
      final language = _storage.locale.value;
      if (language != null) {
        return language;
      }
      return 'vi'; // fallback
    });
  }

  @override
  Result<void> setLanguage(String languageCode) {
    return executeSync<void, void>(() {
      _storage.locale.value = languageCode;
    });
  }
}
```

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
