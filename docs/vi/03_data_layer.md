# 03. Tầng Dữ Liệu (Data Layer - Execution & Integration)

Tầng Dữ Liệu đóng vai trò là "Cổng Tích Hợp" (The Integration Gateway). Nó nhận các yêu cầu nghiệp vụ sạch từ tầng Domain, kết nối ra thế giới bên ngoài (mạng Internet, cơ sở dữ liệu đĩa cục bộ, bộ nhớ an toàn), thu về dữ liệu thô, sau đó dịch và chuyển hóa dữ liệu thô thành các thực thể sạch (`Entities`) gửi ngược lại cho Domain.

Tại monorepo, toàn bộ các logic tích hợp này được chia nhỏ thành các **Micro-packages** độc lập theo nghiệp vụ, nằm trong thư mục `packages/data/`:

| Micro-Package | Package Name | Mô tả |
|:---|:---|:---|
| `packages/data/core` | `data_core` | `IBaseRepository` với các hàm wrapper `execute()` và `executeSync()` xử lý lỗi tự động |
| `packages/data/auth` | `data_auth` | RepositoryImpl, Models/DTOs, DataSources cho nghiệp vụ xác thực |
| `packages/data/language` | `data_language` | RepositoryImpl cho nghiệp vụ đa ngôn ngữ (đọc/ghi Storage) |

---

## 📂 1. Cấu Trúc Thư Mục Gói Dữ Liệu

```text
packages/data/<module_name>/
├── lib/
│   ├── data_<module_name>.dart    # Barrel file phơi bày các class triển khai
│   ├── di/
│   │   └── module.dart            # Đăng ký DI cục bộ của Data Layer
│   └── src/
│       ├── data_sources/          # Kết nối trực tiếp với API hoặc Cache
│       │   ├── remote/            # Remote DataSource (Retrofit)
│       │   └── local/             # Local DataSource (Storage/DB)
│       ├── models/                # DTOs (Data Transfer Objects) - Phản ánh cấu trúc JSON
│       └── repositories_impl/    # Lớp cài đặt cụ thể của các Interface của Domain
└── pubspec.yaml
```

---

## 🧬 2. Các Lớp Thành Phần & Quy Trình Biến Đổi Dữ Liệu

### A. Đối tượng Truyền Dữ liệu (Models / DTOs)
Models là các lớp phản ánh chính xác cấu trúc dữ liệu vật lý (JSON) trả về từ Server hoặc lưu trữ cục bộ.
- **Quy tắc**: Mọi Model bắt buộc phải được tạo bằng `freezed` và `json_serializable` để tự động hóa quá trình tuần tự hóa dữ liệu (`fromJson`/`toJson`).
- **Mapper Method**: Tầng Domain cấm tuyệt đối việc sử dụng Model. Do đó, mọi Model bắt buộc phải khai báo hàm `.toEntity()` để biến đổi dữ liệu thô thành thực thể Domain sạch.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:domain_auth/domain_auth.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

@freezed
class UserModel with _$UserModel {
  const UserModel._(); // Cho phép khai báo hàm mở rộng bên trong class

  const factory UserModel({
    @JsonKey(name: 'id') required String id,
    @JsonKey(name: 'email') required String email,
    @JsonKey(name: 'full_name', defaultValue: '') required String fullName,
    @JsonKey(name: 'avatar_url', defaultValue: '') required String avatar,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);

  // Ánh xạ thành Entity sạch của tầng Domain
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

### B. Các Nguồn Cung cấp Dữ liệu (DataSources)
Là lớp giao tiếp thấp nhất, chịu trách nhiệm bắn request HTTP hoặc thao tác đọc ghi ổ đĩa:
- **Remote DataSources**: Được xây dựng trên bộ đôi `dio` (từ `core_network`) và `retrofit`. Chúng ta khai báo Interface và để trình tạo sinh mã viết logic gọi API thực tế.
- **Local DataSources**: Bọc secure storage reactive (`core_storage`) cho key-value, hoặc Drift DAO (`core_database`) cho SQL quan hệ. Xem [14. Hệ Thống Database](./14_database_system.md) cho ví dụ `CacheEntryLocalDataSource` trong `data_core`.

*Lưu ý: DataSources chỉ được trả về `Models`, KHÔNG bao giờ trả về `Entities`. DataSources cũng không lo lắng việc xử lý lỗi mà cho phép Exception (như `DioException`) văng tự do ra ngoài để RepositoryImpl bắt giữ.*

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

### C. IBaseRepository (từ `data_core`)

Package `data_core` cung cấp lớp trừu tượng `IBaseRepository` với ba hàm wrapper xử lý lỗi tự động:

| Hàm | Mục đích | Kiểu trả về |
|:----|:---------|:------------|
| `execute<R,T>()` | Thao tác bất đồng bộ (Gọi API, Local DB, Firebase...), nhận `R`, map sang Entity `T` | `Future<Result<T>>` |
| `executeSync<R,T>()` | Thao tác đồng bộ, nhận `R`, map sang `T` | `Result<T>` |

Cả ba hàm đều tự động bắt Exception và chuyển hóa thành `AppFailure` thông qua `ErrorHandler.handleError(e)`.

### D. Triển khai Thực tế Kho lưu trữ (Repository Implementations)
Đây là tủy xương của tầng Data, kế thừa Interface từ tầng Domain, thực hiện luồng xử lý lỗi an toàn và ánh xạ kiểu dữ liệu:

> [!IMPORTANT]
> **Quy trình Xử lý Nghiêm ngặt trong `RepositoryImpl`**:
> 1. Kế thừa `IBaseRepository` từ `data_core` để tận dụng wrapper xử lý lỗi.
> 2. Gọi DataSource bên trong hàm wrapper tương ứng (`execute` hoặc `executeSync`).
> 3. **Nếu thành công**: Sử dụng `mapper` để map DTO → Entity, tự động bọc `Result.success(entity)`.
> 4. **Nếu Exception**: Wrapper tự động chuyển hóa thành `Result.failure(AppFailure)` qua `ErrorHandler.handleError(e)`.

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

**Ví dụ RepositoryImpl đồng bộ dùng `executeSync` (không qua API):**
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
      return 'vi';
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
