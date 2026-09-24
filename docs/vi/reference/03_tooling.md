<!-- translated-from: docs/en/reference/03_tooling.md@3bd1af3 -->
# Tra cứu công cụ

**Trang này trả lời:** chạy script nào, với tham số gì, mã thoát của nó nghĩa là gì, và CI gate nào chạy nó?

Mỗi tool một bảng. Mọi tool nằm trong `tools/`, đều là Dart thuần (trừ bản kiểm tra 16 KB), và chạy từ **thư mục gốc repo**. Bản đầy đủ — mọi tham số, trường hợp bị từ chối và chế độ lỗi — nằm ở [`tools/README.vi.md` § Tham chiếu đầy đủ](../../../tools/README.vi.md#-tham-chiếu-đầy-đủ-từng-tool).

Mã thoát theo cùng một quy ước ở mọi tool: `0` thành công, `1` kiểm tra thất bại hoặc không làm được việc, `64` tham số sai (không chạy hay ghi gì cả).

---

## Vấn đề → công cụ

| Vấn đề | Lệnh |
|---|---|
| **Kiểm tra luật phân tầng còn đúng không** | `dart tools/arch_check/check.dart` |
| **Kiểm tra docs còn mô tả đúng cây thư mục hiện tại** | `dart tools/docs_check/check.dart` |
| **Sửa một tool gate — chứng minh nó vẫn fail đúng chỗ** | `cd tools && dart test` |
| **Package nào là code mẫu có thể xoá?** | `dart tools/sample_cleanup/remove_sample.dart --list` |
| **Xoá một package mẫu một cách an toàn** | `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` (bỏ `--apply` để xem trước) — `<bundle>` là một trong `auth`, `home`, `settings`, `onboarding`, `dashboard`, `splash`, `cache` |
| Tạo package feature / domain / data / core mới | `dart tools/module_generator/generate.dart …` |
| Vừa thêm, đổi tên hoặc xoá file trong `lib/` | `dart tools/barrel_generator/generate.dart <pkg>/lib` |
| Vừa đổi version dependency | `dart tools/dependency_sync.dart` |
| CI cần chặn lệch version | `dart tools/dependency_sync.dart --check` |
| Nghi có asset / file / translation / package chết | `dart tools/unused_checker/check_script.dart` |
| Muốn biết gì đã lỗi thời trên pub.dev | `dart tools/check_outdated.dart` |
| Vừa clone về, cần dựng mọi thứ | `dart tools/workspace_setup/configure.dart` |
| Chưa có project Firebase nhưng app phải compile và build được | `dart tools/workspace_setup/configure.dart --stub-firebase` |
| Test phủ bao nhiêu phần trăm mỗi package? | `flutter test --coverage` trong từng package, rồi `dart tools/coverage_report/report.dart` |
| Cấu hình Firebase cho dev / staging / prod | `dart tools/firebase/firebase_config.dart --app mobile` |
| Sinh lại splash screen và app icon | `dart tools/theme_generator/theme_setting.dart --app mobile` |
| Kiểm tra tương thích 16 KB page-size của Android 15+ | `./tools/android_compliance/16kb_ckeck.sh <apk>` |
| Nhờ AI review một thay đổi | `dart tools/code_review/code_review.dart --changed` |

## Các CI gate trong một bảng

`.github/workflows/pr_quality_check.yml` chạy những lệnh này, theo đúng thứ tự. Toàn bộ pipeline: [`../operations/01_cicd.md`](../operations/01_cicd.md).

| Gate | Lệnh | Chặn merge? |
|:--|:--|:--|
| 0 | `dart tools/composer/composer.dart verify` | Có |
| 1 | `dart tools/arch_check/check.dart`, rồi `cd tools && dart test` | Có |
| 2 | `flutter analyze` | Có |
| 3 | `flutter test --coverage` trong mọi package có `test/`, rồi `dart tools/coverage_report/report.dart` | Test thì có; báo cáo coverage thì không (chỉ tư vấn) |
| 4 | `dart tools/dependency_sync.dart --check` | Có |
| 5 | `dart tools/docs_check/check.dart` | Có |
| — | `dart tools/unused_checker/check_unused_packages.dart` | Không (bước tư vấn) |
| — | `dart tools/code_review/code_review.dart` (workflow riêng) | Không (tư vấn) |

---

## `arch_check`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/arch_check/check.dart` | Cưỡng chế các luật phân tầng R1–R15 trên import, pubspec và tên file | `0` sạch (R6 chỉ cảnh báo) · `1` có vi phạm chặn · `64` mọi tham số khác `--help` | 1 |
| `dart tools/arch_check/check.dart --help` | Mô tả từng luật | `0` | — |

- Chỉ đọc import và file `pubspec.yaml`, không cần codegen, và chạy xong trong vài trăm ms.
- Ba cạnh ngược chiều đã duyệt được in ra ở mọi lần chạy. Cạnh thứ tư phải cập nhật cùng lúc allow-list trong `check.dart` và RULE-01.
- Từng luật, kèm lý do nó tồn tại: [chi tiết](../../../tools/README.vi.md#arch_check). Dòng registry mà mỗi luật cưỡng chế: R1 RULE-01 · R2 RULE-03 · R3 RULE-04 · R4 RULE-09 · R5 RULE-06 · R6 RULE-76 · R7 RULE-30 · R8 RULE-12 · R9 RULE-07 · R10 RULE-05 · R11 RULE-02 · R12 RULE-72 · R13 RULE-71 · R14 RULE-40 · R15 RULE-78.

## `composer`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/composer/composer.dart list [--app <id>]` | In phần lắp ráp của từng app | `0` · `1` manifest không hợp lệ · `64` cờ sai | — |
| `dart tools/composer/composer.dart sync [--app <id>]` | Sinh lại danh sách `workspace:` ở root, path dependency và `injection.dart` của từng app từ `app_manifest.yaml` | `0` · `1` manifest hoặc YAML không hợp lệ, mất marker `composer:managed`, một package managed bị khai tay · `64` cờ sai | — |
| `dart tools/composer/composer.dart verify` | Như trên, nhưng không ghi gì và fail khi lệch; ngầm bật `--strict` | `0` · `1` lệch, thiếu module trên đĩa, hoặc mọi trường hợp `sync` từ chối · `64` cờ sai | 0 |

- Chỉ các vùng giữa `composer:managed:<region>` và `composer:end:<region>` là được sinh ra; không bao giờ sửa tay chúng (RULE-16).
- Một lần `sync` không strict mà bỏ qua module thiếu sẽ in khối `PARTIAL COMPOSITION` kèm dòng `git checkout --` để khôi phục các file.
- Kiểm tra manifest, cách tìm package và layer `api`: [chi tiết](../../../tools/README.vi.md#composer).

### `bootstrap` — trước khi composer chạy được

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/composer/bootstrap.dart [--dry-run]` | Trên bản checkout từng phần, bỏ mọi mục managed mà thư mục không có `pubspec.yaml`, để `flutter pub get` resolve được | `0` đã bỏ, hoặc không có gì để bỏ · `1` không có vùng managed, hoặc một package đang có khai path dependency viết tay tới package thiếu · `64` tham số sai | — |

Nó không import package nào, nên chạy được trước khi pub từng resolve. Trình tự đầy đủ: [`12_module_isolation.md` § 2](../guides/12_module_isolation.md#2-làm-việc-trên-bản-checkout-từng-phần). Chi tiết: [`bootstrap`](../../../tools/README.vi.md#bootstrap--trước-khi-composer-chạy-được).

## `docs_check`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/docs_check/check.dart` | Mọi đường dẫn repo và link tương đối trong mọi `*.md` đều tồn tại; en ↔ vi cùng hình dạng; mọi `RULE-NN` có trong registry | `0` · `1` tham chiếu chết, lệch hình dạng, hoặc RULE-ID lạ/trùng · `64` tham số sai | 5 |
| `dart tools/docs_check/check.dart --verbose` | Kèm khối allowlist copy-paste được và mọi tham chiếu tới sample đã gỡ | như trên | — |
| `dart tools/docs_check/check.dart --stale-translations` | Liệt kê file `docs/vi` đang chậm hơn bản tiếng Anh | `0` (tư vấn) | — |
| `dart tools/docs_check/check.dart --stamp-translations docs/vi/<file>.md` | Đóng dấu một bản dịch vừa đồng bộ | `0` | — |

- Đường dẫn vắng mặt hợp lệ nằm trong `tools/docs_check/allowlist.txt`, mỗi mục kèm lý do; khác biệt hình dạng có chủ đích nằm trong `tools/docs_check/parity_allowlist.txt`.
- Tham chiếu vào một bundle mẫu đã gỡ bằng `remove_sample` được tóm lại thành một dòng INFO cho mỗi bundle, không bao giờ làm fail.
- Cách resolve đường dẫn, placeholder, chỉ số parity và dấu bản dịch: [chi tiết](../../../tools/README.vi.md#docs_check).

## `sample_cleanup`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/sample_cleanup/remove_sample.dart --list` | Phân loại mọi package là `framework`, `sample` hay `shell` | `0` | — |
| `dart tools/sample_cleanup/remove_sample.dart <bundle> [--verbose]` | Chạy thử: sẽ gỡ gì, cái gì vỡ, cái gì xuống cấp an toàn, tài liệu nào sẽ chết | `0` · `64` cờ hoặc bundle lạ, hoặc nhiều hơn một bundle | — |
| `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` | Gỡ bundle | `0` · `1` hỏng giữa chừng (file dùng chung được khôi phục; thư mục đã xoá thì không) · `64` như trên | — |

- Nguồn sự thật: [`tools/sample_manifest.yaml`](../../../tools/sample_manifest.yaml). Tool không bao giờ sửa file này, và đó là cách `docs_check` nhận ra một bundle đã gỡ.
- Package `<id>_api` của một bundle được giữ lại chừng nào còn package khác import nó.
- Chi tiết: [`sample_cleanup`](../../../tools/README.vi.md#sample_cleanup).

## `module_generator`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<sm>] [<route>] [--group <g>] [--apps <id,id>]` | Dựng khung một package, ghép nó vào các app, chạy codegen và barrel | `0` · `1` một bước thất bại (đã rollback) · `64` tham số sai hoặc thiếu, tên đã có, id app lạ | Được smoke-test trong một job CI riêng |
| `dart tools/module_generator/generate.dart --help` | Cách dùng | `0` | — |

| Tham số | Giá trị |
|---|---|
| `<type>` | `1` feature · `2` domain · `3` data · `4` core · `5` custom |
| `<name>` | Một tên package Dart (`profile` → `feature_profile`) |
| `<prefix>` | Chỉ loại `5`; truyền `""` cho loại 1–4 |
| `<sm>` | Chỉ feature — `1` Provider · `2` BLoC · `3` không dùng |
| `<route>` | Chỉ feature — `1` `IFeatureRouteModule` · `2` `INavDestinationModule` · `3` không sinh |
| `--group` | Chỉ loại `4`/`5` — thư mục nhóm trong `platform/`; mặc định `infra` |
| `--apps` | Mọi loại — chỉ ghép vào những app này; mặc định mọi app |

- Không có terminal thì thiếu một giá trị là lỗi, không bao giờ tự lấy mặc định: với feature, luôn truyền đủ năm tham số.
- Feature được sinh kèm test pass ngay. Một ví dụ đi từng bước: [`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md).
- Nó ghi những gì, cơ chế an toàn và thời gian build: [chi tiết](../../../tools/README.vi.md#module_generator).

## `barrel_generator`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/barrel_generator/generate.dart <pkg>/lib` | Sinh lại mọi barrel `*.dart` dưới đường dẫn, rồi `dart format` | `0` · `1` `dart format` thất bại (barrel đã được ghi) · `64` đường dẫn không tồn tại, một cờ, hoặc đường dẫn thứ hai | — |

- Chạy sau mọi lần thêm, đổi tên hay xoá file trong `lib/` — và **sau** `build_runner` / `gen-l10n`, vì file được sinh cũng được export (RULE-75).
- Nó xoá mọi dòng `export` viết tay. Chi tiết: [`barrel_generator`](../../../tools/README.vi.md#barrel_generator).

## `dependency_sync`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/dependency_sync.dart` | Ghi version từ `pubspec_dependencies.yaml` vào mọi package; sửa các mục `path:` cục bộ bị hỏng | `0` · `1` catalog hoặc pubspec không hợp lệ · `64` cờ sai | — |
| `dart tools/dependency_sync.dart --check` | Báo cáo lệch, không ghi gì | `0` · `1` có lệch hoặc catalog không hợp lệ · `64` cờ sai | 4 |

Version chỉ nằm trong catalog (RULE-74). Chi tiết: [`dependency_sync`](../../../tools/README.vi.md#dependency_sync).

## `unused_checker`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/unused_checker/check_script.dart` | Chạy cả bốn kiểm tra, kèm tóm tắt | `0` · `1` một kiểm tra thất bại · `64` tham số sai | — |
| `dart tools/unused_checker/check_unused_packages.dart` | Dependency được khai mà không bao giờ import | `0` · `1` · `64` | Bước tư vấn |
| `dart tools/unused_checker/check_unused_assets.dart` | Asset không được tham chiếu | `0` · `1` · `64` | — |
| `dart tools/unused_checker/check_unused_translate.dart` | Key ARB không bao giờ được dùng | `0` · `1` · `64` | — |
| `dart tools/unused_checker/check_unused_file.dart` | File Dart mồ côi | `0` · `1` · `64` | — |

- `check_unused_packages` là mặt đối xứng của `arch_check` R5 (RULE-06): hãy chạy cả hai trước khi mở PR.
- Kiểm tra asset, file và bản dịch dựa trên khớp chữ, nên thứ gì được truy cập động sẽ là báo động giả. Chi tiết: [`unused_checker`](../../../tools/README.vi.md#unused_checker).

## `check_outdated`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/check_outdated.dart` | Báo các package trong catalog có version mới hơn trên pub.dev; trên terminal thì đề nghị nâng version | `0` · `1` resolve, `pub outdated` hay việc áp bản cập nhật thất bại · `64` tham số sai | — |

Chi tiết: [`check_outdated`](../../../tools/README.vi.md#check_outdated).

## `workspace_setup`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/workspace_setup/configure.dart` | Setup đầy đủ: kích hoạt `flutterfire_cli`, `flutter clean`, `pub get`, `gen-l10n`, `build_runner`, barrel | `0` · mã thoát của lệnh thất bại · `64` tham số sai | Chạy trước Gate 2–5 |
| `dart tools/workspace_setup/configure.dart --stub-firebase` | Như trên, kèm stub Firebase chỉ để compile ở nơi chưa có file thật | như trên | CI dùng |
| `dart tools/workspace_setup/configure.dart --help` | In các bước, không chạy gì | `0` | — |

Chỉ `pub get` + `build_runner` thì chưa phải là setup: các barrel `lib/src/gen/gen.dart` (đã gitignore) đến từ lượt chạy barrel. Không có `configure.sh` hay `.bat`. Chi tiết: [`workspace_setup`](../../../tools/README.vi.md#workspace_setup).

## `firebase`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/firebase/firebase_config.dart [--app <id>]` | Chạy `flutterfire configure` cho từng flavor và build mode của một app | `0` · `1` không có terminal, thiếu Firebase CLI hoặc chưa đăng nhập, không chạy từ root · `64` tham số sai | — |

Chỉ chạy tương tác; cần Firebase CLI đã cài và đã đăng nhập. `--app` là bắt buộc khi workspace có hai app. Chi tiết: [`firebase`](../../../tools/README.vi.md#firebase).

## `theme_generator`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/theme_generator/theme_setting.dart [--app <id>]` | Sinh splash screen và app icon từ cấu hình theo flavor ở root | `0` · `1` app không nhận được, hoặc một generator thất bại (file được khôi phục) · `64` tham số sai | — |

`--app admin` hiện bị từ chối: admin không có thư mục nền tảng. Chi tiết: [`theme_generator`](../../../tools/README.vi.md#theme_generator).

## `android_compliance`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `./tools/android_compliance/16kb_ckeck.sh <apk\|apex\|dir>` | Kiểm tra tương thích 16 KB page-size của Android 15+ (căn lề zip và ELF) | `0` mọi thư viện native đều căn 16 KB (hoặc không có thư viện nào) · `1` có thư viện lệch căn, thiếu tham số, sai loại file, APK không đọc được, hoặc thiếu công cụ SDK | — |
| `.\tools\android_compliance\16kb_ckeck.bat <apk>` | Như trên trên Windows, qua Git Bash | như trên | — |

Hãy build APK release của một flavor trước. Lỗi chính tả trong tên file (`ckeck`) được giữ có chủ đích. Chi tiết: [`android_compliance`](../../../tools/README.vi.md#android_compliance).

## `code_review`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/code_review/code_review.dart --changed \| --all \| --file <f> [--focus …] [--language vi]` | Review bằng Gemini theo `tools/code_review/review_prompt.md` | `0` · `1` không có API key khi không có terminal, hoặc `--file` / `--folder` không tồn tại · `64` tuỳ chọn sai | Workflow tư vấn |

Cần API key Gemini (`GEMINI_API_KEY`, `--api-key`, hoặc file `tools/code_review/.gemini_api_key` đã gitignore). Chi tiết: [`code_review`](../../../tools/README.vi.md#code_review) và [`tools/code_review/README.vi.md`](../../../tools/code_review/README.vi.md).

## `coverage_report`

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `dart tools/coverage_report/report.dart [--min <pct>] [--min-package <pct>] [--no-summary]` | Line coverage theo package từ mọi `*/coverage/lcov.info`, bỏ qua file được sinh | `0` · `1` không tìm thấy `lcov.info`, hoặc không đạt ngưỡng · `64` tham số sai | 3 (tư vấn) |

Chạy `flutter test --coverage` trong từng package trước. Chi tiết: [`coverage_report`](../../../tools/README.vi.md#coverage_report).

## Test cho các tool (`tools/test/`)

| Lệnh | Mục đích | Mã thoát | CI gate |
|:--|:--|:--|:--|
| `cd tools && dart test` | Chạy mọi tool gate trên các workspace tạm, kiểm tra mã thoát và output (~15 s) | `0` · `1` một test thất bại | 1 |

Khi sửa một gate, hãy thêm đúng test lẽ ra đã bắt được bug (RULE-64). Mỗi file test phủ gì: [chi tiết](../../../tools/README.vi.md#test-cho-các-tool-toolstest).

---

**Tiếp theo:** [`04_review_checklist.md`](04_review_checklist.md) · [`01_rules.md`](01_rules.md) · [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md)
