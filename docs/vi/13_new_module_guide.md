# 13. Hướng Dẫn Tạo Module Mới (New Module Creation Guide)
Tài liệu này cung cấp hướng dẫn chi tiết để tạo một **Feature**, **Domain**, **Data**, hoặc **Core** Package mới trong hệ thống Monorepo.

---

## 🚀 1. Sử dụng Công Cụ Tự Động (Khuyên dùng)

Dự án cung cấp bộ công cụ CLI tại `tools/module_generator/generate.dart` để tự động hóa toàn bộ quy trình thiết lập boilerplate.

### Cú pháp chung:
```bash
dart tools/module_generator/generate.dart <loại> <tên_module> [<thư_mục>] [<state_management>]
```

| Tham số | Giá trị | Mô tả |
|:--------|:--------|:------|
| `<loại>` | `1` Feature, `2` Domain, `3` Data, `4` Core, `5` Custom | Loại module |
| `<tên_module>` | Ví dụ: `profile`, `payment`, `chat` | Tên nghiệp vụ |
| `<thư_mục>` | (Chỉ cho Custom) Ví dụ: `features` | Thư mục cha |
| `<state_management>` | (Chỉ cho Feature) `1` Provider, `2` BLoC, `3` None | Công cụ quản lý trạng thái |

### Ví dụ thực tế:
```bash
# Tạo Feature 'profile' với Provider:
dart tools/module_generator/generate.dart 1 profile "" 1

# Tạo Domain micro-package 'payment':
dart tools/module_generator/generate.dart 2 payment

# Tạo Data micro-package 'payment':
dart tools/module_generator/generate.dart 3 payment
```

### Công cụ sẽ tự động thực hiện:
1. Tạo cấu trúc thư mục tiêu chuẩn cho loại module tương ứng.
2. Sinh file `pubspec.yaml` với đầy đủ dependencies (bao gồm `retrofit`/`dio` cho Data, `go_router` cho Feature).
3. Thiết lập Micro-package DI (`lib/di/module.dart`).
4. Sinh `.gitignore` cho code generation.
5. Đăng ký package mới vào `workspace` trong root `pubspec.yaml`.
6. Đăng ký DI module vào `app/lib/di/injection.dart` (tự động phân loại vào các danh sách `_coreModules`, `_featureModules`, v.v.).
7. Chạy `dependency_sync.dart` để đồng bộ phiên bản thư viện.
8. Chạy `flutter pub get`.
9. Sinh barrel files (`lib/<package_name>.dart`).
10. Chạy `build_runner build --workspace` để sinh mã DI.

---

## 🏗️ 2. Quy Trình Tạo Feature Package

### Bước 1: Chạy Generator
```bash
dart tools/module_generator/generate.dart 1 profile "" 1
```

### Bước 2: Cấu trúc thư mục được tạo
```text
packages/features/profile/
├── lib/
│   ├── di/
│   │   └── module.dart
│   └── src/
│       ├── pages/
│       ├── providers/      # Hoặc blocs/ tùy lựa chọn
│       ├── routing/
│       └── widgets/
└── pubspec.yaml
```

### Bước 3: Định nghĩa Route
Tạo file định tuyến trong `lib/src/routing/`. Ví dụ với Provider:
```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

part 'route_module.g.dart';

@TypedGoRoute<ProfileRoute>(path: '/profile')
class ProfileRoute extends GoRouteDataCustom with $ProfileRoute {
  const ProfileRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChangeNotifierProvider(
      create: (context) => getIt<ProfileProvider>(),
      child: const ProfilePage(),
    );
  }
}
```

### Bước 4: Đăng ký route qua DI (không sửa list trong AppRouter)
**Không** mở `app_router.dart` để append route.

1. Hoàn thiện TypedGoRoute + Navigator trong thư mục `routing/` của feature.
2. Đăng ký một trong hai:
   - `@LazySingleton(as: IFeatureRouteModule)` cho màn stack/độc lập, hoặc
   - `@LazySingleton(as: IDashboardTabModule)` **chỉ** khi là tab bottom-nav chính (`order` + `path` + `routes` + `navigationBarItem`).
3. Tùy chọn: `@LazySingleton(as: IAppEntryLocation)` cho cold start.
4. Đảm bảo package có trong `app/pubspec.yaml` và `ExternalModule` trong `injection.dart` (CLI thường làm sẵn).
5. Chạy `build_runner` và **hot restart**.

Đọc `docs/vi/08_routing.md` mục Dashboard trước khi chọn `IDashboardTabModule`.

---

## 🧬 3. Quy Trình Tạo Domain Micro-Package

### Bước 1: Chạy Generator
```bash
dart tools/module_generator/generate.dart 2 payment
```

### Bước 2: Cấu trúc được tạo
```text
packages/domain/payment/
├── lib/
│   ├── di/
│   │   └── module.dart
│   └── src/
│       ├── entities/
│       ├── repositories/
│       └── usecases/
└── pubspec.yaml
```

### Bước 3: Triển khai nghiệp vụ
1. Tạo Entity tại `lib/src/entities/`.
2. Tạo Repository interface tại `lib/src/repositories/`.
3. Tạo UseCase tại `lib/src/usecases/` (đánh dấu `@injectable`).
4. Chạy barrel generator: `dart tools/barrel_generator/generate.dart packages/domain/payment/lib`
5. Chạy build_runner: `dart run build_runner build -d --workspace`

---

## 💾 4. Quy Trình Tạo Data Micro-Package

### Bước 1: Chạy Generator
```bash
dart tools/module_generator/generate.dart 3 payment
```

### Bước 2: Cấu trúc được tạo
```text
packages/data/payment/
├── lib/
│   ├── di/
│   │   └── module.dart
│   └── src/
│       ├── data_sources/
│       ├── models/
│       └── repositories_impl/
└── pubspec.yaml
```

### Bước 3: Triển khai tích hợp
1. Tạo DTO/Model tại `lib/src/models/` (kèm `.toEntity()`).
2. Tạo Remote DataSource tại `lib/src/data_sources/remote/` (Retrofit `@RestApi()`).
3. Tạo RepositoryImpl tại `lib/src/repositories_impl/` (kế thừa `IBaseRepository` từ `data_core`).
4. Chạy barrel generator và build_runner.

---

## 🔧 5. Quy Trình Tạo Core Package

### Bước 1: Chạy Generator
```bash
dart tools/module_generator/generate.dart 4 analytics
```

### Bước 2: Đăng ký vào Workspace & DI
Generator tự động thực hiện:
1. Thêm vào `workspace` trong root `pubspec.yaml`.
2. Tạo `lib/di/module.dart` với `@InjectableInit.microPackage()`.
3. Đăng ký `CoreAnalyticsPackageModule` vào `app/lib/di/injection.dart` (vào danh sách `_coreModules`).

---

## 💡 Lưu Ý Quan Trọng
- **Sử dụng Barrel Tool**: Luôn chạy `dart tools/barrel_generator/generate.dart` khi thêm file hoặc thư mục mới.
- **Đồng bộ phiên bản**: Sau khi tạo module, chạy `dart tools/dependency_sync.dart` nếu cần cập nhật phiên bản thư viện.
- **Tuân thủ Layer**: Feature KHÔNG được phụ thuộc trực tiếp vào Data layer. Chỉ được phụ thuộc vào Domain layer.
- **Micro-package DI**: Luôn sử dụng `@InjectableInit.microPackage()` cho các package con.
- **Stdout/Stderr**: Nếu viết thêm các công cụ trong `tools/`, tuyệt đối không dùng `print`, hãy dùng `stdout` và `stderr`.
- **Build Runner**: Dùng lệnh `dart run build_runner build -d --workspace` (flag `-d` thay cho `--delete-conflicting-outputs` đã bị deprecated).
