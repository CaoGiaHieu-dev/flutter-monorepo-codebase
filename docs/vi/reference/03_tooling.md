# Tra cứu công cụ

**File này trả lời:** chạy script nào, với tham số gì, và khi nào?

**Đọc xong bạn có thể:** chọn đúng công cụ cho mọi việc bảo trì, và biết trước cạm bẫy của nó.

Tất cả công cụ nằm trong `tools/`, đều là Dart thuần — chạy từ **thư mục gốc repo**.

---

## Vấn đề → công cụ

| Vấn đề | Lệnh |
|---|---|
| Tạo package feature / domain / data / core mới | `dart tools/module_generator/generate.dart …` |
| Vừa thêm, đổi tên hoặc xoá file trong `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Vừa đổi version dependency | `dart tools/dependency_sync.dart` |
| CI cần chặn lệch version | `dart tools/dependency_sync.dart --check` |
| Nghi có asset / file / translation / package chết | `dart tools/unused_checker/check_script.dart` |
| Muốn biết gì đã lỗi thời trên pub.dev | `dart tools/check_outdated.dart` |
| Vừa clone về, cần dựng mọi thứ | `dart tools/workspace_setup/configure.dart` |
| Cấu hình Firebase cho dev / staging / prod | `dart tools/firebase/firebase_config.dart` |
| Sinh lại splash screen và app icon | `dart tools/theme_generator/theme_setting.dart` |
| Kiểm tra tương thích 16 KB page-size của Android 15+ | `./tools/android_compliance/16kb_ckeck.sh` |
| Nhờ AI review một thay đổi | `dart tools/code_review/code_review.dart --changed` |

---

## `module_generator`

Dựng khung package và đăng ký nó khắp workspace.

```bash
dart tools/module_generator/generate.dart <type> <name> [<dir>] [<sm>] [<route>]
```

| Tham số | Giá trị |
|---|---|
| `<type>` | `1` feature · `2` domain · `3` data · `4` core · `5` custom |
| `<name>` | tên thư mục trần (`profile`) — package sẽ thành `feature_profile` |
| `<dir>` | chỉ dùng cho type `5` |
| `<sm>` | chỉ feature — `1` Provider · `2` BLoC · `3` không dùng |
| `<route>` | chỉ feature — `1` `IFeatureRouteModule` · `2` `IDashboardTabModule` · `3` không |

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1   # feature + Provider + route stack
dart tools/module_generator/generate.dart 1 chat    "" 2 2   # feature + BLoC + tab bottom-nav
dart tools/module_generator/generate.dart 2 payment          # domain micro-package
dart tools/module_generator/generate.dart 3 payment          # data micro-package
```

Chạy thiếu tham số thì nó sẽ hỏi tương tác.

**Nó làm gì:** tạo cây thư mục (bao gồm `lib/src/utils/`, cho mọi tầng), render template, thêm package vào danh sách `workspace:` gốc và `app/pubspec.yaml`, đăng ký module DI vào `app/lib/di/injection.dart`, rồi chạy dependency sync, `pub get`, `gen-l10n`, barrel generator, `build_runner`, và `dart fix --apply`.

**Hành vi an toàn**

- **Kiểm tra toolchain trước tiên.** `assertToolchainAvailable()` chạy trước khi động vào bất cứ file dùng chung nào, nên thiếu SDK là fail ngay lập tức thay vì chết ở bước 8.
- **Từ chối thư mục đã tồn tại.** Nó sẽ không âm thầm ghi đè lên package có sẵn.
- **Rollback khi thất bại.** Ba file dùng chung (`pubspec.yaml` gốc, `app/pubspec.yaml`, `app/lib/di/injection.dart`) được sao lưu trước mọi thao tác ghi; nếu bước sau fail thì chúng được khôi phục và thư mục module mới bị xoá.
- **Tự phát hiện FVM**, yêu cầu *cả hai*: có file cấu hình (`.fvmrc` hoặc `.fvm/fvm_config.json`) *và* `fvm --version` chạy được. Chỉ một tín hiệu thôi là cho kết quả sai: repo này pin version trong `.fvmrc` trong khi một máy cụ thể có thể không hề cài `fvm`.

> [!NOTE]
> Module domain và data chỉ được tạo thư mục và nối pubspec — entity, use case, repository phải viết tay. Xem [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md).

---

## `barrel_generator`

```bash
dart tools/barrel_generator/generate.dart packages/<layer>/<package>/lib
```

Sinh lại barrel `*.dart` cho mọi thư mục dưới đường dẫn đã cho, rồi format. Chạy nó sau **bất kỳ** thao tác thêm / đổi tên / xoá file nào trong `lib/`.

Bỏ qua `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, và file khai `part of`.

> [!CAUTION]
> Nó **xoá mọi dòng `export` viết tay** trong barrel trước khi sinh lại. Cần re-export thứ gì từ package khác thì đặt `export` vào một file nguồn bình thường rồi để barrel nhặt file đó lên.

---

## `dependency_sync`

`pubspec_dependencies.yaml` ở gốc repo là nguồn chân lý duy nhất cho version.

```bash
dart tools/dependency_sync.dart          # ghi version vào mọi package
dart tools/dependency_sync.dart --check  # chỉ kiểm tra; exit 1 nếu lệch
```

Nó cũng sửa các mục `path:` cục bộ bị gãy. Dùng `--check` trong CI và pre-commit.

> [!NOTE]
> Nó parse theo từng dòng chứ không dùng YAML parser, nên `dependency_overrides` và cú pháp multi-line/anchor không được xử lý. Dependency native của Gradle (ví dụ `play-services-auth` trong `app/android/app/build.gradle.kts`) hoàn toàn nằm ngoài phạm vi của nó — chúng không có nguồn chân lý tập trung nào.

---

## `unused_checker`

```bash
dart tools/unused_checker/check_script.dart              # cả bốn, kèm tổng kết
dart tools/unused_checker/check_unused_assets.dart       # asset không được tham chiếu
dart tools/unused_checker/check_unused_translate.dart    # key .arb không ai dùng
dart tools/unused_checker/check_unused_file.dart         # file Dart mồ côi
dart tools/unused_checker/check_unused_packages.dart     # dependency khai mà không dùng
```

`check_unused_packages.dart` chính là cái thực thi [luật 2](01_rules.md#2-khai-báo-dependency-tường-minh) — chạy nó trước mỗi PR.

> [!WARNING]
> Các checker asset / file / translation hoạt động bằng đối chiếu văn bản, nên sẽ báo nhầm với bất cứ thứ gì được với tới động (đường dẫn asset ghép từ chuỗi, key tra lúc chạy). Xác nhận kỹ trước khi xoá.

---

## `check_outdated`

```bash
dart tools/check_outdated.dart
```

Liệt kê package có version mới hơn trên pub.dev. Cập nhật `pubspec_dependencies.yaml` rồi chạy `dependency_sync`.

---

## `workspace_setup`

```bash
dart tools/workspace_setup/configure.dart
```

Dựng đầy đủ cho một bản clone mới: activate `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n`, `build_runner`.

> [!CAUTION]
> **Không có** `configure.sh` và **không có** `configure.bat`. Chỉ tồn tại `configure.dart`. Các tài liệu và bước CI cũ trỏ tới hai file shell đó đều đã hỏng và đã được sửa.

---

## `firebase`

```bash
dart tools/firebase/firebase_config.dart
```

Chạy `flutterfire configure` cho từng flavor, sinh ra ba file `firebase_options_*.dart` mà `packages/core/common/lib/src/firebase/firebase_module.dart` import vào.

> [!WARNING]
> Ba file sinh ra đó bị git ignore, và `firebase_module.dart` import **cả ba một cách vô điều kiện**. Do đó một bản clone mới **không compile được** cho tới khi chạy lệnh này — kể cả khi bạn chỉ build dev. Xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Phải chạy từ thư mục gốc repo; script kiểm tra sự tồn tại của `pubspec.yaml` rồi mới chạy tiếp.

---

## `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart
```

Điều khiển `flutter_native_splash` và `icons_launcher` dựa trên các file cấu hình theo flavor ở gốc repo (`flutter_native_splash-*.yaml`, `icons_launcher-*.yaml`).

---

## `android_compliance`

```bash
./tools/android_compliance/16kb_ckeck.sh    # macOS / Linux
.\tools\android_compliance\16kb_ckeck.bat   # Windows
```

Kiểm tra các thư viện native `.so` xem có căn chỉnh 16 KB page-size cho Android 15+ chưa. Đây là công cụ duy nhất trong repo viết bằng shell script thay vì Dart.

> [!NOTE]
> Tên file đúng là `16kb_ckeck` — một lỗi gõ được giữ nguyên vì đã có script và tài liệu tham chiếu tới nó.

---

## `code_review`

```bash
dart tools/code_review/code_review.dart --all
dart tools/code_review/code_review.dart --changed
dart tools/code_review/code_review.dart --file app/lib/main.dart
dart tools/code_review/code_review.dart --all --focus architecture,security
```

Review bằng Gemini, điều khiển bởi `tools/code_review/review_prompt.md`. Cần API key trong `tools/code_review/code_review_config.json` (file này để rỗng khi ship; đừng commit key thật).

> [!NOTE]
> Workflow GitHub chạy nó ở **chế độ cảnh báo** — bước "fail on critical issues" có dòng `exit 1` bị comment lại, nên nó không bao giờ chặn PR. Xem [`../operations/01_cicd.md`](../operations/01_cicd.md).

---

## Điểm không nhất quán đã biết

`tools/workspace_setup/configure.dart` và `tools/theme_generator/theme_setting.dart` phát hiện FVM bằng cách **chỉ** kiểm tra `.fvm/fvm_config.json`. Repo này pin version trong `.fvmrc`, thứ mà hai script đó không nhìn tới, nên chúng luôn rơi về `dart` / `flutter` toàn cục. Trên máy không cài FVM thì kết quả tình cờ vẫn đúng, nhưng đây không phải cách phát hiện đáng tin như `module_generator` hiện đang làm.

---

**Tiếp theo:** [`04_review_checklist.md`](04_review_checklist.md) · [`01_rules.md`](01_rules.md) · [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md)
