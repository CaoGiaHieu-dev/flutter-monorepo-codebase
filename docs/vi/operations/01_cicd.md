# CI/CD

Tài liệu này trả lời: **có những pipeline nào, mỗi cái làm gì, cần secret gì, và hiện đang hỏng chỗ nào.** Đọc xong bạn cấu hình được secret cho repo, chạy được build, và tái hiện được mọi bước CI ở máy local trước khi push.

> [!IMPORTANT]
> Các pipeline phát hành phụ thuộc vào **secret của repo** cho mọi đầu vào bị gitignore — Firebase options, `google-services.json`, `env.prod`, keystore release, `Config.yaml` của fastlane ([§7](#7-secrets)). Thiếu chúng thì pipeline dừng ngay ở bước đầu và nêu tên secret còn thiếu. Đừng cho rằng chúng đang chạy xanh khi bạn chưa cấu hình secret và tự chạy thử một lần.

---

## 1. Danh sách pipeline

Template có **năm** pipeline — bốn trên GitHub Actions, một trên Azure DevOps.

| Pipeline | File | Kích hoạt | Đầu ra |
|:---|:---|:---|:---|
| Build and Distribute | `.github/workflows/flutter_build.yml` | Thủ công (`workflow_dispatch`) | APK release đã ký → Firebase App Distribution, kèm symbol obfuscation làm artifact |
| AI Code Review | `.github/workflows/code_review.yml` | PR vào `main`/`develop`/`master` + thủ công | Báo cáo Markdown + comment trên PR |
| Fastlane build and distribute | `.github/workflows/fastlane.yml` | Thủ công (`workflow_dispatch`) | Uỷ quyền cho các lane Fastlane |
| **PR Quality Check** | `.github/workflows/pr_quality_check.yml` | **PR vào `main`/`develop`/`master`** + thủ công | Đạt/không — chặn merge; sau đó build một APK dev bản debug và smoke test module generator |
| Azure Build + Distribute | `azure-ci-cd.yml` | `trigger: none` (chỉ chạy tay) | Artifact APK prod + symbol obfuscation → Firebase |

`pr_quality_check.yml` là pipeline duy nhất chặn được merge. Nó chạy sáu gate chặn theo thứ tự — lệch composition, luật kiến trúc, `flutter analyze`, test từng package, lệch catalog, độ chính xác của docs — cộng một audit chỉ cảnh báo, và bộ test riêng của các tool gate chạy ngay sau Gate 1 — rồi ở hai job tiếp theo, build app (APK `dev` bản debug), điều mà không gate nào chứng minh được, và smoke test module generator. Xem [§6](#6-quality-gate).

---

## 2. `flutter_build.yml` — Build and Distribute

Pipeline release Android chính. Chỉ chạy tay: **Actions → Build and Distribute → Run workflow**.

### Tham số đầu vào

| Tham số | Bắt buộc | Mặc định | Ghi chú |
|:---|:---|:---|:---|
| `flavor` | có | `prod` | `dev` / `staging` / `prod` |
| `version` | có | `1.0.0` | Trở thành `--build-name` |
| `notes` | không | — | Ghép vào release notes của Firebase |
| `groups` | không | `test` | Alias nhóm tester của Firebase App Distribution, cách nhau bằng dấu phẩy, truyền vào `--groups`. Mỗi alias phải tồn tại trong Firebase console; để rỗng = upload bản phát hành mà không mời ai |

Build number không phải tham số — nó dùng `${{ github.run_number }}`, nên tự tăng theo mỗi lần chạy workflow.

### Các bước, theo thứ tự

1. **Checkout** — `actions/checkout@v7`.
2. **Set Up Java** — bản Oracle, **Java 17**. Khớp với `sourceCompatibility`/`targetCompatibility` trong `apps/mobile/android/app/build.gradle.kts`.
3. **Set Up Flutter** — `subosito/flutter-action@v2` với `flutter-version-file: .fvmrc`, nên phiên bản là bản `.fvmrc` ghim (hiện là **`3.47.4`**) — cùng một nguồn duy nhất mà `pr_quality_check.yml` và `code_review.yml` đọc. Kênh `stable`, bật cache.
4. **Restore gitignored build inputs from secrets** — chỉ cho flavor được chọn, mỗi file lấy từ một secret base64 ([§7](#7-secrets)):
   - `firebase_options_<flavor>.dart` trong `apps/mobile/lib/firebase/`; hai flavor còn lại nhận một stub chỉ để biên dịch, vì `firebase_module.dart` import cả ba file còn injectable chỉ đăng ký options của flavor đang build;
   - `apps/mobile/android/app/src/<flavor>/google-services.json` — thiếu nó thì plugin Gradle `com.google.gms.google-services` làm build fail;
   - `apps/mobile/env.prod` (chỉ prod — `env.dev` / `env.stg` đã được commit);
   - chỉ prod: `apps/mobile/android/keystore.jks` + `key.properties` (`storeFile=../keystore.jks`) — bắt buộc, vì Gradle **từ chối** build release prod khi thiếu `key.properties` ([`02_fastlane_release.md` §4](02_fastlane_release.md#4-ký-ứng-dụng)). dev được ký bằng keystore dev đã commit. **staging** chưa có secret riêng: Gradle cũng từ chối build release staging khi thiếu `key-stg.properties`, nên bước này export `ORG_GRADLE_PROJECT_allowDevKeystoreForStaging=true` và in một `::warning::` — bản staging khi đó được ký một cách tường minh bằng keystore dev **công khai**. Cách sửa đúng là thêm secret keystore cho staging và khôi phục chúng thành `apps/mobile/android/key-stg.properties` + keystore của nó ngay trong bước này, rồi bỏ opt-in kia.

   Thiếu secret nào thì bước này fail kèm lỗi nêu đúng tên secret đó — trước khi tốn thời gian cho codegen hay Gradle. Nó chạy **trước** bước sinh code vì `build_runner` phải phân giải được các import của `firebase_module.dart`.
5. **Get dependencies from the committed lockfile** — `flutter pub get --enforce-lockfile`. `pubspec.lock` của workspace đã được commit; lockfile nào không còn khớp các pubspec sẽ fail ngay tại đây thay vì bị resolve lại âm thầm.
6. **Install Dependencies** — `dart tools/workspace_setup/configure.dart`. Script Dart này làm trọn gói: pub get, sinh l10n, `build_runner` và lượt sinh barrel cho cả workspace.
7. **Build APK** — chú ý dòng `cd apps/mobile` đứng riêng phía trước:
   ```bash
   cd apps/mobile
   flutter build apk --flavor="$FLAVOR" --build-name="$VERSION" --build-number="$GITHUB_RUN_NUMBER" \
     --dart-define-from-file="$GITHUB_WORKSPACE/apps/mobile/$ENV_FILE" \
     --obfuscate --split-debug-info="$GITHUB_WORKSPACE/obfuscate/" \
     --no-tree-shake-icons --verbose
   ```
   `ENV_FILE` là `env.dev` / `env.stg` / `env.prod`, do bước 4 đặt — cùng cách ánh xạ flavor sang file mà Fastlane dùng.
8. **Upload obfuscation symbols** — `--obfuscate` khiến mọi stack trace của bản build không đọc được nếu thiếu các file symbol mà `--split-debug-info` ghi vào `obfuscate/`, và chúng không nằm trong APK. Chúng được upload thành artifact `debug-symbols-<flavor>-<version>+<run>` (giữ 90 ngày), **trước** bước phân phối để một lần upload lỗi không làm mất chúng. Đọc crash bằng `flutter symbolize -i <file-stack-trace> -d <artifact>/app.android-arm64.symbols`.
9. **Distribute** — dùng thẳng Firebase CLI: Node 22 (`actions/setup-node@v6`), `npm install --global firebase-tools@15`, rồi `firebase appdistribution:distribute apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk --app <FIREBASE_ANDROID_APP_ID> --release-notes-file … --groups <groups>`. Xác thực qua `GOOGLE_APPLICATION_CREDENTIALS`, trỏ tới JSON của `FIREBASE_SERVICE_ACCOUNT_KEY` được ghi ra một file tạm (`umask 077`) và bị xoá khi bước kết thúc. Release notes (`Build version`, `Flavor`, `Notes`) đi qua một file, mọi tham số đi qua `env:`, nên dấu nháy hay `$(…)` trong `notes` được truyền nguyên văn. Thiếu secret thì bước này fail và nêu đúng tên. (Bước này thay cho action bên thứ ba `nickwph/firebase-app-distribution-action@v1`; tên secret không đổi.)

> [!NOTE]
> **`cd apps/mobile` không phải tuỳ chọn.** Chạy `flutter build apk` từ thư mục gốc sẽ lỗi khó hiểu `android/app/build.gradle not found`, vì project Flutter nằm trong `apps/mobile/` chứ không ở gốc workspace. Build ở local cũng vậy — xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Đường dẫn artifact được dựng từ flavor (`app-$FLAVOR-release.apk`) nên đúng cho cả ba flavor. Đó là cách làm đúng; Azure **không** làm vậy — xem [§5](#5-azure-ci-cdyml--azure-devops).

> [!WARNING]
> Firebase App ID **không** tách theo flavor: flavor nào cũng upload vào `secrets.FIREBASE_ANDROID_APP_ID`. Các flavor có application ID khác nhau (`.dev`, `.stg`), nên mỗi flavor là một app Firebase riêng — hãy đặt secret này thành app của flavor bạn dispatch, hoặc tách nó ra theo flavor.

### Lưu ý chi phí

Job chạy trên `macos-latest` dù chỉ build Android. Runner macOS bị tính phí theo hệ số cao hơn hẳn Linux trên các gói GitHub-hosted. Trừ khi bạn định bật lại phần build iOS (hiện đang comment) trong cùng job này, `ubuntu-latest` build Android tốt tương đương và rẻ hơn nhiều.

---

## 3. `code_review.yml` — AI Code Review

Chạy chính công cụ review dùng Gemini của repo (`tools/code_review/code_review.dart`) rồi trả kết quả về pull request.

**Kích hoạt**: pull request vào `main` / `develop` / `master` có đụng `apps/*/lib/**/*.dart`, `modules/**/*.dart` hoặc `platform/**/*.dart` (trừ file generated), cộng thêm chạy tay với bộ chọn phạm vi (`changed` / `all` / `domain` / `data` / `platform` / `presentation`) và ngôn ngữ báo cáo (`en` / `vi` / `ja` / `ko` / `zh`).

**Nó làm gì**: lấy danh sách file thay đổi bằng `tj-actions/changed-files` (ghim theo SHA commit — các tag của nó từng bị ghi đè trong vụ tấn công chuỗi cung ứng tháng 3/2025), chạy reviewer, upload báo cáo Markdown làm artifact (giữ 30 ngày), rồi phân tích báo cáo đó và đăng **comment inline đúng dòng** khi dòng đó nằm trong diff của PR. Phát hiện nằm ngoài diff được gom thành comment riêng theo từng file.

**Quyền (permissions)**: workflow khai báo `contents: read`, `pull-requests: write` (review kèm comment inline) và `issues: write` (comment theo từng file và comment "không có vấn đề"), nên vẫn chạy được ở repo mà `GITHUB_TOKEN` mặc định chỉ có quyền đọc. Danh sách file thay đổi đi vào script review qua `env:` — mỗi dòng một file, không bao giờ nội suy thẳng vào script — và danh sách file của PR được đọc bằng `github.paginate`, nên PR đụng hơn 30 file vẫn nhận comment inline trên tất cả.

**Phạm vi `changed` khi chạy tay**: diff nhánh đang checkout với merge-base của nó và nhánh mặc định của repo (được fetch tường minh; checkout có đủ lịch sử), giữ các file Dart dưới `lib/` hoặc `test/` của một app, `modules/` và `platform/`, trừ file generated, rồi review bằng `--file`. Nó **không** dùng `--changed` của chính công cụ, vốn là `git diff HEAD` — thay đổi chưa commit — và luôn rỗng trên một checkout mới. Dispatch ngay trên nhánh mặc định thì nó không thấy gì và báo như vậy.

### Ghim phiên bản Flutter

Bước cài dependency chạy `dart tools/workspace_setup/configure.dart`. Flutter lấy từ `.fvmrc` (`flutter-version-file`) ở mọi lần chạy — kể cả pull request — trừ khi lần chạy tay điền tham số tuỳ chọn `flutter_version`. (Trước đây `flutter_version` chỉ được bind ở `workflow_dispatch`, nên mọi lần chạy cho PR đều cài bản stable mới nhất lúc đó.)

### Bước "Fail on Critical Issues" không hề fail

Bước cuối đếm số file mà báo cáo đánh dấu ưu tiên HIGH — dòng `**<Nhãn ưu tiên>:** 🔴 HIGH` duy nhất trong phần của mỗi file (do `tools/code_review/lib/services/report_service.dart` ghi; nhãn được dịch, giá trị thì không). Trước đây nó đếm mọi ký hiệu 🔴 trong báo cáo, luôn gồm cả dòng chú giải `| 🔴 **High** | … |`, nên kết quả không bao giờ bằng 0. Sau đó nó cố ý không làm gì với kết quả đếm:

```bash
if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "::error::$CRITICAL_COUNT file(s) with HIGH-priority findings in the code review"
  echo "::warning::Please review the detailed report and fix critical issues"
  # Don't fail the build, just warn
  # exit 1
fi
```

`exit 1` bị comment, nên **AI review chỉ mang tính khuyến nghị và không bao giờ chặn merge**. Muốn nó chặn thật thì bỏ comment dòng đó — nhưng chỉ nên làm sau khi bạn tin tưởng tỉ lệ báo nhầm của nó trên codebase của mình, không thì mọi PR sẽ tắc.

---

## 4. `fastlane.yml` — Fastlane build and distribute

Chạy tay, giao toàn bộ việc build cho Fastlane, chạy **từ thư mục gốc repo** (`fastlane/Fastfile` ở gốc import các lane từ `apps/mobile/fastlane/`; xem [`02_fastlane_release.md` §1](02_fastlane_release.md#1-vì-sao-chạy-được-từ-bất-kỳ-đâu)).

### Tham số đầu vào

| Tham số | Mặc định | Ghi chú |
|:---|:---|:---|
| `build-on` | `self-hosted` | `self-hosted` hoặc `macos-latest`. Build iOS thì bắt buộc là máy Mac đã cài sẵn chứng chỉ ký |
| `platform` | `both` | `both` → `fastlane flutter` (iOS trước, Android sau); `android` → `fastlane android build`; `ios` → `fastlane ios build` |
| `flutter_version` | `3.47.4` | Được `subosito/flutter-action` cài **và** truyền cho lane; lane dừng nếu Flutter tìm thấy khác phiên bản này |
| `version` | `1.0.0` | `--build-name` |
| `build_number` | *(rỗng)* | Rỗng nghĩa là `auto`: số mới nhất trên store (`distribute_store`) hoặc trên Firebase (`distribute_firebase`) cộng một; không có đích phân phối thì lấy build number trong `apps/mobile/pubspec.yaml`. Nếu nhập số thì phải là số nguyên dương |
| `flavor` | `prod` | `dev` / `staging` / `prod` |
| `change_log` | `Initial release` | Release notes. Luôn được ưu tiên hơn mọi nguồn khác (không file tạm cũ nào thay thế được nó) |
| `build_type` | `apk` | Chỉ cho Android |
| `distribute_store` | `false` | Play Store và/hoặc TestFlight, tuỳ `platform` |
| `track` | `internal` | Track của Play, chỉ dùng khi có `distribute_store`: `internal`, `alpha` (closed testing), `beta` (open testing) hoặc `production` — các track có sẵn của Play Console. Track closed testing tự tạo được gọi bằng đúng tên của nó: thêm tên đó vào danh sách `options` của tham số |
| `distribute_firebase` | `true` | Firebase App Distribution |

### Các bước

1. **Checkout**, **Java 17**.
2. **Ruby 3.3 + `bundle install`** ở thư mục gốc repo (`ruby/setup-ruby` với `bundler-cache` trên runner GitHub-hosted, `bundle install` thường trên `self-hosted`). `Gemfile` ở gốc khai `fastlane` và `cocoapods`, rồi nạp plugin từ `apps/mobile/fastlane/Pluginfile` qua `fastlane/Pluginfile`, nên không còn bước `fastlane add_plugin` — lệnh đó cần tương tác và fail trên runner.
3. **Flutter** đúng phiên bản `flutter_version`.
4. **Restore gitignored build inputs from secrets** — `apps/mobile/fastlane/Config.yaml`, Firebase options của flavor (các flavor khác nhận stub), `google-services.json` (Android), `GoogleService-Info.plist` (iOS, không bắt buộc), `env.prod` và keystore release (prod; staging export `ORG_GRADLE_PROJECT_allowDevKeystoreForStaging=true` kèm một `::warning::`, như ở [§2](#2-flutter_buildyml--build-and-distribute)), cùng các file credential mà `Config.yaml` trỏ tới — chỉ những file mà kiểu phân phối đã chọn cần đến. Service account Firebase được ghi ra `firebase.credentials_map.<flavor>`, hoặc `.default` khi flavor không có mục riêng — đúng cách lùi mà các lane dùng. Key App Store Connect chỉ được ghi khi `paths.app_store_connect_key_filepath` kết thúc bằng `AuthKey_<app_store_connect.api_key_id>.p8`, cái tên duy nhất mà `xcrun altool` dùng để tìm nó ([`02_fastlane_release.md` §2](02_fastlane_release.md#2-cấu-hình)). Mọi secret thiếu đều được báo đúng tên, rồi bước này fail.
5. **Build and distribute** — `bundle exec fastlane <lane> …`. Tham số đi vào script qua `env:`, không bao giờ được nội suy thẳng vào script, nên một change log chứa dấu nháy hay `$(…)` vẫn được truyền nguyên văn. Lane tự lo phần thiết lập toolchain: `flutter pub get --enforce-lockfile`, `gen-l10n`, `build_runner`, rồi lượt sinh barrel (`tools/barrel_generator/generate.dart` cho từng package) — các barrel `lib/src/gen/gen.dart` nằm trong gitignore, nên trên một runner sạch không thiếu bước này thì không gì compile được.
6. **Upload obfuscation symbols** — các lane build với `--split-debug-info=apps/mobile/obfuscate`; thư mục đó được upload thành artifact `debug-symbols-<platform>-<flavor>-<version>+<run>` (90 ngày), kể cả khi bước phân phối fail sau khi đã build xong.

> [!NOTE]
> **Ký mã iOS** (chứng chỉ, provisioning profile) không được workflow nào thiết lập. `platform: both` / `ios` cần một runner mà keychain đã có sẵn chúng — trên thực tế là một máy Mac `self-hosted`.

---

## 5. `azure-ci-cd.yml` — Azure DevOps

Hai stage trên pool self-hosted tên `codebase`. `trigger: none` nên chỉ chạy khi kích hoạt tay hoặc từ release.

**Stage `Build`**: lấy SHA commit ngắn vào `commitTag` → tải `env.prod`, `firebase_options_prod.dart` và `google-services.prod.json` dạng *secure file* của Azure rồi copy vào đúng chỗ (Firebase options của dev/staging nhận stub chỉ để biên dịch) → cài Flutter phiên bản `$(flutter-version)` → `flutter clean` → `flutter pub get --enforce-lockfile` → "Flutter Config" → tải `key.properties` và `keystore.jks` dạng secure file vào `apps/mobile/android/` → build APK prod với `--dart-define-from-file=$(Build.SourcesDirectory)/apps/mobile/env.prod` → publish thành artifact `android`, và symbol obfuscation (`obfuscate/`, thứ `flutter symbolize` cần để đọc stack trace của bản build) thành artifact `debug-symbols`.

**Stage `Distribute`**: tải artifact về → `UseNode@1` (Node 22) → tải secure file `firebase-service-account.json` → `npx --yes firebase-tools@15 appdistribution:distribute app-prod-release.apk --app … --release-notes-file … --groups "test"`, với `GOOGLE_APPLICATION_CREDENTIALS` trỏ tới đường dẫn của secure file đó. Không có gì được cài global trên agent, và `$(note)` / `$(FIREBASE-ANDROID-ID)` đi vào script qua `env:` chứ không bị macro-expand thẳng vào script. `test` là alias nhóm tester: nó phải tồn tại trong Firebase App Distribution — sửa task để mời nhóm khác.

Các biến pipeline phải khai trong tab Variables của Azure: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, và `FIREBASE-ANDROID-ID`. Credential Firebase là một secure file, không phải biến ([§7](#azure-devops)).

Tên file artefact, lệnh gọi `configure.dart` và file env đều nhất quán: build publish `app-prod-release.apk`, stage Distribute tải về và upload đúng tên đó, "Flutter Config" chạy `dart tools/workspace_setup/configure.dart`, còn file dart-define là `apps/mobile/env.prod` — đúng file mà Fastlane và `flutter_build.yml` dùng cho prod. Secure file nào vắng mặt trong thư viện thì task `DownloadSecureFile@1` tương ứng fail, trước khi có gì được build.

Pipeline này **chỉ build prod** (`--flavor=prod`, `app-prod-release.apk`).

Các task build và distribute cho iOS có mặt nhưng đã bị comment toàn bộ.

---

## 6. Quality gate

`pr_quality_check.yml` chạy trên mọi pull request vào `main`, `develop` hoặc `master`. Đây là pipeline duy nhất có thể chặn merge.

Job `quality`, từng bước: checkout → Flutter từ `.fvmrc` → **`flutter pub get --enforce-lockfile`** → Gate 0 → Gate 1 → test của các tool gate (`cd tools && dart test`) → `dart tools/workspace_setup/configure.dart --stub-firebase` (các stub Firebase chỉ để biên dịch trước, rồi clean, pub get, gen-l10n, `build_runner`, barrel) → Gate 2–5, với báo cáo coverage sau Gate 3 → audit chỉ cảnh báo. Bước `--enforce-lockfile` chính là thứ buộc PR tuân theo `pubspec.lock` đã commit: nó fail khi lockfile không còn khớp các pubspec, trong khi `flutter pub get` thường bên trong `configure.dart` sẽ âm thầm resolve lại.

| # | Gate | Lệnh | Chặn merge |
|:--|:---|:---|:---|
| 0 | Composition khớp manifest của mọi app | `dart tools/composer/composer.dart verify` | có |
| 1 | Luật kiến trúc | `dart tools/arch_check/check.dart` | có |
| 1 | …và test riêng của các tool gate | `cd tools && dart test` | có |
| 2 | Phân tích tĩnh | `flutter analyze` | có |
| 3 | Test theo từng package | `flutter test --coverage` trong mọi package có thư mục `test/`, trừ `tools/` | có |
| — | Báo cáo coverage | `dart tools/coverage_report/report.dart` — line coverage từng package trong job summary | không (chỉ tham khảo) |
| 4 | Lệch catalog version | `dart tools/dependency_sync.dart --check` | có |
| 5 | Độ chính xác của docs và tương đương en ↔ vi | `dart tools/docs_check/check.dart` | có |
| — | Audit dependency thừa | `dart tools/unused_checker/check_unused_packages.dart` | không (chỉ cảnh báo) |

Gate 0 và 1 chạy đầu tiên là có chủ đích: chúng chỉ đọc manifest, import và pubspec và không cần codegen — `pub get` là đủ, vì `tools/` là thành viên của workspace — mỗi gate xong trong một hai giây, nên lỗi composition hay phân tầng fail ngay sau bước resolve dependency thay vì sau cả chu kỳ thiết lập, analyze và test. Gate 1 cũng là gate **duy nhất** nhìn thấy được phân tầng; không có gì trong `analysis_options.yaml` biết rằng core không được import feature.

Mọi gate đều là một script trong `tools/`, và một gate đã âm thầm thôi fail trông y hệt một PR sạch. Vì vậy các gate có test riêng, trong `tools/test/`, chạy như nửa sau của Gate 1: mỗi test dựng một workspace dùng một lần trong thư mục tạm, chạy tool trên đó như một subprocess (compile sang kernel một lần cho mỗi file, nên cả bộ mất khoảng 15 giây) rồi kiểm tra exit code và output. Chúng phủ `arch_check` (một fixture sạch và một fixture vi phạm cho mỗi luật R1–R10; R6 phải cảnh báo mà vẫn exit 0), `composer verify` (manifest đã sync thì qua; `phase: befor`, layer lạ, module trùng và module không có trên đĩa bị từ chối kèm đường dẫn key), `dependency_sync --check` (lệch version và catalog sai định dạng exit 1), `docs_check` (tham chiếu chết exit 1, span `<placeholder>` và sample bundle đã gỡ thì không, gốc repo lấy từ vị trí script; cặp en ↔ vi thiếu heading, code block hay dòng bảng thì exit 1), barrel generator (dấu `/` ở cuối, thư mục `web/` bên trong `lib/`), composer `bootstrap --dry-run` (báo member bị thiếu, không ghi gì), phần kiểm tra `--apps` của module generator (id app lạ exit 64 và không ghi gì), các stub của `configure.dart --stub-firebase` (mỗi flavor một file, file thật được giữ, `configure.dart` không chạm tới import `package:` nào) và báo cáo coverage (parse lcov, loại file sinh ra, `--min`). Sửa một gate thì thêm case vào đó. Giống Gate 0 và 1, chúng không cần codegen, nên chạy trước bước thiết lập chứ không nằm trong Gate 3.

Gate 3 phải lặp theo từng package vì đây là Pub Workspace: test nằm trong `test/` của từng package — hiện ở `platform/*/test/` và `modules/*/*/test/`, mười chín package — nên chạy một lệnh `flutter test` ở gốc sẽ không thấy chúng. Gate này bỏ qua `tools/`, vì test của nó đã chạy rồi.

Mỗi package chạy với `--coverage`, để lại `<package>/coverage/lcov.info` (đã gitignore). Bước kế tiếp, **Coverage report (advisory)**, đọc tất cả bằng `dart tools/coverage_report/report.dart` và ghi bảng line coverage theo từng package — đã loại file sinh ra (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `gen/`, …) — vào job summary của lần chạy. Nó vẫn chạy khi có test fail (`if: !cancelled()`), là `continue-on-error` và không có ngưỡng. Muốn biến coverage thành gate, thêm `--min <pct>` (tổng) hoặc `--min-package <pct>` (từng package) vào bước đó và bỏ `continue-on-error`; xem [`../reference/03_tooling.md`](../reference/03_tooling.md).

> [!IMPORTANT]
> `flutter analyze` sạch **không** chứng minh app build được. `analysis_options.yaml` loại trừ `**.freezed.dart`, `**.g.dart`, `**.config.dart` và `**.module.dart`, nên analyzer không bao giờ nhìn vào code sinh ra. Chuyển một type sang package khác là đủ để một file `.freezed.dart` tham chiếu tới symbol nó không thấy được: analyze vẫn xanh trong khi build APK fail. Chỉ build thật mới bắt được loại lỗi đó.

Đó là việc của job thứ hai, **`build`**. Nó không phải một gate có số — nó `needs: quality`, nên chỉ bắt đầu khi mọi gate đã qua và một lỗi phân tầng hay analyze không bao giờ phải trả giá bằng một lần build Gradle — nhưng nó thuộc cùng lần chạy workflow, và build đỏ thì workflow fail. Nó cài **Java 17** (AGP 9 / Gradle 9 cần 17 trở lên, và 17 khớp `jvmTarget` của app), Flutter từ `.fvmrc`, chạy `flutter pub get --enforce-lockfile`, rồi `configure.dart --stub-firebase`, mà các stub Firebase chỉ để biên dịch của nó — ba file options cộng một `apps/mobile/android/app/src/<flavor>/google-services.json` cho mỗi flavor, đúng stub trong [`../getting-started/01_setup.md` §3.2](../getting-started/01_setup.md#32-chưa-có-firebase-project-dùng-stub), với package name đọc từ `build.gradle.kts` — là thứ một lần build Gradle cần, rồi từ `apps/mobile/`:

```bash
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

Bản debug không cần keystore release và `env.dev` đã được commit, nên job này không cần secret nào.

Job thứ ba, **`generator-smoke`**, cũng `needs: quality`. Không có gì khác chạy thử các template của module generator — chúng là file Mustache mà không analyzer nào đọc — nên một template sinh ra dependency thừa, vi phạm phân tầng hay code không còn analyze được sẽ đến tay developer kế tiếp chạy nó. Job làm đúng việc developer đó sẽ làm: pub get, `configure.dart --stub-firebase`, rồi

```bash
dart tools/module_generator/generate.dart 1 smoke "" 2 2   # feature BLoC, tab bottom-nav
```

— template rộng nhất: routing, localization, DI và mọi `app_manifest.yaml` — và bắt kết quả qua các gate: `flutter analyze`, test riêng của module được sinh (`flutter test` trong package `feature_smoke` mới sinh — test page và test BLoC mà generator ghi ra phải pass mà không cần sửa), `arch_check`, `composer verify`, và `check_unused_packages`, chỉ fail khi dependency thừa nằm trong `feature_smoke` (ở chỗ khác thì vẫn là audit chỉ cảnh báo của job quality, hiện dưới dạng warning). Không commit gì; bản checkout bị bỏ đi.

Hãy đặt **cả ba** job là required status check trong branch protection rule.

**Vẫn còn thiếu:** các pipeline phát hành (`flutter_build.yml`, `fastlane.yml`, `azure-ci-cd.yml`) đều là `workflow_dispatch` và **không** chạy gate nào của riêng chúng. Một lần dispatch thủ công từ nhánh chưa từng mở PR vẫn sẽ build, ký và phân phối code chưa được kiểm. Nếu điều đó quan trọng với bạn, hãy thêm gate 0–5 vào `flutter_build.yml` giữa "Install Dependencies" và "Build APK", hoặc quy định chỉ phát hành từ nhánh đã merge.

---

## 7. Secrets

### GitHub Actions

Mọi file dưới đây đều bị gitignore, nên runner sạch không có file nào; các workflow phát hành giải mã chúng từ secret. `<FLAVOR>` là `DEV`, `STAGING` hoặc `PROD` — chỉ cần secret của flavor đang build. Trừ khi ghi chú *nguyên văn*, secret chứa **base64** của file.

| Secret | Ghi ra | Cần cho | Cách tạo giá trị |
|:---|:---|:---|:---|
| `FIREBASE_OPTIONS_<FLAVOR>_DART_B64` | `firebase_options_<flavor>.dart` trong `apps/mobile/lib/firebase/` | `flutter_build.yml`, `fastlane.yml` — mọi bản build của flavor đó | `cd apps/mobile/lib/firebase && base64 -w0 firebase_options_dev.dart` (sinh file bằng `dart tools/firebase/firebase_config.dart --app mobile`) |
| `GOOGLE_SERVICES_<FLAVOR>_JSON_B64` | `apps/mobile/android/app/src/<flavor>/google-services.json` | cả hai — mọi bản build Android của flavor đó | `base64 -w0 apps/mobile/android/app/src/dev/google-services.json` |
| `GOOGLE_SERVICE_INFO_<FLAVOR>_PLIST_B64` | `ios/flavors/<flavor>/GoogleService-Info.plist` bên trong `apps/mobile/` | `fastlane.yml`, bản build iOS — không bắt buộc (chỉ cảnh báo nếu thiếu) | `base64 -w0 apps/mobile/ios/flavors/dev/GoogleService-Info.plist` |
| `ENV_PROD_B64` | `apps/mobile/env.prod` | cả hai — bản build **prod** (`env.dev` / `env.stg` đã commit) | `base64 -w0 apps/mobile/env.prod`. Thay cho secret `ENV` cũ, vốn được giải mã ra `.env` ở gốc cho mọi flavor |
| `KEYSTORE_BASE64` | `apps/mobile/android/keystore.jks` | cả hai — bản build Android **prod** | `base64 -w0 upload-keystore.jks` |
| `KEYSTORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS` | `apps/mobile/android/key.properties` (*nguyên văn*) | cả hai — bản build Android **prod** | Mật khẩu keystore, mật khẩu key, alias của key |
| `FASTLANE_CONFIG_YAML_B64` | `apps/mobile/fastlane/Config.yaml` | `fastlane.yml` — luôn luôn | `base64 -w0 apps/mobile/fastlane/Config.yaml` |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | JSON *nguyên văn*. `flutter_build.yml` ghi nó ra một file tạm làm `GOOGLE_APPLICATION_CREDENTIALS` cho Firebase CLI; `fastlane.yml` ghi nó ra `firebase.credentials_map.<flavor>` (hoặc `.default`) trong `Config.yaml` | cả hai — phân phối qua Firebase | Nội dung file JSON service-account của Firebase (service account có role *Firebase App Distribution Admin*) |
| `GOOGLE_PLAY_JSON_KEY_B64` | `paths.google_play_key_prod` trong `Config.yaml` | `fastlane.yml` — `distribute_store` + Android | `base64 -w0 google-play-store.json` |
| `APP_STORE_CONNECT_API_KEY_P8_B64` | `paths.app_store_connect_key_filepath` trong `Config.yaml` — phải kết thúc bằng `AuthKey_<api_key_id>.p8`, không thì bước này fail | `fastlane.yml` — `distribute_store` + iOS | `base64 -w0 AuthKey_XXXX.p8` |
| `FIREBASE_ANDROID_APP_ID` | — | `flutter_build.yml` | Firebase App ID, ví dụ `1:1234567890:android:abcdef` |
| `GEMINI_API_KEY` | — | `code_review.yml` | Tạo tại <https://aistudio.google.com/app/apikey> |
| `GITHUB_TOKEN` | — | `code_review.yml` | GitHub tự cấp — không cần tự tạo |

Thêm tại **Settings → Secrets and variables → Actions → New repository secret**.

Các secret keystore là **bắt buộc** với prod: Gradle từ chối build release prod khi thiếu `key.properties` ([`02_fastlane_release.md` §4](02_fastlane_release.md#4-ký-ứng-dụng)), và workflow nêu tên secret bị thiếu trước khi tốn thời gian build. Gradle cũng từ chối build release staging khi thiếu `key-stg.properties`; hiện chưa có secret keystore cho staging, nên `flutter_build.yml` và `fastlane.yml` export `ORG_GRADLE_PROJECT_allowDevKeystoreForStaging=true` cho staging và in một `::warning::` nói rằng bản build được ký bằng keystore dev **công khai**. Hãy thêm secret keystore cho staging và khôi phục `apps/mobile/android/key-stg.properties` từ chúng để ký staging đúng cách, rồi bỏ opt-in đó. Đường dẫn tương đối trong `Config.yaml` được giải theo `apps/mobile/`, đúng như cách các lane giải.

> [!CAUTION]
> `base64` không có `-w0` sẽ chèn xuống dòng trên Linux, làm `base64 -d` trong workflow hỏng. Trên macOS, `base64 -i <file>` vốn đã cho một dòng duy nhất. Luôn tự kiểm tra bằng `base64 -d` ở local trước khi dán vào.

### Azure DevOps

Azure dùng thư viện **Secure files** thay vì secret: upload các file sau tại **Pipelines → Library → Secure files**, đặt đúng những tên này:

| Secure file | Copy tới |
|:---|:---|
| `env.prod` | `apps/mobile/env.prod` |
| `firebase_options_prod.dart` | `firebase_options_prod.dart` trong `apps/mobile/lib/firebase/` |
| `google-services.prod.json` | `apps/mobile/android/app/src/<flavor>/google-services.json`, flavor `prod` |
| `key.properties` | `apps/mobile/android/key.properties` — với `storeFile=../keystore.jks` |
| `keystore.jks` | `apps/mobile/android/keystore.jks` |
| `firebase-service-account.json` | Không copy: stage Distribute trỏ `GOOGLE_APPLICATION_CREDENTIALS` tới nó cho Firebase CLI. Cùng JSON service-account với secret `FIREBASE_SERVICE_ACCOUNT_KEY` của GitHub |

`FIREBASE-ANDROID-ID` là biến pipeline.

---

## 8. Tái hiện CI ở local

Chạy những lệnh này trước khi push; chúng đúng là những lệnh pipeline dùng.

```bash
# 1. Lockfile đã commit, rồi Gate 0 và 1 — đúng phần đầu của
#    pr_quality_check.yml; cả hai gate đều không cần codegen
flutter pub get --enforce-lockfile
dart tools/composer/composer.dart verify
dart tools/arch_check/check.dart
(cd tools && dart test)                # test riêng của các tool gate

# 2. Thiết lập toàn workspace — bước setup của CI; --stub-firebase chỉ ghi
#    stub Firebase để biên dịch ở nơi chưa có file thật — rồi các gate còn
#    lại, theo đúng thứ tự
dart tools/workspace_setup/configure.dart --stub-firebase
flutter analyze
dart tools/dependency_sync.dart --check
dart tools/docs_check/check.dart

# 3. Test theo từng package (gate 3 — xem §6), rồi bảng coverage
(cd platform/storage && flutter test --coverage)
(cd platform/database && flutter test --coverage)
# ...lặp cho mọi package có thư mục test/
dart tools/coverage_report/report.dart

# 4. Job generator-smoke — trong một bản clone nháp, không phải working tree
#    của bạn: nó đăng ký `smoke` vào mọi manifest và ghi lại lockfile
#    dart tools/module_generator/generate.dart 1 smoke "" 2 2
#    flutter analyze && (cd modules/smoke/feature && flutter test)
#    dart tools/arch_check/check.dart && dart tools/composer/composer.dart verify

# 5. Job build của pr_quality_check.yml (cần stub Firebase hoặc file thật —
#    xem bên dưới) — chú ý cd
(cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev)

# 6. Đúng lệnh build release mà CI chạy — chú ý cd
cd apps/mobile
flutter build apk --flavor=dev --build-name=1.0.0 --build-number=1 \
  --dart-define-from-file=env.dev --obfuscate --split-debug-info=../../obfuscate/ \
  --no-tree-shake-icons
```

> [!NOTE]
> Ở local đường dẫn dart-define là `env.dev` (tương đối so với `apps/mobile/`). CI dùng đúng các file đó — `apps/mobile/env.<dev|stg|prod>` — nhưng trỏ tới bằng đường dẫn tuyệt đối, qua `$GITHUB_WORKSPACE` trên GitHub và `$(Build.SourcesDirectory)` trên Azure, vì việc đếm `../` từ thư mục app đã hỏng ngay khi app lùi xuống sâu hơn một cấp.

Build lần đầu trên máy sạch còn cần đã chạy `flutterfire configure` — các file `firebase_options_*.dart` và `google-services.json` sinh ra bị gitignore, mà `apps/mobile/lib/firebase/firebase_module.dart` import cả ba file options vô điều kiện. (các job của `pr_quality_check.yml` chạy `configure.dart --stub-firebase`, tạo stub options cho mọi app có `lib/firebase/firebase_module.dart` và một `google-services.json` cho mỗi flavor Android — đủ cho analyze, test và một bản build debug, nhưng không đủ để Firebase hoạt động thật; chạy đúng cờ đó ở local khi bạn chưa có project Firebase; các pipeline phát hành khôi phục file thật từ secret — [§7](#7-secrets).) Xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 9. Danh sách việc cần sửa

Các mục còn mở, theo thứ tự ưu tiên tương đối:

- [ ] `flutter_build.yml` — chạy sáu gate của `pr_quality_check.yml` trước khi build, để một lần dispatch thủ công không thể ship code chưa kiểm
- [ ] `flutter_build.yml` / `fastlane.yml` — thêm secret keystore cho staging, khôi phục `apps/mobile/android/key-stg.properties` từ chúng và bỏ opt-in `allowDevKeystoreForStaging`, để staging thôi bị ký bằng key dev công khai ([§2](#2-flutter_buildyml--build-and-distribute))
- [ ] `code_review.yml` — quyết định có bỏ comment `exit 1` hay không (chỉ sau khi tin tưởng tỷ lệ báo nhầm của nó)
- [ ] `flutter_build.yml` — cân nhắc `ubuntu-latest` thay cho `macos-latest` với build chỉ cho Android
- [ ] `flutter_build.yml` — tách `FIREBASE_ANDROID_APP_ID` theo flavor ([§2](#2-flutter_buildyml--build-and-distribute))
- [ ] `fastlane.yml` — thiết lập ký mã iOS (ví dụ `match`) nếu muốn build iOS trên runner GitHub-hosted

---

## Xem thêm

- [`02_fastlane_release.md`](02_fastlane_release.md) — lane, ký ứng dụng và quy trình phát hành
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — chạy lần đầu, khởi tạo Firebase, flavor
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — toàn bộ script trong `tools/`
