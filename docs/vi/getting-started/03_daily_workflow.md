<!-- translated-from: docs/en/getting-started/03_daily_workflow.md@d6a34fc -->
# 03 · Vòng lặp làm việc hàng ngày

**Trang này trả lời:** khi nào thì gõ lệnh nào? Bỏ qua thì hỏng chuyện gì?

**Đọc xong bạn có thể:** làm việc trong monorepo này mà không dính những thứ tốn thời gian kinh điển — code sinh ra bị cũ, barrel bị cũ và phần ghép app lệch khỏi manifest của nó.

---

## 1. Vòng lặp

```text
   sửa code
        │
        ├─ có đụng annotation?  ──► dart run build_runner build --workspace
        │
        ├─ có thêm/đổi tên/xoá file trong lib/?  ──► dart tools/barrel_generator/generate.dart <pkg>/lib
        │
        ├─ có sửa app_manifest.yaml?  ──► dart tools/composer/composer.dart sync
        │
        ├─ có sửa pubspec_dependencies.yaml?  ──► dart tools/dependency_sync.dart
        │
        ▼
   flutter analyze  ──►  flutter test (theo từng package)  ──►  commit
```

---

## 2. `build_runner` — sau khi đụng vào annotation

```bash
dart run build_runner build --workspace
```

Chạy mỗi khi bạn thêm, xoá hoặc sửa bất kỳ thứ nào sau đây:

| Annotation / thay đổi | Generator | Sinh ra |
| :--- | :--- | :--- |
| `@freezed`, thêm union case, thêm field | `freezed` | `*.freezed.dart` |
| `@JsonSerializable`, `fromJson` / `toJson` | `json_serializable` | `*.g.dart` |
| `@injectable`, `@lazySingleton`, `@Singleton(as:)`, `@module`, `@PostConstruct`, `@disposeMethod` | `injectable_generator` | `*.module.dart`, và `lib/di/injection.config.dart` của từng app |
| `@RestApi`, `@GET`, `@POST` | `retrofit_generator` | `*.g.dart` |
| `@DriftDatabase`, `@DriftAccessor`, thêm bảng | `drift_dev` | `<tên>_database.g.dart`, cạnh file database của bạn (ví dụ `cache_database.g.dart`) |
| `@TypedGoRoute`, `@TypedShellRoute` | `go_router_builder` | `*_route_module.g.dart` |
| Thêm asset mới vào `platform/ui/design_system/assets/` | `flutter_gen_runner` (chỉ `core_base_ui` khai) | `lib/src/gen/assets.gen.dart` |

> [!WARNING]
> Dấu hiệu bạn quên chạy: `Undefined class '_$SomethingImpl'`, `The getter '$myRoute' isn't defined`, `Type X is not registered inside GetIt`, hoặc binding DI mới thêm im lặng không tồn tại.

> [!CAUTION]
> Tuyệt đối không sửa tay file sinh ra (`*.g.dart`, `*.freezed.dart`, `*.module.dart`, `injection.config.dart`). Lần chạy kế tiếp sẽ xoá sạch sửa đổi của bạn. Hãy sửa file nguồn có annotation.

### Chế độ watch

Cho vòng lặp sửa–chạy liên tục:

```bash
dart run build_runner watch --workspace
```

---

## 3. Barrel generator — sau khi thêm, đổi tên hoặc xoá file

Mỗi package phơi public API qua **một barrel duy nhất**, `lib/<package_name>.dart` (RULE-75). Nó được sinh tự động, không bảo trì tay, và export mọi file library dưới `lib/`.

```bash
dart tools/barrel_generator/generate.dart modules/auth/feature/lib
dart tools/barrel_generator/generate.dart modules/auth/domain/lib
dart tools/barrel_generator/generate.dart platform/infra/storage/lib
```

Tool chỉ nhận `lib/` của một package và không nhận gì khác (đường dẫn khác thoát với mã `64`). Nó bỏ qua `*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*_test.dart` và các file `part of`, nhưng vẫn export các library sinh ra khác đang có trên đĩa (`*.module.dart`, mọi thứ dưới `lib/src/gen/`). Vì vậy hãy chạy nó **sau** `build_runner` và `flutter gen-l10n`. Nó thay mọi `export` trong barrel, xoá mọi barrel theo thư mục, rồi format lại phần vừa ghi.

Bên trong một package, file import file cụ thể (`../pages/notes_page.dart`), không bao giờ import barrel.

> [!WARNING]
> Dấu hiệu bạn quên chạy: class mới compile được bên trong package của nó nhưng **vô hình** với bên ngoài — báo `Undefined class` dù file rõ ràng đang tồn tại. CI cũng bắt barrel cũ: sau `configure.dart`, nó làm hỏng build nếu generator đổi hay thêm bất kỳ file `.dart` nào.

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
> Dependency native của Android trong `apps/mobile/android/app/build.gradle.kts` nằm **ngoài** catalog này. Hiện chỉ có `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:…")`; nâng nó là việc sửa Gradle thủ công.

---

## 5. Các tool còn lại trong `tools/`

| Tool | Lệnh | Dùng khi |
| :--- | :--- | :--- |
| **Module generator** | `dart tools/module_generator/generate.dart <loại> <tên> [<prefix>] [<SM>] [<route>] [--apps <id,id>]` | Dựng khung package Feature / Domain / Data / Core / Custom / API mới (`<loại>` 1–6). Nó thêm module vào **mọi** `app_manifest.yaml` (hoặc chỉ các app trong `--apps`) rồi chạy `composer sync` để đăng ký package vào workspace và vào từng app. `apps/admin` chỉ ghép auth + settings, nên hãy truyền `--apps mobile` cho module không thuộc về đó. Luôn truyền đủ mọi tham số: feature thiếu `<SM>` hoặc `<route>` thì thoát với mã `64` khi không có terminal. `--help` in cú pháp; mọi tham số có trong [`../reference/03_tooling.md`](../reference/03_tooling.md#module_generator). |
| **Composer** | `dart tools/composer/composer.dart sync` / `verify` / `describe --app <id>` | `sync` sau khi sửa một `app_manifest.yaml`; `verify` là CI Gate 0; `describe` in ra thứ app khai báo và thứ shell resolve. [`../guides/13_app_composition.md`](../guides/13_app_composition.md). |
| **Unused checker** | `dart tools/unused_checker/check_script.dart` | Dọn dẹp định kỳ. Nó chạy cả bốn kiểm tra và không có lệnh con; muốn chạy riêng một kiểm tra thì gọi script của nó (`check_unused_assets.dart`, `check_unused_file.dart`, `check_unused_packages.dart`, `check_unused_translate.dart`: asset, file, package, translation). Kiểm tra package là một bước của CI. |
| **Outdated checker** | `dart tools/check_outdated.dart` | Trước một đợt nâng version. Tool liệt kê thứ pub.dev đã có bản mới. Trên terminal, nó hiện tiếp một checklist tương tác: `a` ghi các version đã chọn vào catalog rồi chạy `dependency_sync` + `pub get`, còn `q` để thoát. Không có terminal (CI, pipe) thì nó chỉ báo cáo. |
| **AI code review** | `dart tools/code_review/code_review.dart --changed` | Rà soát tuỳ chọn trước khi mở PR, không bao giờ là gate chặn merge. Cần Gemini API key (`GEMINI_API_KEY`, `--api-key`, hoặc lưu khi tool hỏi). Hỗ trợ thêm `--all`, `--file <đường_dẫn>`, `--focus architecture,security`, và `--language <mã>` chỉ cho lần chạy đó. |
| **Workspace setup** | `dart tools/workspace_setup/configure.dart` | Lần setup đầu tiên của một bản clone, sau một lần rebase lớn, hoặc khi mọi thứ hỏng không rõ lý do. Script chạy theo thứ tự: activate `flutterfire_cli` (bỏ qua với `--stub-firebase`, vì các stub thay thế thứ nó sẽ sinh ra) → `flutter clean` → `flutter pub get` → `flutter gen-l10n` trong mọi package có `l10n.yaml` → `dart run build_runner build --workspace` → barrel generator cho mọi package có `lib/` (bỏ qua các app). Dừng ngay ở bước đầu tiên bị lỗi. `--stub-firebase` còn ghi thêm các file Firebase chỉ-để-biên-dịch ([`01_setup.md`](01_setup.md#32-chưa-có-firebase-project-dùng-stub)). |

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

Các lệnh CI chạy, theo đúng thứ tự của nó ([`../operations/01_cicd.md`](../operations/01_cicd.md)). Chạy những lệnh mà thay đổi của bạn đụng tới:

```bash
# Gate 0 — phần ghép khớp mọi app_manifest.yaml
dart tools/composer/composer.dart verify

# Gate 1 — các luật phân tầng, và test riêng của các tool gate (chỉ khi bạn sửa tools/)
dart tools/arch_check/check.dart
(cd tools && dart test)

# Gate 2 — phân tích tĩnh, sạch trên toàn workspace (info cũng tính)
flutter analyze

# Gate 3 — test nằm theo từng package, nên chạy mọi package có thư mục test/
#         (cùng quy tắc CI dùng để tìm package; bash — Git Bash trên Windows)
for pubspec in $(find apps modules platform -name pubspec.yaml -not -path '*/build/*' -not -path '*/.dart_tool/*' | sort); do
  dir=$(dirname "$pubspec")
  [ -d "$dir/test" ] || continue
  (cd "$dir" && flutter test) || { echo "FAILED: $dir"; break; }
done

# Gate 4 — catalog version đang đồng bộ
dart tools/dependency_sync.dart --check

# Gate 5 — tài liệu vẫn mô tả đúng cây này
dart tools/docs_check/check.dart

# CI cũng chặn ở đây — không có dependency khai báo mà không ai import (RULE-06)
dart tools/unused_checker/check_unused_packages.dart
```

Test nằm ở `<package>/test/`, ở bất cứ đâu package đó nằm. Vòng lặp tự tìm chứ không liệt kê cứng, nên vẫn đúng khi bạn thêm một package có test hay gỡ một sample từng có test — CI áp dụng cùng quy tắc (mọi thư mục có `pubspec.yaml` và `test/`) nhưng khác ở ba điểm: nó tìm từ root của repository, chạy hết mọi package rồi mới báo fail thay vì dừng lại, và báo fail nếu không tìm thấy package nào. Vòng lặp dừng ở package fail đầu tiên và in tên package; hãy viết test của bạn ngay cạnh code bạn viết, với fake tự viết (repo không dùng mockito/mocktail) — `flutter_test` trong package Flutter, `package:test` trong package Dart thuần. Vòng lặp phủ `apps/`, `modules/` và `platform/`; `tools/` có bộ test riêng, nằm ở Gate 1. Trên Windows, chạy nó trong Git Bash (đi kèm Git for Windows) — PowerShell và `cmd` không có `find`/`dirname` kiểu này.

Import thiếu khai báo bị `arch_check` (R5) bắt; unused checker lo chiều ngược lại.

> [!CAUTION]
> `flutter analyze` **không** bắt được lỗi thứ tự DI (RULE-13): một `@Singleton` eager phụ thuộc type do module chạy *sau* đăng ký vẫn compile bình thường rồi ném `not registered` lúc khởi động. Vòng lặp Gate 3 bắt được nó — `test/di_smoke_test.dart` của mỗi app boot đồ thị thật cho mọi flavor và dựng mọi factory (RULE-63). Khi nó fail, [../guides/05_di.md](../guides/05_di.md) § 8 chỉ cách đọc các file sinh ra để tìm thủ phạm.

### Tuỳ chọn: chứng minh app vẫn build được

Phân tích tĩnh sạch không có nghĩa là build Android sạch (lỗi Gradle/Kotlin nằm ngoài Dart):

```bash
cd apps/mobile
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

---

## 7. Bẫy thường gặp

| Bẫy | Triệu chứng | Cách xử lý |
| :--- | :--- | :--- |
| Quên `build_runner` sau khi đổi annotation | `Undefined class '_$…Impl'`, type không đăng ký được trong DI | `dart run build_runner build --workspace` |
| Quên barrel generator sau khi thêm file | Class mới vô hình bên ngoài package | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Sửa tay file sinh ra | Thay đổi biến mất ở lần codegen kế tiếp | Sửa file nguồn có annotation |
| Sửa tay một `app_manifest.yaml`, hoặc một vùng `composer:managed`, mà không chạy sync | `composer verify` báo lỗi (Gate 0) | Chỉ sửa manifest, rồi `dart tools/composer/composer.dart sync` (RULE-16) |
| Chạy `pub get` bên trong package con | Xuất hiện `pubspec.lock` lạc chỗ | Xoá chúng đi, chạy `flutter pub get` tại root |
| Chạy `flutter build apk` từ gốc repo | `Target file "lib\main.dart" not found` | `cd apps/mobile` trước |
| Hardcode version trong pubspec của package | `dependency_sync --check` báo lỗi | Đưa version về `pubspec_dependencies.yaml`, sync lại |
| Import package mà không khai báo | Compile được cục bộ (workspace dùng chung `package_config.json`), gãy khi tách package | Khai vào `pubspec.yaml` của package đó (`dependencies:`, không phải `dev_dependencies:`); kiểm tra bằng `dart tools/arch_check/check.dart` (R5). Unused checker lo chiều ngược lại — khai mà không import |
| Đăng ký controller màn hình là singleton | State rò rỉ giữa các lần mở màn hình | Controller của feature là `@injectable` (RULE-10) — xem [../guides/05_di.md](../guides/05_di.md) |

---

## Đọc tiếp ở đâu

| Bạn muốn… | Đọc |
| :--- | :--- |
| Hiểu kiến trúc | [../architecture/01_overview.md](../architecture/01_overview.md) |
| Tạo feature đầu tiên | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
| Xem đầy đủ danh sách luật | [../reference/01_rules.md](../reference/01_rules.md) |
| Tra cứu tooling | [../reference/03_tooling.md](../reference/03_tooling.md) |
