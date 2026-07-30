# 10. Danh Mục Kiểm Tra Review Code (Pull Request Review Checklist)

Tài liệu này cung cấp bảng kiểm tra (checklist) tiêu chuẩn bắt buộc áp dụng đối với tất cả thành viên phát triển và Reviewer trước khi thực hiện Merge bất kỳ Pull Request (PR) nào vào nhánh chính. Mục tiêu tối thượng là duy trì sự hoàn hảo của kiến trúc **Micro-packages Monorepo**, **SOLID**, và các quy định an toàn hệ thống.

---

## 📂 1. Cấu Trúc Mô-đun (Monorepo & Packages Structure)
- [ ] **Workspace Resolution**: File `pubspec.yaml` của package mới hoặc sửa đổi đã khai báo thuộc tính `resolution: workspace` ở tệp tin cấu hình chưa?
- [ ] **Barrel File Export**: Mọi API, Widget công khai đã được xuất bản đầy đủ thông qua tệp barrel chính `lib/<package_name>.dart` để các gói khác sử dụng chưa? (Và các tệp tin chi tiết cài đặt được giấu kín bên trong `src/` chưa?)
- [ ] **Git Isolation**: Package mới có chứa tệp tin quản lý `.gitignore` riêng biệt để cô lập các tệp tin sinh mã (`.g.dart`, `.freezed.dart`) cục bộ không?

---

## 🧬 2. Thẩm Định Tầng Core (Core Packages Layer)
- [ ] **Hằng số (Constants)**: Toàn bộ hằng số mới đã được khai báo viết hoa toàn bộ và sử dụng dấu gạch dưới (`UPPER_SNAKE_CASE`) trong gói `core_common` chưa?
- [ ] **Quy chuẩn Design System**: Có Widget hiển thị thô nào đang bị viết đè lên thiết kế chung không? Đã tái sử dụng các component của `core_base_ui` chưa?
- [ ] **Theme Extensions**: Việc lấy màu sắc và kiểu chữ tại giao diện có sử dụng đúng các Extension tiện ích (`context.themeExtension.primary`, `context.textTheme`) không?

---

## 🧠 3. Thẩm Định Tầng Nghiệp Vụ (Domain Package Layer)
- [ ] **Pure Dart Constraint**: Tệp tin nguồn mới thuộc các gói `packages/domain/*` có sạch bóng 100% các import liên quan đến Flutter UI (`material.dart`, `widgets.dart`) và thư viện gọi mạng (`dio`, `retrofit`) không?
- [ ] **Entities Immutability**: Các thực thể dữ liệu mới có được bao bọc an toàn và đảm bảo tính bất biến (`freezed`) không? Đã khai báo hàm constructor trống `const Class._()` chưa?
- [ ] **Single Responsibility UseCases**: Mỗi UseCase có đảm bảo chỉ thực hiện duy nhất một hành động nghiệp vụ đơn lẻ và trả về kết quả qua sealed class `Result<T, AppFailure>` không?

---

## 💾 4. Thẩm Định Tầng Dữ Liệu (Data Package Layer)
- [ ] **Data Class Serialization**: Các Models (DTOs) có khai báo đầy đủ hàm `.toEntity()` để biến đổi dữ liệu thô sang thực thể sạch trước khi trả về cho Domain không?
- [ ] **Exception Catcher Boundary**: Lớp triển khai `RepositoryImpl` có sử dụng khối `try-catch` để chặn toàn bộ Exception và chuyển hóa thành thực thể lỗi có kiểm soát `AppFailure` không? (Tuyệt đối cấm sử dụng câu lệnh `throw` văng lỗi ra UI).
- [ ] **Retrofit API Interfaces**: Việc kết nối API có sử dụng đúng Retrofit Generator thay vì code chay các lệnh gửi mạng không?

---

## 🖥️ 5. Thẩm Định Tầng Giao Diện (Feature Presentation Layer)
- [ ] **Feature Boundary**: Mỗi Feature package có sở hữu một bounded UI concern duy nhất không? Các tab/màn không liên quan (ví dụ Home vs Settings) **không** bị nhét chung một package; Dashboard chỉ ghép route.
- [ ] **UI Controller Standard**: Các UI Controllers (ViewModel / Bloc) có kế thừa từ Base Class chuẩn (`BaseProvider`, `BaseBloc`...) không? Ưu tiên Bloc hơn Cubit; Cubit chỉ khi không cần event. Cho phép Freezed UI state tùy chỉnh khi `ViewState<T>` không đủ.
- [ ] **Controller Lifecycle (Auto-dispose)**: Các logic UI gắn liền màn hình có đảm bảo **KHÔNG** đăng ký dạng Singleton (`@singleton` hoặc `@lazySingleton`) không? Chúng có được đánh dấu `@injectable` và quản lý vòng đời đúng cách ở Route Level (qua `ChangeNotifierProvider` hoặc `BlocProvider`) để giải phóng bộ nhớ khi tắt màn hình không?
- [ ] **Decentralized Localization (Đa ngôn ngữ phân rã)**: Feature có sử dụng interface `IFeatureLocalization` để đăng ký bản dịch vào DI thay vì can thiệp trực tiếp vào `root_app.dart` không? Các chuỗi văn bản trên giao diện đã được đa ngôn ngữ hóa thay vì viết cứng (hardcode) chưa?

---

## 🚦 6. Định Tuyến & Điều Phối (Decoupled Routing & DI)
- [ ] **Decoupled Scoped Navigators**: Lớp giao diện (Pages) và ViewModels có tuân thủ quy tắc gọi gián tiếp qua Interface Scoped Navigator cục bộ (ví dụ: `AuthNavigator`) thay vì import trực tiếp tệp route của Feature khác không?
- [ ] **Dynamic route DI**: Feature đã lộ diện qua `IFeatureRouteModule` và/hoặc `IDashboardTabModule` (và tùy chọn `IAppEntryLocation`) — **không** sửa list `$…Route` cứng trong `app_router.dart`?
- [ ] **Dashboard misuse**: Nếu đụng tab/shell — `feature_dashboard` chỉ còn `DashboardRouteModule` (chrome)? Không import page tab vào dashboard? `IDashboardTabModule` chỉ cho đích bottom-nav thật (không phải màn chỉ push)?
- [ ] **Action Handlers**: Với hành động UI liên feature (ví dụ logout từ Settings), có dùng `I*ActionHandler` ở `core_di` kèm `*ActionHandlerImpl` ở feature sở hữu (không import trực tiếp package sở hữu) không?
- [ ] **Shell Widgets**: App Shell có dùng `NavigatorWrapperWidget` / `UndefineRouteWidget` (không còn `_RootChildWrapper` / `UndefineRouteScreen`) không?
- [ ] **Fallbacks**: Module thiếu có được xử lý bằng `getAllOrEmpty` / `getItOrNull` + rỗng/`SizedBox.shrink()` không?
- [ ] **Platform Transitions**: Các Route của Feature mới có kế thừa đúng `GoRouteDataCustom` để có sẵn platform transitions và ghi nhận log Screen View tự động không?
- [ ] **Injectable Module Registers**: Gói mới có khai báo module DI cục bộ `@InjectableInit.microPackage()` tại `di/module.dart` không? Đã đăng ký module đó vào tệp `app/lib/di/injection.dart` của Host App chưa?

---

## 🛠️ 7. Công Cụ Phát Triển & CLI Script Tools
- [ ] **No Print Rule**: Các công cụ phát triển (ví dụ: CLI tools trong `tools/`) có tuân thủ quy định tuyệt đối không sử dụng lệnh `print()` mà chuyển sang dùng `stdout.writeln` / `stderr.writeln` không?
- [ ] **No Linter Ignores**: Các tệp tin có sạch bóng các chú thích bỏ qua linter không chuẩn như `// ignore_for_file: avoid_print`?

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
