🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# 🛠️ Development Tools

Thư mục này chứa các công cụ CLI dành cho lập trình viên, hỗ trợ tự động hóa quy trình phát triển và duy trì chất lượng mã nguồn cho Flutter Clean Architecture Monorepo. `tools/` là một thành viên workspace (package `core_tools`, xem `tools/pubspec.yaml`), nên sau `flutter pub get` ở gốc là chạy được mọi tool. **Luôn chạy từ thư mục gốc của repo.**

Tham chiếu đầy đủ (tham số, mã thoát, chế độ lỗi của từng tool): [`docs/vi/reference/03_tooling.md`](../docs/vi/reference/03_tooling.md).

> **Quy tắc**: Tất cả CLI Tools trong thư mục này **CẤM** sử dụng `print()`. Bắt buộc dùng `stdout.writeln()` và `stderr.writeln()`. Tool nào gọi `dart` / `flutter` thì phát hiện FVM qua `tools/shared/toolchain.dart` — không hardcode tiền tố `fvm`.

---

## 📁 Directory Structure

```text
tools/
├── pubspec.yaml                     # Package core_tools (thành viên workspace)
├── arch_check/                      # 🛡️ Cưỡng chế luật phân tầng (Gate 1 của CI)
│   └── check.dart                   # R1-R10: hướng phụ thuộc, domain thuần Dart, ranh giới feature, scale qua context…
├── composer/                        # 🧩 Ghép app từ app_manifest.yaml (Gate 0 của CI)
│   ├── composer.dart                # sync / verify / list — sinh workspace list, dependency của app, injection.dart
│   └── bootstrap.dart               # Checkout từng phần: bỏ member vắng mặt để `pub get` resolve được (không import package)
├── docs_check/                      # 📚 Mọi đường dẫn docs nhắc tới phải tồn tại (Gate 5 của CI)
│   ├── check.dart
│   ├── parity.dart                  # Tương đương en <-> vi: heading từng cấp, code block, dòng bảng
│   ├── allowlist.txt                # Đường dẫn vắng mặt có chủ đích, kèm lý do
│   └── parity_allowlist.txt         # Chênh lệch hình dạng en/vi có chủ đích, kèm lý do
├── shared/                          # 🔗 Code dùng chung giữa các tool
│   ├── app_locator.dart             # Tìm app qua app_manifest.yaml, chọn app bằng --app <id>
│   └── toolchain.dart               # Phát hiện FVM (.fvmrc + `fvm --version`) cho mọi tool gọi dart/flutter
├── sample_cleanup/                  # 🧹 Phân loại và gỡ code mẫu an toàn
│   └── remove_sample.dart           # --list / dry-run / --apply, có rollback
├── sample_manifest.yaml             # 📑 Nguồn chân lý: package nào là sample/framework/shell
├── module_generator/                # 🏗️ CLI tạo module mới (Feature/Domain/Data/Core/Custom)
│   ├── generate.dart                # Entry point chính
│   ├── src/
│   │   ├── input_actions.dart       # Xử lý tham số CLI & interactive input, kiểm tra tên
│   │   ├── module_type.dart         # Enum ModuleType, StateManagementType, FeatureRouteContribution; ModuleConfig
│   │   ├── pubspec_generator.dart   # Sinh pubspec.yaml với dependencies đúng tầng
│   │   └── common_helpers.dart      # Tạo thư mục/template, ghi app_manifest.yaml, chạy lệnh, rollback
│   └── templates/                   # Template mustache (common, domain, data, feature/{bloc,provider,default,routing,localization,test})
├── barrel_generator/                # 📦 Sinh barrel files (export *.dart)
│   └── generate.dart                # Quét lib/ và tạo file barrel tự động
├── code_review/                     # 🤖 AI-powered code review (Gemini)
│   ├── code_review.dart             # Entry point
│   ├── lib/                         # Phần lõi của tool
│   ├── review_prompt.md             # Prompt AI chi tiết
│   ├── code_review_config.json      # Cấu hình (ngôn ngữ, batch) — không chứa API key
│   └── README.md                    # Tài liệu chi tiết (README.vi.md: tiếng Việt)
├── unused_checker/                  # 🧹 Phân tích & dọn dẹp tài nguyên dư thừa
│   ├── check_script.dart            # Chạy tất cả kiểm tra cùng lúc
│   ├── check_unused_assets.dart     # Phát hiện assets không sử dụng
│   ├── check_unused_file.dart       # Phát hiện files mồ côi
│   ├── check_unused_packages.dart   # Phát hiện packages khai báo mà không dùng
│   ├── check_unused_translate.dart  # Phát hiện translation keys dư thừa
│   ├── monorepo_helper.dart         # Dùng chung: tìm gốc repo, liệt kê package
│   └── output_formatter.dart        # Dùng chung: định dạng kết quả
├── workspace_setup/                 # ⚙️ Thiết lập workspace tổng
│   ├── configure.dart               # Script đa nền tảng (Windows/macOS/Linux)
│   └── firebase_stubs.dart          # --stub-firebase: Firebase options + google-services.json chỉ để compile (chỉ dart:io)
├── coverage_report/                 # 📊 Line coverage từng package từ lcov.info (CI Gate 3, tham khảo)
│   └── report.dart
├── test/                            # ✅ Test riêng của các tool (`cd tools && dart test`, CI Gate 1)
├── firebase/                        # 🔥 Cấu hình Firebase đa môi trường
│   └── firebase_config.dart
├── theme_generator/                 # 🎨 Sinh Splash Screen & App Icons
│   └── theme_setting.dart
├── android_compliance/              # 📱 Kiểm tra Android 15+ 16KB Page Size
│   ├── 16kb_ckeck.sh                # macOS/Linux (file thực thi)
│   └── 16kb_ckeck.bat               # Windows — gọi .sh qua Git Bash
├── dependency_sync.dart             # 📦 Đồng bộ version thư viện từ catalog (Gate 4 với --check)
└── check_outdated.dart              # 🔄 Kiểm tra thư viện lỗi thời trên pub.dev
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

Chạy trước `flutter analyze` trong CI: nó chỉ đọc import và pubspec, không cần codegen, nên
xong trong vài trăm ms (tool tự in thời gian chạy), và là thứ duy nhất nhìn thấy được phân tầng —
`analysis_options.yaml` không biết rằng core không được import feature. Tham số khác `--help`
bị từ chối (exit 64).

R7 cũng nằm ngoài tầm của analyzer. `core_responsive` không cung cấp extension nào trên
`num`, nên `16.h` không compile được — nhưng một extension sót lại từ package khác, hoặc do
ai đó tự thêm, vẫn qua được type-check trong khi đọc một biến global không báo cho ai. Chỉ
`context.h(16)` mới đăng ký dependency `InheritedWidget` và rebuild khi metrics đổi.

### 🧩 Composer (Ghép app từ manifest)
```bash
# Sinh lại workspace list, dependency của app và injection.dart từ mọi app_manifest.yaml:
dart tools/composer/composer.dart sync

# Chỉ kiểm tra (CI Gate 0) — exit 1 nếu lệch, không ghi gì; ngầm bật --strict:
dart tools/composer/composer.dart verify

# Xem app ghép những gì (--app lọc một app, dùng được cho cả list/sync/verify):
dart tools/composer/composer.dart list --app admin
```

Chỉ vùng giữa marker `composer:managed` và `composer:end` được sinh; phần còn lại của các file
đó vẫn viết tay. `--strict` biến module khai báo trong manifest mà vắng trên đĩa thành lỗi thay vì
cảnh báo. Lệnh/cờ lạ bị từ chối (exit 64). Một pubspec/manifest không phải YAML hợp lệ (thường là
key trùng) bị từ chối với tên file và dòng lỗi thay vì crash; một package vừa nằm trong vùng
`composer:managed:deps` vừa được khai báo tay thì có thông báo riêng. Manifest sai cấu trúc
(`phase` khác `before`/`after`, layer lạ, id trùng, key lạ, …) bị từ chối trước mọi lệnh với
`apps/<id>/app_manifest.yaml: <key>: <vấn đề>`, exit 1, không ghi gì. Khi một module khai báo
trong manifest không có trên đĩa, cảnh báo PARTIAL COMPOSITION chỉ liệt kê file thực sự bị
ghi lại trong lần chạy đó.

```bash
# Checkout từng phần (một submodule module chưa init): composer cần workspace đã resolve, còn pub
# từ chối workspace có member không có pubspec.yaml. Tool này không import package nên chạy trước:
dart tools/composer/bootstrap.dart            # --dry-run để chỉ báo cáo
flutter pub get
dart tools/composer/composer.dart sync
dart tools/workspace_setup/configure.dart
```

`bootstrap` chỉ xoá bớt — trong vùng `composer:managed:workspace` ở root và vùng
`composer:managed:deps` của từng app — những mục mà thư mục không có `pubspec.yaml`, và in dòng
`git checkout --` để hoàn tác. Checkout đầy đủ thì không có gì để bỏ (exit 0, không ghi gì). Exit 1,
không ghi gì, khi một package đang có khai path dependency viết tay tới một package vắng mặt — hãy
init thêm submodule đó. Xem `docs/vi/guides/12_module_isolation.md` § 3.

### 📚 Docs Check (Đường dẫn trong tài liệu)
```bash
# Mọi đường dẫn repo mà một file Markdown nhắc tới phải tồn tại — CI Gate 5:
dart tools/docs_check/check.dart

# Kèm khối allowlist copy-paste được cho các tham chiếu chết:
dart tools/docs_check/check.dart --verbose
```

Cùng lần chạy đó kiểm tra **tương đương en ↔ vi**: mọi `docs/en/**.md` có bản `docs/vi` tương
ứng, và mọi `<name>.md` có `<name>.vi.md` nằm cạnh, phải có cùng số heading ở mỗi cấp, số code
block và số dòng bảng ở cả hai ngôn ngữ. Chênh lệch thì exit 1 kèm cả hai con số; chênh lệch có
chủ đích ghi vào `tools/docs_check/parity_allowlist.txt` dạng `<english file> <metric>` kèm lý do.

Kiểm tra mọi file `*.md` trong repo: span trong backtick bắt đầu bằng một thư mục cấp gốc có
thật, và link Markdown (tính tương đối từ file chứa nó). Đường dẫn vắng mặt có chủ đích (file
sinh ra, secret, "tự tạo file này") nằm trong `tools/docs_check/allowlist.txt` kèm lý do.
Exit 1 khi có tham chiếu chết không giải thích được, 64 khi gặp tham số lạ.

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
mọi `*.md`) tới đường dẫn sắp bị xoá. Chúng chỉ mang tính thông tin: sau khi gỡ,
`dart tools/docs_check/check.dart` (CI Gate 5) nhận ra chúng trỏ vào một sample bundle đã gỡ
(mọi package của bundle vắng mặt, theo `tools/sample_manifest.yaml` — tool gỡ không bao giờ sửa
file này), in một dòng INFO cho mỗi bundle và vẫn đạt. Sửa các tài liệu đó lúc nào tiện.
Cờ lạ (ví dụ `--aply`) hay tên bundle sai bị từ chối với exit 64 thay vì bị bỏ qua.
Bundle: `auth`, `home`, `settings`, `onboarding`, `cache`, `dashboard`, `splash`.


### 🏗️ Module Generator (Tạo Module Mới)
```bash
# Cú pháp: dart tools/module_generator/generate.dart <loại> <tên> [<prefix>] [<SM>] [<route>] [--group <nhóm>] [--apps <id,id>]
# <loại>: 1=Feature, 2=Domain, 3=Data, 4=Core (core_<tên>), 5=Custom
# <prefix> (chỉ Custom): tiền tố tên package -> <prefix>_<tên> tại platform/<nhóm>/<tên>; loại khác truyền ""
# <SM> (chỉ Feature): 1=Provider, 2=BLoC, 3=None
# <route> (chỉ Feature): 1=IFeatureRouteModule, 2=INavDestinationModule (tab điều hướng chính), 3=none
# --group (chỉ Core/Custom): foundation|layers|infra|ui|state|shell — thư mục nhóm trong platform/; mặc định infra
# Chỉ chọn 2 khi feature là tab chính sau đăng nhập — xem docs/{en,vi}/guides/04_routing.md.

# Feature 'profile' + Provider + stack routes (IFeatureRouteModule):
dart tools/module_generator/generate.dart 1 profile "" 1 1

# Feature 'chat' + BLoC + tab điều hướng chính (INavDestinationModule):
dart tools/module_generator/generate.dart 1 chat "" 2 2

# Domain micro-package 'payment':
dart tools/module_generator/generate.dart 2 payment

# Data micro-package 'payment':
dart tools/module_generator/generate.dart 3 payment

# Core package 'logging' (core_logging tại platform/infra/logging):
dart tools/module_generator/generate.dart 4 logging

# Core package 'charts' trong nhóm ui (core_charts tại platform/ui/charts):
dart tools/module_generator/generate.dart 4 charts --group ui

# Custom package 'billing' với tiền tố 'acme' (acme_billing tại platform/infra/billing):
dart tools/module_generator/generate.dart 5 billing acme

# Interactive (không tham số, cần terminal):
dart tools/module_generator/generate.dart

# Chỉ một số app: compose vào mobile, không đụng admin (id = app.id trong apps/*/app_manifest.yaml):
dart tools/module_generator/generate.dart 1 chat "" 2 2 --apps mobile

# Xem cú pháp:
dart tools/module_generator/generate.dart --help
```

CLI thêm module vào mọi `app_manifest.yaml` (hoặc chỉ các app mà `--apps` nêu tên) (Feature/Domain/Data vào danh sách `modules:`,
Core/Custom vào nhóm DI `core`), scaffold stub DI route, rồi **tự chạy**
`dart tools/composer/composer.dart sync` (sinh lại workspace list, dependency của app và
`injection.dart`), `dependency_sync`, `flutter pub get`, `gen-l10n` (chỉ với Feature), barrel
generator, `build_runner`, barrel generator lần nữa (để export cả file sinh ra), và
`dart fix --apply`. Không cần chạy composer sync bằng tay.
**Không** cần (và **không** nên) sửa list `$…Route` trong `app_router.dart` — host thu thập bằng DI.
Có lỗi giữa chừng thì tool rollback và exit 1.

Tham số được kiểm tra **trước** khi ghi bất cứ thứ gì (lỗi → exit 64 kèm usage):
- `<name>` (và `<prefix>`) phải là tên package Dart hợp lệ: chữ thường, số, `_`, bắt đầu bằng chữ cái, không phải từ khoá Dart (`Bad-Name` bị từ chối ngay); tên package đã có trong repo cũng bị từ chối.
- `<SM>` và `<route>` chỉ nhận `1`/`2`/`3`; `<prefix>`, `<SM>`, `<route>` truyền cho sai loại module bị từ chối; cờ lạ bị từ chối.
- `--apps` phải nêu ít nhất một id app có thật; id lạ (hoặc giá trị rỗng, hoặc truyền cờ hai lần) bị từ chối và các id có thật được liệt kê.
- Feature thiếu `<SM>` hoặc `<route>` thì hỏi giá trị còn thiếu trên terminal (bỏ trống = `1`); không có terminal (hoặc stdin hết) thì báo lỗi thay vì lặng lẽ lấy mặc định.
- Việc ghép vào `app_manifest.yaml` đọc manifest bằng YAML (không so chuỗi con — `core_net` không còn bị coi là "đã có" vì `core_network`); nếu không ghép được vào manifest nào thì exit 1 và rollback.

Feature khởi đầu với các test pass ngay khi sinh: `test/<name>_page_test.dart` (page dưới
`ResponsiveInit` và localization của nó, controller được cung cấp đúng như route cung cấp) cộng
`test/<name>_provider_test.dart` hoặc `test/<name>_bloc_test.dart` (không có với SM `3`).

### 📦 Barrel Files Generator
```bash
# Sinh cho 1 package cụ thể:
dart tools/barrel_generator/generate.dart modules/profile/feature/lib

# Sinh cho domain micro-package:
dart tools/barrel_generator/generate.dart modules/auth/domain/lib

# Xem cú pháp:
dart tools/barrel_generator/generate.dart --help
```

Không truyền đường dẫn thì dùng `lib`. Chạy **sau** `gen-l10n` / `build_runner`: barrel export cả
file sinh ra đang có trên đĩa. Dòng `export` viết tay trong barrel bị thay thế. `dart format` chạy
qua toolchain của repo (FVM nếu có). Exit 64 khi đường dẫn không tồn tại (chỉ hỏi lại đường dẫn khi
chạy không tham số trên terminal) hoặc gặp cờ lạ, 1 khi sinh hoặc format thất bại.

### 📦 Dependency Sync (Version Catalog)
```bash
# Đồng bộ version từ pubspec_dependencies.yaml xuống tất cả packages, rồi pub get:
dart tools/dependency_sync.dart

# Chỉ báo cáo lệch (không ghi) — exit 1 nếu có; CI Gate 4 / pre-commit:
dart tools/dependency_sync.dart --check
```

### 🔄 Outdated Dependencies Checker
```bash
# Kiểm tra phiên bản thư viện đã lỗi thời trên pub.dev:
dart tools/check_outdated.dart
```

Resolve mọi package của catalog trong một sandbox, chạy `pub outdated`, rồi (trên terminal) đưa
checklist để nâng version trong catalog và chạy lại `dependency_sync` + `pub get`. Không có
terminal thì chỉ báo cáo, không sửa catalog. Exit khác 0 khi resolve, `pub outdated` hay bước áp
dụng cập nhật thất bại.

### 🤖 Code Review (AI-Powered)
```bash
# Review toàn bộ files (mọi lib/ dưới apps/, modules/, platform/):
dart tools/code_review/code_review.dart --all

# Review file cụ thể:
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart

# Review các thay đổi chưa commit (git diff HEAD):
dart tools/code_review/code_review.dart --changed

# Focus vào architecture + security:
dart tools/code_review/code_review.dart --all --focus architecture,security

# Báo cáo tiếng Việt cho lần chạy này (không ghi vào code_review_config.json):
dart tools/code_review/code_review.dart --all --language vi
```

File sinh tự động (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`,
`*.mocks.dart`, mọi thứ dưới `gen/` / `generated/`, `firebase_options_*.dart`), test và file bị
git ignore luôn bị loại. Báo cáo luôn là Markdown; `--format` chỉ nhận `markdown`. API key:
`--api-key`, biến `GEMINI_API_KEY`, hoặc file `tools/code_review/.gemini_api_key` (gitignored);
lấy key tại https://aistudio.google.com/app/apikey. Chi tiết:
[`code_review/README.vi.md`](code_review/README.vi.md).

### 🧹 Unused Checker (Dọn Dẹp)
```bash
# Chạy tất cả kiểm tra (khuyên dùng) — exit 1 nếu một kiểm tra thất bại:
dart tools/unused_checker/check_script.dart

# Hoặc chạy riêng từng loại (mỗi script có --help):
dart tools/unused_checker/check_unused_assets.dart
dart tools/unused_checker/check_unused_packages.dart
dart tools/unused_checker/check_unused_translate.dart
dart tools/unused_checker/check_unused_file.dart
```

Kết quả chỉ là gợi ý: có code mẫu và scaffolding cố ý chưa dùng. `check_unused_packages.dart`
chạy trong CI dưới dạng tham khảo (không chặn merge). Gỡ một sample thì dùng `remove_sample.dart`,
không dựa vào lời của `unused_checker`.

### ⚙️ Workspace Setup & Config
```bash
# Thiết lập workspace (bước setup trên một bản clone mới):
dart tools/workspace_setup/configure.dart   # đa nền tảng
# ...kèm stub Firebase chỉ để compile ở nơi chưa có file thật (chưa có project Firebase; CI chạy đúng lệnh này):
dart tools/workspace_setup/configure.dart --stub-firebase

# Firebase config (ghi vào apps/<id>/lib/firebase/, ios/, android/ của app đó):
dart tools/firebase/firebase_config.dart --app mobile

# Theme (splash + icons):
dart tools/theme_generator/theme_setting.dart --app mobile

# Workspace hiện có hai app (mobile, admin) nên --app là bắt buộc. Cả hai tool đều có --help.
```

- `configure.dart` chạy theo thứ tự: `dart pub global activate flutterfire_cli` →
  `flutter clean` → `flutter pub get` → `flutter gen-l10n` ở mọi package có `l10n.yaml` →
  `dart run build_runner build --workspace` → barrel generator cho mọi package có `lib/` (bỏ qua
  app). Dừng ở lệnh lỗi đầu tiên với đúng exit code của nó.
  `--stub-firebase` ghi thêm — đầu tiên, trước codegen, và liệt kê ở cuối — **chỉ khi chưa có**, một `firebase_options_<flavor>.dart` cho mỗi
  flavor của mọi app có `lib/firebase/firebase_module.dart` và một
  `android/app/src/<flavor>/google-services.json` cho mỗi flavor Gradle (package name đọc từ
  `build.gradle.kts`). Chúng giúp app compile và build được; mọi thứ dựa trên Firebase đều không chạy.
- `firebase_config.dart` chạy tương tác (cần terminal) và cần Firebase CLI đã cài
  (`npm install -g firebase-tools`) và đã `firebase login` — tool **không** tự cài Firebase CLI
  (FlutterFire CLI thì được tự cài qua `dart pub global activate` nếu thiếu); thiếu Firebase CLI
  thì in hướng dẫn cài và exit 1, chưa login thì thử `firebase login` tối đa 2 lần rồi exit 1.
- `theme_setting.dart` dùng các file `flutter_native_splash-<flavor>.yaml` /
  `icons_launcher-<flavor>.yaml` ở gốc repo, cần `android/` và `ios/` trong app, và
  `flutter_native_splash` + `icons_launcher` trong `pubspec.yaml` của app — thiếu thì báo lỗi
  trước khi ghi gì (`--app admin` hiện bị từ chối vì admin chưa có thư mục nền tảng). Generator
  thất bại thì mọi file nó tạo/sửa dưới `android/`, `ios/`, `web/` được khôi phục.

### 📊 Coverage Report
```bash
# Sau `flutter test --coverage` trong từng package — bảng theo package, kèm dòng tổng:
dart tools/coverage_report/report.dart
# Biến thành gate: tổng dưới 60 %, hoặc bất kỳ package nào dưới 40 %, thì exit 1:
dart tools/coverage_report/report.dart --min 60 --min-package 40
```

Đọc mọi `*/coverage/lcov.info`, loại file sinh ra (`*.g.dart`, `*.freezed.dart`, `*.config.dart`,
`*.module.dart`, `gen/`, …) và nối bảng vào `$GITHUB_STEP_SUMMARY` khi chạy trên GitHub Actions.
CI Gate 3 chạy nó sau các test, chỉ để tham khảo (không ngưỡng).

### 📱 Android 16KB Page Size
```bash
# Build APK release của một flavor rồi kiểm tra (từ thư mục gốc):
./tools/android_compliance/16kb_ckeck.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk   # macOS/Linux
.\tools\android_compliance\16kb_ckeck.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

Tham số có thể là một APK, một APEX hoặc một thư mục chứa thư viện native. Bản `.bat` chỉ tìm
Git Bash rồi gọi file `.sh`.

---

## 🔑 Prerequisites

- **Dart SDK**: >= 3.13.3
- **Flutter SDK**: >= 3.47.4 (`.fvmrc` ghim `3.47.4`; FVM là tùy chọn)
- **Ruby**: >= 3.0 (cho Fastlane, chỉ cần khi build CI/CD)
- **Gemini API Key**: Chỉ cần cho Code Review Tool
- **Firebase CLI** (`npm install -g firebase-tools`, đã `firebase login`): Chỉ cần cho `firebase_config.dart`

---

## 💡 Best Practices

### Workflow Tạo Module Mới:
```bash
# 1. Tạo domain + data micro-packages (generator tự chạy composer sync, build_runner, barrel):
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
