# 🛠️ Development Tools

Thư mục này chứa các công cụ CLI dành cho lập trình viên, hỗ trợ tự động hóa quy trình phát triển và duy trì chất lượng mã nguồn cho Flutter Clean Architecture Monorepo.

> **Quy tắc**: Tất cả CLI Tools trong thư mục này **CẤM** sử dụng `print()`. Bắt buộc dùng `stdout.writeln()` và `stderr.writeln()`.

---

## 📁 Directory Structure

```text
tools/
├── arch_check/                      # 🛡️ Cưỡng chế luật phân tầng (Gate 1 của CI)
│   └── check.dart                   # R1-R10: hướng phụ thuộc, domain thuần Dart, ranh giới feature, scale qua context…
├── composer/                        # 🧩 Ghép app từ app_manifest.yaml (Gate 0 của CI)
│   └── composer.dart                # sync / verify / list — sinh workspace list, dependency của app, injection.dart
├── docs_check/                      # 📚 Mọi đường dẫn docs nhắc tới phải tồn tại (Gate 5 của CI)
│   ├── check.dart
│   └── allowlist.txt                # Đường dẫn vắng mặt có chủ đích, kèm lý do
├── shared/                          # 🔗 Code dùng chung giữa các tool
│   ├── app_locator.dart             # Tìm app qua app_manifest.yaml, chọn app bằng --app <id>
│   └── toolchain.dart               # Phát hiện FVM (.fvmrc + `fvm --version`) cho mọi tool gọi dart/flutter
├── sample_cleanup/                  # 🧹 Phân loại và gỡ code mẫu an toàn
│   └── remove_sample.dart           # --list / dry-run / --apply, có rollback
├── sample_manifest.yaml             # 📑 Nguồn chân lý: package nào là sample/framework/shell
├── module_generator/               # 🏗️ CLI tạo module mới (Feature/Domain/Data/Core)
│   ├── generate.dart               # Entry point chính
│   └── src/
│       ├── input_actions.dart       # Xử lý tham số CLI & interactive input
│       ├── module_type.dart         # Enum ModuleType, StateManagementType, ModuleConfig
│       ├── pubspec_generator.dart   # Sinh pubspec.yaml với dependencies đúng tầng
│       └── common_helpers.dart      # Tạo thư mục, ghi workspace + app_manifest.yaml, chạy CLI
├── barrel_generator/               # 📦 Sinh barrel files (export *.dart)
│   └── generate.dart               # Quét lib/ và tạo file barrel tự động
├── code_review/                    # 🤖 AI-powered code review (Gemini)
│   ├── code_review.dart            # Script review chính
│   ├── lib/                        # Phần lõi của tool
│   ├── review_prompt.md            # Prompt AI chi tiết
│   ├── code_review_config.json     # Cấu hình (ngôn ngữ, batch) — không chứa API key
│   └── README.md                   # Tài liệu chi tiết
├── unused_checker/                 # 🧹 Phân tích & dọn dẹp tài nguyên dư thừa
│   ├── check_script.dart           # Chạy tất cả kiểm tra cùng lúc
│   ├── check_unused_assets.dart    # Phát hiện assets không sử dụng
│   ├── check_unused_file.dart      # Phát hiện files mồ côi
│   ├── check_unused_packages.dart  # Phát hiện packages không sử dụng
│   └── check_unused_translate.dart # Phát hiện translation keys dư thừa
├── workspace_setup/                # ⚙️ Thiết lập workspace tổng
│   └── configure.dart              # Script đa nền tảng (Windows/macOS/Linux)
├── firebase/                       # 🔥 Cấu hình Firebase đa môi trường
│   └── firebase_config.dart
├── theme_generator/                # 🎨 Sinh Splash Screen & App Icons
│   └── theme_setting.dart
├── android_compliance/             # 📱 Kiểm tra Android 15+ 16KB Page Size
│   ├── 16kb_ckeck.sh               # macOS/Linux (file thực thi)
│   └── 16kb_ckeck.bat              # Windows — gọi .sh qua Git Bash
├── dependency_sync.dart            # 📦 Đồng bộ version thư viện từ catalog
└── check_outdated.dart             # 🔄 Kiểm tra thư viện lỗi thời trên pub.dev
```

---

## 🚀 Quick Usage

### 🛡️ Architecture Check (Cưỡng chế luật phân tầng)
```bash
# Kiểm tra 10 luật kiến trúc (R1–R10) — exit 1 nếu có vi phạm (dùng được cho CI):
dart tools/arch_check/check.dart

# Xem mô tả đầy đủ từng luật:
dart tools/arch_check/check.dart --help
```

Chạy trước `flutter analyze` trong CI: nó chỉ đọc import và pubspec nên xong trong ~200 ms,
và là thứ duy nhất nhìn thấy được phân tầng — `analysis_options.yaml` không biết
rằng core không được import feature.

R7 cũng nằm ngoài tầm của analyzer. `core_responsive` không cung cấp extension nào trên
`num`, nên `16.h` không compile được — nhưng một extension sót lại từ package khác, hoặc do
ai đó tự thêm, vẫn qua được type-check trong khi đọc một biến global không báo cho ai. Chỉ
`context.h(16)` mới đăng ký dependency `InheritedWidget` và rebuild khi metrics đổi.

### 🧩 Composer (Ghép app từ manifest)
```bash
# Sinh lại workspace list, dependency của app và injection.dart từ mọi app_manifest.yaml:
dart tools/composer/composer.dart sync

# Chỉ kiểm tra (CI Gate 0) — exit 1 nếu lệch:
dart tools/composer/composer.dart verify

# Xem app ghép những gì (--app lọc một app, dùng được cho cả list/sync/verify):
dart tools/composer/composer.dart list --app admin
```

Cờ lạ bị từ chối (exit 64). Một pubspec/manifest không phải YAML hợp lệ (thường là key trùng)
bị từ chối với tên file và dòng lỗi thay vì crash; một package vừa nằm trong vùng
`composer:managed:deps` vừa được khai báo tay thì có thông báo riêng. Khi một module khai báo
trong manifest không có trên đĩa, cảnh báo PARTIAL COMPOSITION chỉ liệt kê file thực sự bị
ghi lại trong lần chạy đó.

### 🧹 Sample Cleanup (Gỡ code mẫu)
```bash
# Xem package nào là sample, framework hay shell:
dart tools/sample_cleanup/remove_sample.dart --list

# Xem trước việc gỡ bundle 'auth' (mặc định dry-run, không ghi gì):
dart tools/sample_cleanup/remove_sample.dart auth

# Thực sự gỡ:
dart tools/sample_cleanup/remove_sample.dart auth --apply

# Liệt kê đủ mọi tham chiếu tài liệu sẽ chết (mặc định chỉ in 15 dòng đầu):
dart tools/sample_cleanup/remove_sample.dart auth --verbose
```

Dry-run in ra cả những sample khác sẽ vỡ và vỡ ở đâu — thông tin mà hướng dẫn
gỡ feature thủ công không có.

Cả dry-run lẫn `--apply` đều đếm các tham chiếu trong tài liệu (`docs/`, `.agents/`,
mọi `*.md`) tới đường dẫn sắp bị xoá — đúng con số mà `dart tools/docs_check/check.dart`
(CI Gate 5) sẽ báo sau khi gỡ (gỡ `home` hiện để lại ~60 tham chiếu). Gate 5 fail cho tới
khi các tham chiếu đó được sửa. Cờ lạ (ví dụ `--aply`) bị từ chối với exit 64 thay vì bị
bỏ qua.


### 🏗️ Module Generator (Tạo Module Mới)
```bash
# Cú pháp: dart tools/module_generator/generate.dart <loại> <tên> [<prefix>] [<SM>] [<route>]
# <loại>: 1=Feature, 2=Domain, 3=Data, 4=Core, 5=Custom
# <prefix> (chỉ Custom): tiền tố tên package -> <prefix>_<tên> tại platform/<tên>; loại khác truyền ""
# <SM> (chỉ Feature): 1=Provider, 2=BLoC, 3=None
# <route> (chỉ Feature): 1=IFeatureRouteModule, 2=INavDestinationModule (tab Bottom Nav), 3=none
# Chon 2 chi khi feature la tab chinh sau login - xem docs/{en,vi}/guides/04_routing.md.

# Feature 'profile' + Provider + stack routes (IFeatureRouteModule):
dart tools/module_generator/generate.dart 1 profile "" 1 1

# Feature 'chat' + BLoC + tab Bottom Nav (INavDestinationModule):
dart tools/module_generator/generate.dart 1 chat "" 2 2

# Domain micro-package 'payment':
dart tools/module_generator/generate.dart 2 payment

# Data micro-package 'payment':
dart tools/module_generator/generate.dart 3 payment

# Core package 'logging':
dart tools/module_generator/generate.dart 4 logging

# Custom package 'billing' với tiền tố 'acme' (acme_billing tại platform/billing):
dart tools/module_generator/generate.dart 5 billing acme

# Interactive (không tham số, cần terminal):
dart tools/module_generator/generate.dart

# Xem cú pháp:
dart tools/module_generator/generate.dart --help
```

CLI thêm module vào mọi `app_manifest.yaml`, scaffold stub DI route, rồi **tự chạy**
`dart tools/composer/composer.dart sync` (sinh lại workspace list, dependency của app và
`injection.dart`), `dependency_sync`, `flutter pub get`, `gen-l10n`, barrel generator,
`build_runner`, barrel generator lần nữa (để export cả file sinh ra), và `dart fix --apply`.
Không cần chạy composer sync bằng tay.
**Không** cần (và **không** nên) sửa list `$…Route` trong `app_router.dart` — host thu thập bằng DI.

Tham số được kiểm tra **trước** khi ghi bất cứ thứ gì (lỗi → exit 64 kèm usage):
- `<name>` (và `<prefix>`) phải là tên package Dart hợp lệ: chữ thường, số, `_`, bắt đầu bằng chữ cái, không phải từ khoá Dart (`Bad-Name` bị từ chối ngay).
- `<SM>` và `<route>` chỉ nhận `1`/`2`/`3`; `<prefix>`, `<SM>`, `<route>` truyền cho sai loại module bị từ chối; cờ lạ bị từ chối.
- Feature thiếu `<SM>` hoặc `<route>` thì hỏi giá trị còn thiếu trên terminal (bỏ trống = `1`); không có terminal (hoặc stdin hết) thì báo lỗi thay vì lặng lẽ lấy mặc định.
- Việc ghép vào `app_manifest.yaml` đọc manifest bằng YAML (không so chuỗi con — `core_net` không còn bị coi là "đã có" vì `core_network`); nếu không ghép được vào manifest nào thì exit 1 và rollback.

### 📦 Barrel Files Generator
```bash
# Sinh cho 1 package cụ thể:
dart tools/barrel_generator/generate.dart modules/profile/feature/lib

# Sinh cho domain micro-package:
dart tools/barrel_generator/generate.dart modules/auth/domain/lib

# Xem cú pháp:
dart tools/barrel_generator/generate.dart --help
```

Chạy **sau** `gen-l10n` / `build_runner`: barrel export cả file sinh ra đang có trên đĩa.
`dart format` chạy qua toolchain của repo (FVM nếu có); format thất bại → exit 1.

### 📦 Dependency Sync (Version Catalog)
```bash
# Đồng bộ version từ pubspec_dependencies.yaml xuống tất cả packages:
dart tools/dependency_sync.dart

# Chỉ kiểm tra xung đột (không ghi đè) — phù hợp CI/pre-commit:
dart tools/dependency_sync.dart --check
```

### 🔄 Outdated Dependencies Checker
```bash
# Kiểm tra phiên bản thư viện đã lỗi thời trên pub.dev:
dart tools/check_outdated.dart
```

Exit khác 0 khi `pub get`, `pub outdated`, đọc JSON, hay bước áp dụng cập nhật thất bại.
Không có terminal thì chỉ báo cáo, không sửa catalog.

### 🤖 Code Review (AI-Powered)
```bash
# Review toàn bộ files:
dart tools/code_review/code_review.dart --all

# Review file cụ thể:
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart

# Review files đã thay đổi:
dart tools/code_review/code_review.dart --changed

# Focus vào architecture + security:
dart tools/code_review/code_review.dart --all --focus architecture,security

# Báo cáo tiếng Việt cho lần chạy này (không ghi vào code_review_config.json):
dart tools/code_review/code_review.dart --all --language vi
```

File sinh tự động (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`,
`lib/src/gen/**`, `firebase_options_*.dart`), test và file bị git ignore luôn bị loại.
Báo cáo luôn là Markdown; `--format` chỉ nhận `markdown`. Key lấy tại
https://aistudio.google.com/app/apikey. Chi tiết: [`code_review/README.md`](code_review/README.md).

### 🧹 Unused Checker (Dọn Dẹp)
```bash
# Chạy tất cả kiểm tra (khuyên dùng):
dart tools/unused_checker/check_script.dart

# Hoặc chạy riêng từng loại:
dart tools/unused_checker/check_unused_assets.dart
dart tools/unused_checker/check_unused_packages.dart
dart tools/unused_checker/check_unused_translate.dart
dart tools/unused_checker/check_unused_file.dart
```

### ⚙️ Workspace Setup & Config
```bash
# Thiết lập workspace:
dart tools/workspace_setup/configure.dart   # đa nền tảng

# Firebase config (ghi vào apps/<id>/lib/firebase/, ios/, android/ của app đó):
dart tools/firebase/firebase_config.dart --app mobile

# Theme (splash + icons):
dart tools/theme_generator/theme_setting.dart --app mobile

# Workspace chỉ có một app thì bỏ được --app. Cả hai tool đều có --help.
```

- `firebase_config.dart` chạy tương tác (cần terminal) và cần Firebase CLI đã cài
  (`npm install -g firebase-tools`) và đã `firebase login` — tool **không** tự cài CLI nữa;
  thiếu CLI thì in hướng dẫn cài và exit 1, chưa login thì thử `firebase login` tối đa 2 lần
  rồi exit 1.
- `theme_setting.dart` cần `android/` và `ios/` trong app, và `flutter_native_splash` +
  `icons_launcher` trong `pubspec.yaml` của app — thiếu thì báo lỗi trước khi ghi gì
  (`--app admin` hiện bị từ chối vì admin chưa có thư mục nền tảng). Generator thất bại thì
  mọi file nó tạo/sửa dưới `android/`, `ios/`, `web/` được khôi phục.

### 📱 Android 16KB Page Size
```bash
# Build APK release của một flavor rồi kiểm tra (từ thư mục gốc):
./tools/android_compliance/16kb_ckeck.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk   # macOS/Linux
.\tools\android_compliance\16kb_ckeck.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

---

## 🔑 Prerequisites

- **Dart SDK**: >= 3.13.3
- **Flutter SDK**: >= 3.47.4
- **Ruby**: >= 3.0 (cho Fastlane, chỉ cần khi build CI/CD)
- **Gemini API Key**: Chỉ cần cho Code Review Tool
- **Firebase CLI** (`npm install -g firebase-tools`, đã `firebase login`): Chỉ cần cho `firebase_config.dart`

---

## 💡 Best Practices

### Workflow Tạo Module Mới:
```bash
# 1. Tạo domain + data micro-packages:
dart tools/module_generator/generate.dart 2 payment
dart tools/module_generator/generate.dart 3 payment

# 2. Triển khai code (Entities → Repository Interfaces → UseCases → Models → DataSources → RepositoryImpl)

# 3. Sinh mã DI / Freezed / JSON:
dart run build_runner build --workspace

# 4. Sinh barrel files — SAU build_runner, vì barrel export cả file sinh ra:
dart tools/barrel_generator/generate.dart modules/payment/domain/lib
dart tools/barrel_generator/generate.dart modules/payment/data/lib
```

### Workflow Dọn Dẹp Định Kỳ:
```bash
# 1. Kiểm tra tài nguyên dư thừa:
dart tools/unused_checker/check_script.dart

# 2. Kiểm tra thư viện lỗi thời:
dart tools/check_outdated.dart

# 3. Đồng bộ version:
dart tools/dependency_sync.dart
```

---

**Built with ❤️ for Flutter Clean Architecture Development**