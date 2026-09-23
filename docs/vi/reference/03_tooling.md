# Tra cứu công cụ

**File này trả lời:** chạy script nào, với tham số gì, và khi nào?

**Đọc xong bạn có thể:** chọn đúng công cụ cho mọi việc bảo trì, và biết trước cạm bẫy của nó.

Tất cả công cụ nằm trong `tools/`, đều là Dart thuần — chạy từ **thư mục gốc repo**.

---

## Vấn đề → công cụ

| Vấn đề | Lệnh |
|---|---|
| **Kiểm tra luật phân tầng còn đúng không** | `dart tools/arch_check/check.dart` |
| **Kiểm tra docs còn mô tả đúng cây thư mục hiện tại** | `dart tools/docs_check/check.dart` |
| **Package nào là code mẫu có thể xoá?** | `dart tools/sample_cleanup/remove_sample.dart --list` |
| **Xoá một package mẫu một cách an toàn** | `dart tools/sample_cleanup/remove_sample.dart <tên>` |
| Tạo package feature / domain / data / core mới | `dart tools/module_generator/generate.dart …` |
| Vừa thêm, đổi tên hoặc xoá file trong `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Vừa đổi version dependency | `dart tools/dependency_sync.dart` |
| CI cần chặn lệch version | `dart tools/dependency_sync.dart --check` |
| Nghi có asset / file / translation / package chết | `dart tools/unused_checker/check_script.dart` |
| Muốn biết gì đã lỗi thời trên pub.dev | `dart tools/check_outdated.dart` |
| Vừa clone về, cần dựng mọi thứ | `dart tools/workspace_setup/configure.dart` |
| Cấu hình Firebase cho dev / staging / prod | `dart tools/firebase/firebase_config.dart --app mobile` |
| Sinh lại splash screen và app icon | `dart tools/theme_generator/theme_setting.dart --app mobile` |
| Kiểm tra tương thích 16 KB page-size của Android 15+ | `./tools/android_compliance/16kb_ckeck.sh` |
| Nhờ AI review một thay đổi | `dart tools/code_review/code_review.dart --changed` |

---

## `arch_check`

Cưỡng chế luật phân tầng bằng máy. **Gate 1 của `pr_quality_check.yml`** — chạy trước `flutter analyze` vì nó chỉ đọc import và `pubspec.yaml`, không cần codegen, xong trong khoảng 200 ms.

```bash
dart tools/arch_check/check.dart          # exit 1 khi có vi phạm chặn
dart tools/arch_check/check.dart --help   # mô tả đầy đủ từng luật
```

| Luật | Kiểm tra gì |
|---|---|
| R1 | Hướng phụ thuộc — `core/*` không được import hay khai `feature_*` / `data_*` / `domain_*`, trừ các ngoại lệ đã duyệt |
| R2 | Domain thuần Dart — không import `flutter` / `dio` / `retrofit`, không khai `flutter` trong `dependencies:` |
| R3 | Ranh giới feature — không feature nào import feature khác hay package `data_*` |
| R4 | `static const` public phải nằm trong `utils/` của package |
| R5 | Mọi `package:` import dùng trong `lib/` phải được khai trong `pubspec.yaml` của chính package đó |
| R6 | File generated còn giữ header của generator (chỉ cảnh báo) |
| R7 | Scale responsive phải qua `BuildContext` — cấm receiver trần `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`, trong mọi file dùng `core_responsive` |
| R8 | Contract của `core_di` mà chỉ feature implement thì phải resolve bằng `getItOrNull` / `getAllOrEmpty`, cấm `getIt` / `getAll` (dạng ném lỗi) |
| R9 | `platform_kernel` và mọi package `*_contracts` không import **và không khai** package kéo theo Flutter |
| R10 | Không file nào trong một app (`apps/<id>/`) import module — chỉ `injection.dart`, điểm lắp ráp, được phép gọi tên một module. (`platform/app_shell` là core nên do R1 phủ) |

Ba ngoại lệ hướng lên được hardcode trong tool **và in ra mỗi lần chạy**, kèm lý do từng cái — để chúng không mục ruỗng âm thầm trong một dòng comment. Thêm cái thứ tư nghĩa là phải sửa cả `.agents/AGENTS.md` lẫn danh sách cho phép trong `check.dart`, nếu không build sẽ fail.

R7 tồn tại vì `flutter analyze` không thấy được khác biệt này. Bản thân `core_responsive` không cung cấp extension nào trên `num`, nên `16.h` không phân giải được về nó — nhưng một extension khai ở package khác, hoặc do ai đó tự thêm cục bộ, vẫn type-check sạch trong khi đọc một biến toàn cục chẳng báo cho ai. Chỉ `context.h(16)` mới đăng ký dependency `InheritedWidget` lên `ResponsiveScope`, tức mới rebuild khi metrics đổi. Dạng trần là một lỗi giá trị cũ âm thầm, và không linter nào có luật cho nó. Check chỉ chạy trên file có tham chiếu `core_responsive`, và khớp receiver là số hoặc dấu đóng ngoặc theo sau bởi `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`.

R10 tồn tại vì tính tháo-lắp được là lời hứa template đưa ra trong bốn tài liệu mà không có gì kiểm tra. `network_config_impl.dart` import `data_auth` và `domain_auth` để đọc và làm mới token phiên, nên xoá module auth là app shell hỏng ngay ở khâu biên dịch — đúng một chỗ trong shell phá đi thứ mà mọi file còn lại cẩn thận giữ gìn. `getItOrNull` không cứu được: nó canh một *lookup*, còn lỗi ở đây là một *import*, thứ trình biên dịch giải quyết từ rất lâu trước khi có lookup nào chạy. Cách sửa là một hợp đồng (`IAuthSessionGateway` trong `core_di`, do `data_auth` hiện thực), và phép kiểm là một dòng chính sách — một app được phép import package module ở đúng một file, điểm lắp ráp, vì nhiệm vụ của file đó chính là gọi tên những gì nó lắp.

R8 tồn tại vì khả năng tháo module là tính chất mà app shell dựa vào, nhưng trước đó không có gì giữ nó. Tool tự suy ra tập hợp lúc chạy: mọi type khai trong `core_di`, thu hẹp lại còn những type mà ràng buộc `implements` / `extends` / `as:` duy nhất nằm trong một package `modules/*/feature`. Một lookup ném lỗi lên các type đó vẫn compile — package gọi nó phụ thuộc `core_di` chứ không phụ thuộc feature — rồi crash lúc runtime ở bản build không có feature đó. Contract do app shell implement (`IThemeStorage`, `ILanguageStorage`) thì luôn được đăng ký, nên cố ý nằm ngoài tập hợp này. Feature sở hữu được miễn trừ với chính contract của nó: package đã có trong build thì đăng ký của nó cũng có.

R5 là ảnh gương của `unused_checker`: tool kia tìm dependency *đã khai mà không dùng*, tool này tìm dependency *đang dùng mà không khai*. Pub Workspaces che giấu hoàn toàn loại thứ hai — mọi thứ resolve được cục bộ qua `package_config.json` dùng chung, và chỉ vỡ khi tách package ra hay publish.

---

## `composer`

```bash
dart tools/composer/composer.dart list              # liệt kê app và thành phần
dart tools/composer/composer.dart sync --app mobile # sinh lại
dart tools/composer/composer.dart verify            # gate 0 của CI — fail khi lệch
```

Ba thứ phải khớp nhau và trước đây đều sửa tay: danh sách `workspace:` ở root, dependency dạng path của app, và `lib/di/injection.dart` của nó. Thêm một module nghĩa là sửa cả ba cho khớp, và sai thì vỡ lúc boot với `"<Type> is not registered"` — thứ `flutter analyze` không thấy được.

`composer` sinh cả ba từ các `app_manifest.yaml` — file riêng của mỗi app từ manifest của chính nó, còn danh sách `workspace:` dùng chung ở root từ tất cả manifest gộp lại — nhưng **chỉ** phần nằm giữa marker `composer:managed:<region>` và `composer:end:<region>`. Dependency ngoài, flavor và khai báo asset vẫn viết tay.

Package được phân giải theo **tên**, tìm bằng cách quét `pubspec.yaml`. Không chỗ nào mã hoá đường dẫn, nên di chuyển package không phải sửa tool hay manifest. Package của module khớp được cả hai quy ước đặt tên — `domain_auth` và `auth_domain` đều nhận.

`--strict` (tự động bật trong `verify`) biến "manifest khai một module không có trên đĩa" từ cảnh báo thành lỗi. Không có nó, `sync` ghép những gì tìm được — chính điều này cho phép một dev làm việc khi chỉ checkout module của mình.

Cả `sync` lẫn `verify` còn **từ chối** một pubspec của app khai báo tay một package do composer quản lý ở ngoài vùng marker. Pub từ chối key trùng, nên chỉ một lỗi đó là cả workspace ngừng resolve — và đó chính là lỗi composer từng tự gây ra.

Một lần sync không strict mà có bỏ qua thứ gì sẽ in ra khối **`PARTIAL COMPOSITION`**: các file đã-commit mà nó vừa ghi đè (`pubspec.yaml` gốc, cùng `pubspec.yaml` và `injection.dart` của mỗi app được sync), cùng dòng `git checkout --` để khôi phục. Phép lắp ráp nó viết ra đúng ở local và sai khi commit, và CI Gate 0 bắt được trong mọi trường hợp, vì `verify` sinh lại từ manifest trên runner có đủ mọi module. Xem [`12_module_isolation.md`](../guides/12_module_isolation.md).

---

## `docs_check`

**Gate 5 của `pr_quality_check.yml`.** Giải đường dẫn cho mọi path trong repo mà tài liệu nhắc tới, và fail ngay ở cái đầu tiên không tồn tại.

```bash
dart tools/docs_check/check.dart            # thoát 1 nếu có tham chiếu chết
dart tools/docs_check/check.dart --verbose  # kèm block allowlist để copy-paste
```

Hai loại tham chiếu được kiểm tra trong mọi file Markdown của repo — chỉ bỏ qua trạng thái tool, output build và dependency native tải về (`.dart_tool`, `build`, `Pods`, …). Trước đây nó chỉ phủ `docs/`, `.agents/`, `README.md` và `CLAUDE.md`; mở rộng ra thì lộ 11 link chết trong các hướng dẫn ở `.github`, một README của package và README của fastlane:

| Loại | Ví dụ | Cách giải |
|---|---|---|
| Path trong backtick | `` `platform/kernel/lib/platform_kernel.dart` `` | Tính từ gốc repo, nhưng chỉ khi chuỗi bắt đầu bằng một thư mục top-level có thật |
| Markdown link | `[…](../../../tools/arch_check/check.dart)` | Tương đối với **file chứa link**, không phải thư mục đang chạy lệnh |

Phép thử "thư mục top-level" chính là thứ làm cho check này dùng được. Repo đầy những chuỗi backtick trông như path nhưng không phải: `utils/` và `routing/` là quy ước tồn tại trong cả chục package, `ViewState` là một type, `flutter pub get` là một lệnh. Coi chúng là path sinh ra 817 "lỗi" ở lần chạy đầu và sẽ dạy cả team thói quen phớt lờ gate này. Neo vào `platform/`, `modules/`, `apps/`, `tools/`, `docs/`, `.agents/`, `.github/` còn lại khoảng 1 300 tham chiếu thật — và những chuỗi bị bỏ qua đúng là loại reviewer nhìn mắt thường cũng xác minh được.

Chuỗi có khoảng trắng, `*`, `{` hoặc `<` cũng bị bỏ qua: đó là lệnh shell, glob hoặc placeholder, mỗi thứ mô tả một *tập hợp* chứ không phải một file.

Những path vắng mặt một cách chính đáng nằm trong `tools/docs_check/allowlist.txt`, mỗi dòng một path kèm lý do. Chỉ đúng ba lý do được chấp nhận:

1. **Sinh tự động** — `apps/mobile/lib/di/injection.config.dart`, build output.
2. **Bí mật** — `apps/mobile/env.prod`, `apps/mobile/android/key.properties`; không bao giờ commit.
3. **Hướng dẫn** — file mà người đọc *được bảo là hãy tạo ra* (`app_elevation.dart` trong guide design system), hoặc placeholder đại diện cho module của chính người đọc (`modules/profile/feature`).

Mọi trường hợp khác là drift, và cách sửa là sửa tài liệu. Một entry không kèm lý do là không hợp lệ — khoảnh khắc allowlist trở thành danh sách những path ai đó bịt miệng, gate này hết đáng chạy.

> [!NOTE]
> Check này cố ý không nói gì về việc tài liệu có *đúng* hay không, chỉ nói những thứ nó trỏ tới có tồn tại hay không. Đó là một chuẩn thấp, và là chuẩn duy nhất máy giữ được. Trích dẫn theo số dòng (`generate.dart:90-101`) fail check này theo thiết kế — đó là loại tham chiếu mục nhanh nhất, còn gọi tên symbol thì sống sót qua mọi chỉnh sửa phía trên nó.

---

## `sample_cleanup`

Trả lời câu "cái nào là code mẫu, và xoá sao cho không vỡ app?".

```bash
dart tools/sample_cleanup/remove_sample.dart --list    # bảng phân loại
dart tools/sample_cleanup/remove_sample.dart auth      # dry-run (mặc định)
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

Nguồn chân lý của nó là [`tools/sample_manifest.yaml`](../../../tools/sample_manifest.yaml), phân loại mọi package thành `framework`, `sample` hay `shell`. Không có code mẫu nào nằm bên trong package framework: mỗi sample là một package riêng, nên gỡ một sample luôn là thao tác gỡ trọn một bundle.

Phần đáng đọc nhất là output của dry-run. Xoá `auth` không chỉ là ba thư mục: nó in ra chính xác những dòng cần gỡ khỏi `pubspec.yaml` gốc và khỏi manifest, pubspec, `injection.dart` của mọi app, các contract trong `core_di` trở thành code chết, **và sample nào sẽ vỡ, vỡ như thế nào** — `HomeProfileBloc` nhận `IAuthStatusStream` qua constructor nên DI không dựng nổi — cùng các liên kết xuống cấp an toàn, như `feature_settings` ẩn dòng logout khi `getItOrNull<IAuthActionHandler>()` trả về null.

Chỉ ghi khi truyền `--apply`, và các file dùng chung được snapshot trước để fail giữa chừng thì rollback được.

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
| `<dir>` | chỉ cho type `5` — tiền tố tên package: `<dir>_<name>` tại `platform/<name>`. Từ chỉ tầng (`feature`, `domain`, `data`, `core`) bị từ chối; hãy dùng type 1–4 |
| `<sm>` | chỉ feature — `1` Provider · `2` BLoC · `3` không dùng |
| `<route>` | chỉ feature — `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` không |

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1   # feature + Provider + route stack
dart tools/module_generator/generate.dart 1 chat    "" 2 2   # feature + BLoC + tab bottom-nav
dart tools/module_generator/generate.dart 2 payment          # domain micro-package
dart tools/module_generator/generate.dart 3 payment          # data micro-package
```

Chạy thiếu tham số thì nó sẽ hỏi tương tác.

**Nó làm gì:** tạo cây thư mục (bao gồm `lib/src/utils/`, cho mọi tầng), render template, thêm module vào mọi `app_manifest.yaml`, chạy `composer sync` (sinh lại danh sách `workspace:` ở root cùng `pubspec.yaml` và `lib/di/injection.dart` của từng app), rồi dependency sync, `pub get`, `gen-l10n`, barrel generator, `build_runner`, và `dart fix --apply` trên package mới.

> [!IMPORTANT]
> Nó không bao giờ tự ghi danh sách `workspace:` ở root, `pubspec.yaml` hay `lib/di/injection.dart` của app. Các file đó nằm giữa marker `composer:managed` và chỉ `composer sync` ghi chúng — một dòng thêm ngoài marker là dòng composer không bao giờ xoá, còn sửa tay bên trong là drift mà CI Gate 0 chặn.

**Hành vi an toàn**

- **Kiểm tra toolchain trước tiên.** `assertToolchainAvailable()` chạy trước khi động vào bất cứ file dùng chung nào, nên thiếu SDK là fail ngay lập tức thay vì chết ở bước 8.
- **Từ chối thư mục đã tồn tại.** Nó sẽ không âm thầm ghi đè lên package có sẵn.
- **Rollback khi thất bại.** Các file dùng chung bị thay đổi — mọi `app_manifest.yaml`, và những gì `composer sync` ghi lại (`pubspec.yaml` gốc, `pubspec.yaml` và `lib/di/injection.dart` của từng app) — được sao lưu trước mọi thao tác ghi; nếu bước sau fail thì chúng được khôi phục và thư mục module mới bị xoá.
- **Tự phát hiện FVM**, yêu cầu *cả hai*: có file cấu hình (`.fvmrc` hoặc `.fvm/fvm_config.json`) *và* `fvm --version` chạy được. Chỉ một tín hiệu thôi là cho kết quả sai: repo này pin version trong `.fvmrc` trong khi một máy cụ thể có thể không hề cài `fvm`.

> [!NOTE]
> Module domain và data chỉ được tạo thư mục và nối pubspec — entity, use case, repository phải viết tay. Xem [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md).

---

## `barrel_generator`

```bash
dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib
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
> Nó parse theo từng dòng chứ không dùng YAML parser, nên `dependency_overrides` và cú pháp multi-line/anchor không được xử lý. Dependency native của Gradle (ví dụ `play-services-auth` trong `apps/mobile/android/app/build.gradle.kts`) hoàn toàn nằm ngoài phạm vi của nó — chúng không có nguồn chân lý tập trung nào.

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

Dựng đầy đủ cho một bản clone mới: activate `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n`, `build_runner`, rồi barrel generator cho từng package.

> [!CAUTION]
> **Không có** `configure.sh` và **không có** `configure.bat`. Chỉ tồn tại `configure.dart` — gọi nó bằng `dart`, đừng bao giờ qua một wrapper shell.

---

## `firebase`

```bash
dart tools/firebase/firebase_config.dart              # app duy nhất của workspace
dart tools/firebase/firebase_config.dart --app mobile # một trong nhiều app
```

Chạy `flutterfire configure` bên trong app được chọn cho từng flavor và build mode, sinh ra ba file `lib/firebase/firebase_options_*.dart` mà `lib/firebase/firebase_module.dart` của chính app đó import (với app mẫu là `apps/mobile/lib/firebase/firebase_module.dart`), cùng `GoogleService-Info.plist` và `google-services.json` theo flavor. Khi có nhiều app mà không truyền `--app`, script liệt kê các app rồi thoát thay vì cấu hình bừa một app.

> [!WARNING]
> Ba file sinh ra đó bị git ignore, và `firebase_module.dart` import **cả ba một cách vô điều kiện**. Do đó một bản clone mới **không compile được** cho tới khi chạy lệnh này — kể cả khi bạn chỉ build dev. Xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Phải chạy từ thư mục gốc repo; script kiểm tra sự tồn tại của `pubspec.yaml` rồi mới chạy tiếp.

---

## `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart              # app duy nhất của workspace
dart tools/theme_generator/theme_setting.dart --app mobile # một trong nhiều app
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
dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart
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
