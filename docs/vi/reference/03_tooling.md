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
| **Xoá một package mẫu một cách an toàn** | `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` (bỏ `--apply` để xem trước) — `<bundle>` là một trong `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` |
| Tạo package feature / domain / data / core mới | `dart tools/module_generator/generate.dart …` |
| Vừa thêm, đổi tên hoặc xoá file trong `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Vừa đổi version dependency | `dart tools/dependency_sync.dart` |
| CI cần chặn lệch version | `dart tools/dependency_sync.dart --check` |
| Nghi có asset / file / translation / package chết | `dart tools/unused_checker/check_script.dart` |
| Muốn biết gì đã lỗi thời trên pub.dev | `dart tools/check_outdated.dart` |
| Vừa clone về, cần dựng mọi thứ | `dart tools/workspace_setup/configure.dart` |
| Cấu hình Firebase cho dev / staging / prod | `dart tools/firebase/firebase_config.dart --app mobile` |
| Sinh lại splash screen và app icon | `dart tools/theme_generator/theme_setting.dart --app mobile` |
| Kiểm tra tương thích 16 KB page-size của Android 15+ | `./tools/android_compliance/16kb_ckeck.sh <apk>` |
| Nhờ AI review một thay đổi | `dart tools/code_review/code_review.dart --changed` |

---

## `arch_check`

Cưỡng chế luật phân tầng bằng máy. **Gate 1 của `pr_quality_check.yml`** — chạy trước `flutter analyze` vì nó chỉ đọc import và `pubspec.yaml`, không cần codegen, xong trong khoảng 200 ms.

```bash
dart tools/arch_check/check.dart          # exit 1 khi có vi phạm chặn
dart tools/arch_check/check.dart --help   # mô tả đầy đủ từng luật
```

Tool không nhận tham số nào khác: bất cứ thứ gì ngoài `--help` (một `--fix`, một lần gõ nhầm `--help`) đều thoát với mã `64` thay vì trông như một lần chạy sạch.

| Luật | Kiểm tra gì |
|---|---|
| R1 | Hướng phụ thuộc — không package `platform/*` nào được import hay khai `feature_*` / `data_*` / `domain_*`, trừ các ngoại lệ đã duyệt |
| R2 | Domain thuần Dart — không import `flutter` / `dio` / `retrofit`, không khai `flutter` trong `dependencies:` |
| R3 | Ranh giới feature — không feature nào import feature khác hay package `data_*` |
| R4 | `static const` public phải nằm trong một thư mục `utils/` (file dưới `styles/` — design token của `core_base_ui` — được miễn). Package không có hằng số public thì không cần `utils/` |
| R5 | Mọi `package:` import dùng trong `lib/` phải được khai trong mục `dependencies:` của chính package đó — khai ở `dev_dependencies` không được tính |
| R6 | File generated còn giữ header của generator (chỉ cảnh báo) |
| R7 | Scale responsive phải qua `BuildContext` — cấm receiver trần `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`, trong mọi file có nhắc tới `core_responsive` |
| R8 | Contract của `core_di` được implement dưới `modules/` — ở bất kỳ tầng nào — thì bên ngoài module implement nó phải resolve bằng `getItOrNull` / `getAllOrEmpty`, cấm `getIt` / `getAll` (dạng ném lỗi) |
| R9 | `platform_kernel` và mọi package `*_contracts` không import **và không khai** package kéo theo Flutter |
| R10 | Không file nào trong một app (`apps/<id>/`) import module — chỉ `injection.dart`, điểm lắp ráp, được phép gọi tên một module. (`platform/app_shell` là core nên do R1 phủ) |

Ba ngoại lệ hướng lên được hardcode trong tool **và in ra mỗi lần chạy**, kèm lý do từng cái — để chúng không mục ruỗng âm thầm trong một dòng comment. Thêm cái thứ tư nghĩa là phải sửa danh sách cho phép trong `check.dart` — thiếu bước này build sẽ fail — và ghi cạnh đó vào `.agents/AGENTS.md` §2, file mà tool không đọc.

R7 tồn tại vì `flutter analyze` không thấy được khác biệt này. Bản thân `core_responsive` không cung cấp extension nào trên `num`, nên `16.h` không phân giải được về nó — nhưng một extension khai ở package khác, hoặc do ai đó tự thêm cục bộ, vẫn type-check sạch trong khi đọc một biến toàn cục chẳng báo cho ai. Chỉ `context.h(16)` mới đăng ký dependency `InheritedWidget` lên `ResponsiveScope`, tức mới rebuild khi metrics đổi. Dạng trần là một lỗi giá trị cũ âm thầm, và không linter nào có luật cho nó. Check chỉ chạy trên file có tham chiếu `core_responsive`, và khớp receiver là số hoặc dấu đóng ngoặc theo sau bởi `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm`.

R10 tồn tại vì tính tháo-lắp được là lời hứa template đưa ra trong bốn tài liệu mà không có gì kiểm tra. `network_config_impl.dart` import `data_auth` và `domain_auth` để đọc và làm mới token phiên, nên xoá module auth là app shell hỏng ngay ở khâu biên dịch — đúng một chỗ trong shell phá đi thứ mà mọi file còn lại cẩn thận giữ gìn. `getItOrNull` không cứu được: nó canh một *lookup*, còn lỗi ở đây là một *import*, thứ trình biên dịch giải quyết từ rất lâu trước khi có lookup nào chạy. Cách sửa là một hợp đồng (`IAuthSessionGateway` trong `core_di`, do `data_auth` hiện thực), và phép kiểm là một dòng chính sách — một app được phép import package module ở đúng một file, điểm lắp ráp, vì nhiệm vụ của file đó chính là gọi tên những gì nó lắp.

R8 tồn tại vì khả năng tháo module là tính chất mà app shell dựa vào, nhưng trước đó không có gì giữ nó. Tool tự suy ra tập hợp lúc chạy: mọi type khai trong `core_di`, thu hẹp lại còn những type có ràng buộc `implements` / `extends` / `as:` trong một package dưới `modules/` — ở bất kỳ tầng nào, nên `IAuthSessionGateway` do `data_auth` implement cũng nằm trong tập hợp chẳng kém gì navigator của một feature — và gắn với module implement nó. Một lookup ném lỗi lên các type đó vẫn compile — package gọi nó phụ thuộc `core_di` chứ không phụ thuộc module — rồi crash lúc runtime ở bản build không có module đó. Contract do app shell implement (`IThemeStorage`, `ILanguageStorage`) thì luôn được đăng ký, nên cố ý nằm ngoài tập hợp này. Module bị gỡ nguyên khối, nên mọi package của chính module implement được phép resolve contract của nó theo kiểu eager: chỉ cần một package của module có trong build thì đăng ký cũng có.

R5 là ảnh gương của `unused_checker`: tool kia tìm dependency *đã khai mà không dùng*, tool này tìm dependency *đang dùng mà không khai*. Pub Workspaces che giấu hoàn toàn loại thứ hai — mọi thứ resolve được cục bộ qua `package_config.json` dùng chung, và chỉ vỡ khi tách package ra hay publish.

---

## `composer`

```bash
dart tools/composer/composer.dart list              # liệt kê app và thành phần
dart tools/composer/composer.dart list --app admin  # chỉ một app
dart tools/composer/composer.dart sync --app mobile # sinh lại
dart tools/composer/composer.dart verify            # gate 0 của CI — fail khi lệch
dart tools/composer/bootstrap.dart                  # chỉ cho checkout từng phần — chạy trước `flutter pub get`
```

`--app <id>` lọc như nhau cho `list`, `sync` và `verify`; danh sách `workspace:` ở root vẫn được tính từ mọi app. Cờ lạ, hoặc `--app` không kèm id, thoát với mã `64`. Một pubspec hay manifest không phải YAML hợp lệ — thường là do key trùng — bị từ chối kèm tên file, `file:dòng` và thông báo của parser, exit `1`, thay vì làm tool crash.

Mọi `app_manifest.yaml` cũng được **kiểm tra trước khi bất kỳ lệnh nào chạy**; mỗi lỗi được in dạng `apps/<id>/app_manifest.yaml: <key>: <vấn đề>` (ví dụ `di_groups[0].phase: expected \`before\` or \`after\`, got a string (\`befor\`)`), và tool thoát `1` mà không ghi gì. Bị từ chối: manifest rỗng hoặc không phải map; key lạ ở bất kỳ cấp nào (`module:` thay cho `modules:`); `di_groups` thiếu hoặc rỗng; group không có `name` (một Dart identifier, duy nhất trong manifest) hoặc có `phase` khác `before`/`after`, hoặc group `before` đứng sau group `after`; `packages` không phải list; `from_modules` không thuộc `domain`/`data`/`feature`, hoặc một layer được hai group gom; group không có cả `packages` lẫn `from_modules`; module không có dạng `{ id, layers }`, module id trùng, `layers` rỗng, layer ngoài `domain`/`data`/`feature` hoặc không được `from_modules` của group nào gom; một package được ghép hai lần (bởi hai group, hoặc bởi một group và `extra_dependencies`); và hai manifest trùng `app.id`. Trước đây mỗi trường hợp này hoặc crash kèm stack trace, hoặc — tệ hơn — thoát `0` với một `injection.dart` đã âm thầm bỏ mất module.

Ba thứ phải khớp nhau và trước đây đều sửa tay: danh sách `workspace:` ở root, dependency dạng path của app, và `lib/di/injection.dart` của nó. Thêm một module nghĩa là sửa cả ba cho khớp, và sai thì vỡ lúc boot với `"<Type> is not registered"` — thứ `flutter analyze` không thấy được.

`composer` sinh cả ba từ các `app_manifest.yaml` — file riêng của mỗi app từ manifest của chính nó, còn danh sách `workspace:` dùng chung ở root từ tất cả manifest gộp lại — nhưng **chỉ** phần nằm giữa marker `composer:managed:<region>` và `composer:end:<region>`. Dependency ngoài, flavor và khai báo asset vẫn viết tay.

Danh sách `workspace:` ở root rộng hơn những gì manifest liệt kê: composer lần theo `dependencies` và `dev_dependencies` của từng package được ghép tới mọi package trong workspace mà chúng chạm tới. Nhờ vậy `core_responsive`, `core_ui_kit` và `platform_kernel` — không đăng ký DI module nào, nên không mục `di_groups` nào nhắc tên — vẫn là thành viên workspace. Danh sách tuỳ chọn `extra_dependencies:` trong manifest chỉ dành cho package workspace mà **chính** `lib/` của app import mà không ghép; hai app mẫu đều không cần.

Package được phân giải theo **tên**, tìm bằng cách quét `pubspec.yaml`. Không chỗ nào mã hoá đường dẫn, nên di chuyển package không phải sửa tool hay manifest. Package của module khớp được cả hai quy ước đặt tên — `domain_auth` và `auth_domain` đều nhận.

`--strict` (tự động bật trong `verify`) biến "manifest khai một module không có trên đĩa" từ cảnh báo thành lỗi. Không có nó, `sync` ghép những gì tìm được — chính điều này cho phép một dev làm việc khi chỉ checkout module của mình.

Cả `sync` lẫn `verify` còn **từ chối**, mã thoát `1`, khi một file mà chúng sinh vào — `pubspec.yaml` gốc, `pubspec.yaml` hoặc `lib/di/injection.dart` của một app — bị thiếu, hoặc đã mất marker `composer:managed:<region>` / `composer:end:<region>` của một vùng. Chúng nêu tên file và marker, và `sync` không ghi gì cả. Trước đây marker bị thiếu chỉ là một cảnh báo rồi báo "up to date": xoá một marker rồi sửa tay phần nó từng bảo vệ vẫn qua được Gate 0.

Cả hai còn **từ chối** một pubspec của app khai báo tay một package do composer quản lý ở ngoài vùng marker. Pub từ chối key trùng, nên chỉ một lỗi đó là cả workspace ngừng resolve — và đó chính là lỗi composer từng tự gây ra.

Một lần sync không strict mà có bỏ qua thứ gì sẽ in ra khối **`PARTIAL COMPOSITION`**: các file đã-commit mà lần chạy đó thực sự ghi lại — chỉ những file ấy; file vốn đã chứa đúng phép lắp ráp này không bị liệt kê (các ứng viên là `pubspec.yaml` gốc, cùng `pubspec.yaml` và `injection.dart` của mỗi app được sync) — cùng dòng `git checkout --` để khôi phục. Phép lắp ráp nó viết ra đúng ở local và sai khi commit, và CI Gate 0 bắt được trong mọi trường hợp, vì `verify` sinh lại từ manifest trên runner có đủ mọi module. Xem [`12_module_isolation.md`](../guides/12_module_isolation.md).

### `bootstrap` — trước khi composer chạy được

```bash
dart tools/composer/bootstrap.dart            # bỏ khỏi các vùng managed mọi member không có trên đĩa
dart tools/composer/bootstrap.dart --dry-run  # chỉ báo cáo
```

`composer.dart` import `package:path` và `package:yaml`, nên cần một workspace đã resolve — mà một bản checkout **từng phần** vừa clone (một submodule module chưa init, tức là thư mục rỗng) thì không resolve được: danh sách `workspace:` ở root và path dependency managed của từng app (đều đã commit) vẫn nêu tên nó, và `flutter pub get` từ chối cả workspace. `tools/composer/bootstrap.dart` **không import package nào** (chỉ `dart:io` và `OutputFormatter` vốn cũng chỉ dùng `dart:io`), nên chạy được trước khi pub từng resolve. Nó xoá, chỉ trong vùng `composer:managed:workspace` ở root và vùng `composer:managed:deps` của từng app, mọi mục mà thư mục không có `pubspec.yaml`, in ra những gì đã bỏ cùng dòng `git checkout --` để hoàn tác, rồi bảo bạn chạy `flutter pub get` → `composer.dart sync` → `workspace_setup/configure.dart`. Sau đó `sync` viết lại các vùng từ manifest.

Exit `0` khi đã cắt bớt hoặc không có gì để cắt (checkout đầy đủ — nó không ghi gì); `1`, không ghi gì, khi không có vùng `composer:managed:workspace` (không chạy từ root) hoặc khi một package đang có khai path dependency **viết tay** tới một thư mục vắng mặt (`modules/auth/data` mà thiếu `modules/auth/domain`) — cắt bớt không sửa được, nên nó nêu dòng đó và bảo bạn init thêm submodule ấy; `64` khi gặp tham số lạ. Trình tự đầy đủ: [`12_module_isolation.md` § 3](../guides/12_module_isolation.md#3-làm-việc-trên-bản-checkout-từng-phần).

---

## `docs_check`

**Gate 5 của `pr_quality_check.yml`.** Giải đường dẫn cho mọi path trong repo mà tài liệu nhắc tới, gom tất cả những path không tồn tại, in ra theo từng file, rồi thoát với mã 1. Ngoại lệ duy nhất là tham chiếu vào một sample bundle bạn đã gỡ bằng `remove_sample` — được tóm tắt dạng INFO, không bao giờ làm fail (xem bên dưới).

```bash
dart tools/docs_check/check.dart            # thoát 1 nếu có tham chiếu chết
dart tools/docs_check/check.dart --verbose  # kèm block allowlist để copy-paste và mọi tham chiếu tới sample đã gỡ
dart tools/docs_check/check.dart --help     # cú pháp; mọi tham số khác thoát mã 64
```

Hai loại tham chiếu được kiểm tra trong mọi file Markdown của repo — chỉ bỏ qua trạng thái tool, output build và dependency native tải về (`.dart_tool`, `build`, `Pods`, …). Trước đây nó chỉ phủ `docs/`, `.agents/`, `README.md` và `CLAUDE.md`; mở rộng ra thì lộ 11 link chết trong các hướng dẫn ở `.github`, một README của package và README của fastlane:

| Loại | Ví dụ | Cách giải |
|---|---|---|
| Path trong backtick | `` `platform/kernel/lib/platform_kernel.dart` `` | Tính từ gốc repo, nhưng chỉ khi chuỗi bắt đầu bằng một thư mục top-level có thật |
| Markdown link | `[…](../../../tools/arch_check/check.dart)` | Tương đối với **file chứa link**, không phải thư mục đang chạy lệnh |

Phép thử "thư mục top-level" chính là thứ làm cho check này dùng được. Repo đầy những chuỗi backtick trông như path nhưng không phải: `utils/` và `routing/` là quy ước tồn tại trong cả chục package, `ViewState` là một type, `flutter pub get` là một lệnh. Coi chúng là path sinh ra 817 "lỗi" ở lần chạy đầu và sẽ dạy cả team thói quen phớt lờ gate này. Neo vào `platform/`, `modules/`, `apps/`, `tools/`, `docs/`, `.agents/`, `.github/` còn lại khoảng 1 900 tham chiếu thật (tại thời điểm viết) — và những chuỗi bị bỏ qua đúng là loại reviewer nhìn mắt thường cũng xác minh được.

Chuỗi có khoảng trắng bị bỏ qua: đó là lệnh shell. Chuỗi có `*` hoặc `{` là glob, mô tả một *tập hợp* chứ không phải một file — đạt khi có ít nhất một đường dẫn khớp. Chuỗi có một đoạn `<placeholder>` (`modules/<owner>/feature/lib/src/handlers`) là **khuôn mẫu** cho module của chính người đọc, không phải tham chiếu: chỉ phần cố định trước placeholder đầu tiên phải tồn tại (`modules`), nên một path placeholder không bao giờ fail chỉ vì hiện chưa module nào có thư mục đó. Một path placeholder nằm dưới thư mục packages/domain đã bị xoá từ lâu vẫn fail, vì phần cố định đó không tồn tại. Danh sách thư mục gốc vẫn giữ `packages/` và `app/` trần, nơi không còn gì, để tài liệu còn trỏ tới đó sẽ fail thay vì bị bỏ qua.

**Sample đã gỡ không làm fail gate.** `remove_sample.dart <bundle> --apply` xoá các package của bundle nhưng không bao giờ sửa `tools/sample_manifest.yaml`, và `docs_check` đọc định nghĩa bundle ở đó: bundle có **mọi** package vắng mặt trên đĩa được coi là "đã gỡ", và tham chiếu chết nằm trong nó — path của package, thư mục `modules/<id>` đã trống, một mục trong `orphaned_contracts` — được báo thành một dòng tóm tắt cho mỗi bundle thay vì một lỗi:

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

---

## `sample_cleanup`

Trả lời câu "cái nào là code mẫu, và xoá sao cho không vỡ app?".

```bash
dart tools/sample_cleanup/remove_sample.dart --list    # bảng phân loại
dart tools/sample_cleanup/remove_sample.dart auth      # dry-run (mặc định)
dart tools/sample_cleanup/remove_sample.dart auth --verbose  # dry-run, liệt kê đủ mọi tham chiếu tài liệu
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

Nguồn chân lý của nó là [`tools/sample_manifest.yaml`](../../../tools/sample_manifest.yaml), phân loại mọi package thành `framework`, `sample` hay `shell`. Không có code mẫu nào nằm bên trong package framework: mỗi sample là một package riêng, nên gỡ một sample luôn là thao tác gỡ trọn một bundle.

Phần đáng đọc nhất là output của dry-run. Xoá `auth` không chỉ là ba thư mục: nó in ra chính xác những dòng cần gỡ khỏi `pubspec.yaml` gốc và khỏi manifest, pubspec, `injection.dart` của mọi app, các contract trong `core_di` trở thành code chết, **và sample nào sẽ vỡ, vỡ như thế nào** (danh sách `breaks` trong `tools/sample_manifest.yaml` — hiện trống với mọi sample) — cùng các liên kết xuống cấp an toàn, như `feature_settings` ẩn dòng logout khi `getItOrNull<IAuthActionHandler>()` trả về null, hay `feature_home` hiển thị trạng thái chưa đăng nhập khi `getItOrNull<IAuthStatusStream>()` ở route trả về null.

Cả dry-run lẫn `--apply` đều đếm các **tham chiếu Markdown** tới những đường dẫn sắp bị xoá — đường dẫn trong backtick và link tương đối trong mọi `*.md` (`docs/`, `.agents/`, các README), so khớp đúng như cách `docs_check` làm. Chúng chỉ mang tính thông tin: `dart tools/docs_check/check.dart` (CI Gate 5) nhận ra chúng trỏ vào một sample bundle đã gỡ, in một dòng INFO cho bundle đó và vẫn đạt — sửa các tài liệu đó lúc nào tiện. Đó cũng là lý do tool không bao giờ sửa `tools/sample_manifest.yaml`: định nghĩa bundle còn nằm đó là cách `docs_check` biết. Tool in 15 dòng đầu; `--verbose` liệt kê đủ.

Các bundle: `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` (`--list` in chúng kèm bảng phân loại).

Chỉ ghi khi truyền `--apply`, và các file dùng chung được snapshot trước để fail giữa chừng thì rollback được. Tham số được kiểm tra trước: cờ lạ (`--aply`), có cờ mà thiếu tên bundle, sai tên bundle, hoặc nhiều hơn một bundle đều thoát với mã `64` (không có tham số nào thì in cách dùng và thoát mã `0`) — gõ sai cờ không bao giờ lặng lẽ biến thành dry-run, cũng không bị bỏ qua khi đứng cạnh `--apply`.

---

## `module_generator`

Dựng khung package và đăng ký nó khắp workspace.

```bash
dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<sm>] [<route>]
dart tools/module_generator/generate.dart --help   # cú pháp
```

| Tham số | Giá trị |
|---|---|
| `<type>` | `1` feature · `2` domain · `3` data · `4` core · `5` custom |
| `<name>` | tên thư mục trần (`profile`) — package sẽ thành `feature_profile`. Phải là tên package Dart hợp lệ: chữ thường, số và `_`, bắt đầu bằng chữ cái, không phải từ khoá Dart |
| `<prefix>` | chỉ cho type `5` — tiền tố tên package: `<prefix>_<name>` tại `platform/<name>`, cùng quy tắc đặt tên như `<name>`. Từ chỉ tầng (`feature`, `domain`, `data`, `core`) bị từ chối; hãy dùng type 1–4. Với type 1–4 tham số này phải rỗng — truyền `""` |
| `<sm>` | chỉ feature — `1` Provider · `2` BLoC · `3` không dùng |
| `<route>` | chỉ feature — `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` không |

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1   # feature + Provider + route stack
dart tools/module_generator/generate.dart 1 chat    "" 2 2   # feature + BLoC + tab bottom-nav
dart tools/module_generator/generate.dart 2 payment          # domain micro-package
dart tools/module_generator/generate.dart 3 payment          # data micro-package
dart tools/module_generator/generate.dart 5 billing acme     # acme_billing tại platform/billing
```

**Tham số được kiểm tra trước khi ghi bất cứ thứ gì**, và mọi lần từ chối đều thoát với mã `64` kèm cú pháp: `<name>` hay `<prefix>` không hợp lệ (`Bad-Name`), `<sm>` / `<route>` khác `1`/`2`/`3`, `<prefix>` / `<sm>` / `<route>` truyền cho loại module không nhận nó, cờ lạ, nhiều hơn năm tham số, hoặc **tên package đã có** trong một `pubspec.yaml` bất kỳ của repo. Pub resolve workspace theo tên, nên trùng tên trước đây chỉ lộ ra ở `pub get`, sau khi composer đã ghi lại các manifest — và thư mục mới không có nghĩa là tên mới: `5 shell platform_app` là `platform_app_shell` (đã có ở `platform/app_shell`), `2 core` / `3 core` là `domain_core` / `data_core`.

Không tham số và có terminal thì tool hỏi mọi thứ. Feature thiếu `<sm>` hoặc `<route>` thì hỏi phần còn thiếu (bỏ trống câu trả lời là chọn `1`). **Không có terminal** — CI, shell của agent, stdin đã hết — thì giá trị cần hỏi trở thành lỗi, exit `64`, không bao giờ lặng lẽ lấy mặc định: với feature hãy luôn truyền đủ năm tham số. Mọi output của tool đều bằng tiếng Anh.

**Nó làm gì:** tạo cây thư mục (bao gồm `lib/src/utils/`, cho mọi tầng), render template (pubspec mới chép `environment:` từ `pubspec.yaml` gốc), thêm module vào mọi `app_manifest.yaml`, chạy `composer sync` (sinh lại danh sách `workspace:` ở root cùng `pubspec.yaml` và `lib/di/injection.dart` của từng app), rồi dependency sync, `pub get`, `gen-l10n`, barrel generator, `build_runner`, barrel generator **lần nữa**, và `dart fix --apply` trên package mới. Barrel chạy hai lần vì template import các barrel anh em, nên chúng phải có trước khi `build_runner` đọc package, trong khi barrel cũng export file sinh ra (`module.module.dart`, `lib/src/gen/**`) — nên lần chạy cuối phải đứng sau codegen.

> [!IMPORTANT]
> Nó không bao giờ tự ghi danh sách `workspace:` ở root, `pubspec.yaml` hay `lib/di/injection.dart` của app. Các file đó nằm giữa marker `composer:managed` và chỉ `composer sync` ghi chúng — một dòng thêm ngoài marker là dòng composer không bao giờ xoá, còn sửa tay bên trong là drift mà CI Gate 0 chặn.

**Hành vi an toàn**

- **Kiểm tra toolchain trước tiên.** `assertToolchainAvailable()` chạy trước khi động vào bất cứ file dùng chung nào, nên thiếu SDK là fail ngay lập tức thay vì chết ở bước 8.
- **Từ chối thư mục đã tồn tại.** Nó sẽ không âm thầm ghi đè lên package có sẵn.
- **Rollback khi thất bại.** Các file dùng chung bị thay đổi — mọi `app_manifest.yaml`, những gì `composer sync` ghi lại (`pubspec.yaml` gốc, `pubspec.yaml` và `lib/di/injection.dart` của từng app) và `pubspec.lock` gốc — được sao lưu trước mọi thao tác ghi; nếu bước sau fail thì chúng được khôi phục, thư mục module mới bị xoá, và tool thoát với mã `1`. Nếu lỗi xảy ra sau khi `pub get` hoặc `build_runner` đã bắt đầu, rollback còn chạy lại `flutter pub get` và `dart run build_runner build --workspace`: nếu không, các file sinh tự động không theo dõi bởi git (`.dart_tool/package_config.json`, `injection.config.dart` của từng app, `module.module.dart`) vẫn còn tham chiếu package đã xoá. Tool chỉ báo workspace sạch khi tất cả các bước đó thành công; nếu không, nó liệt kê những gì còn sót và in ra các lệnh cần chạy.
- **Việc đăng ký được kiểm chứng.** Manifest đã liệt kê package hay chưa được quyết định bằng cách parse YAML, không so chuỗi con — trước đây một phép thử theo dòng từng coi `core_net` là đã đăng ký vì `core_network` chứa nó, và package lặng lẽ không vào app nào mà vẫn exit `0`. Mỗi lần sửa đều được parse lại; nếu không thêm được module vào một manifest (không có danh sách `modules:`, hoặc nhóm DI `core`, đúng định dạng mong đợi) thì cả lần chạy rollback và thoát với mã `1`.
- **Tự phát hiện FVM** — mọi tool có gọi lệnh ngoài đều dùng chung `tools/shared/toolchain.dart` — yêu cầu *cả hai*: có file cấu hình (`.fvmrc` hoặc `.fvm/fvm_config.json`) *và* `fvm --version` chạy được. Chỉ một tín hiệu thôi là cho kết quả sai: repo này pin version trong `.fvmrc` trong khi một máy cụ thể có thể không hề cài `fvm`.

**Package mới khai báo gì.** Chỉ những package mà template của nó import, nên nó qua `check_unused_packages` ngay lần chạy đầu — thêm `core_network`, `core_storage`… khi code cần. Feature khai `core_di`, `core_common`, `core_base_ui` và `core_responsive` (mọi page được sinh đều bố cục qua `AdaptiveContent`, với `AppSpacing` / `AppTextStyles` scale qua context), cộng `provider_state_management` + `domain_core` cho Provider, hoặc `bloc_state_management` + `core_ui_kit` cho BLoC (trạng thái loading là `LoadingWidget` của kit); chỉ feature mới nhận `flutter_localizations` và `intl`, thứ mà output `gen-l10n` của nó import. Package domain nhận `domain_core` và một contract repository `I<Name>Repository` (trong `repositories/`, một method giữ chỗ `ping()` trả `Result<void>`). Package data nhận `data_core` và `<Name>RepositoryImpl extends IBaseRepository` (trong `repositories_impl/`); khi `domain_<name>` đã tồn tại, nó khai thêm `domain_core` + `domain_<name>`, implements contract đó và đăng ký dưới contract (`@LazySingleton(as: I<Name>Repository)`) — vì vậy hãy sinh domain trước. Package core và custom khởi đầu không có dependency workspace nào.

**Thứ tự nav destination.** `INavDestinationModule.order` của feature `<route>` `2` bằng `order` cao nhất trong các destination hiện có dưới `modules/*/feature` cộng 10 (10 nếu chưa có cái nào), nên các tab được sinh ra không bao giờ trùng thứ tự. Đánh số lại tuỳ ý; chỉ thứ tự tương đối là quan trọng.

> [!NOTE]
> Ngoài các stub đó, entity, use case, model và data source phải viết tay. Xem [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md).

---

## `barrel_generator`

```bash
dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib
dart tools/barrel_generator/generate.dart --help   # cú pháp
```

Sinh lại barrel `*.dart` cho mọi thư mục dưới đường dẫn đã cho, rồi chạy `dart format` trên đó qua toolchain của repo (FVM nếu đã cài đặt). Chạy nó sau **bất kỳ** thao tác thêm / đổi tên / xoá file nào trong `lib/` — và sau `build_runner` / `gen-l10n`, vì file sinh ra đang có trên đĩa cũng được export (`core_ui_kit` lấy `Assets` sinh ra của `core_base_ui` theo cách đó).

Mã thoát: `64` khi đường dẫn không tồn tại (nó chỉ hỏi lại đường dẫn khi chạy không tham số trên terminal), khi gặp một cờ hoặc đường dẫn thứ hai; `1` khi `dart format` thất bại — barrel đã được ghi nhưng chưa format. Cờ không bao giờ bị hiểu thành đường dẫn (trước đây `--help` từng bị đọc như tên thư mục), và `<pkg>/lib/` giống hệt `<pkg>/lib` (dấu phân cách ở cuối từng sinh ra `lib/.dart`).

Thư mục bị bỏ qua: thư mục ẩn, `lib/gen`, và các thư mục nền tảng / build (`android`, `ios`, `web`, `build`, …) **chỉ khi nằm ngoài** `lib/` — so theo từng đoạn đường dẫn tính từ gốc package, nên `lib/src/widgets/web/` vẫn được export như mọi thư mục khác. `lib/src/gen` vẫn được duyệt như trước.

Bỏ qua `.g.dart`, `.freezed.dart`, `.mocks.dart`, `*_test.dart`, `firebase_options*`, và file khai `part of`. Các file sinh khác — `module.module.dart`, `injection.config.dart`, `lib/src/gen/**` — vẫn được export nếu đang có trên đĩa.

> [!CAUTION]
> Nó **xoá mọi dòng `export` viết tay** trong barrel trước khi sinh lại. Cần re-export thứ gì từ package khác thì đặt `export` vào một file nguồn bình thường rồi để barrel nhặt file đó lên.

---

## `dependency_sync`

`pubspec_dependencies.yaml` ở gốc repo là nguồn chân lý duy nhất cho version.

```bash
dart tools/dependency_sync.dart          # ghi version vào mọi package
dart tools/dependency_sync.dart --check  # chỉ kiểm tra; exit 1 nếu lệch
dart tools/dependency_sync.dart --help   # in cách dùng; mọi cờ khác thoát mã 64, không sync gì
```

Nó cũng sửa các mục `path:` cục bộ bị gãy. Dùng `--check` trong CI và pre-commit.

> [!NOTE]
> Catalog và mọi pubspec được đọc bằng YAML parser, nên comment cuối dòng header (`dependencies: # runtime`) không còn là vấn đề. Catalog phải là một map chỉ gồm `dependencies:` và `dev_dependencies:`, mỗi mục là map package → **chuỗi version constraint**; mọi thứ khác — section lạ, nguồn lồng `git:`/`path:`, số không có ngoặc kép, giá trị rỗng, package được pin ở cả hai section, YAML không hợp lệ — bị từ chối dạng `pubspec_dependencies.yaml: <section>.<package>: <vấn đề>` (hoặc `file:dòng` với YAML hỏng), exit `1`, kể cả với `--check`, và không ghi gì. Một pubspec trong workspace không parse được cũng bị từ chối như vậy trước khi chạm vào bất kỳ file nào. Khi ghi lại, tool chỉ thay đúng các ký tự của giá trị đó, nên comment và định dạng được giữ nguyên. `dependency_overrides` được cố ý để nguyên, và dependency khai báo dạng map (`path:`/`git:`/`sdk:`/`hosted:`) không bao giờ bị ghi đè — chỉ `path:` của package trong workspace được sửa. Dependency native của Gradle (ví dụ `play-services-auth` trong `apps/mobile/android/app/build.gradle.kts`) hoàn toàn nằm ngoài phạm vi của nó — chúng không có nguồn chân lý tập trung nào.

---

## `unused_checker`

```bash
dart tools/unused_checker/check_script.dart              # cả bốn, kèm tổng kết
dart tools/unused_checker/check_unused_assets.dart       # asset không được tham chiếu
dart tools/unused_checker/check_unused_translate.dart    # key .arb không ai dùng
dart tools/unused_checker/check_unused_file.dart         # file Dart mồ côi
dart tools/unused_checker/check_unused_packages.dart     # dependency khai mà không dùng
```

Mỗi check tự tìm gốc repo từ vị trí của chính nó, nên chạy được từ bất kỳ thư mục làm việc nào; gốc không chứa package nào là lỗi (exit `1`), không bao giờ là kết quả sạch — trước đây chạy từ thư mục con thì chúng thấy 0 package và báo thành công. Mọi script nhận `--help`; tham số khác thoát với mã `64`.

[Luật 2](01_rules.md#2-khai-báo-dependency-tường-minh) có hai nửa: `arch_check` R5 bắt package được import mà không khai; `check_unused_packages.dart` bắt package đã khai mà không import (nó quét `lib/`, `bin/`, `test/` và `tool/` — package không có `lib/`, như `core_tools`, được đọc toàn bộ — nên dependency chỉ test dùng vẫn tính là đang dùng). Chạy cả hai trước mỗi PR.

> [!WARNING]
> Các checker asset / file / translation hoạt động bằng đối chiếu văn bản, nên sẽ báo nhầm với bất cứ thứ gì được với tới động (đường dẫn asset ghép từ chuỗi, key tra lúc chạy). Xác nhận kỹ trước khi xoá.

---

## `check_outdated`

```bash
dart tools/check_outdated.dart
```

Liệt kê package trong `pubspec_dependencies.yaml` có version mới hơn trên pub.dev. Khi chạy trong terminal, nó hiện checklist (mặc định chọn hết); gõ `a` để ghi version đã chọn vào catalog rồi chạy `dependency_sync` và `pub get`, `q` để thoát. Không có terminal (CI, pipe) thì chỉ liệt kê.

Tool thoát với mã `1` khi resolve catalog, `pub outdated`, đọc JSON của nó, hay bước áp dụng cập nhật (`dependency_sync`, `pub get`) thất bại, nên script phân biệt được một lần kiểm tra lỗi với một lần mọi thứ đã mới nhất. Ngoài `--help` nó không nhận tham số nào; tham số khác thoát với mã `64`.

---

## `workspace_setup`

```bash
dart tools/workspace_setup/configure.dart
dart tools/workspace_setup/configure.dart --help   # các bước sẽ chạy, theo thứ tự — không chạy gì
```

Dựng đầy đủ cho một bản clone mới. Script chạy theo thứ tự: activate `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n` trong mọi package có `l10n.yaml`, `build_runner build --workspace`, rồi barrel generator cho mọi package có `lib/` (bỏ qua các app). Đây **chính là** bước setup. Chỉ chạy `pub get` + `build_runner` thì các barrel `lib/src/gen/gen.dart` bị gitignore sẽ không có, và `flutter analyze` khi đó báo lỗi ở `gen/gen.dart`, `AppLocalizations` và `Assets`.

Script làm việc trên gốc repo bất kể thư mục làm việc. `--help` / `-h` in các bước và thoát `0`; mọi tham số khác thoát `64` **trước khi chạy bất cứ gì** — trước đây script bỏ qua tham số, nên `--help` chạy toàn bộ bước setup có tính phá huỷ.

> [!CAUTION]
> **Không có** `configure.sh` và **không có** `configure.bat`. Chỉ tồn tại `configure.dart` — gọi nó bằng `dart`, đừng bao giờ qua một wrapper shell.

---

## `firebase`

```bash
dart tools/firebase/firebase_config.dart              # app duy nhất của workspace
dart tools/firebase/firebase_config.dart --app mobile # một trong nhiều app
dart tools/firebase/firebase_config.dart --help       # cú pháp
```

Chạy `flutterfire configure` bên trong app được chọn cho từng flavor và build mode, sinh ra ba file `lib/firebase/firebase_options_*.dart` mà `lib/firebase/firebase_module.dart` của chính app đó import (với app mẫu là `apps/mobile/lib/firebase/firebase_module.dart`), cùng `GoogleService-Info.plist` và `google-services.json` theo flavor. Khi có nhiều app mà không truyền `--app`, script liệt kê các app rồi thoát thay vì cấu hình bừa một app.

> [!WARNING]
> Ba file sinh ra đó bị git ignore, và `firebase_module.dart` import **cả ba một cách vô điều kiện**. Do đó một bản clone mới **không compile được** cho tới khi chạy lệnh này — kể cả khi bạn chỉ build dev. Xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Phải chạy từ thư mục gốc repo; script kiểm tra sự tồn tại của `pubspec.yaml` rồi mới chạy tiếp.

Script cần **Firebase CLI đã được cài và đã đăng nhập**. Cụ thể là Node.js + npm, `npm install -g firebase-tools`, và một lần `firebase login` tương tác bằng tài khoản Google có quyền vào Firebase project của bạn. Script không còn tự cài CLI: nếu `firebase` không có trong `PATH`, nó in hướng dẫn cài đặt rồi thoát với mã `1`. Khi chưa đăng nhập hoặc phiên đã hết hạn, nó chạy `firebase login` **tối đa hai lần**, rồi thoát với mã `1` và yêu cầu bạn tự đăng nhập (`firebase login` trả về thành công mà không đăng nhập khi không mở được prompt, nên vòng lặp thử lại vô hạn trước đây không bao giờ dừng). Ngược lại, FlutterFire CLI thì được activate qua `dart pub global activate` khi còn thiếu.

Script chạy tương tác — không có dạng cờ cho các câu trả lời — nên nó **từ chối chạy khi không có terminal** (exit `1`). Tham số khác `--app <id>` / `--help` thoát với mã `64`. Script chỉ hỏi một project ID và dùng nó cho **mọi** flavor. Muốn mỗi flavor một project, hoặc cần stub chỉ để biên dịch khi chưa có Firebase project, xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md) § 3.

---

## `theme_generator`

```bash
dart tools/theme_generator/theme_setting.dart              # app duy nhất của workspace
dart tools/theme_generator/theme_setting.dart --app mobile # một trong nhiều app
dart tools/theme_generator/theme_setting.dart --help       # cú pháp
```

Điều khiển `flutter_native_splash` và `icons_launcher` dựa trên các file cấu hình theo flavor ở gốc repo (`flutter_native_splash-*.yaml`, `icons_launcher-*.yaml`).

Trước khi ghi bất cứ thứ gì, tool kiểm tra app có nhận được chúng không: app cần có `android/` và `ios/` (các file cấu hình bật cả hai nền tảng), phải khai báo `flutter_native_splash` và `icons_launcher` trong `pubspec.yaml`, và các file cấu hình phải nằm ở gốc repo. Thiếu gì thì liệt kê ra rồi thoát với mã `1`. **`--app admin` hiện bị từ chối** — `apps/admin` không có thư mục nền tảng và không khai báo package nào trong hai package trên. Nếu một generator fail giữa chừng, mọi file nó đã tạo hoặc sửa dưới `android/`, `ios/` và `web/` của app được khôi phục, và tool thoát với mã `1`; các file cấu hình đã chép vào app luôn được xoá. Tham số khác `--app <id>` / `--help` thoát với mã `64`.

---

## `android_compliance`

```bash
# Trước hết build APK release của một flavor (cd apps/mobile && flutter build apk --flavor dev --release), rồi:
./tools/android_compliance/16kb_ckeck.sh apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk     # macOS / Linux
.\tools\android_compliance\16kb_ckeck.bat apps\mobile\build\app\outputs\flutter-apk\app-<flavor>-release.apk   # Windows (Git Bash)
```

Kiểm tra một APK (căn chỉnh zip, rồi căn chỉnh ELF của các thư viện native `.so` bên trong), một APEX, hoặc một thư mục thư viện native xem đã tương thích 16 KB page-size cho Android 15+ chưa. Tool nhận đúng một đường dẫn; không truyền gì thì in cú pháp và thoát với mã `1`, còn `--help` in cú pháp với mã `0`. File phải là `.apk`, `.apex` hoặc một `.so` — file khác (kể cả `.aab`) thoát `1`. APK mà `unzip` không đọc được (không phải zip, bị cắt cụt) thoát `1`; chỉ trường hợp "không có entry `lib/*`" (unzip exit `11`) mới là kết quả đạt không-có-thư-viện-native — trước đây mọi lỗi unzip đều bị báo thành kết quả đạt đó. File `.sh` có quyền thực thi, nên lệnh `./` chạy được đúng như viết; file `.bat` chỉ là wrapper chạy `.sh` qua Git Bash và trả về mã thoát của nó. Đây là công cụ duy nhất trong repo viết bằng shell script thay vì Dart.

> [!NOTE]
> Tên file đúng là `16kb_ckeck` — một lỗi gõ được giữ nguyên vì đã có script và tài liệu tham chiếu tới nó.

---

## `code_review`

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
> Workflow GitHub chạy nó ở **chế độ cảnh báo** — bước "fail on critical issues" có dòng `exit 1` bị comment lại, nên nó không bao giờ chặn PR. Xem [`../operations/01_cicd.md`](../operations/01_cicd.md).

---

**Tiếp theo:** [`04_review_checklist.md`](04_review_checklist.md) · [`01_rules.md`](01_rules.md) · [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md)
