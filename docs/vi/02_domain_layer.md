# 02. Tầng Domain (Domain Layer - Pure Business Logic)

Tầng Domain đóng vai trò là "Bộ Não" (The Core Kernel) của toàn bộ monorepo, chứa đựng tất cả các quy tắc nghiệp vụ (Business Rules), logic xử lý cốt lõi và các hợp đồng giao tiếp trừu tượng. 

Tại cấu trúc Monorepo, toàn bộ tầng Domain được chia nhỏ thành các **Micro-packages** độc lập theo nghiệp vụ, nằm trong thư mục `packages/domain/`:

| Micro-Package | Package Name | Mô tả |
|:---|:---|:---|
| `packages/domain/core` | `domain_core` | Các thực thể, repository interfaces, và result types dùng chung toàn hệ thống (`Result<T>`, `BaseEntity<T>`) |
| `packages/domain/auth` | `domain_auth` | Entities, UseCases, và Repository interfaces cho nghiệp vụ xác thực (Login, Register, Social Auth) |
| `packages/domain/language` | `domain_language` | Entities, UseCases cho nghiệp vụ đa ngôn ngữ (Get/Set Language) |

---

## 🏛️ 1. Nguyên Tắc Độc Lập Tuyệt Đối (Pure-Dart Mandate)

Mọi gói `packages/domain/*` là gói **Dart thuần túy** (Pure Dart Package). Để bảo vệ tính bền vững của nghiệp vụ và khả năng Unit Test tuyệt đối:
- **Cấm nhập thư viện Flutter**: Không import `flutter/material.dart`, không chứa bất kỳ Widget UI hay thao tác render nào.
- **Cấm phụ thuộc vào thư viện kết nối / lưu trữ cụ thể**: Không import `dio`, `retrofit`, hay `shared_preferences`.
- **Thư viện được phép**: `dart:core`, `core_common` (hằng số, enums, AppFailure), `domain_core` (Result, BaseEntity), `freezed_annotation`, `json_annotation`, và `injectable`.

> [!CAUTION]
> **Quy tắc Biên dịch Tĩnh**: Nếu phát hiện tệp tin nào trong `packages/domain/*` có chứa dòng import liên quan đến Flutter UI hoặc Dio, trình rà soát CI/CD tĩnh toàn cục sẽ báo lỗi biên dịch và từ chối chạy.

---

## 📂 2. Cấu Trúc Thư Mục Thành Phần

```text
packages/domain/<module_name>/
├── lib/
│   ├── domain_<module_name>.dart  # Barrel file chính (Xuất bản các API công khai)
│   ├── di/
│   │   └── module.dart            # Định vị DI cục bộ cho gói Domain
│   └── src/
│       ├── entities/              # Thực thể nghiệp vụ bất biến (Immutable Entities)
│       ├── params/                # Cấu trúc tham số truyền vào UseCases
│       ├── repositories/          # Giao diện trừu tượng mô tả kho lưu trữ
│       ├── usecases/              # Logic nghiệp vụ đóng gói thành các khối hành động đơn lẻ
│       └── services/              # (Tùy chọn) Dịch vụ nghiệp vụ đặc thù
└── pubspec.yaml
```

---

## 💎 3. Triển Khai Các Thành Phần Nghiệp Vụ

### A. Thực thể Nghiệp vụ Bất biến (Entities)
Entities là đối tượng dữ liệu sạch mô tả các nghiệp vụ thật của app (như `User`, `Transaction`). Mọi thực thể trong Domain đều kế thừa thuộc tính bất biến (Immutability) thông qua `freezed`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_entity.freezed.dart';

@freezed
class UserEntity with _$UserEntity {
  const UserEntity._(); // Bắt buộc phải có để xài getter / helper methods trong class

  const factory UserEntity({
    required String id,
    required String email,
    required String fullName,
    required String avatarUrl,
  }) = _UserEntity;

  // Logic nghiệp vụ nội tại của thực thể
  bool get hasAvatar => avatarUrl.isNotEmpty;
  String get displayName => fullName.trim().isEmpty ? 'Người dùng' : fullName;
}
```

### B. Tham số UseCase (Params)
Khi UseCase yêu cầu truyền nhiều tham số đầu vào, chúng ta gom chúng thành một cấu trúc bất biến duy nhất để duy trì tính minh bạch:

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

### C. Giao diện Kho lưu trữ (Repository Interfaces)
Định nghĩa các "Hợp đồng" mà tầng dữ liệu (Data) buộc phải tuân theo. Mọi kết quả trả về từ Repository luôn được bao bọc an toàn lỗi qua `Result<T>`:

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
> `Result<T>` là sealed class Freezed định nghĩa trong `domain_core`, có 4 variant: `Success<T>`, `Failure<T>` (chứa `AppFailure`), `None<T>`, `Cancel<T>`.

### D. Các Ca Sử Dụng Nghiệp Vụ (UseCases)
Mỗi UseCase chỉ giải quyết duy nhất **một hành động nghiệp vụ khép kín** (Single Responsibility Principle). ViewModels tại các Feature chỉ giao tiếp với UseCases, tuyệt đối không gọi trực tiếp Repository:

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
    // 1. Kiểm tra nghiệp vụ cơ bản tại Domain (nếu cần)
    if (params.password.length < 6) {
      return const Result.failure(
        AppFailure.validation(message: 'Mật khẩu phải từ 6 ký tự trở lên'),
      );
    }
    
    // 2. Kích hoạt kết nối dữ liệu gián tiếp
    return _authRepository.login(params);
  }
}
```

---

## ⚡ 4. Tự Động Hóa Tiêm Phụ Thuộc (DI Generation)

Để giúp Host App giải quyết các UseCases được khai báo `@injectable`, gói `domain` tự động hóa việc xuất bản đăng ký DI cục bộ:
- Tệp `packages/domain/<module>/lib/di/module.dart` chứa khai báo khởi tạo:
  ```dart
  import 'package:injectable/injectable.dart';

  @InjectableInit.microPackage()
  void initMicroPackage() {}
  ```
- Khi biên dịch bằng `build_runner`, module sẽ tạo ra tệp sinh mã tiêm phụ thuộc cục bộ `module.module.dart`, sau đó được tích hợp mượt mà vào container DI toàn cục tại Host App.

> [!TIP]
> Nếu Domain micro-package phụ thuộc vào Repository interfaces chưa được đăng ký DI (vì chúng nằm ở tầng Data), hãy thêm `ignoreUnregisteredTypes` vào khai báo:
> ```dart
> @InjectableInit.microPackage(ignoreUnregisteredTypes: [ILanguageRepository])
> void initMicroPackage() {}
> ```

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
