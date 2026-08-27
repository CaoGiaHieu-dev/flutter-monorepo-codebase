# 03 · Vòng lặp làm việc hàng ngày

**Trang này trả lời:** khi nào thì gõ lệnh nào? Bỏ qua thì hỏng chuyện gì?

**Đọc xong bạn có thể:** làm việc trong monorepo này mà không dính hai thứ tốn thời gian kinh điển — code sinh ra bị cũ, và thiếu export trong barrel.

---

## 1. Vòng lặp

```text
   sửa code
        │
        ├─ có đụng annotation?  ──► dart run build_runner build -d --workspace
        │
        ├─ có thêm/đổi tên/xoá file trong lib/?  ──► dart tools/barrel_generator/generate.dart <pkg>/lib
        │
        ├─ có sửa pubspec_dependencies.yaml?  ──► dart tools/dependency_sync.dart
        │
        ▼
   flutter analyze  ──►  flutter test (theo từng package)  ──►  commit
```

---

## 2. `build_runner` — sau khi đụng vào annotation

```bash
dart run build_runner build -d --workspace
```

Chạy mỗi khi bạn thêm, xoá hoặc sửa bất kỳ thứ nào sau đây:

| Annotation / thay đổi | Generator | Sinh ra |
| :--- | :--- | :--- |
| `@freezed`, thêm union case, thêm field | `freezed` | `*.freezed.dart` |
| `@JsonSerializable`, `fromJson` / `toJson` | `json_serializable` | `*.g.dart` |
| `@injectable`, `@lazySingleton`, `@Singleton(as:)`, `@module`, `@PostConstruct`, `@disposeMethod` | `injectable_generator` | `*.module.dart`, `app/lib/di/injection.config.dart` |
| `@RestApi`, `@GET`, `@POST` | `retrofit_generator` | `*.g.dart` |
| `@DriftDatabase`, `@DriftAccessor`, thêm bảng | `drift_dev` | `app_database.g.dart` |
| `@TypedGoRoute`, `@TypedShellRoute` | `go_router_builder` | `*_route_module.g.dart` |
| Thêm asset mới vào thư mục `assets/` | `flutter_gen_runner` | `gen/assets.gen.dart` |

> [!WARNING]
> Dấu hiệu bạn quên chạy: `Undefined class '_$SomethingImpl'`, `The getter '$myRoute' isn't defined`, `Type X is not registered inside GetIt`, hoặc binding DI mới thêm im lặng không tồn tại.

> [!CAUTION]
> Tuyệt đối không sửa tay file sinh ra (`*.g.dart`, `*.freezed.dart`, `*.module.dart`, `injection.config.dart`). Lần chạy kế tiếp sẽ xoá sạch sửa đổi của bạn. Hãy sửa file nguồn có annotation.

### Chế độ watch

Cho vòng lặp sửa–chạy liên tục:

```bash
dart run build_runner watch -d --workspace
```

---

## 3. Barrel generator — sau khi thêm, đổi tên hoặc xoá file

Mỗi package phơi public API qua các file barrel (`src.dart`, `<package>.dart`, và một file cho mỗi thư mục). Chúng được sinh tự động, không bảo trì tay.

```bash
dart tools/barrel_generator/generate.dart packages/features/auth/lib
dart tools/barrel_generator/generate.dart packages/domain/auth/lib
dart tools/barrel_generator/generate.dart packages/core/storage/lib
```

Tool tự bỏ qua file sinh ra (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*_test.dart`) và các file `part of`, sau đó format lại phần vừa ghi.

> [!WARNING]
> Dấu hiệu bạn quên chạy: class mới compile được bên trong package của nó nhưng **vô hình** với bên ngoài — báo `Undefined class` dù file rõ ràng đang tồn tại.

---

## 4. `dependency_sync` — sau khi sửa catalog version

Version thư viện **không bao giờ** được viết tay vào `pubspec.yaml` của package. Nguồn chân lý duy nhất là `pubspec_dependencies.yaml` ở gốc repo.

```bash
# 1. Sửa pubspec_dependencies.yaml
# 2. Đẩy version xuống mọi thành viên workspace:
dart tools/dependency_sync.dart

# Chỉ kiểm tra — thoát mã 1 nếu có sai lệch. Dùng cho CI / pre-commit:
dart tools/dependency_sync.dart --check
```

Tool cũng tự sửa các mục `path:` bị gãy của package trong workspace.

> [!NOTE]
> Dependency native của Android trong `app/android/app/build.gradle.kts` nằm **ngoài** catalog này. Nâng `play-services-auth` hay `androidx.window` là việc sửa Gradle thủ công.

---

## 5. Các tool còn lại trong `tools/`

| Tool | Lệnh | Dùng khi |
| :--- | :--- | :--- |
| **Module generator** | `dart tools/module_generator/generate.dart <loại> <tên> [thư_mục] [SM] [route]` | Dựng khung package Feature / Domain / Data / Core mới. Nó tự đăng ký package vào workspace gốc, `app/pubspec.yaml` và `app/lib/di/injection.dart`. Chạy không tham số để vào chế độ tương tác. |
| **Unused checker** | `dart tools/unused_checker/check_script.dart` | Dọn dẹp định kỳ. Có lệnh con riêng cho asset, file, package, translation. |
| **Outdated checker** | `dart tools/check_outdated.dart` | Trước một đợt nâng version — liệt kê thứ pub.dev đã có bản mới. |
| **AI code review** | `dart tools/code_review/code_review.dart --changed` | Rà soát tuỳ chọn trước khi mở PR. Cần Gemini API key trong `tools/code_review/code_review_config.json`. Hỗ trợ thêm `--all`, `--file <đường_dẫn>`, `--focus architecture,security`. |
| **Workspace setup** | `dart tools/workspace_setup/configure.dart` | Sau một lần rebase lớn, hoặc khi mọi thứ hỏng không rõ lý do — gộp clean + pub get + l10n + build_runner trong một lượt. |

Ví dụ module generator:

```bash
# Feature 'profile', state management Provider, route dạng stack:
dart tools/module_generator/generate.dart 1 profile "" 1 1

# Feature 'chat', BLoC, tab bottom-nav:
dart tools/module_generator/generate.dart 1 chat "" 2 2

# Micro-package Domain + Data cho 'payment':
dart tools/module_generator/generate.dart 2 payment
dart tools/module_generator/generate.dart 3 payment
```

> [!NOTE]
> Mọi CLI tool trong `tools/` dùng `stdout.writeln()` / `stderr.writeln()`. `print()` bị cấm — hãy giữ luật này nếu bạn viết thêm tool.

---

## 6. Trước khi commit

```bash
# 1. Phân tích tĩnh — phải sạch trên toàn workspace
flutter analyze

# 2. Test — test nằm theo từng package, nên chạy theo từng package
cd packages/core/common                  && flutter test && cd -
cd packages/core/database                && flutter test && cd -
cd packages/core/network                 && flutter test && cd -
cd packages/core/provider_state_management && flutter test && cd -
cd packages/core/storage                 && flutter test && cd -
cd packages/data/auth                    && flutter test && cd -

# 3. Catalog version đang đồng bộ
dart tools/dependency_sync.dart --check

# 4. Không có dependency thiếu khai / thừa
dart tools/unused_checker/check_unused_packages.dart
```

Test nằm ở `packages/<layer>/<package>/test/`. Hiện chỉ sáu package trên có test; hãy viết test của bạn ngay cạnh code bạn viết.

> [!CAUTION]
> `flutter analyze` **không** bắt được lỗi thứ tự DI. Một `@Singleton` eager phụ thuộc type được đăng ký ở module chạy *sau* vẫn compile bình thường rồi ném `not registered` lúc khởi động. Sau khi đổi đăng ký DI, hãy mở file sinh ra `app/lib/di/injection.config.dart` và kiểm tra thứ tự. Xem [../guides/05_di.md](../guides/05_di.md).

### Tuỳ chọn: chứng minh app vẫn build được

Phân tích tĩnh sạch không có nghĩa là build Android sạch (lỗi Gradle/Kotlin nằm ngoài Dart):

```bash
cd app
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

---

## 7. Bẫy thường gặp

| Bẫy | Triệu chứng | Cách xử lý |
| :--- | :--- | :--- |
| Quên `build_runner` sau khi đổi annotation | `Undefined class '_$…Impl'`, type không đăng ký được trong DI | `dart run build_runner build -d --workspace` |
| Quên barrel generator sau khi thêm file | Class mới vô hình bên ngoài package | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Sửa tay file sinh ra | Thay đổi biến mất ở lần codegen kế tiếp | Sửa file nguồn có annotation |
| Chạy `pub get` bên trong package con | Xuất hiện `pubspec.lock` lạc chỗ | Xoá chúng đi, chạy `flutter pub get` tại root |
| Chạy `flutter build apk` từ gốc repo | `Target file "lib\main.dart" not found` | `cd app` trước |
| Hardcode version trong pubspec của package | `dependency_sync --check` báo lỗi | Đưa version về `pubspec_dependencies.yaml`, sync lại |
| Import package mà không khai báo | Compile được cục bộ (workspace dùng chung `package_config.json`), gãy khi tách package | Khai vào `pubspec.yaml` của package đó; kiểm tra bằng unused checker |
| Đăng ký controller màn hình là singleton | State rò rỉ giữa các lần mở màn hình | Controller của feature phải là `@injectable` (factory) — xem [../guides/05_di.md](../guides/05_di.md) |

---

## Đọc tiếp ở đâu

| Bạn muốn… | Đọc |
| :--- | :--- |
| Hiểu kiến trúc | [../architecture/01_overview.md](../architecture/01_overview.md) |
| Tạo feature đầu tiên | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
| Xem đầy đủ danh sách luật | [../reference/01_rules.md](../reference/01_rules.md) |
| Tra cứu tooling | [../reference/03_tooling.md](../reference/03_tooling.md) |
