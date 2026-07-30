# 07. Quy Chuẩn Đặt Tên & Quy Tắc Lập Trình Khắt Khe (Rules & Conventions)

Để bảo đảm monorepo duy trì được tính đồng nhất tuyệt đối về mặt thẩm mỹ mã nguồn và không bị gãy vỡ kiến trúc (Architecture Breakdown) khi nhiều lập trình viên cùng làm việc chung, **tất cả thành viên bắt buộc phải tuân thủ nghiêm ngặt 100% các quy định sau đây.**

---

## 💎 1. Quy Tắc Khởi Tạo Data Class (Freezed Standard)

- **Quy định**: Mọi đối tượng dữ liệu thô tại tầng Data (Models/DTOs) và các thực thể trạng thái UI (State Models) **BẮT BUỘC** phải được cấu trúc bằng thư viện `freezed` để đảm bảo tính bất biến (Immutability).
- **Entities (tầng Domain) & Request Params**: Việc dùng `freezed` là **KHÔNG BẮT BUỘC** (khuyến khích dùng để code ngắn hơn, nhưng cho phép dùng class Dart thuần túy kết hợp `equatable` nếu muốn giữ Domain sạch không phụ thuộc vào trình sinh mã).

✅ **Ví dụ Thực thể Domain Dùng Freezed (Chuẩn):**
```dart
@freezed
class UserEntity with _$UserEntity {
  const UserEntity._(); // Bắt buộc phải khai báo hàm constructor trống này mới sử dụng được getter/method!
  
  const factory UserEntity({
    required String id,
    required String fullName,
  }) = _UserEntity;
}
```

---

## 🏷️ 2. Thống Nhất Hậu Tố Tên Lớp & Tệp Tin (Naming Suffixes)

Tất cả các tệp tin và tên lớp phải được đặt tên đồng nhất dựa theo chức năng kỹ thuật của chúng để dễ tìm kiếm:

| Tầng Kiến Trúc             | Hậu tố Tệp tin (Snake Case)   | Hậu tố Tên Class (Pascal Case) | Ví dụ Minh họa            |
| :------------------------- | :---------------------------- | :----------------------------- | :------------------------ |
| **Giao diện (UI Pages)**   | `_page.dart` / `_screen.dart` | `Page` / `Screen`              | `LoginPage`, `HomeScreen` |
| **Giao diện (UI Widgets)** | `_widget.dart` / `_card.dart` | `Widget` / `Card`              | `PrimaryButtonWidget`     |
| **Bộ điều khiển UI**       | `_provider.dart` / `_bloc.dart` | `Provider` / `Bloc` / `Cubit`  | `LoginProvider`, `AuthBloc` |
| **Logic Nghiệp vụ**        | `_usecase.dart`               | `UseCase`                      | `LoginUseCase`            |
| **Thực thể sạch**          | `_entity.dart`                | `Entity`                       | `UserEntity`              |
| **Interface Kho lưu trữ**  | `i_` + `_repository.dart`     | Bắt đầu bằng chữ `I`           | `IAuthRepository`         |
| **Đối tượng API Nhận**     | `_response.dart`              | `Response`                     | `UserResponse`            |
| **Đối tượng API Gửi**      | `_request.dart`               | `Request`                      | `LoginRequest`            |
| **Triển khai Kho**         | `_repository_impl.dart`       | `RepositoryImpl`               | `AuthRepositoryImpl`      |
| **Lớp điều hướng cụ thể**  | `_navigator_impl.dart`        | `NavigatorImpl`                | `AuthNavigatorImpl`       |
| **Interface Action Handler**| `i_` + `_action_handler.dart` | Bắt đầu bằng chữ `I`           | `IAuthActionHandler`      |
| **Impl Action Handler**    | `_action_handler_impl.dart`   | `ActionHandlerImpl`            | `AuthActionHandlerImpl`   |

---

## 🔠 3. Quy Tắc Đặt Hằng Số & Cấu Hình Đa Môi Trường (Constants & Flavors)

- **Quy định**: Tuyệt đối không viết cứng (hard-code) các chuỗi String, endpoint API, mã màu HEX, hoặc khóa bộ nhớ trực tiếp trong code UI. Tất cả phải được khai báo tập trung trong gói `core_common` hoặc `core_base_ui`.
- **Định dạng**: Tên biến hằng số **BẮT BUỘC PHẢI VIẾT HOA TOÀN BỘ VỚI DẤU GẠCH DƯỚI (`UPPER_SNAKE_CASE`)** để phân biệt với các biến thông thường:
- **Đa môi trường**: Sử dụng `AppConfig.appFlavor` để truy xuất Flavor hiện tại (`Flavor.dev`, `Flavor.staging`, `Flavor.prod`) thay vì check `kDebugMode` thủ công để luôn kiểm soát chặt chẽ hành vi hệ thống theo Flavor phát triển.

```dart
class ApiConstants {
  ApiConstants._();
  
  // BẮT BUỘC UPPER_SNAKE_CASE
  static const String BASE_URL = 'https://api.codebase.com/v1';
  static const String SUBMIT_APPLICATION = '/jobs/apply';
}
```

---

## 🧱 4. Phân Tách Tầng Vật Lý Chặt Chẽ (Strict Layer Isolation & DI)

Tầng nghiệp vụ Domain (`packages/domain/* (Micro-packages)`) đóng vai trò trung tâm và tuyệt đối không được chứa bất kỳ thông tin nhập khẩu nào liên quan đến Flutter UI hay các thư viện gọi mạng:

- **Cấm nhập khẩu tại Domain**: `package:flutter/material.dart`, `package:dio/dio.dart`, `package:retrofit/retrofit.dart`.
- **Phân Định Phạm Vi Đăng Ký DI (Dependency Injection Scope)**:
  - **Feature UI Controllers (ViewModel / Bloc)**: Các logic giao diện gắn liền với một màn hình **BẮT BUỘC** phải được đăng ký bằng `@injectable` để GetIt có thể khởi tạo đối tượng mới hoàn toàn mỗi khi truy xuất. Tuyệt đối không dùng Singleton cho chúng. Sau đó, tại tầng định tuyến (`Route level`), sử dụng Widget cung cấp tương ứng (ví dụ: `ChangeNotifierProvider` hoặc `BlocProvider`) để hệ thống tự động giải phóng (Auto-dispose) khi người dùng rời màn hình.
  - **Global Controllers (App-wide)**: Được phép sử dụng `@lazySingleton` (ví dụ: `AuthProvider`, `ThemeProvider`, `LanguageProvider`) vì chúng cần duy trì trạng thái suốt vòng đời ứng dụng.
  - **Constructor Injection**: Tuyệt đối **không** dùng hàm gọi tĩnh `getIt<T>()` trực tiếp bên trong các lớp nghiệp vụ. Tất cả các Navigators, UseCases, Repositories, và Configurations phải nhận phụ thuộc của mình (Dependencies) thông qua **Constructor Injection** để hỗ trợ Mocking & Unit testing hoàn hảo.

```dart
// domain/lib/usecases/login_usecase.dart

// ❌ CẤM TUYỆT ĐỐI (LỖI KIẾN TRÚC NẶNG)
import 'package:dio/dio.dart'; 
import 'package:flutter/widgets.dart';

// ✅ HỢP LỆ (DART THUẦN)
import 'package:domain/repositories/i_auth_repository.dart';
```

---

## 🚦 5. Quy Tắc Định Tuyến & Điều Hướng An Toàn (Routing & Navigation Standard)

Hệ thống định tuyến `go_router` được thiết kế lại hoàn toàn độc lập, an toàn kiểu và sử dụng định tuyến phân rã (decentralized scoped routing):

- **`AppRouter` là Singleton**: Lớp `AppRouter` được quản lý như một `@singleton` của GetIt. Không viết các thuộc tính tĩnh hoặc static lookups.
- **Lắp route bằng DI động**: **CẤM** sửa `app_router.dart` để append `$…Route` / hardcode `StatefulShellBranch`. Feature đăng ký `IFeatureRouteModule` (stack; **không order**) hoặc `IDashboardTabModule` (tab; **có order**). Tùy chọn: `IAppEntryLocation`. Chrome dashboard: chỉ `DashboardRouteModule` trong `feature_dashboard`. Host dùng `getAllOrEmpty` / `getItOrNull` kèm fallback rỗng/`SizedBox`. Chi tiết: `docs/vi/08_routing.md` mục Dashboard.
- **Định tuyến Phân rã (Decentralized Navigators)**: Các interface Navigator được định nghĩa tập trung tại `core_di` và các lớp triển khai `NavigatorImpl` phải được đặt cục bộ bên trong thư mục `routing/` của từng Feature package tương ứng (không triển khai tập trung ở App Shell).
- **Truyền context trực tiếp**: Các phương thức điều hướng bắt buộc phải nhận `BuildContext context` từ lớp UI để đảm bảo vòng đời widget và thực thi các thao tác chuyển trang thông qua GoRouteData:
  ```dart
  @Singleton(as: AuthNavigator)
  class AuthNavigatorImpl implements AuthNavigator {
    @override
    void toLogin(BuildContext context) => const LoginRoute().go(context);
  }
  ```
- **Khởi Tạo Deep Link An Toàn**: Luồng xử lý liên kết sâu (`DeeplinkProvider` được cấu hình dạng `@lazySingleton`) phải được gọi an toàn bên trong sự kiện kết thúc vẽ khung hình (`WidgetsBinding.instance.endOfFrame.whenComplete`) ở `initState` của `NavigatorWrapperWidget` tại `app/lib/presentation/widgets/navigator_wrapper_widget.dart`. Điều này đảm bảo `BuildContext` đã hoàn thành render và tránh hoàn toàn các xung đột vòng đời UI khi chuyển hướng trang tức thì.
- **Trang Lỗi Shell**: `errorPageBuilder` của GoRouter **BẮT BUỘC** dùng `UndefineRouteWidget` (không viết widget ẩn danh inline).

---

## 🚀 6. Khởi Tạo Tầng Ứng Dụng Tập Trung & Tái Cấu Trúc Main.dart

Để giữ cho entrypoint của dự án luôn sạch sẽ và dễ bảo trì:
- **`AppInitializer`**: Tất cả logic cấu hình hệ thống ban đầu (DI Container, HttpOverrides, Logger, Hướng màn hình, System UI Overlay) phải được đóng gói tập trung trong phương thức tĩnh `AppInitializer.init()`.
- **`main.dart` Tinh Gọn**: File `main.dart` **không** chứa mã nguồn khởi tạo dịch vụ hỗn tạp. Nó chỉ phục vụ duy nhất nhiệm vụ bọc ứng dụng trong `runZonedGuarded` và chuyển giao cho `AppInitializer.init` trong môi trường `MainScope`.

---

## 🔒 7. Bảo Mật SSL/TLS Certificate Pinning & Kiểm Soát HttpOverrides

Hạ tầng mạng bắt buộc phải được bảo vệ chống lại các cuộc tấn công nghe lén Man-in-the-Middle (MITM) một cách nghiêm ngặt:

- **Global SSL Pinning**: Việc cài đặt mã băm public key (SPKI SHA-256 hashes) được quản lý tập trung thông qua `HttpOverrides.global` sử dụng `_MyHttpSecurityPinningHttpOverrides` bọc lấy `HttpSecurityPinningClient`.
- **Khống Chế Theo Flavor**:
  - Ở môi trường **Phát triển (`Flavor.dev`)**: Kích hoạt bypass SSL `badCertificateCallback = (...) => true` để hỗ trợ test các server nội bộ có chứng chỉ tự ký.
  - Ở môi trường **Staging và Production (`Flavor.staging` / `Flavor.prod`)**: **BẮT BUỘC** tắt bypass SSL và thực thi so khớp mã băm SPKI nghiêm ngặt để đảm bảo an toàn tuyệt đối cho người dùng cuối.

---

## 🛑 8. Phòng Chống Crash & Quản Lý Lỗi Lọt Ra UI

- **Quy định**: Tuyệt đối cấm sử dụng câu lệnh `throw` để quăng Exception tự do từ tầng Data văng thẳng ra giao diện. Giao diện (UI) không có trách nhiệm try-catch để bắt lỗi kết nối.
- **Giải pháp**: Tất cả các lỗi phải được bắt gọn tại `RepositoryImpl` của tầng Data, chuyển hóa thành thực thể `AppFailure` tương thích và trả về dưới dạng `Result.failure(failure)`.

```dart
// data/lib/repositories_impl/auth_repository_impl.dart

// ✅ CHUẨN MỰC
try {
  final response = await _remoteDataSource.login(params);
  return Result.success(response.toEntity());
} on DioException catch (e) {
  return Result.failure(AppFailure.serverError(message: e.message));
}
```

---

## 🚦 9. Tự Động Hóa Quản Lý Trạng Thái UI (State Management Agnostic)

Do hệ thống hỗ trợ đa nền tảng quản lý trạng thái, bạn phải tuân thủ nghiêm ngặt theo Base Class của thư viện bạn đang sử dụng:

- **Provider**: Bắt buộc kế thừa `BaseProvider<T>` và dùng `executeOperation` để tự động hóa Loading và Error.
- **BLoC**: Ưu tiên kế thừa `BaseBloc` (chỉ dùng `BaseCubit` khi không cần Event). **`ViewState<T>` khuyến nghị cho màn hình đơn giản nhưng không bắt buộc** — feature phức tạp được tự định nghĩa Freezed UI state và dùng `BaseBloc<Event, CustomState>` kèm `emit()`.

*(Vui lòng tham khảo sâu các tài liệu README.md bên trong các package `provider_state_management` hoặc `bloc_state_management` để xem ví dụ chi tiết).*

---

## 🛠️ 10. Quy Chuẩn Scripts & Cấu Trúc Monorepo

- **Flat Workspace**: Cấu trúc Monorepo được tổ chức phẳng thông qua cấu hình `resolution: workspace` ở `pubspec.yaml` gốc. Không được tạo các node workspace trung gian trong các thư mục con.
- **Công cụ CLI & Scripts**: Tất cả các script hỗ trợ tự động hóa sinh mã hoặc tác vụ hệ thống (ví dụ: `barrel_generator`, `generate_localization`) chỉ được phép tạo dưới dạng các file thực thi chạy trên Linux/macOS (`.sh`) và Windows Command Prompt (`.bat`). **CẤM TUYỆT ĐỐI** việc tạo các file script Windows PowerShell (`.ps1`) do các hạn chế về chính sách bảo mật thực thi script trên Windows.

---

## 📦 11. Quản Lý Phiên Bản Phụ Thuộc Tập Trung (Centralized Dependency Management)

Để giải quyết triệt để vấn đề xung đột phiên bản (Dependency Version Conflict) giữa các Feature Package và Core Package trong monorepo khi có nhiều lập trình viên cùng làm việc, hệ thống áp dụng cơ chế **Quản lý Tập trung thông qua Catalog**:

- **Tệp Cấu Hình Gốc**: Mọi phiên bản của các thư viện bên thứ ba (third-party dependencies & dev_dependencies) bắt buộc phải được khai báo duy nhất tại tệp [pubspec_dependencies.yaml](file:///c:/Users/PC/Desktop/codebase/pubspec_dependencies.yaml) ở thư mục gốc của monorepo. Đây là **Single Source of Truth (SSOT)** của toàn bộ dự án.
- **Công Cụ Đồng Bộ Tự Động**: Tuyệt đối không khai báo phiên bản tùy ý trong các tệp `pubspec.yaml` của từng gói con. Thay vào đó, sau khi thêm/sửa đổi thư viện, lập trình viên bắt buộc phải chạy lệnh đồng bộ:
  ```bash
  dart tools/dependency_sync.dart
  ```
  Công cụ này sẽ tự động phân tích và đồng bộ hóa chính xác phiên bản từ `pubspec_dependencies.yaml` sang toàn bộ các gói trong monorepo.
- **Kiểm Tra Tính Đồng Nhất (CI/CD & Git Hook)**:
  Lập trình viên có thể kiểm tra tính đồng nhất của phiên bản bằng lệnh:
  ```bash
  dart tools/dependency_sync.dart --check
  ```
  Lệnh này sẽ quét toàn bộ workspace và báo lỗi (exit code 1) nếu phát hiện bất kỳ sự lệch pha (mismatch) nào so với catalog. Lệnh này được tích hợp trực tiếp vào quy trình CI/CD và Git Pre-commit Hook để ngăn chặn triệt để việc đẩy mã nguồn bị xung đột phiên bản lên hệ thống.

---

## 🎨 12. Quy Chuẩn Sử Dụng Theme & Styles (Design System)

Để bảo đảm giao diện nhất quán, hỗ trợ Dark/Light mode tự động và scale chính xác trên nhiều kích thước thiết bị (responsive), tất cả UI phải sử dụng Design System từ gói `core_base_ui`:

- **Tuyệt đối không hard-code** màu sắc, khoảng cách, bo góc (ví dụ: `Colors.white`, `16.0`, `Radius.circular(8)`).
- **Màu sắc (Colors)**: Các màu đã được hỗ trợ tự động đổi theo Theme (Light/Dark). Truy cập nhanh qua `context.colors`:
  - `context.colors.textPrimary`, `context.colors.textSecondary`, `context.colors.surface`, `context.colors.primary`, v.v.
  - *(Lưu ý Quan trọng: Tên biến màu sắc, style text, khoảng cách bắt buộc phải đặt tên ĐỒNG BỘ 100% với tên gọi trên bản thiết kế Figma/Design System. Nếu Design quy định tên là `wht`, `l2`, `bk` hay `abc`, lập trình viên phải giữ nguyên tên gọi đó trong code để đảm bảo giao tiếp đồng nhất với Designer).*
- **Kiểu chữ (Typography / Text Styles)**: Bắt buộc sử dụng hệ thống Typography đã được định nghĩa sẵn qua `context` (được cấu hình với `.sp` của `flutter_screenutil` để tự động scale text size):
  - Ví dụ: `AppTextStyles.bodyMediumStyle(context)Style`, `AppTextStyles.titleLargeStyle(context)Style`, `AppTextStyles.displaySmallStyle(context)Style`, `AppTextStyles.labelSmallStyle(context)Style`.
  - Không hard-code `TextStyle(fontSize: 14)` trực tiếp trên Widget.
- **Kích thước & Khoảng cách (Spacing/Padding/Margin)**: Dùng `AppSpacing` để đảm bảo padding/margin tự động scale theo `.w` (của `flutter_screenutil`):
  - `AppSpacing.xs`, `AppSpacing.sm`, `AppSpacing.md`, `AppSpacing.lg`, `AppSpacing.xl`
- **Bo góc (Border Radius)**: Dùng `AppRadius` để tự động scale bo góc theo `.r`:
  - Lấy hằng số double: `AppRadius.sm`, `AppRadius.md`, `AppRadius.circular`
  - Lấy đối tượng BorderRadius: `AppRadius.smRadius`, `AppRadius.mdRadius`, `AppRadius.circularRadius`
- **Gradients & Shadows**: Sử dụng tập trung từ `AppGradients` và `AppShadows`.

---

## 🌍 13. Quy Chuẩn Đa Ngôn Ngữ & Tài Nguyên (Localization & Assets)

- **Bắt buộc dịch thuật**: Tất cả các đoạn văn bản hiển thị trên giao diện (hardcoded UI text, toast messages, server error messages) đều **BẮT BUỘC** phải được đưa vào hệ thống đa ngôn ngữ.
- **Phân tách theo Feature (Feature-Scoped Translations)**: Mỗi tính năng (Feature) phải định nghĩa các tệp dịch thuật `.arb` của riêng mình bên trong thư mục `assets/language/` (ví dụ: `packages/features/auth/assets/language/en.arb`). Gói `core_base_ui` CHỈ được dùng để chứa các chuỗi dịch thuật toàn cục.
- Khi gọi bản dịch, hãy dùng extension của riêng Feature đó (ví dụ: `context.l10nAuth.translationKey`) thay vì delegate toàn cục.
- **Tuyệt đối cấm** việc viết cứng (hardcode) chuỗi trực tiếp trên UI.
- **Ủy quyền Phân rã (Decentralized Delegation)**: Các Feature packages **KHÔNG ĐƯỢC PHÉP** chỉnh sửa tệp `app/lib/presentation/root_app.dart` để thêm `LocalizationsDelegates`. Thay vào đó, chúng phải cung cấp một bản triển khai của interface `IFeatureLocalization` và đăng ký vào DI cục bộ (`@LazySingleton(as: IFeatureLocalization)`). Root app sẽ tự động thu thập tất cả các delegate thông qua `getIt.getAll<IFeatureLocalization>()`. Cùng pattern với routing: đăng ký `IFeatureRouteModule` / `IDashboardTabModule` / `IAppEntryLocation` / `DashboardRouteModule`; host thu thập bằng `getAllOrEmpty` / `getItOrNull` — **không** hardcode route feature vào `app_router.dart`.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
