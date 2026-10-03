🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# 🛠️ Development Tools

Thư mục này chứa các công cụ CLI dành cho lập trình viên, hỗ trợ tự động hóa quy trình phát triển và duy trì chất lượng mã nguồn cho Flutter Clean Architecture Monorepo. `tools/` là một thành viên workspace (package `core_tools`, xem `tools/pubspec.yaml`), nên sau `flutter pub get` ở gốc là chạy được mọi tool. **Luôn chạy từ thư mục gốc của repo.**

Tra cứu một trang (lệnh, mục đích, mã thoát, CI gate): [`docs/vi/reference/03_tooling.md`](../docs/vi/reference/03_tooling.md). Chi tiết đầy đủ của từng tool — tham số, trường hợp bị từ chối, chế độ lỗi — nằm ở [§ Tham chiếu đầy đủ](#-tham-chiếu-đầy-đủ-từng-tool) bên dưới.

> **Quy tắc**: Tất cả CLI Tools trong thư mục này **CẤM** sử dụng `print()`. Bắt buộc dùng `stdout.writeln()` và `stderr.writeln()`. Tool nào gọi `dart` / `flutter` thì phát hiện FVM qua `tools/shared/toolchain.dart` — không hardcode tiền tố `fvm`.

---

## 📁 Directory Structure

```text
tools/
├── pubspec.yaml                     # Package core_tools (thành viên workspace)
├── arch_check/                      # 🛡️ Cưỡng chế luật phân tầng (Gate 1 của CI)
│   ├── check.dart                   # R1-R20: hướng phụ thuộc, domain thuần Dart, ranh giới feature, scale qua context, catalog của shell, nhánh theo platform, handler Bloc async, không ghi console, không số layout thô…
│   ├── source_rules.dart            # Các phép quét chữ đứng sau R8 (lookup ném lỗi), R18 (handler `on<>`), R19 (`print`) và R20 (số layout thô)
│   └── platform_forks.dart          # Danh sách cho phép của R17 (mỗi mục kèm lý do) và phép quét nhánh theo platform
├── composer/                        # 🧩 Ghép app từ app_manifest.yaml (Gate 0 của CI)
│   ├── composer.dart                # sync / verify / list / describe / new — sinh workspace list, dependency của app, injection.dart, facts, report; tạo một app
│   ├── src/                         # manifest_v2 (schema), catalog, package_facts, provisions, facts_emit, report, checks (V3, V7, V8, V10-V12…), platform_notes, new_app
│   ├── app_template/                # File Mustache mà `composer new` render vào apps/<id>/ (manifest, pubspec, README, lib/, test/, env.dev)
│   └── bootstrap.dart               # Checkout từng phần: bỏ member vắng mặt để `pub get` resolve được (không import package)
├── docs_check/                      # 📚 Mọi đường dẫn docs nhắc tới phải tồn tại (Gate 5 của CI)
│   ├── check.dart
│   ├── parity.dart                  # Tương đương en <-> vi: heading từng cấp, code block, dòng bảng
│   ├── allowlist.txt                # Đường dẫn vắng mặt có chủ đích, kèm lý do
│   └── parity_allowlist.txt         # Chênh lệch hình dạng en/vi có chủ đích, kèm lý do
├── shared/                          # 🔗 Code dùng chung giữa các tool
│   ├── app_locator.dart             # Tìm app qua app_manifest.yaml, chọn app bằng --app <id>
│   ├── contract_scan.dart           # Đọc tĩnh các contract DI: nơi hiện thực (R8) và đăng ký đúng type (R16, V3, V10) — một bộ quét cho arch_check và composer
│   ├── toolchain.dart               # Phát hiện FVM (.fvmrc + `fvm --version`) cho mọi tool gọi dart/flutter
│   └── workspace.dart               # Phép duyệt khám phá dùng chung (pubspec, app manifest, lcov) và tập thư mục bỏ qua
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
│   ├── 16kb_check.sh                # macOS/Linux (file thực thi)
│   └── 16kb_check.bat               # Windows — gọi .sh qua Git Bash
├── dependency_sync.dart             # 📦 Đồng bộ version thư viện từ catalog (Gate 4 với --check)
└── check_outdated.dart              # 🔄 Kiểm tra thư viện lỗi thời trên pub.dev
```

---

## 🚀 Quick Usage

### 🛡️ Architecture Check (Cưỡng chế luật phân tầng)
```bash
# Kiểm tra 20 luật kiến trúc (R1–R20) — exit 1 nếu có vi phạm (dùng được cho CI):
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

# Một app khai gì và shell resolve gì từ nó, và mọi key của manifest:
dart tools/composer/composer.dart describe --app admin
dart tools/composer/composer.dart describe --catalog

# App thứ ba, bằng một lệnh (không bao giờ chạy flutter create — nó in dòng lệnh):
dart tools/composer/composer.dart new reports --name "Codebase Reports" --platforms web,windows --modules auth,settings
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
Trường hợp ngược lại — một thư mục package dưới `modules/` hoặc `platform/` mà không app nào lắp
ráp (còn sót lại sau khi module bị gỡ khỏi mọi manifest) — làm `verify` fail và chỉ là cảnh báo
khi `sync`, kèm tên thư mục và cách sửa: xoá nó, hoặc thêm lại vào một manifest.

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
init thêm submodule đó. Xem `docs/vi/guides/12_module_isolation.md` § 2.

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

`--apply` còn sửa khối `capabilities:` trong `app_manifest.yaml` của mỗi app: contract mà bundle là
nơi cung cấp duy nhất (`capabilities:` trong bundle, ví dụ `splash` cho sample splash) chuyển từ
`provided` sang `{ state: absent, reason: "sample <bundle> removed" }`, để `composer verify` vẫn
xanh: `--apply` tự chạy `composer sync` (khi workspace có composer) để các vùng sinh ra theo kịp manifest, và thoát mã `1` kèm lý do của composer nếu nó từ chối. Các contract bundle dùng chung với module khác (`shared_capabilities:`)
được nêu trong các bước tiếp theo; DI smoke test của app sẽ chỉ ra contract nào mất nơi cung cấp cuối cùng.

Cả dry-run lẫn `--apply` đều đếm các tham chiếu trong tài liệu (`docs/`, `.claude/`,
mọi `*.md`) tới đường dẫn sắp bị xoá. Chúng chỉ mang tính thông tin: sau khi gỡ,
`dart tools/docs_check/check.dart` (CI Gate 5) nhận ra chúng trỏ vào một sample bundle đã gỡ
(mọi package của bundle vắng mặt, theo `tools/sample_manifest.yaml` — tool gỡ không bao giờ sửa
file này), in một dòng INFO cho mỗi bundle và vẫn đạt. Sửa các tài liệu đó lúc nào tiện.
Cờ lạ (ví dụ `--aply`) hay tên bundle sai bị từ chối với exit 64 thay vì bị bỏ qua.
Bundle: `auth`, `home`, `settings`, `onboarding`, `cache`, `dashboard`, `splash`.


### 🏗️ Module Generator (Tạo Module Mới)
```bash
# Cú pháp: dart tools/module_generator/generate.dart <loại> <tên> [<prefix>] [<SM>] [<route>] [--group <nhóm>] [--apps <id,id>]
# <loại>: 1=Feature, 2=Domain, 3=Data, 4=Core (core_<tên>), 5=Custom, 6=API (<tên>_api tại modules/<tên>/api)
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

# Package API của module 'chat' (chat_api: stub ChatNavigator; feature_chat, nếu đã có, sẽ implement nó):
dart tools/module_generator/generate.dart 6 chat

# Interactive (không tham số, cần terminal):
dart tools/module_generator/generate.dart

# Chỉ một số app: compose vào mobile, không đụng admin (id = app.id trong apps/*/app_manifest.yaml):
dart tools/module_generator/generate.dart 1 chat "" 2 2 --apps mobile

# Xem cú pháp:
dart tools/module_generator/generate.dart --help
```

CLI thêm module vào mọi `app_manifest.yaml` (hoặc chỉ các app mà `--apps` nêu tên) (Feature/Domain/Data/API vào danh sách `modules:`,
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
chạy trong CI dưới dạng **chặn** (RULE-06; cây sạch, nên một khai báo không dùng làm PR fail). File không dùng (`check_unused_file.dart`) vẫn chỉ để tham khảo và không chạy trong CI. Gỡ một sample thì dùng `remove_sample.dart`,
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
./tools/android_compliance/16kb_check.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk   # macOS/Linux
.\tools\android_compliance\16kb_check.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

Tham số có thể là một APK, một APEX hoặc một thư mục chứa thư viện native. Bản `.bat` chỉ tìm
Git Bash rồi gọi file `.sh`.

---

## 📖 Tham chiếu đầy đủ, từng tool

Mọi thứ mỗi tool làm, từ chối và in ra — bản đầy đủ của bảng một trang trong [`docs/vi/reference/03_tooling.md`](../docs/vi/reference/03_tooling.md). Mọi tool đều là Dart thuần; chạy chúng từ **thư mục gốc của repo**.

### `arch_check`

Cưỡng chế luật phân tầng bằng máy. **Gate 1 của `pr_quality_check.yml`** — chạy trước `flutter analyze` vì nó chỉ đọc import và `pubspec.yaml`, không cần codegen, xong trong khoảng 200 ms.

```bash
dart tools/arch_check/check.dart          # exit 1 khi có vi phạm chặn
dart tools/arch_check/check.dart --help   # mô tả đầy đủ từng luật
```

Tool không nhận tham số nào khác: bất cứ thứ gì ngoài `--help` (một `--fix`, một lần gõ nhầm `--help`) đều thoát với mã `64` thay vì trông như một lần chạy sạch.

| Luật | Kiểm tra gì |
|---|---|
| R1 | Hướng phụ thuộc — không package nào dưới `platform/` (mọi nhóm; kể cả `data_core` và `domain_core`, nhận diện theo thư mục chứ không theo tên) được import hay khai `feature_*` / `data_*` / `domain_*`, package API của module (`<id>_api`) hay package nào dưới `modules/`, trừ bốn ngoại lệ đã duyệt |
| R2 | Domain thuần Dart — không `flutter` / UI / `go_router` / `provider` / `flutter_bloc` / `dio` / `retrofit` / `drift` / `http`, không package `core_*` / `platform_*` / `data_*` / `feature_*` / `<id>_api` nào, và không plugin Flutter hay package phụ thuộc Flutter SDK, dù import hay khai trong `dependencies:`; chỉ `domain_core` và các package `domain_*` khác |
| R3 | Ranh giới tầng của module (Feature → Domain ← Data), cả trong import **và** `pubspec.yaml` — không feature nào import hay khai feature khác hoặc package `data_*` (`<id>_api` của module khác thì được); không package data nào import hay khai package `feature_*` hoặc `data_*` của module khác (`data_core` và của chính module thì được); package API của module (`modules/<id>/api`) chỉ import và khai `platform/foundation/*` cùng package Flutter/pub |
| R4 | `static const` public phải nằm trong một thư mục `utils/` (file dưới `styles/` — design token của `core_base_ui` — được miễn). Package không có hằng số public thì không cần `utils/` |
| R5 | Mọi `package:` import dùng trong `lib/` phải được khai trong mục `dependencies:` của chính package đó — khai ở `dev_dependencies` không được tính |
| R6 | File generated còn giữ header của generator (chỉ cảnh báo) |
| R7 | Scale responsive phải qua `BuildContext` — cấm receiver trần `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`, trong mọi file Dart viết tay dưới `lib/` của mọi package (không chỉ file có nhắc tới `core_responsive`); comment và chuỗi được xoá trắng trước |
| R8 | Contract của `core_di` hay type của package API được implement dưới `modules/` — ở bất kỳ tầng nào — thì bên ngoài module implement nó phải resolve bằng `getItOrNull` / `getAllOrEmpty`, cấm lookup dạng ném lỗi. Đọc trên mã đã bỏ comment, nên `getIt<T>()`, `getIt.get<T>()`, `getIt.getAll<T>()`, `GetIt.I<T>()`, `GetIt.instance<T>()`, type argument xuống dòng sau và `final T x = getIt();` không kiểu đều tính. Thêm: một class `@injectable` / `@lazySingleton` / `@singleton` nằm ngoài mọi module không được nhận một contract như vậy làm tham số constructor bắt buộc (không nullable, không phải `@factoryParam`) — injectable resolve nó bằng get ném lỗi |
| R9 | `platform_kernel` không import **và không khai** Flutter hay package kéo theo Flutter, thư viện transport (`dio`, `retrofit`, `drift`, `http`), plugin Flutter, hay package nào phụ thuộc Flutter SDK (xác định qua pubspec của workspace và `.dart_tool/package_config.json`) |
| R10 | Không file nào trong một app (`apps/<id>/lib` và `apps/<id>/test`) import module (kể cả package API của nó) — chỉ `lib/**/injection.dart`, điểm lắp ráp, được phép gọi tên một module. (`platform/shell/app_shell` là core nên do R1 phủ) |
| R11 | Chiều giữa các nhóm platform — package `platform/*` nằm ở `platform/<group>/<package>` và `dependencies:` (không tính dev) của nó chỉ gọi tên package platform mà nhóm của nó được chạm tới: `layers/domain` không gì cả; foundation → foundation, `layers/domain`; `layers/data` → foundation, `layers/domain`; infra → foundation, layers; ui → foundation, ui; state → foundation, layers, ui; shell → mọi nhóm |
| R12 | Không PowerShell — không có `*.ps1` nào trong cây làm việc (chính sách thực thi mặc định của Windows chặn script chưa ký); hãy viết script Dart đa nền tảng |
| R13 | Không tắt analyzer — không có comment dòng `// ignore:` / `// ignore_for_file:` trong bất kỳ `.dart` viết tay nào (kể cả `tools/` và `test/`; bỏ qua file sinh `*.g` / `.freezed` / `.config` / `.module` / `.gr` / `.mocks.dart`, `firebase_options_*` và `lib/src/gen/**`). Chữ nằm trong chuỗi hoặc doc comment `///` không bị báo. Thêm nữa: không có `analysis_options.yaml` nào ngoài file ở gốc repo — file cục bộ của package sẽ thay bộ lint chung và có thể tắt luật mà không ai thấy (sửa file gốc vẫn do review giữ) |
| R14 | Thư mục data source là `data_sources/` — không có thư mục nào tên `datasources` (mọi kiểu hoa/thường) dưới `modules/`, `platform/` hay `apps/`, kể cả thư mục rỗng |
| R15 | Tiền tố `I` dành riêng cho interface — dưới `modules/`, `platform/` và `apps/*/lib`, class tên `I[A-Z]…` phải là `abstract`, `interface` hoặc `sealed`; class thường / `base` / `final` hay `mixin class` không abstract đều fail. Class cụ thể bắt đầu bằng từ viết tắt hai chữ (`IOClient`) cũng bị báo |
| R16 | Catalog contract của shell đầy đủ — một contract `core_di` hay của package API module mà package `platform/` resolve bằng `getItOrNull<X>` / `getAllOrEmpty<X>`, và chỉ một module (hoặc không ai) đăng ký, cần một dòng `ShellContract<X>` trong `SHELL_CONTRACTS`; type của mỗi dòng phải được một package khai báo. Bỏ qua khi không có catalog của `platform_app_shell` |
| R17 | Nhánh theo platform là quyết định của app — `Platform.isX`, `Platform.operatingSystem`, `kIsWeb`, `defaultTargetPlatform` và `TargetPlatform.` trong Dart viết tay dưới `platform/<group>/<package>/lib`, `modules/<id>/<layer>/lib` và `apps/<id>/lib` (comment và chuỗi đã xoá trắng) chỉ xuất hiện trong các file của danh sách cho phép ở `tools/arch_check/platform_forks.dart`, mỗi file kèm lý do; mục không có lý do, hoặc ứng với file không còn rẽ nhánh hay không còn tồn tại, bị báo |
| R18 | Handler event của Bloc là async (RULE-52) — mọi `on<Event>(handler)` trong `lib/` của package `platform/`, `modules/` và `apps/` là closure inline khai báo `async`, hoặc là tear-off của method khai báo cùng file có dạng `Future<void> … async`. Handler khai báo ở nơi khác (file `part`, mixin) không bị xét |
| R19 | Chẩn đoán lúc chạy đi qua `DynamicLogger` (RULE-65) — không gọi `print(`, `debugPrint(` hay `debugPrintStack(` trong `lib/` của package `platform/` hay `modules/` nào (test và tool không bị quét; tool ghi bằng `stdout.writeln`) |
| R20 | Không số thô cho layout và vẽ (RULE-30, RULE-33) — trong `lib/` của `platform/` và `modules/`, ngoài `styles/`, `utils/` và file sinh, không có literal số làm giá trị của `SizedBox(width:|height:|dimension:)`, `EdgeInsets.all/symmetric/only/fromLTRB` (và `EdgeInsetsDirectional`), `BorderRadius.circular(`, `Radius.circular(`, `Offset(`, `fontSize:`, `blurRadius:` hay `strokeWidth:`; `context.w(16)` và token thì qua, `0` thì qua. Chặn (blocking) — cây hiện không có vi phạm |

Ba ngoại lệ hướng lên được hardcode trong tool **và in ra mỗi lần chạy**, kèm lý do từng cái — để chúng không mục ruỗng âm thầm trong một dòng comment. Thêm cái thứ tư nghĩa là phải sửa danh sách cho phép trong `check.dart` — thiếu bước này build sẽ fail — và ghi cạnh đó dưới RULE-01 trong [`01_rules.md`](../docs/vi/reference/01_rules.md) (cả hai ngôn ngữ), file mà tool không đọc.

R7 tồn tại vì `flutter analyze` không thấy được khác biệt này. Bản thân `core_responsive` không cung cấp extension nào trên `num`, nên `16.h` không phân giải được về nó — nhưng một extension khai ở package khác, hoặc do ai đó tự thêm cục bộ, vẫn type-check sạch trong khi đọc một biến toàn cục chẳng báo cho ai. Chỉ `context.h(16)` mới đăng ký dependency `InheritedWidget` lên `ResponsiveScope`, tức mới rebuild khi metrics đổi. Dạng trần là một lỗi giá trị cũ âm thầm, và không linter nào có luật cho nó. Check chạy trên mọi file Dart viết tay dưới `lib/` (một extension có thể được khai hay chạm tới trong file chẳng bao giờ import `core_responsive`), trên mã đã xoá trắng comment và chuỗi, và khớp receiver là số hoặc dấu đóng ngoặc theo sau bởi `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`.

R10 tồn tại vì tính tháo-lắp được là lời hứa template đưa ra trong bốn tài liệu mà không có gì kiểm tra. `network_config_impl.dart` import `data_auth` và `domain_auth` để đọc và làm mới token phiên, nên xoá module auth là app shell hỏng ngay ở khâu biên dịch — đúng một chỗ trong shell phá đi thứ mà mọi file còn lại cẩn thận giữ gìn. `getItOrNull` không cứu được: nó canh một *lookup*, còn lỗi ở đây là một *import*, thứ trình biên dịch giải quyết từ rất lâu trước khi có lookup nào chạy. Cách sửa là một hợp đồng (`ISessionGateway` trong `core_di`, do `data_auth` hiện thực), và phép kiểm là một dòng chính sách — một app được phép import package module ở đúng một file, điểm lắp ráp, vì nhiệm vụ của file đó chính là gọi tên những gì nó lắp.

R11 tồn tại vì chiều giữa các nhóm được viết ra ở bốn nơi mà chỉ review giữ nó. Nhóm được đọc từ thư mục — thứ duy nhất ghi nhận nó — nên một package bị chuyển vào sai nhóm, hay nằm ngoài mọi nhóm, fail chắc chắn như một cạnh sai. Dev dependency được loại trừ có chủ đích: chúng không bao giờ đi vào đồ thị của bên dùng (test của `platform_app_shell` dùng `core_storage` cho fake).

R8 tồn tại vì khả năng tháo module là tính chất mà app shell dựa vào, nhưng trước đó không có gì giữ nó. Tool tự suy ra tập hợp lúc chạy: mọi type khai trong `core_di` hay trong một package API của module (`<id>_api`), thu hẹp lại còn những type có ràng buộc `implements` / `extends` / `as:` trong một package dưới `modules/` — ở bất kỳ tầng nào, nên `ISessionGateway` do `data_auth` implement cũng nằm trong tập hợp chẳng kém gì navigator của một feature — và gắn với module implement nó. Một lookup ném lỗi lên các type đó vẫn compile — package gọi nó phụ thuộc `core_di` chứ không phụ thuộc module — rồi crash lúc runtime ở bản build không có module đó. Contract do app shell implement (`IThemeStorage`, `ILanguageStorage`) thì luôn được đăng ký, nên cố ý nằm ngoài tập hợp này. Module bị gỡ nguyên khối, nên mọi package của chính module implement được phép resolve contract của nó theo kiểu eager: chỉ cần một package của module có trong build thì đăng ký cũng có.

R12–R15 và R17–R20 đọc file, không đọc đồ thị package: mọi file mà git không bỏ qua — đã track, mới thêm, và module được checkout dạng submodule (ngoài một git checkout thì là mọi file). R13, R15 và R17–R20 chạy một lexer Dart nhỏ (`tools/arch_check/dart_source.dart`) xoá trắng comment và chuỗi trước, nên chữ nằm trong chuỗi, template hay doc comment không bao giờ bị báo. Mỗi luật có id trong bảng đăng ký: RULE-72 (R12), RULE-71 (R13), RULE-40 (R14), RULE-78 (R15), RULE-81 (R16), RULE-82 (R17), RULE-52 (R18), RULE-65 (R19), RULE-30 / RULE-33 (R20).

R16 tồn tại vì với mỗi dòng của catalog shell, app khai rằng nó cung cấp contract đó hoặc làm không có nó và vì sao (`capabilities:`, RULE-81) — và điều đó chỉ đúng khi catalog đầy đủ. R8 đã suy ra contract nào biến mất cùng một module; R16 đọc cùng tập đó (qua `tools/shared/contract_scan.dart`, bộ quét mà `arch_check` và `composer` dùng chung nên không thể bất đồng) và hỏi câu ngược lại: shell có tra cứu một contract mà không có dòng nào không? Thêm một lookup như vậy làm Gate 1 fail cho tới khi dòng đó — và nhờ vậy mục `capabilities:` của từng app — có mặt. Nửa thứ hai chặn việc đổi tên để lại một dòng cho type không còn tồn tại.

R17 tồn tại vì "tôi đang chạy ở đâu" từng có năm câu trả lời riêng trong Dart dùng chung mà không manifest nào thấy được. Việc app bật gì trên một platform được khai trong manifest và đọc từ `PlatformFacts`; `resolveAppPlatform()` là hàm duy nhất hỏi runtime của Flutter. Vài nhánh còn lại là về sự khả dụng của API hệ điều hành (`Platform` của `dart:io` ném lỗi trên web; mỗi hệ điều hành xin quyền thông báo theo cách riêng), được liệt kê kèm lý do trong `kPlatformForkAllowList` để ngoại lệ hiện ra khi review.

Phép quét lookup của R8 đọc cùng mã đã bỏ comment như R18–R20 (`tools/arch_check/source_rules.dart`), nên lookup xuống dòng hay viết `getIt.get<T>()` không còn tàng hình. Nửa thứ hai chặn cách khác mà đồ thị sập khi thiếu module: injectable dựng các class `@injectable` / `@lazySingleton` bằng get ném lỗi cho mỗi tham số constructor không nullable, nên một class của shell hay platform nhận contract thuộc module theo cách đó sẽ kéo sập cả container khi module bị tháo. Tham số nullable và `@factoryParam` là tuỳ chọn nên qua. Tham số mà phép quét không xác định được kiểu (một `this.x` không có field tương ứng trong class, một giá trị mặc định) được bỏ qua — phép quét thà bỏ sót còn hơn báo nhầm.

R18 tồn tại vì analyzer không thấy được: một `on<Event>((event, emit) { _load(emit); })` đồng bộ vẫn type-check, trả về trước khi việc xong, và `emit` đến muộn ném "emit was called after an event handler completed normally" lúc chạy. Phép quét đọc chính chữ của closure (`async` sau danh sách tham số) hoặc method cùng file đứng sau tear-off (`Future<void>` và `async`). Handler dạng biểu thức được viết `async => …`; template bloc của generator làm đúng như vậy.

R19 tồn tại vì `print` đi vào log release và không lọc được; `DynamicLogger.log` thì lọc được. Phép quét chạy trên mã đã xoá trắng comment và chuỗi, nên doc comment minh hoạ `print(x)` không phải lời gọi, và một method chỉ đặt tên như vậy cũng không phải.

R20 là nửa bằng số của RULE-30 / RULE-33 mà trước đây chỉ review gánh: một literal ở chỗ lẽ ra là `context.w/h/sp/r` hay một token. Nó nhìn *những ký tự đầu của mỗi đối số*, nên `context.w(16)` (bắt đầu bằng một lời gọi) và `AppSpacing.md` qua, còn `16`, `-4` và `.5` thì không; `0` và `0.0` qua vì số không scale ra không. `styles/` (design token) và `utils/` (hằng số) là nơi số thô được phép sống. Chạy trên cây thật nó không thấy vi phạm nào, nên nó chặn chứ không chỉ khuyên.

R5 là ảnh gương của `unused_checker`: tool kia tìm dependency *đã khai mà không dùng*, tool này tìm dependency *đang dùng mà không khai*. Pub Workspaces che giấu hoàn toàn loại thứ hai — mọi thứ resolve được cục bộ qua `package_config.json` dùng chung, và chỉ vỡ khi tách package ra hay publish.

### `composer`

```bash
dart tools/composer/composer.dart list              # liệt kê app và thành phần
dart tools/composer/composer.dart list --app admin  # chỉ một app
dart tools/composer/composer.dart describe --app mobile # báo cáo của app (nội dung vùng report trong README)
dart tools/composer/composer.dart describe --catalog    # mọi key manifest, catalog contract của shell, các giá trị mặc định suy ra, các key trong pubspec, các check V1–V17 và các mã vấn đề
dart tools/composer/composer.dart new reports --platforms web,windows --modules auth,settings   # tạo apps/reports từ tools/composer/app_template/
dart tools/composer/composer.dart sync --app mobile # sinh lại
dart tools/composer/composer.dart verify            # gate 0 của CI — fail khi lệch
dart tools/composer/bootstrap.dart                  # chỉ cho checkout từng phần — chạy trước `flutter pub get`
```

`--app <id>` lọc như nhau cho `list`, `sync` và `verify`; danh sách `workspace:` ở root vẫn được tính từ mọi app. Cờ lạ, hoặc `--app` không kèm id, thoát với mã `64`. Một pubspec hay manifest không phải YAML hợp lệ — thường là do key trùng — bị từ chối kèm tên file, `file:dòng` và thông báo của parser, exit `1`, thay vì làm tool crash.

Mọi `app_manifest.yaml` cũng được **kiểm tra trước khi bất kỳ lệnh nào chạy**; mỗi lỗi được in dạng `apps/<id>/app_manifest.yaml: <key>: <vấn đề>` (ví dụ `di_groups[0].phase: expected \`before\` or \`after\`, got a string (\`befor\`)`), và tool thoát `1` mà không ghi gì. Bị từ chối: manifest rỗng hoặc không phải map; key lạ ở bất kỳ cấp nào (`module:` thay cho `modules:`); `di_groups` thiếu hoặc rỗng; group không có `name` (một Dart identifier, duy nhất trong manifest) hoặc có `phase` khác `before`/`after`, hoặc group `before` đứng sau group `after`; `packages` không phải list; `from_modules` không thuộc `domain`/`data`/`feature`, hoặc một layer được hai group gom; group không có cả `packages` lẫn `from_modules`; module không có dạng `{ id, layers }`, module id trùng, `layers` rỗng, layer ngoài `domain`/`data`/`feature` hoặc không được `from_modules` của group nào gom; một package được ghép hai lần (bởi hai group, hoặc bởi một group và `extra_dependencies`); và hai manifest trùng `app.id`. Trước đây mỗi trường hợp này hoặc crash kèm stack trace, hoặc — tệ hơn — thoát `0` với một `injection.dart` đã âm thầm bỏ mất module.

**App tự khai báo trong manifest.** Ngoài phần thành phần (`di_groups`, `modules`), `app_manifest.yaml` nói app *là gì*: `app.name`, `flavors` (và, với mỗi flavor mà một platform có thể pin TLS, một quyết định `ssl_pinning` — `pins` hoặc `disabled` kèm lý do), các key `env` (`required_in` các flavor, hoặc `native_only`), `platforms` (mỗi platform có `runner: committed | scaffold` và, tùy chọn, những gì nó bật: `splash`, `push`, `deep_links`, `orientation`, `window` — cửa sổ desktop mà app áp dụng trong `ShellHooks.configureWindow`), `capabilities` (mỗi contract tùy chọn trong catalog của shell là `provided`, hoặc `{ state: absent, reason }` — vắng mặt là một quyết định) và `why` cho mỗi DI group. `app.kind` đã bỏ: nó không có nơi dùng, và composer từ chối nó bằng thông báo gỡ bỏ. `describe --catalog` in mọi key kèm giá trị mặc định, thứ từ chối nó và file đọc nó. `sync` biến phần khai báo thành Dart const trong vùng `facts` của `lib/app/app_profile.dart`, thành báo cáo trong vùng `report` của `README.md` của app, và chuyển `configureDependencies` vào vùng `modules` của `injection.dart`, nên cả file đều được sinh. `verify` từ chối khai báo thiếu (`<file>: <key>: <vấn đề>`, kèm dòng để dán khi có; `push: true` cần `core_notifications` được ghép và hỗ trợ platform đó, `window` chỉ cho platform desktop) và bất kỳ vùng nào trong ba vùng đó khác với bản sinh lại; một package có thể mang `platforms:` và `composition.app_provides` trong `pubspec.yaml` của chính nó, báo cáo đọc chúng còn `verify` **kiểm tra** chúng.

**`verify` giữ phần khai báo theo những gì (Gate 0).** Ngoài hình dạng của manifest (V1, V2, V4, V5, V6, V8, V9, V14, V16) và drift (V13):

| Check | Giữ |
|:-:|:--|
| V3 | `capabilities:` khớp với code, cả hai chiều: contract khai `provided` mà không package được ghép nào hay `lib/` của chính app đăng ký, hoặc khai `absent` mà vẫn có thứ đăng ký, bị từ chối kèm key trong manifest, file đăng ký và dòng để dán; mọi dòng **required** của catalog đều có nơi hiện thực trong các package được ghép (thông báo nêu package có hiện thực, dù được ghép hay không) |
| V7 | mọi package app liên kết có khai `platforms:` trong pubspec đều liệt kê mọi platform app khai — `core_database` không có `web`, `core_notifications` không có `windows` / `linux`. Phép kiểm tra bắt đầu từ các package được ghép rồi đi theo `dependencies:` (không theo `dev_dependencies:`), nên package chỉ được tới qua package khác cũng bị giữ đúng điều đó; thông báo nêu package và nhóm DI hay module đã kéo nó vào, hoặc cả chuỗi (`feature_foo -> core_database`). Như V8, nó từ chối trước khi ghi gì |
| V10 | `composition.app_provides`: thứ một package được ghép cần app đăng ký — `FirebaseOptions` cho `core_notifications` — được đăng ký dưới `apps/<id>/lib/`, với một `@Environment('<flavor>')` cho mọi flavor đã khai (đăng ký không có environment phủ mọi flavor) |
| V11 | các file env đang tồn tại (`env.dev`, `env.stg`, `env.prod`) chứa đúng các key `env:` khai: key chưa khai, hoặc key đã khai mà thiếu (`KEY=` — rỗng cũng được), bị từ chối kèm tên file. Key `native_only` được đếm ở đây và không bao giờ ở lúc boot |
| V12 | `app.entrypoint` tồn tại và gọi `runShellApp(` kèm `profile:`; `test/di_smoke_test.dart` tồn tại, gọi `checkAppContract(` và chứa `callFactories: true` (nó dựng mọi factory `@injectable`, RULE-63) |
| V15 | flavor cũng là một sự thật native: các `productFlavors` của runner Android đã commit (`android/app/build.gradle[.kts]`) và các scheme flavor của runner iOS đã commit (`ios/Runner.xcodeproj/xcshareddata/xcschemes`) đúng là các flavor mà `flavors:` khai — flavor bị xoá khỏi manifest mà vẫn còn trong Gradle (hoặc ngược lại) bị từ chối kèm tên cả hai; runner không nêu flavor nào thì không nói gì. V11 thêm: file env của flavor mà manifest không khai. Báo cáo in application ID / bundle ID của từng flavor đọc từ các file đó |
| V16 | mỗi mục `di_groups` có `why` không rỗng (`no ordering constraint: <lý do>` khi không có ràng buộc), và các nhóm mà template đặt tên giữ thứ tự tương đối `core → notifications → shell → ui → domain → data → feature → other` (RULE-13) |
| V17 | gốc repo là workspace node duy nhất (RULE-16) — pubspec của một thành viên (app, package, `tools/`) có key `workspace:` ở cấp cao nhất bị từ chối dạng `<path>/pubspec.yaml: workspace: …`. Đây là check toàn workspace, không thuộc riêng app nào: không phụ thuộc `--app` |

V3, V10, V11, V12 và V17 là các check về source: `verify` fail vì chúng, còn `sync` in chúng thành cảnh báo và vẫn ghi, vì các file sinh ra không phụ thuộc vào chúng và một chỉnh sửa dang dở phải còn sinh lại được. Phép quét đăng ký (`tools/shared/contract_scan.dart`) đọc source, không đọc đồ thị, và áp dụng luật đúng-type của GetIt (RULE-14): class mang `@Injectable` / `@Singleton` / `@LazySingleton` được đăng ký là chính nó, hoặc là thứ `as:` gán cho nó; thành viên của class `@module` được đăng ký là type nó khai. `implements X` không đăng ký gì. Một `getIt.register…` viết tay thì nó không thấy — `checkAppContract` (smoke test, và một lần boot debug) suy lại sự thật từ đồ thị thật và là nguồn quyết định. Phép quét này cũng điền cột **Implemented by** của § 4 trong báo cáo (các package đăng ký từng contract, hoặc `—`).

**`composer new` tạo một app.** `new <id> --platforms <a,b> [--modules <x,y>] [--name "<text>"]` render `tools/composer/app_template/` — các file Mustache cho `app_manifest.yaml`, `pubspec.yaml`, `README.md`, `lib/main.dart`, `lib/app/app_profile.dart` và `app_hooks.dart`, `lib/di/injection.dart`, `test/di_smoke_test.dart`, `test/app_profile_test.dart`, `env.dev` và `.gitignore` — vào `apps/<id>/`. Phần ghép là của `apps/admin`: các nhóm `core`, `shell`, `ui`, `domain`, `data`, `feature` và `other`, mọi layer mà từng module được yêu cầu có trên đĩa, và `core_database` nằm trong `core` chỉ khi một module được yêu cầu liên kết nó. `capabilities:` được **suy ra** bằng phép quét đăng ký từ những gì các package đó đăng ký — `provided` ở nơi có thứ đăng ký contract, còn lại là `absent` kèm lý do `not composed: no module this app composes registers <Type> — replace this with why the app goes without` (trạng thái của app, không phải nhắc lại việc shell làm khi thiếu nó — cột "If absent" của báo cáo nói điều đó một lần; không bao giờ là `TODO`, thứ V14 từ chối; báo cáo liệt kê mọi lý do như vậy dưới "Decisions to revisit" cho đến khi tác giả thay nó) — và version dependency lấy từ `pubspec_dependencies.yaml`, nên Gate 0 và 4 qua ngay. Mọi thứ có thể từ chối đều chạy trước và không ghi gì: id (một đoạn tên package, không phải app, thư mục hay package `<id>_app` đã có), tên (không dấu nháy, backslash hay `$`), các platform, các module, một module liên kết `core_notifications` (push cần `FirebaseOptions` — hãy theo mẫu `apps/mobile`), một platform mà package được liên kết không hỗ trợ (`--platforms web` với module mở database: thông báo nêu tên module và chuỗi phụ thuộc) và manifest đã render, qua cùng parser và các check mà `sync` chạy. Sau đó nó ghi file, chạy `sync` và `verify`, và in những gì cần chạy tiếp (`flutter pub get`, `build_runner`, smoke test) — sau dòng `flutter create` là phần dọn dẹp mà lệnh đó buộc phải làm (`rm -f test/widget_test.dart analysis_options.yaml`, `rm -rf .idea *.iml`), và với app chưa có màn hình là lệnh generator kèm `--apps <id>` (thiếu nó, generator thêm module vào mọi app). Smoke test sinh ra dựng mọi lazy singleton **và gọi mọi factory `@injectable`** một lần (`findAll<Object>(instantiateLazySingletons: true, callFactories: true)`, RULE-63 — tham số `@factoryParam` phải nullable, vì lời gọi không truyền gì), và hỏi `checkDeclaredStarts(appProfile, appHooks)`, nên một cửa sổ đã khai cùng hook `configureWindow` của nó là một cách khởi động hợp lệ. App liên kết `core_database` nhận một smoke test đã có sẵn double của `path_provider` và đóng từng database của package giữa các lần boot (cùng `drift` làm dev dependency); app mà không module nào được ghép đóng góp route hay tab sẽ được báo rằng smoke test của nó fail với C05 cho đến khi có một cái. Nó **không bao giờ chạy `flutter create`**: mỗi platform là `runner: scaffold`, và dòng lệnh cần chạy được in ra. Mã thoát `0` · `1` bị từ chối, hoặc `verify` fail sau khi ghi · `64` tham số sai.

Ba thứ phải khớp nhau và trước đây đều sửa tay: danh sách `workspace:` ở root, dependency dạng path của app, và `lib/di/injection.dart` của nó. Thêm một module nghĩa là sửa cả ba cho khớp, và sai thì vỡ lúc boot với `"<Type> is not registered"` — thứ `flutter analyze` không thấy được.

`composer` sinh cả ba từ các `app_manifest.yaml` — file riêng của mỗi app từ manifest của chính nó, còn danh sách `workspace:` dùng chung ở root từ tất cả manifest gộp lại — nhưng **chỉ** phần nằm giữa marker `composer:managed:<region>` và `composer:end:<region>`. Dependency ngoài, flavor và khai báo asset vẫn viết tay.

Danh sách `workspace:` ở root rộng hơn những gì manifest liệt kê: composer lần theo `dependencies` và `dev_dependencies` của từng package được ghép tới mọi package trong workspace mà chúng chạm tới. Nhờ vậy `core_responsive`, `core_ui_kit` và `platform_kernel` — không đăng ký DI module nào, nên không mục `di_groups` nào nhắc tên — vẫn là thành viên workspace. Danh sách tuỳ chọn `extra_dependencies:` trong manifest chỉ dành cho package workspace mà **chính** `lib/` của app import mà không ghép; hai app mẫu đều không cần.

Layer `api` của một module (`- { id: auth, layers: [api, domain, data, feature] }`) không cần mục `di_groups`: package `<id>_api` chỉ chứa hợp đồng, nên nó chỉ thành workspace member — không là dependency của app, không có dòng nào trong `injection.dart`. `--strict` / `verify` vẫn đòi nó có trên đĩa. Một group có thể gom nó bằng `from_modules: api` nếu có ngày package API đăng ký thứ gì đó.

Package được phân giải theo **tên**, tìm bằng cách quét `pubspec.yaml`. Không chỗ nào mã hoá đường dẫn, nên di chuyển package không phải sửa tool hay manifest. Package của module khớp được cả hai quy ước đặt tên — `domain_auth` và `auth_domain` đều nhận.

`--strict` (tự động bật trong `verify`) biến "manifest khai một module không có trên đĩa" từ cảnh báo thành lỗi. Không có nó, `sync` ghép những gì tìm được — chính điều này cho phép một dev làm việc khi chỉ checkout module của mình.

Cả `sync` lẫn `verify` còn **từ chối**, mã thoát `1`, khi một file mà chúng sinh vào — `pubspec.yaml` gốc, `pubspec.yaml`, `lib/di/injection.dart`, `lib/app/app_profile.dart` hoặc `README.md` của một app — bị thiếu, hoặc đã mất marker `composer:managed:<region>` / `composer:end:<region>` của một vùng. Chúng nêu tên file và marker, và `sync` không ghi gì cả. Trước đây marker bị thiếu chỉ là một cảnh báo rồi báo "up to date": xoá một marker rồi sửa tay phần nó từng bảo vệ vẫn qua được Gate 0.

Cả hai còn **từ chối** một pubspec của app khai báo tay một package do composer quản lý ở ngoài vùng marker. Pub từ chối key trùng, nên chỉ một lỗi đó là cả workspace ngừng resolve — và đó chính là lỗi composer từng tự gây ra.

Một lần sync không strict mà có bỏ qua thứ gì sẽ in ra khối **`PARTIAL COMPOSITION`**: các file đã-commit mà lần chạy đó thực sự ghi lại — chỉ những file ấy; file vốn đã chứa đúng phép lắp ráp này không bị liệt kê (các ứng viên là `pubspec.yaml` gốc, cùng `pubspec.yaml` và `injection.dart` của mỗi app được sync) — cùng dòng `git checkout --` để khôi phục. Phép lắp ráp nó viết ra đúng ở local và sai khi commit, và CI Gate 0 bắt được trong mọi trường hợp, vì `verify` sinh lại từ manifest trên runner có đủ mọi module. Xem [`12_module_isolation.md`](../docs/vi/guides/12_module_isolation.md).

#### `bootstrap` — trước khi composer chạy được

```bash
dart tools/composer/bootstrap.dart            # bỏ khỏi các vùng managed mọi member không có trên đĩa
dart tools/composer/bootstrap.dart --dry-run  # chỉ báo cáo
```

`composer.dart` import `package:path` và `package:yaml`, nên cần một workspace đã resolve — mà một bản checkout **từng phần** vừa clone (một submodule module chưa init, tức là thư mục rỗng) thì không resolve được: danh sách `workspace:` ở root và path dependency managed của từng app (đều đã commit) vẫn nêu tên nó, và `flutter pub get` từ chối cả workspace. `tools/composer/bootstrap.dart` **không import package nào** (chỉ `dart:io` và `OutputFormatter` vốn cũng chỉ dùng `dart:io`), nên chạy được trước khi pub từng resolve. Nó xoá, chỉ trong vùng `composer:managed:workspace` ở root và vùng `composer:managed:deps` của từng app, mọi mục mà thư mục không có `pubspec.yaml`, in ra những gì đã bỏ cùng dòng `git checkout --` để hoàn tác, rồi bảo bạn chạy `flutter pub get` → `composer.dart sync` → `workspace_setup/configure.dart`. Sau đó `sync` viết lại các vùng từ manifest.

Exit `0` khi đã cắt bớt hoặc không có gì để cắt (checkout đầy đủ — nó không ghi gì); `1`, không ghi gì, khi không có vùng `composer:managed:workspace` (không chạy từ root) hoặc khi một package đang có khai path dependency **viết tay** tới một thư mục vắng mặt (`modules/auth/data` mà thiếu `modules/auth/domain`) — cắt bớt không sửa được, nên nó nêu dòng đó và bảo bạn init thêm submodule ấy; `64` khi gặp tham số lạ. Trình tự đầy đủ: [`12_module_isolation.md` § 2](../docs/vi/guides/12_module_isolation.md#2-làm-việc-trên-bản-checkout-từng-phần).

### `docs_check`

**Gate 5 của `pr_quality_check.yml`.** Giải đường dẫn cho mọi path trong repo mà tài liệu nhắc tới, gom tất cả những path không tồn tại, in ra theo từng file, rồi thoát với mã 1. Ngoại lệ duy nhất là tham chiếu vào một sample bundle bạn đã gỡ bằng `remove_sample` — được tóm tắt dạng INFO, không bao giờ làm fail (xem bên dưới).

```bash
dart tools/docs_check/check.dart            # thoát 1 nếu có tham chiếu chết, lệch cấu trúc en ↔ vi hoặc lỗi RULE-ID
dart tools/docs_check/check.dart --verbose  # kèm block allowlist để copy-paste và mọi tham chiếu tới sample đã gỡ
dart tools/docs_check/check.dart --help     # cú pháp; mọi tham số khác thoát mã 64
```

Hai loại tham chiếu được kiểm tra trong mọi file Markdown của repo — chỉ bỏ qua trạng thái tool, output build và dependency native tải về (`.dart_tool`, `build`, `Pods`, …). Trước đây nó chỉ phủ `docs/`, `.agents/`, `README.md` và `CLAUDE.md`; mở rộng ra thì lộ 11 link chết trong các hướng dẫn ở `.github`, một README của package và README của fastlane:

| Loại | Ví dụ | Cách giải |
|---|---|---|
| Path trong backtick | `` `platform/foundation/kernel/lib/platform_kernel.dart` `` | Tính từ gốc repo, nhưng chỉ khi chuỗi bắt đầu bằng một thư mục top-level có thật |
| Markdown link | `[…](arch_check/check.dart)` | Tương đối với **file chứa link**, không phải thư mục đang chạy lệnh |

Phép thử "thư mục top-level" chính là thứ làm cho check này dùng được. Repo đầy những chuỗi backtick trông như path nhưng không phải: `utils/` và `routing/` là quy ước tồn tại trong cả chục package, `ViewState` là một type, `flutter pub get` là một lệnh. Coi chúng là path sinh ra 817 "lỗi" ở lần chạy đầu và sẽ dạy cả team thói quen phớt lờ gate này. Neo vào `platform/`, `modules/`, `apps/`, `tools/`, `docs/`, `.agents/`, `.github/` còn lại khoảng 1 900 tham chiếu thật (tại thời điểm viết) — và những chuỗi bị bỏ qua đúng là loại reviewer nhìn mắt thường cũng xác minh được.

Chuỗi có khoảng trắng bị bỏ qua: đó là lệnh shell. Chuỗi có `*` hoặc `{` là glob, mô tả một *tập hợp* chứ không phải một file — đạt khi có ít nhất một đường dẫn khớp. Chuỗi có một đoạn `<placeholder>` (`modules/<owner>/feature/lib/src/handlers`) là **khuôn mẫu** cho module của chính người đọc, không phải tham chiếu: chỉ phần cố định trước placeholder đầu tiên phải tồn tại (`modules`), nên một path placeholder không bao giờ fail chỉ vì hiện chưa module nào có thư mục đó. Một path placeholder nằm dưới thư mục packages/domain đã bị xoá từ lâu vẫn fail, vì phần cố định đó không tồn tại. Danh sách thư mục gốc vẫn giữ `packages/` và `app/` trần, nơi không còn gì, để tài liệu còn trỏ tới đó sẽ fail thay vì bị bỏ qua.

**Sample đã gỡ không làm fail gate.** `remove_sample.dart <bundle> --apply` xoá các package của bundle nhưng không bao giờ sửa `tools/sample_manifest.yaml`, và `docs_check` đọc định nghĩa bundle ở đó: bundle có **mọi** package vắng mặt trên đĩa (trừ package `modules/<id>/api` mà remove_sample giữ lại vì còn nơi import) được coi là "đã gỡ", và tham chiếu chết nằm trong nó — path của package, thư mục `modules/<id>` đã trống, một mục trong `orphaned_contracts` — được báo thành một dòng tóm tắt cho mỗi bundle thay vì một lỗi:

```text
INFO: 118 reference(s) in 32 document(s) point to removed sample bundle "auth" — expected after remove_sample; update the docs at your leisure.
```

`--verbose` liệt kê chúng. Bundle còn dù chỉ một package trên đĩa thì không phải "đã gỡ" — sample bị xoá dở là drift và fail như thường — và một path chết nằm ngoài mọi bundle đã gỡ vẫn thoát mã 1. Khi tài liệu không còn nhắc tới sample đã gỡ, bạn có thể xoá mục bundle của nó khỏi manifest.

Những path vắng mặt một cách chính đáng nằm trong `tools/docs_check/allowlist.txt`, mỗi dòng một path kèm lý do. Chỉ đúng ba lý do được chấp nhận:

1. **Sinh tự động** — `apps/mobile/lib/di/injection.config.dart`, build output.
2. **Bí mật** — `apps/mobile/env.prod`, `apps/mobile/android/key.properties`; không bao giờ commit.
3. **Hướng dẫn** — file mà người đọc *được bảo là hãy tạo ra* (`app_elevation.dart` trong guide design system), hoặc placeholder đại diện cho module của chính người đọc (`modules/profile/feature`).

Mọi trường hợp khác là drift, và cách sửa là sửa tài liệu. Một entry không kèm lý do là không hợp lệ — khoảnh khắc allowlist trở thành danh sách những path ai đó bịt miệng, gate này hết đáng chạy.

> [!NOTE]
> Check này cố ý không nói gì về việc tài liệu có *đúng* hay không, chỉ nói những thứ nó trỏ tới có tồn tại hay không. Đó là một chuẩn thấp, và là chuẩn duy nhất máy giữ được. Trích dẫn theo số dòng (`generate.dart:90-101`) fail check này theo thiết kế — đó là loại tham chiếu mục nhanh nhất, còn gọi tên symbol thì sống sót qua mọi chỉnh sửa phía trên nó.

**Tương đương cấu trúc en ↔ vi.** Cùng lần chạy đó so sánh mọi cặp bản dịch — `docs/en/<path>.md` với `docs/vi/<path>.md`, và `<name>.md` với `<name>.vi.md` nằm cạnh ở bất kỳ đâu (`README.md`, `tools/README.md`, README của package) — theo hình dạng, vì bản dịch không thể diff từng chữ: số heading ở mỗi cấp (`h1`–`h6`), số code block rào (`code-blocks`) và số dòng bảng (`table-rows`, kể cả bảng trong trích dẫn) phải khớp. Heading và bảng nằm trong code block không được tính. Mọi chênh lệch đều làm lần chạy fail:

```text
1 parity mismatch(es):

  docs/en/guides/01_new_feature.md  table-rows: en 18 vs vi 17  (docs/vi/guides/01_new_feature.md)
```

Chênh lệch gần như luôn có nghĩa là một mục, một lệnh hay một dòng bảng chỉ tới được một ngôn ngữ — hãy dịch nó sang. Chênh lệch thật sự có chủ đích thì ghi vào `tools/docs_check/parity_allowlist.txt` dạng `<english file> <metric>` (hoặc `*` cho mọi metric) kèm lý do sau `#`; entry không có lý do bị từ chối, còn entry không còn khớp chênh lệch nào sẽ in `WARN` để xoá đi. Hiện danh sách này rỗng: mọi cặp đều cùng hình dạng. Logic nằm ở `tools/docs_check/parity.dart`.

**Trích dẫn RULE-ID.** Mọi token `RULE-<chữ số>` trong bất kỳ file Markdown nào — kể cả trong code block, các file `SKILL.md` và `tools/code_review/review_prompt.md` — phải là id của một dòng `| RULE-NN |` trong bảng đăng ký của [`01_rules.md`](../docs/vi/reference/01_rules.md). Không id nào được định nghĩa hai lần, và `docs/vi/reference/01_rules.md` phải định nghĩa đúng cùng tập id. Mỗi lỗi được in dạng `file:line` và thoát 1. Luật bị bỏ vẫn giữ dòng của nó, đánh dấu retired, để trích dẫn cũ vẫn phân giải được; id không bao giờ bị tái sử dụng. Khi chưa có bảng đăng ký, phép kiểm bị bỏ qua kèm một dòng `INFO`. Logic nằm ở `tools/docs_check/rule_ids.dart`.

**Bản dịch cũ (tham khảo).** Một file `docs/vi` có thể bắt đầu bằng dấu ghi tên commit tiếng Anh mà nó được đồng bộ theo:

```text
<!-- translated-from: docs/en/<path>.md@<short-sha> -->
```

Một lần chạy bình thường in một dòng `INFO` đếm số bản dịch mà nguồn tiếng Anh có commit mới hơn commit đã ghi — nó không bao giờ fail. `--stale-translations` liệt kê chúng; `git diff <sha> -- <en file>` cho thấy cần mang gì sang. Sau khi đồng bộ, commit thay đổi tiếng Anh trước, rồi chạy `--stamp-translations docs/vi/<file>.md`; không truyền file thì nó đóng dấu mọi file `docs/vi` là mới nhất, chỉ đúng khi mới bắt đầu dùng dấu. Logic nằm ở `tools/docs_check/translations.dart`.

```bash
dart tools/docs_check/check.dart --stale-translations                       # liệt kê bản dịch chậm hơn nguồn tiếng Anh
dart tools/docs_check/check.dart --stamp-translations docs/vi/<file>.md      # sau khi đồng bộ một file
```

### `sample_cleanup`

Trả lời câu "cái nào là code mẫu, và xoá sao cho không vỡ app?".

```bash
dart tools/sample_cleanup/remove_sample.dart --list    # bảng phân loại
dart tools/sample_cleanup/remove_sample.dart auth      # dry-run (mặc định)
dart tools/sample_cleanup/remove_sample.dart auth --verbose  # dry-run, liệt kê đủ mọi tham chiếu tài liệu
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

Nguồn chân lý của nó là [`tools/sample_manifest.yaml`](sample_manifest.yaml), phân loại mọi package thành `framework`, `sample` hay `shell`. Không có code mẫu nào nằm bên trong package framework: mỗi sample là một package riêng, nên gỡ một sample luôn là thao tác gỡ trọn một bundle.

Phần đáng đọc nhất là output của dry-run. Xoá `auth` không chỉ là ba thư mục: nó in ra chính xác những dòng cần gỡ khỏi `pubspec.yaml` gốc và khỏi manifest, pubspec, `injection.dart` của mọi app, **các package API nó giữ lại** (bên dưới), **và sample nào sẽ vỡ, vỡ như thế nào** (danh sách `breaks` trong `tools/sample_manifest.yaml` — hiện trống với mọi sample) — cùng các liên kết xuống cấp an toàn, như `feature_settings` ẩn dòng logout khi `getItOrNull<IAuthActionHandler>()` trả về null, hay `feature_home` hiển thị trạng thái chưa đăng nhập khi `getItOrNull<ISessionStatusStream>()` ở route trả về null.

Cả dry-run lẫn `--apply` đều đếm các **tham chiếu Markdown** tới những đường dẫn sắp bị xoá — đường dẫn trong backtick và link tương đối trong mọi `*.md` (`docs/`, `.claude/`, các README), so khớp đúng như cách `docs_check` làm. Chúng chỉ mang tính thông tin: `dart tools/docs_check/check.dart` (CI Gate 5) nhận ra chúng trỏ vào một sample bundle đã gỡ, in một dòng INFO cho bundle đó và vẫn đạt — sửa các tài liệu đó lúc nào tiện. Đó cũng là lý do tool không bao giờ sửa `tools/sample_manifest.yaml`: định nghĩa bundle còn nằm đó là cách `docs_check` biết. Tool in 15 dòng đầu; `--verbose` liệt kê đủ.

**Package API của module được giữ lại khi vẫn còn nơi import nó.** `auth` gồm cả `auth_api`, nhưng `feature_onboarding` và `feature_settings` phụ thuộc nó; xoá nó sẽ làm hỏng biên dịch của chúng. Vì vậy mọi package `modules/<id>/api` của bundle mà một package ngoài bundle vẫn khai (`dependencies:` hay `dev_dependencies:`) đều được **giữ lại**: dry-run đánh dấu nó `k` kèm các nơi import, `--apply` báo lại lần nữa, mục `workspace:` ở root được giữ và mọi mục manifest từng liệt kê nó được viết lại thành `{ id: <id>, layers: [api] }`. Các hợp đồng của nó khi đó không còn implementation — `getItOrNull` của nơi dùng trả về null và chúng dùng fallback. Khi không còn ai import, chạy lại `remove_sample <id> --apply` thì nó cũng bị xoá. `docs_check` coi một bundle chỉ còn sót package API là đã gỡ.

Các bundle: `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` (`--list` in chúng kèm bảng phân loại).

Chỉ ghi khi truyền `--apply`, và các file dùng chung được snapshot trước để fail giữa chừng thì rollback được. Tham số được kiểm tra trước: cờ lạ (`--aply`), có cờ mà thiếu tên bundle, sai tên bundle, hoặc nhiều hơn một bundle đều thoát với mã `64` (không có tham số nào thì in cách dùng và thoát mã `0`) — gõ sai cờ không bao giờ lặng lẽ biến thành dry-run, cũng không bị bỏ qua khi đứng cạnh `--apply`.

### `module_generator`

Dựng khung package và đăng ký nó khắp workspace.

```bash
dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<sm>] [<route>] [--group <g>] [--apps <id,id>]
dart tools/module_generator/generate.dart --help   # cú pháp
```

| Tham số | Giá trị |
|---|---|
| `<type>` | `1` feature · `2` domain · `3` data · `4` core · `5` custom |
| `<name>` | tên thư mục trần (`profile`) — package sẽ thành `feature_profile`. Phải là tên package Dart hợp lệ: chữ thường, số và `_`, bắt đầu bằng chữ cái, không phải từ khoá Dart |
| `<prefix>` | chỉ cho type `5` — tiền tố tên package: `<prefix>_<name>` tại `platform/<group>/<name>`, cùng quy tắc đặt tên như `<name>`. Từ chỉ tầng (`feature`, `domain`, `data`, `core`) bị từ chối; hãy dùng type 1–4. Với type 1–4 tham số này phải rỗng — truyền `""` |
| `<sm>` | chỉ feature — `1` Provider · `2` BLoC · `3` không dùng |
| `<route>` | chỉ feature — `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` không |
| `--group` | chỉ type `4`/`5` — thư mục nhóm trong `platform/`: `foundation` · `layers` · `infra` · `ui` · `state` · `shell` (`--group ui`, `--group=ui`). Mặc định `infra`. Nhóm nào chứa gì: [`02_core.md`](../docs/vi/architecture/02_core.md). Nhóm không hợp lệ, hoặc `--group` cho type 1–3, thoát mã 64 |
| `--apps` | tuỳ chọn, mọi loại — chỉ compose module vào các app này: danh sách `app.id` cách nhau bằng dấu phẩy, lấy từ `apps/*/app_manifest.yaml` (`--apps mobile`, `--apps=mobile,admin`). Mặc định: mọi app |

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1   # feature + Provider + route stack
dart tools/module_generator/generate.dart 1 chat    "" 2 2   # feature + BLoC + tab bottom-nav
dart tools/module_generator/generate.dart 2 payment          # domain micro-package
dart tools/module_generator/generate.dart 3 payment          # data micro-package
dart tools/module_generator/generate.dart 4 charts --group ui # core_charts tại platform/ui/charts
dart tools/module_generator/generate.dart 5 billing acme     # acme_billing tại platform/infra/billing
dart tools/module_generator/generate.dart 1 chat    "" 2 2 --apps mobile   # chỉ mobile — admin không bị đụng
```

**Tham số được kiểm tra trước khi ghi bất cứ thứ gì**, và mọi lần từ chối đều thoát với mã `64` kèm cú pháp: `<name>` hay `<prefix>` không hợp lệ (`Bad-Name`), `<sm>` / `<route>` khác `1`/`2`/`3`, `<prefix>` / `<sm>` / `<route>` truyền cho loại module không nhận nó, cờ lạ, nhiều hơn năm tham số, `--apps` không có giá trị, danh sách rỗng, truyền hai lần, hoặc chứa id mà không `app_manifest.yaml` nào khai báo (thông báo liệt kê các id có thật), hoặc **tên package đã có** trong một `pubspec.yaml` bất kỳ của repo. Pub resolve workspace theo tên, nên trùng tên trước đây chỉ lộ ra ở `pub get`, sau khi composer đã ghi lại các manifest — và thư mục mới không có nghĩa là tên mới: `5 shell platform_app` là `platform_app_shell` (đã có ở `platform/shell/app_shell`), `2 core` / `3 core` là `domain_core` / `data_core`.

Không tham số và có terminal thì tool hỏi mọi thứ. Feature thiếu `<sm>` hoặc `<route>` thì hỏi phần còn thiếu (bỏ trống câu trả lời là chọn `1`). **Không có terminal** — CI, shell của agent, stdin đã hết — thì giá trị cần hỏi trở thành lỗi, exit `64`, không bao giờ lặng lẽ lấy mặc định: với feature hãy luôn truyền đủ năm tham số. Mọi output của tool đều bằng tiếng Anh.

**Nó làm gì:** tạo cây thư mục (bao gồm `lib/src/utils/`, cho mọi tầng), render template (pubspec mới chép `environment:` từ `pubspec.yaml` gốc), thêm module vào mọi `app_manifest.yaml` — hoặc chỉ các app mà `--apps` nêu tên — chạy `composer sync` (sinh lại danh sách `workspace:` ở root cùng `pubspec.yaml` và `lib/di/injection.dart` của từng app), rồi dependency sync, `pub get`, `gen-l10n`, barrel generator, `build_runner`, barrel generator **lần nữa**, và `dart fix --apply` trên package mới. Barrel chạy hai lần vì template import các barrel anh em, nên chúng phải có trước khi `build_runner` đọc package, trong khi barrel cũng export file sinh ra (`module.module.dart`, `lib/src/gen/**`) — nên lần chạy cuối phải đứng sau codegen.

> [!IMPORTANT]
> Nó không bao giờ tự ghi danh sách `workspace:` ở root, `pubspec.yaml` hay `lib/di/injection.dart` của app. Các file đó nằm giữa marker `composer:managed` và chỉ `composer sync` ghi chúng — một dòng thêm ngoài marker là dòng composer không bao giờ xoá, còn sửa tay bên trong là drift mà CI Gate 0 chặn.

**Hành vi an toàn**

- **Kiểm tra toolchain trước tiên.** `assertToolchainAvailable()` chạy trước khi động vào bất cứ file dùng chung nào, nên thiếu SDK là fail ngay lập tức thay vì chết ở bước 8.
- **Từ chối thư mục đã tồn tại.** Nó sẽ không âm thầm ghi đè lên package có sẵn.
- **Rollback khi thất bại.** Các file dùng chung bị thay đổi — mọi `app_manifest.yaml`, những gì `composer sync` ghi lại (`pubspec.yaml` gốc, `pubspec.yaml` và `lib/di/injection.dart` của từng app) và `pubspec.lock` gốc — được sao lưu trước mọi thao tác ghi; nếu bước sau fail thì chúng được khôi phục, thư mục module mới bị xoá, và tool thoát với mã `1`. Nếu lỗi xảy ra sau khi `pub get` hoặc `build_runner` đã bắt đầu, rollback còn chạy lại `flutter pub get` và `dart run build_runner build --workspace`: nếu không, các file sinh tự động không theo dõi bởi git (`.dart_tool/package_config.json`, `injection.config.dart` của từng app, `module.module.dart`) vẫn còn tham chiếu package đã xoá. Tool chỉ báo workspace sạch khi tất cả các bước đó thành công; nếu không, nó liệt kê những gì còn sót và in ra các lệnh cần chạy.
- **Việc đăng ký được kiểm chứng.** Manifest đã liệt kê package hay chưa được quyết định bằng cách parse YAML, không so chuỗi con — trước đây một phép thử theo dòng từng coi `core_net` là đã đăng ký vì `core_network` chứa nó, và package lặng lẽ không vào app nào mà vẫn exit `0`. Mỗi lần sửa đều được parse lại; nếu không thêm được module vào một manifest (không có danh sách `modules:`, hoặc nhóm DI `core`, đúng định dạng mong đợi) thì cả lần chạy rollback và thoát với mã `1`.
- **Tự phát hiện FVM** — mọi tool có gọi lệnh ngoài đều dùng chung `tools/shared/toolchain.dart` — yêu cầu *cả hai*: có file cấu hình (`.fvmrc` hoặc `.fvm/fvm_config.json`) *và* `fvm --version` chạy được. Chỉ một tín hiệu thôi là cho kết quả sai: repo này pin version trong `.fvmrc` trong khi một máy cụ thể có thể không hề cài `fvm`.

**Package mới khai báo gì.** Chỉ những package mà template của nó import, nên nó qua `check_unused_packages` ngay lần chạy đầu — thêm `core_network`, `core_storage`… khi code cần. Feature khai `core_di`, `core_common`, `core_base_ui` và `core_responsive` (mọi page được sinh đều bố cục qua `AdaptiveContent`, với `AppSpacing` / `AppTextStyles` scale qua context), cộng `provider_state_management` + `domain_core` cho Provider, hoặc `bloc_state_management` + `core_ui_kit` cho BLoC (trạng thái loading là `LoadingWidget` của kit); chỉ feature mới nhận `flutter_localizations` và `intl`, thứ mà output `gen-l10n` của nó import. Package domain nhận `domain_core` và một contract repository `I<Name>Repository` (trong `repositories/`, một method giữ chỗ `ping()` trả `Result<void>`). Package data nhận `data_core` và `<Name>RepositoryImpl extends BaseRepository` (trong `repositories_impl/`); khi `domain_<name>` đã tồn tại, nó khai thêm `domain_core` + `domain_<name>`, implements contract đó và đăng ký dưới contract (`@LazySingleton(as: I<Name>Repository)`) — vì vậy hãy sinh domain trước. Package core và custom khởi đầu không có dependency workspace nào.

**Test được sinh sẵn.** Feature khởi đầu với các test pass ngay không cần sửa, nên CI Gate 3 có thứ để chạy từ commit đầu tiên: `test/<name>_page_test.dart` pump page dưới `ResponsiveInit` và localization của feature — với controller thật được cung cấp phía trên đúng như route cung cấp — rồi kiểm tra tiêu đề đã dịch và page bố cục được trên cửa sổ điện thoại lẫn tablet; `test/<name>_provider_test.dart` (Provider) chờ `initialize()` và mong đợi success, `test/<name>_bloc_test.dart` (BLoC) mong đợi `initial` rồi `success` sau event `started`. SM `3` chỉ có test page. `flutter_test` nằm trong `dev_dependencies` của pubspec feature. Khi controller nhận use case, hãy thay controller thật bằng fake (xem `modules/auth/feature/test/auth_provider_test.dart`).

**Thời gian build.** Gần như toàn bộ một lần chạy là `build_runner` trên cả workspace (~76 giây trong ~92 giây, đo với cache nóng), và ~50 giây trong đó là compile lại build script AOT, việc mà một package workspace mới buộc phải làm. `--build-filter` giới hạn vào package mới và `di/` của các app không tiết kiệm được gì (77 giây) mà còn để lại 21 output ở chỗ khác chưa build cho tới lần build đầy đủ kế tiếp, nên generator giữ nguyên `build_runner build --workspace` đầy đủ.

**Thứ tự nav destination.** `INavDestinationModule.order` của feature `<route>` `2` bằng `order` cao nhất trong các destination hiện có dưới `modules/*/feature` cộng 10 (10 nếu chưa có cái nào), nên các tab được sinh ra không bao giờ trùng thứ tự. Đánh số lại tuỳ ý; chỉ thứ tự tương đối là quan trọng.

> [!NOTE]
> Ngoài các stub đó, entity, use case, model và data source phải viết tay. Xem [`../guides/02_new_domain_data.md`](../docs/vi/guides/02_new_domain_data.md).

### `barrel_generator`

```bash
dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib
dart tools/barrel_generator/generate.dart --help   # cú pháp
```

Sinh lại barrel `*.dart` cho mọi thư mục dưới đường dẫn đã cho, rồi chạy `dart format` trên đó qua toolchain của repo (FVM nếu đã cài đặt). Chạy nó sau **bất kỳ** thao tác thêm / đổi tên / xoá file nào trong `lib/` — và sau `build_runner` / `gen-l10n`, vì file sinh ra đang có trên đĩa cũng được export (`core_ui_kit` lấy `Assets` sinh ra của `core_base_ui` theo cách đó).

Mã thoát: `64` khi đường dẫn không tồn tại (nó chỉ hỏi lại đường dẫn khi chạy không tham số trên terminal), khi gặp một cờ hoặc đường dẫn thứ hai; `1` khi `dart format` thất bại — barrel đã được ghi nhưng chưa format. Cờ không bao giờ bị hiểu thành đường dẫn (trước đây `--help` từng bị đọc như tên thư mục), và `<pkg>/lib/` giống hệt `<pkg>/lib` (dấu phân cách ở cuối từng sinh ra `lib/.dart`).

Thư mục bị bỏ qua: thư mục ẩn, `lib/gen`, và các thư mục nền tảng / build (`android`, `ios`, `web`, `build`, …) **chỉ khi nằm ngoài** `lib/` — so theo từng đoạn đường dẫn tính từ gốc package, nên `lib/src/widgets/web/` vẫn được export như mọi thư mục khác. `lib/src/gen` vẫn được duyệt như trước.

Bỏ qua `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, `firebase_options*`, và file khai `part of`. Các file sinh khác — `module.module.dart`, `injection.config.dart`, `lib/src/gen/**` — vẫn được export nếu đang có trên đĩa.

> [!CAUTION]
**Cổng barrel-drift trong CI (RULE-75).** Sau `configure.dart` — bước sinh lại barrel của mọi package khi codegen đã chạy — `pr_quality_check.yml` làm job quality fail khi `git diff --exit-code -- '*.dart'` có thay đổi, hoặc khi generator ghi ra một file `.dart` mà git không theo dõi. Vì vậy cả barrel cũ (thêm, đổi tên hoặc xoá file mà không chạy lại generator) lẫn `export` thêm tay (generator xoá nó) đều làm PR fail; cách sửa là chạy generator cho package đó rồi commit kết quả.

> Nó **xoá mọi dòng `export` viết tay** trong barrel trước khi sinh lại. Cần re-export thứ gì từ package khác thì đặt `export` vào một file nguồn bình thường rồi để barrel nhặt file đó lên.

### `dependency_sync`

`pubspec_dependencies.yaml` ở gốc repo là nguồn chân lý duy nhất cho version.

```bash
dart tools/dependency_sync.dart          # ghi version vào mọi package
dart tools/dependency_sync.dart --check  # chỉ kiểm tra; exit 1 nếu lệch hoặc có hosted dependency mà catalog không pin
dart tools/dependency_sync.dart --help   # in cách dùng; mọi cờ khác thoát mã 64, không sync gì
```

Nó cũng sửa các mục `path:` cục bộ bị gãy. Dùng `--check` trong CI và pre-commit.

**Hosted dependency mà catalog không pin thì fail (RULE-74).** Một mục `dependencies:` hay `dev_dependencies:` trong bất kỳ pubspec nào của workspace mà đến từ pub.dev (version trần, không có giá trị, hoặc map có `hosted:` / `version:`) nhưng không có trong `pubspec_dependencies.yaml` được in dạng `Not in the catalog: [<pubspec>] <section>.<package>` và exit `1`, cả với `--check` lẫn chạy thường (chạy thường cũng thoát trước `pub get`). Nguồn `sdk:`, `path:`, `git:` và package trong workspace không thuộc phạm vi của catalog. Cách sửa là pin package vào catalog rồi chạy lại tool.

> [!NOTE]
> Catalog và mọi pubspec được đọc bằng YAML parser, nên comment cuối dòng header (`dependencies: # runtime`) không còn là vấn đề. Catalog phải là một map chỉ gồm `dependencies:` và `dev_dependencies:`, mỗi mục là map package → **chuỗi version constraint**; mọi thứ khác — section lạ, nguồn lồng `git:`/`path:`, số không có ngoặc kép, giá trị rỗng, package được pin ở cả hai section, YAML không hợp lệ — bị từ chối dạng `pubspec_dependencies.yaml: <section>.<package>: <vấn đề>` (hoặc `file:dòng` với YAML hỏng), exit `1`, kể cả với `--check`, và không ghi gì. Một pubspec trong workspace không parse được cũng bị từ chối như vậy trước khi chạm vào bất kỳ file nào. Khi ghi lại, tool chỉ thay đúng các ký tự của giá trị đó, nên comment và định dạng được giữ nguyên. `dependency_overrides` được cố ý để nguyên, và dependency khai báo dạng map (`path:`/`git:`/`sdk:`/`hosted:`) không bao giờ bị ghi đè — chỉ `path:` của package trong workspace được sửa. Dependency native của Gradle (ví dụ `play-services-auth` trong `apps/mobile/android/app/build.gradle.kts`) hoàn toàn nằm ngoài phạm vi của nó — chúng không có nguồn chân lý tập trung nào.

### `unused_checker`

```bash
dart tools/unused_checker/check_script.dart              # cả bốn, kèm tổng kết
dart tools/unused_checker/check_unused_assets.dart       # asset không được tham chiếu
dart tools/unused_checker/check_unused_translate.dart    # key .arb không ai dùng
dart tools/unused_checker/check_unused_file.dart         # file Dart mồ côi
dart tools/unused_checker/check_unused_packages.dart     # dependency khai mà không dùng
```

Mỗi check tự tìm gốc repo từ vị trí của chính nó, nên chạy được từ bất kỳ thư mục làm việc nào; gốc không chứa package nào là lỗi (exit `1`), không bao giờ là kết quả sạch — trước đây chạy từ thư mục con thì chúng thấy 0 package và báo thành công. Mọi script nhận `--help`; tham số khác thoát với mã `64`.

[Luật 2](../docs/vi/reference/01_rules.md#2-khai-báo-dependency-tường-minh) có hai nửa: `arch_check` R5 bắt package được import mà không khai; `check_unused_packages.dart` bắt package đã khai mà không import (nó quét `lib/`, `bin/`, `test/` và `tool/` — package không có `lib/`, như `core_tools`, được đọc toàn bộ — nên dependency chỉ test dùng vẫn tính là đang dùng). Chạy cả hai trước mỗi PR.

Không có allowlist chung: một khai báo không có import chỉ được chấp nhận ở nơi thật sự cần — `flutter` luôn luôn; `flutter_localizations` và `intl` trong package có `l10n.yaml` (output của gen-l10n import chúng); `json_annotation` khi có `json_serializable`; `flutter_svg` khi bật integration `flutter_svg` của `flutter_gen`. `check_unused_file.dart` bắt đầu từ mỗi `lib/main.dart`, `lib/di/`, file routing, class injectable và mọi file không phải barrel nằm ngay dưới `lib/`. Một export trong barrel của package không tính là dùng: file được barrel export chỉ tính là đang dùng khi một file import barrel đó gọi tên một khai báo public của nó (file chỉ khai báo extension hoặc re-export được tính khi barrel của nó được import), nên một file toolkit không ai tham chiếu sẽ bị báo.

> [!WARNING]
> Các checker asset / file / translation hoạt động bằng đối chiếu văn bản, nên sẽ báo nhầm với bất cứ thứ gì được với tới động (đường dẫn asset ghép từ chuỗi, key tra lúc chạy). Xác nhận kỹ trước khi xoá.

### `check_outdated`

```bash
dart tools/check_outdated.dart
```

Liệt kê package trong `pubspec_dependencies.yaml` có version mới hơn trên pub.dev. Khi chạy trong terminal, nó hiện checklist (mặc định chọn hết); gõ `a` để ghi version đã chọn vào catalog rồi chạy `dependency_sync` và `pub get`, `q` để thoát. Không có terminal (CI, pipe) thì chỉ liệt kê.

Tool thoát với mã `1` khi resolve catalog, `pub outdated`, đọc JSON của nó, hay bước áp dụng cập nhật (`dependency_sync`, `pub get`) thất bại, nên script phân biệt được một lần kiểm tra lỗi với một lần mọi thứ đã mới nhất. Ngoài `--help` nó không nhận tham số nào; tham số khác thoát với mã `64`.

### `workspace_setup`

```bash
dart tools/workspace_setup/configure.dart
dart tools/workspace_setup/configure.dart --stub-firebase   # kèm stub Firebase chỉ-để-compile nơi còn thiếu
dart tools/workspace_setup/configure.dart --help   # các bước sẽ chạy, theo thứ tự — không chạy gì
```

Dựng đầy đủ cho một bản clone mới. Script chạy theo thứ tự: activate `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n` trong mọi package có `l10n.yaml`, `build_runner build --workspace`, rồi barrel generator cho mọi package có `lib/` (bỏ qua các app). Đây **chính là** bước setup. Chỉ chạy `pub get` + `build_runner` thì các barrel `lib/src/gen/gen.dart` bị gitignore sẽ không có, và `flutter analyze` khi đó báo lỗi ở `gen/gen.dart`, `AppLocalizations` và `Assets`.

Script làm việc trên gốc repo bất kể thư mục làm việc. `--help` / `-h` in các bước và thoát `0`; mọi tham số khác ngoài `--stub-firebase` thoát `64` **trước khi chạy bất cứ gì** — trước đây script bỏ qua tham số, nên `--help` chạy toàn bộ bước setup có tính phá huỷ.

**`--stub-firebase`** — ghi thêm các file Firebase thay thế **chỉ để compile**, ngay đầu tiên, trước mọi bước codegen (`build_runner` phải resolve được các import của mỗi `firebase_module.dart`; danh sách file đã ghi được in ở cuối), cho bản checkout chưa có project Firebase, đúng những file CI ghi (các job của CI gọi chính cờ này): một `firebase_options_<flavor>.dart` cho mỗi flavor mà `lib/firebase/firebase_module.dart` của app import, và một `android/app/src/<flavor>/google-services.json` cho mỗi product flavor của app có `android/app/build.gradle(.kts)` áp dụng plugin Google Services, với `package_name` = `applicationId` + `applicationIdSuffix` của flavor đó, đọc từ cùng file. **Chỉ ghi file còn thiếu** — file thật luôn được giữ — và mọi đường dẫn đều được in ra, kèm một khung cảnh báo rằng đây không phải cấu hình thật: app compile được và build được APK, nhưng push notification, FCM token và mọi lời gọi Firebase khác đều không hoạt động. Nội dung nằm ở `tools/workspace_setup/firebase_stubs.dart`, file chỉ import `dart:io`: `configure.dart` tự chạy `pub get`, nên không thứ gì nó import được phép cần một package đã resolve.

> [!CAUTION]
> **Không có** `configure.sh` và **không có** `configure.bat`. Chỉ tồn tại `configure.dart` — gọi nó bằng `dart`, đừng bao giờ qua một wrapper shell.

### `firebase`

```bash
dart tools/firebase/firebase_config.dart              # app duy nhất của workspace
dart tools/firebase/firebase_config.dart --app mobile # một trong nhiều app
dart tools/firebase/firebase_config.dart --help       # cú pháp
```

Chạy `flutterfire configure` bên trong app được chọn cho từng flavor và build mode, sinh ra ba file `lib/firebase/firebase_options_*.dart` mà `lib/firebase/firebase_module.dart` của chính app đó import (với app mẫu là `apps/mobile/lib/firebase/firebase_module.dart`), cùng `GoogleService-Info.plist` và `google-services.json` theo flavor. Khi có nhiều app mà không truyền `--app`, script liệt kê các app rồi thoát thay vì cấu hình bừa một app.

> [!WARNING]
> Ba file sinh ra đó bị git ignore, và `firebase_module.dart` import **cả ba một cách vô điều kiện**. Do đó một bản clone mới **không compile được** cho tới khi chạy lệnh này — kể cả khi bạn chỉ build dev. Xem [`../getting-started/01_setup.md`](../docs/vi/getting-started/01_setup.md).

Phải chạy từ thư mục gốc repo; script kiểm tra sự tồn tại của `pubspec.yaml` rồi mới chạy tiếp.

Script cần **Firebase CLI đã được cài và đã đăng nhập**. Cụ thể là Node.js + npm, `npm install -g firebase-tools`, và một lần `firebase login` tương tác bằng tài khoản Google có quyền vào Firebase project của bạn. Script không còn tự cài CLI: nếu `firebase` không có trong `PATH`, nó in hướng dẫn cài đặt rồi thoát với mã `1`. Khi chưa đăng nhập hoặc phiên đã hết hạn, nó chạy `firebase login` **tối đa hai lần**, rồi thoát với mã `1` và yêu cầu bạn tự đăng nhập (`firebase login` trả về thành công mà không đăng nhập khi không mở được prompt, nên vòng lặp thử lại vô hạn trước đây không bao giờ dừng). Ngược lại, FlutterFire CLI thì được activate qua `dart pub global activate` khi còn thiếu.

Script chạy tương tác — không có dạng cờ cho các câu trả lời — nên nó **từ chối chạy khi không có terminal** (exit `1`). Tham số khác `--app <id>` / `--help` thoát với mã `64`. Script chỉ hỏi một project ID và dùng nó cho **mọi** flavor. Muốn mỗi flavor một project, hoặc cần stub chỉ để biên dịch khi chưa có Firebase project, xem [`../getting-started/01_setup.md`](../docs/vi/getting-started/01_setup.md) § 3.

### `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart              # app duy nhất của workspace
dart tools/theme_generator/theme_setting.dart --app mobile # một trong nhiều app
dart tools/theme_generator/theme_setting.dart --help       # cú pháp
```

Điều khiển `flutter_native_splash` và `icons_launcher` dựa trên các file cấu hình theo flavor ở gốc repo (`flutter_native_splash-*.yaml`, `icons_launcher-*.yaml`).

Trước khi ghi bất cứ thứ gì, tool kiểm tra app có nhận được chúng không: app cần có `android/` và `ios/` (các file cấu hình bật cả hai nền tảng), phải khai báo `flutter_native_splash` và `icons_launcher` trong `pubspec.yaml`, và các file cấu hình phải nằm ở gốc repo. Thiếu gì thì liệt kê ra rồi thoát với mã `1`. **`--app admin` hiện bị từ chối** — `apps/admin` không có thư mục nền tảng và không khai báo package nào trong hai package trên. Nếu một generator fail giữa chừng, mọi file nó đã tạo hoặc sửa dưới `android/`, `ios/` và `web/` của app được khôi phục, và tool thoát với mã `1`; các file cấu hình đã chép vào app luôn được xoá. Tham số khác `--app <id>` / `--help` thoát với mã `64`.

### `android_compliance`

```bash
# Trước hết build APK release của một flavor (cd apps/mobile && flutter build apk --flavor dev --release), rồi:
./tools/android_compliance/16kb_check.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk     # macOS / Linux
.\tools\android_compliance\16kb_check.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

Kiểm tra một APK (căn chỉnh zip, rồi căn chỉnh ELF của các thư viện native `.so` bên trong), một APEX, hoặc một thư mục thư viện native xem đã tương thích 16 KB page-size cho Android 15+ chưa. Tool nhận đúng một đường dẫn; không truyền gì thì in cú pháp và thoát với mã `1`, còn `--help` in cú pháp với mã `0`. File phải là `.apk`, `.apex` hoặc một `.so` — file khác (kể cả `.aab`) thoát `1`. APK mà `unzip` không đọc được (không phải zip, bị cắt cụt) thoát `1`; chỉ trường hợp "không có entry `lib/*`" (unzip exit `11`) mới là kết quả đạt không-có-thư-viện-native — trước đây mọi lỗi unzip đều bị báo thành kết quả đạt đó. File `.sh` có quyền thực thi, nên lệnh `./` chạy được đúng như viết; file `.bat` chỉ là wrapper chạy `.sh` qua Git Bash và trả về mã thoát của nó. Đây là công cụ duy nhất trong repo viết bằng shell script thay vì Dart.

### `code_review`

```bash
dart tools/code_review/code_review.dart --all
dart tools/code_review/code_review.dart --changed
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart
dart tools/code_review/code_review.dart --all --focus architecture,security
dart tools/code_review/code_review.dart --all --language vi   # chỉ cho lần chạy này
```

Review bằng Gemini, điều khiển bởi `tools/code_review/review_prompt.md`. Cần Gemini API key: `GEMINI_API_KEY`, `--api-key`, hoặc — khi tool hỏi và bạn đồng ý lưu — file đã gitignore `tools/code_review/.gemini_api_key`. Không có key và không có terminal để hỏi (CI, pipe) thì tool in ra stderr chỗ cần đặt key rồi thoát với mã `1`. Key được gửi qua header `x-goog-api-key`, không bao giờ nằm trong URL, và được xoá khỏi mọi thông báo lỗi, nên lỗi mạng không thể in nó ra terminal hay log CI. Chạy từ root repo, `--all` review mọi `lib/` dưới `apps/`, `modules/` và `platform/`. `--file` hoặc `--folder` không tồn tại thoát `1` trước cả khi đọc API key — trước đây tool in "File not found", không review gì và thoát `0`. Giá trị `--focus` hợp lệ: `security`, `performance`, `bugs`, `style`, `architecture`, `testing`.

- **Luôn bị loại**, dù `--exclude` có thêm gì: file sinh tự động (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`, `*.mocks.dart`, `lib/src/gen/**`, `firebase_options_*.dart`), file test, và mọi file bị git ignore. (Trước đây chỉ một `--exclude` là tắt luôn các loại trừ mặc định.)
- **`--language`** chỉ áp dụng cho lần chạy đó và không được lưu lại; mặc định là `reportLanguage` trong `code_review_config.json` (file được track), đổi bằng `--config`.
- **Báo cáo luôn là Markdown.** `--format` chỉ nhận `markdown`, giữ lại để các script đang truyền `--format markdown` không vỡ.
- Tuỳ chọn lạ hoặc tham số vị trí thừa thoát với mã `64`.

> [!NOTE]
> Workflow GitHub chạy nó ở **chế độ cảnh báo** — bước "fail on critical issues" có dòng `exit 1` bị comment lại, nên nó không bao giờ chặn PR. Xem [`../operations/01_cicd.md`](../docs/vi/operations/01_cicd.md).

### `coverage_report`

```bash
flutter test --coverage                              # trong từng package: ghi <pkg>/coverage/lcov.info (gitignore)
dart tools/coverage_report/report.dart               # mọi */coverage/lcov.info dưới gốc repo
dart tools/coverage_report/report.dart --min 60      # thoát 1 khi TỔNG thấp hơn 60 %
dart tools/coverage_report/report.dart --min-package 40   # thoát 1 khi BẤT KỲ package nào thấp hơn 40 %
```

In line coverage của từng package thành bảng Markdown — package, đường dẫn, số file, số dòng, số dòng được phủ, % và một dòng tổng — và nối nó vào `$GITHUB_STEP_SUMMARY` khi biến này được đặt (`--no-summary` tắt việc đó). CI Gate 3 chạy test của mọi package với `--coverage` rồi chạy bước này, chỉ mang tính tham khảo: không ngưỡng, `continue-on-error`, và vẫn chạy khi có test fail. File sinh ra — `*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gr.dart`, `*.mocks.dart`, mọi thứ dưới `gen/` — bị loại, và một dòng chỉ được đếm một lần dù có bao nhiêu bản ghi `DA:` nhắc tới nó. Chỉ file mà một test nào đó đã nạp mới xuất hiện trong `lcov.info`, nên một file chưa test mà không ai import sẽ không kéo con số xuống. Không tìm thấy `lcov.info` nào thì thoát `1`; tham số sai thoát `64`.

### Test cho các tool (`tools/test/`)

Mọi gate trong `pr_quality_check.yml` là một trong các script ở trên, và một gate đã âm thầm thôi fail trông y hệt một PR sạch. `tools/test/` là thứ ngăn điều đó: nó chạy như nửa sau của CI Gate 1, ngay sau `arch_check`.

```bash
cd tools && dart test                            # cả bộ, ~15 giây
cd tools && dart test test/arch_check_test.dart  # một tool
```

Mỗi test dựng một workspace dùng một lần bằng `Directory.systemTemp.createTemp` — vài pubspec, một manifest, một file nguồn — chạy tool trên đó như một subprocess rồi kiểm tra exit code và output. Không có gì chạm vào repo thật. `test/support/tool_harness.dart` compile mỗi tool thành kernel snapshot một lần cho mỗi file test (snapshot khởi động ~0,5 giây thay vì ~1,7 giây), và với `docs_check` — tool tìm repo từ vị trí script của chính nó — thì copy snapshot vào workspace tạm tại `tools/docs_check/`.

| File | Phủ |
|:---|:---|
| `arch_check_test.dart` | Một fixture sạch và một fixture vi phạm cho mỗi luật R1–R20 (R6 cảnh báo mà vẫn exit `0`), DAG giữa các nhóm theo từng cạnh (ui → state, infra → infra, mọi thứ từ `domain_core`, foundation → shell, package nằm ngoài thư mục nhóm, nhóm platform chạm tới `modules/`), `data_core` / `domain_core` chạm tới feature, API hay domain của module (R1), các danh sách thuần Dart (R2 / R9: thư viện transport, plugin Flutter lấy từ hosted, package chạm Flutter SDK gián tiếp, package workspace có dependency Flutter), các luật tầng module trong import và pubspec (feature khai feature mà không import, data → feature, data → data của module khác), test của app import module (R10), `analysis_options.yaml` cục bộ của package (R13), thư mục `datasources` dưới `apps/` (R14) và các luật package API (domain của chính nó, API khác, package platform ngoài foundation, lookup ném lỗi, import R1/R10); workspace rỗng thì fail; flag lạ exit `64`; R16: một lookup tuỳ chọn chưa vào catalog (do module hiện thực, hoặc không ai đăng ký), một dòng cho type không package nào khai, một dòng parser không đọc được, không có catalog; R8: mọi cách viết lookup (`getIt.get<T>()`, `getIt.getAll<T>()`, `GetIt.I<T>()`, `GetIt.instance<T>()`, type argument bị tách dòng, `getIt()` không kiểu gán vào một type) và tham số bắt buộc thuộc module trên một `@injectable` ngoài module; R7 trong file không import `core_responsive`; R18: closure block và arrow đồng bộ, tear-off của method không async / `void` / không trả `Future<void>`, template bloc của generator (sạch, và bị bắt khi bỏ `async`); R19: `print` / `debugPrint` / `debugPrintStack` trong `lib/` của platform và module, không trong test, tool, comment hay chuỗi; R20: từng constructor và đối số có tên, lời gọi nhiều dòng, `styles/` và `utils/` được miễn; R17: từng cách viết nhánh trong feature và trong app, resolver được phép, comment, chuỗi, test và file ngoài `lib/` bị bỏ qua, một mục allow-list đã cũ (file không còn rẽ nhánh, hoặc đã mất), một mục không có lý do |
| `contract_scan_test.dart` | Bộ quét `arch_check` và `composer` dùng chung: đăng ký theo luật đúng-type (class có annotation, chỉ phần `as:` gán, thành viên `@module`, `Future<X>`, environment), thứ không phải code (comment, chuỗi, block comment), `implements` không đăng ký gì; phép quét nơi hiện thực R8 dùng, không đổi sau khi tách; type đã khai, file sinh, lookup tuỳ chọn |
| `composer_checks_test.dart` | V3, V7, V10, V11, V12, V17 — mỗi check một fixture sạch và một fixture vi phạm (khai `provided` mà không ai đăng ký, mà package đăng ký không được ghép, khai `absent` mà vẫn có đăng ký, bundle đăng ký nửa chừng, `implements` không phải đăng ký, contract required không ai đăng ký; web với `core_database`, module đã kéo một package vào, package chỉ được tới qua package khác (chuỗi được nêu) và dev dependency không bị đi theo; thiếu `FirebaseOptions` cho `prod`; key env chưa khai và key thiếu; entry point không có `profile:`, smoke test bị xoá, smoke test không bao giờ gọi `checkAppContract`, smoke test không có `callFactories: true` (thiếu, `false` hoặc chỉ nằm trong comment); pubspec của thành viên có key `workspace:` riêng, được nêu tên trong `verify` và chỉ bị cảnh báo ở `sync`); `sync` cảnh báo còn `verify` fail; trên các app đã commit, phép quét tĩnh tái hiện đúng ma trận lúc chạy (mobile thiếu `IErrorReporter` và `IAnalytics`; admin còn thiếu thêm contract splash, entry, dashboard và post-sign-in) |
| `app_sync_test.dart` | Các enum composer viết lại, catalog (7 required, 14 optional), `PlatformFacts.today()` và `WindowClass` bằng nguồn của chúng; dead-key guard (mọi key manifest và cả hai key pubspec đều có nơi đọc); `platforms:` / `app_provides` đang phát hành của `core_notifications` và `core_database`; mỗi mục allow-list R17 nêu một file tồn tại |
| `composer_native_profile_test.dart` | Bộ đọc Gradle và Xcode (DSL Groovy và Kotlin, suffix, comment, configuration release thắng), bộ đọc profile (các section ở cấp ngoài cùng của `AppProfile(`, comment bị bỏ qua); trên một app fixture: V15 (flavor runner thiếu và flavor manifest đã bỏ, runner không nêu flavor, ID trong báo cáo), V11 cho file env của flavor chưa khai, V16 (thiếu và `TODO` ở `why`, `feature` trước `domain`), mục 5 của báo cáo (app không đặt gì, section được tinh chỉnh in đúng như viết), lối ra của thông báo từ chối pin |
| `composer_new_test.dart` | `composer new` trong một workspace dùng một lần chứa `app_template/` thật: app qua `verify` ngay, `capabilities:` của nó theo những gì các module đăng ký (`not composed: ...`, không bao giờ là văn bản fallback của shell, không bao giờ `TODO`), `core_database` chỉ vào `core` khi được liên kết, staging và prod có quyết định pin ở nơi một platform pin được, import của smoke test được sắp theo id và nó dựng factory (`callFactories: true`), smoke test của app database có sẵn double còn app thường thì không, app không có màn hình được báo; nó từ chối một id đã có, một platform bị module chặn, module hay platform lạ, id hay tên sai, thiếu `--platforms`, thiếu template — mỗi trường hợp để workspace nguyên từng byte — và không bao giờ tạo thư mục runner |
| `composer_test.dart` | `sync` rồi `verify` thì qua; layer `api` chỉ là workspace member, package API chỉ được chạm tới qua một feature vẫn vào workspace, thiếu nó thì `verify` fail; vùng managed bị sửa tay, module không có trên đĩa, `phase: befor`, layer lạ và module trùng exit `1` kèm đường dẫn key; package có trên đĩa mà không app nào lắp ráp làm `verify` fail và chỉ cảnh báo khi `sync` |
| `dependency_sync_test.dart` | `--check`: khớp thì qua; lệch version, catalog sai định dạng và YAML hỏng exit `1`; mục `dependencies:` / `dev_dependencies:` mà catalog không pin (version trần, `hosted:`, `any`) exit `1` kèm tên pubspec, section và package, còn nguồn `sdk:` / `path:` / `git:` thì qua (RULE-74) |
| `docs_check_test.dart` | Đường dẫn hay link chết exit `1`; span `<placeholder>`, đường dẫn trong allowlist và sample bundle đã gỡ (INFO) exit `0`; gốc repo lấy từ script chứ không từ cwd; tương đương en ↔ vi: thiếu heading, code block hay dòng bảng exit `1` kèm cả hai con số, fence bị bỏ qua, chênh lệch có trong allowlist thì qua, entry cũ thì cảnh báo, entry không lý do bị từ chối |
| `module_generator_test.dart` | `--apps` với id lạ, không có giá trị, danh sách rỗng hoặc truyền hai lần exit `64` và không ghi gì; loại 6 (API) từ chối `<SM>`, prefix, `--group`, tên `<name>_api` đã có và trỏ tới `modules/<name>/api`; `registerInAppManifests` mặc định đụng mọi manifest, với `apps:` thì chỉ các manifest được liệt kê, và thêm `api` vào đầu `layers:` của module |
| `unused_checker_test.dart` | `check_unused_packages`: khai báo không được import bị báo (exit `2`), import chỉ trong test vẫn tính, mỗi ngoại lệ không cần import chỉ đúng khi có lý do của nó (`l10n.yaml`, `json_serializable`, `flutter_gen`); `check_unused_file`: file chỉ được barrel của chính nó export bị báo, gọi tên một khai báo là dùng file đó, file DI và routing là entry point |
| `firebase_stubs_test.dart` | Stub của `--stub-firebase`: một file Dart cho mỗi flavor được import, một `google-services.json` cho mỗi product flavor Gradle với package name có hậu tố (không lấy `signingConfigs`), file thật được giữ, app không dùng Firebase hay plugin thì bỏ qua; `configure.dart` không chạm tới import `package:` nào |
| `coverage_report_test.dart` | Parse lcov (bỏ file sinh ra, mỗi dòng đếm một lần), bảng và dòng tổng, job summary, `--min` / `--min-package`, exit `1` khi không có `lcov.info`, `64` khi tham số sai |
| `barrel_generator_test.dart` | Dấu `/` ở cuối đường dẫn; thư mục `web/` bên trong `lib/` được export, `web/` nền tảng nằm cạnh thì không; export viết tay bị thay |
| `bootstrap_test.dart` | `--dry-run` báo member workspace và dependency của app bị thiếu mà không ghi gì; bỏ `--dry-run` thì các vùng managed bị cắt |
| `remove_sample_test.dart` | Package API mà module khác import được giữ lại (dry-run nêu tên, `--apply` giữ thư mục và mục workspace, viết lại manifest thành `layers: [api]`), chạy lần hai khi không còn ai import thì xoá nó, package API không ai import thì đi cùng module |

Khi sửa một gate, hãy thêm case lẽ ra đã bắt được bug đó. `package:test` là dev dependency duy nhất (ghim trong `pubspec_dependencies.yaml`); fake chỉ là file thường trên đĩa.

---

**Tiếp theo:** [`04_review_checklist.md`](../docs/vi/reference/04_review_checklist.md) · [`01_rules.md`](../docs/vi/reference/01_rules.md) · [`../getting-started/03_daily_workflow.md`](../docs/vi/getting-started/03_daily_workflow.md)

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
