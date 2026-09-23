# CI/CD

Tài liệu này trả lời: **có những pipeline nào, mỗi cái làm gì, cần secret gì, và hiện đang hỏng chỗ nào.** Đọc xong bạn cấu hình được secret cho repo, chạy được build, và tái hiện được mọi bước CI ở máy local trước khi push.

> [!IMPORTANT]
> Các pipeline phát hành phụ thuộc vào **secret của repo** cho mọi đầu vào bị gitignore — Firebase options, `google-services.json`, `env.prod`, keystore release, `Config.yaml` của fastlane ([§7](#7-secrets)). Thiếu chúng thì pipeline dừng ngay ở bước đầu và nêu tên secret còn thiếu. Đừng cho rằng chúng đang chạy xanh khi bạn chưa cấu hình secret và tự chạy thử một lần.

---

## 1. Danh sách pipeline

Template có **năm** pipeline — bốn trên GitHub Actions, một trên Azure DevOps.

| Pipeline | File | Kích hoạt | Đầu ra |
|:---|:---|:---|:---|
| Build and Distribute | `.github/workflows/flutter_build.yml` | Thủ công (`workflow_dispatch`) | APK release đã ký → Firebase App Distribution |
| AI Code Review | `.github/workflows/code_review.yml` | PR vào `main`/`develop`/`master` + thủ công | Báo cáo Markdown + comment trên PR |
| Fastlane build and distribute | `.github/workflows/fastlane.yml` | Thủ công (`workflow_dispatch`) | Uỷ quyền cho các lane Fastlane |
| **PR Quality Check** | `.github/workflows/pr_quality_check.yml` | **PR vào `main`/`develop`/`master`** + thủ công | Đạt/không — chặn merge |
| Azure Build + Distribute | `azure-ci-cd.yml` | `trigger: none` (chỉ chạy tay) | APK prod → Firebase |

`pr_quality_check.yml` là pipeline duy nhất chặn được merge. Nó chạy sáu gate chặn theo thứ tự — lệch composition, luật kiến trúc, `flutter analyze`, test từng package, lệch catalog, độ chính xác của docs — cộng một audit chỉ cảnh báo. Xem [§6](#6-quality-gate).

---

## 2. `flutter_build.yml` — Build and Distribute

Pipeline release Android chính. Chỉ chạy tay: **Actions → Build and Release → Run workflow**.

### Tham số đầu vào

| Tham số | Bắt buộc | Mặc định | Ghi chú |
|:---|:---|:---|:---|
| `flavor` | có | `prod` | `dev` / `staging` / `prod` |
| `version` | có | `1.0.0` | Trở thành `--build-name` |
| `notes` | không | — | Ghép vào release notes của Firebase |

Build number không phải tham số — nó dùng `${{ github.run_number }}`, nên tự tăng theo mỗi lần chạy workflow.

### Các bước, theo thứ tự

1. **Checkout** — `actions/checkout@v4`.
2. **Set Up Java** — bản Oracle, **Java 17**. Khớp với `sourceCompatibility`/`targetCompatibility` trong `apps/mobile/android/app/build.gradle.kts`.
3. **Set Up Flutter** — `subosito/flutter-action@v2`, ghim **`3.47.4`**, kênh `stable`, bật cache.
4. **Restore gitignored build inputs from secrets** — chỉ cho flavor được chọn, mỗi file lấy từ một secret base64 ([§7](#7-secrets)):
   - `firebase_options_<flavor>.dart` trong `apps/mobile/lib/firebase/`; hai flavor còn lại nhận một stub chỉ để biên dịch, vì `firebase_module.dart` import cả ba file còn injectable chỉ đăng ký options của flavor đang build;
   - `apps/mobile/android/app/src/<flavor>/google-services.json` — thiếu nó thì plugin Gradle `com.google.gms.google-services` làm build fail;
   - `apps/mobile/env.prod` (chỉ prod — `env.dev` / `env.stg` đã được commit);
   - chỉ prod: `apps/mobile/android/keystore.jks` + `key.properties` (`storeFile=../keystore.jks`). dev và staging được ký bằng keystore dev đã commit.

   Thiếu secret nào thì bước này fail kèm lỗi nêu đúng tên secret đó — trước khi tốn thời gian cho codegen hay Gradle. Nó chạy **trước** bước sinh code vì `build_runner` phải phân giải được các import của `firebase_module.dart`.
5. **Get dependencies from the committed lockfile** — `flutter pub get --enforce-lockfile`. `pubspec.lock` của workspace đã được commit; lockfile nào không còn khớp các pubspec sẽ fail ngay tại đây thay vì bị resolve lại âm thầm.
6. **Install Dependencies** — `dart tools/workspace_setup/configure.dart`. Script Dart này làm trọn gói: pub get, sinh l10n, và `build_runner` cho cả workspace.
7. **Build APK** — chú ý dòng `cd apps/mobile` đứng riêng phía trước:
   ```bash
   cd apps/mobile
   flutter build apk --flavor="$FLAVOR" --build-name="$VERSION" --build-number="$GITHUB_RUN_NUMBER" \
     --dart-define-from-file="$GITHUB_WORKSPACE/apps/mobile/$ENV_FILE" \
     --obfuscate --split-debug-info="$GITHUB_WORKSPACE/obfuscate/" \
     --no-tree-shake-icons --verbose
   ```
   `ENV_FILE` là `env.dev` / `env.stg` / `env.prod`, do bước 4 đặt — cùng cách ánh xạ flavor sang file mà Fastlane dùng.
8. **Upload and Distribute** — `nickwph/firebase-app-distribution-action@v1`, tải lên `apps/mobile/build/app/outputs/flutter-apk/app-<flavor>-release.apk`.

> [!NOTE]
> **`cd apps/mobile` không phải tuỳ chọn.** Chạy `flutter build apk` từ thư mục gốc sẽ lỗi khó hiểu `android/app/build.gradle not found`, vì project Flutter nằm trong `apps/mobile/` chứ không ở gốc workspace. Build ở local cũng vậy — xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Tên artifact có nội suy flavor (`app-${{ inputs.flavor }}-release.apk`) nên đúng cho cả ba flavor. Đó là cách làm đúng; Azure **không** làm vậy — xem [§5](#5-azure-ci-cdyml--azure-devops).

> [!WARNING]
> Firebase App ID **không** tách theo flavor: flavor nào cũng upload vào `secrets.FIREBASE_ANDROID_APP_ID`. Các flavor có application ID khác nhau (`.dev`, `.stg`), nên mỗi flavor là một app Firebase riêng — hãy đặt secret này thành app của flavor bạn dispatch, hoặc tách nó ra theo flavor.

### Lưu ý chi phí

Job chạy trên `macos-latest` dù chỉ build Android. Runner macOS bị tính phí theo hệ số cao hơn hẳn Linux trên các gói GitHub-hosted. Trừ khi bạn định bật lại phần build iOS (hiện đang comment) trong cùng job này, `ubuntu-latest` build Android tốt tương đương và rẻ hơn nhiều.

---

## 3. `code_review.yml` — AI Code Review

Chạy chính công cụ review dùng Gemini của repo (`tools/code_review/code_review.dart`) rồi trả kết quả về pull request.

**Kích hoạt**: pull request vào `main` / `develop` / `master` có đụng `apps/*/lib/**/*.dart`, `modules/**/*.dart` hoặc `platform/**/*.dart` (trừ file generated), cộng thêm chạy tay với bộ chọn phạm vi (`changed` / `all` / `domain` / `data` / `platform` / `presentation`) và ngôn ngữ báo cáo (`en` / `vi` / `ja` / `ko` / `zh`).

**Nó làm gì**: lấy danh sách file thay đổi bằng `tj-actions/changed-files`, chạy reviewer, upload báo cáo Markdown làm artifact (giữ 30 ngày), rồi phân tích báo cáo đó và đăng **comment inline đúng dòng** khi dòng đó nằm trong diff của PR. Phát hiện nằm ngoài diff được gom thành comment riêng theo từng file.

### Ghim phiên bản Flutter

Bước cài dependency chạy `dart tools/workspace_setup/configure.dart`, và `flutter_version` mặc định `3.47.4`, khớp ràng buộc trong `pubspec.yaml` gốc.

> [!NOTE]
> `flutter_version` chỉ được bind ở `workflow_dispatch`. Với sự kiện `pull_request` thì `github.event.inputs.flutter_version` rỗng, nên `subosito/flutter-action@v2` nhận `flutter-version` rỗng và tự lấy bản stable mới nhất thay vì bản đã pin. Vô hại với một AI review; nhưng đừng sao chép pattern này sang pipeline có tạo artefact.

### Bước "Fail on Critical Issues" không hề fail

Bước cuối đếm số marker 🔴 rồi cố ý không làm gì với kết quả đếm:

```bash
if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "::error::Found $CRITICAL_COUNT critical issues in code review"
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
| `track` | `internal` | Track của Play, chỉ dùng khi có `distribute_store` |
| `distribute_firebase` | `true` | Firebase App Distribution |

### Các bước

1. **Checkout**, **Java 17**.
2. **Ruby 3.3 + `bundle install`** ở thư mục gốc repo (`ruby/setup-ruby` với `bundler-cache` trên runner GitHub-hosted, `bundle install` thường trên `self-hosted`). `Gemfile` ở gốc khai `fastlane` và `cocoapods`, rồi nạp plugin từ `apps/mobile/fastlane/Pluginfile` qua `fastlane/Pluginfile`, nên không còn bước `fastlane add_plugin` — lệnh đó cần tương tác và fail trên runner.
3. **Flutter** đúng phiên bản `flutter_version`.
4. **Restore gitignored build inputs from secrets** — `apps/mobile/fastlane/Config.yaml`, Firebase options của flavor (các flavor khác nhận stub), `google-services.json` (Android), `GoogleService-Info.plist` (iOS, không bắt buộc), `env.prod` và keystore release (prod), cùng các file credential mà `Config.yaml` trỏ tới — chỉ những file mà kiểu phân phối đã chọn cần đến. Mọi secret thiếu đều được báo đúng tên, rồi bước này fail.
5. **Build and distribute** — `bundle exec fastlane <lane> …`. Tham số đi vào script qua `env:`, không bao giờ được nội suy thẳng vào script, nên một change log chứa dấu nháy hay `$(…)` vẫn được truyền nguyên văn. Lane tự lo phần thiết lập toolchain: `flutter pub get --enforce-lockfile`, `gen-l10n`, `build_runner`.

> [!NOTE]
> **Ký mã iOS** (chứng chỉ, provisioning profile) không được workflow nào thiết lập. `platform: both` / `ios` cần một runner mà keychain đã có sẵn chúng — trên thực tế là một máy Mac `self-hosted`.

---

## 5. `azure-ci-cd.yml` — Azure DevOps

Hai stage trên pool self-hosted tên `codebase`. `trigger: none` nên chỉ chạy khi kích hoạt tay hoặc từ release.

**Stage `Build`**: lấy SHA commit ngắn vào `commitTag` → tải `env.prod`, `firebase_options_prod.dart` và `google-services.prod.json` dạng *secure file* của Azure rồi copy vào đúng chỗ (Firebase options của dev/staging nhận stub chỉ để biên dịch) → cài Flutter phiên bản `$(flutter-version)` → `flutter clean` → `flutter pub get --enforce-lockfile` → "Flutter Config" → tải `key.properties` và `keystore.jks` dạng secure file vào `apps/mobile/android/` → build APK prod với `--dart-define-from-file=$(Build.SourcesDirectory)/apps/mobile/env.prod` → publish thành artifact `android`.

**Stage `Distribute`**: tải artifact về rồi `firebase appdistribution:distribute`.

Các biến pipeline phải khai trong tab Variables của Azure: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, và `FIREBASE-ANDROID-ID`.

Tên file artefact, lệnh gọi `configure.dart` và file env đều nhất quán: build publish `app-prod-release.apk`, stage Distribute tải về và upload đúng tên đó, "Flutter Config" chạy `dart tools/workspace_setup/configure.dart`, còn file dart-define là `apps/mobile/env.prod` — đúng file mà Fastlane và `flutter_build.yml` dùng cho prod. Secure file nào vắng mặt trong thư viện thì task `DownloadSecureFile@1` tương ứng fail, trước khi có gì được build.

Pipeline này **chỉ build prod** (`--flavor=prod`, `app-prod-release.apk`).

Các task build và distribute cho iOS có mặt nhưng đã bị comment toàn bộ.

---

## 6. Quality gate

`pr_quality_check.yml` chạy trên mọi pull request vào `main`, `develop` hoặc `master`. Đây là pipeline duy nhất có thể chặn merge.

| # | Gate | Lệnh | Chặn merge |
|:--|:---|:---|:---|
| 0 | Composition khớp manifest của mọi app | `dart tools/composer/composer.dart verify` | có |
| 1 | Luật kiến trúc | `dart tools/arch_check/check.dart` | có |
| 2 | Phân tích tĩnh | `flutter analyze` | có |
| 3 | Test theo từng package | `flutter test` trong mọi package có thư mục `test/` | có |
| 4 | Lệch catalog version | `dart tools/dependency_sync.dart --check` | có |
| 5 | Độ chính xác của docs | `dart tools/docs_check/check.dart` | có |
| — | Audit dependency thừa | `dart tools/unused_checker/check_unused_packages.dart` | không (chỉ cảnh báo) |

Gate 0 và 1 chạy đầu tiên là có chủ đích: chúng chỉ đọc manifest, import và pubspec, không cần codegen, xong trong khoảng 200 ms — nên lỗi phân tầng fail sau vài giây thay vì sau cả chu kỳ analyze và test. Gate 1 cũng là gate **duy nhất** nhìn thấy được phân tầng; không có gì trong `analysis_options.yaml` biết rằng core không được import feature.

Gate 3 phải lặp theo từng package vì đây là Pub Workspace: test nằm trong `test/` của từng package — hiện phần lớn ở `platform/*/test/` — nên chạy một lệnh `flutter test` ở gốc sẽ không thấy chúng.

> [!IMPORTANT]
> `flutter analyze` sạch **không** chứng minh app build được. `analysis_options.yaml` loại trừ `**.freezed.dart`, `**.g.dart`, `**.config.dart` và `**.module.dart`, nên analyzer không bao giờ nhìn vào code sinh ra. Chuyển một type sang package khác là đủ để một file `.freezed.dart` tham chiếu tới symbol nó không thấy được: analyze vẫn xanh trong khi build APK fail. Chỉ build thật mới bắt được loại lỗi đó.

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
| `FIREBASE_SERVICE_ACCOUNT_KEY` | JSON *nguyên văn*. `flutter_build.yml` đưa nó cho action upload; `fastlane.yml` ghi nó ra `firebase.credentials_map.<flavor>` trong `Config.yaml` | cả hai — phân phối qua Firebase | Nội dung file JSON service-account của Firebase |
| `GOOGLE_PLAY_JSON_KEY_B64` | `paths.google_play_key_prod` trong `Config.yaml` | `fastlane.yml` — `distribute_store` + Android | `base64 -w0 google-play-store.json` |
| `APP_STORE_CONNECT_API_KEY_P8_B64` | `paths.app_store_connect_key_filepath` trong `Config.yaml` | `fastlane.yml` — `distribute_store` + iOS | `base64 -w0 AuthKey_XXXX.p8` |
| `FIREBASE_ANDROID_APP_ID` | — | `flutter_build.yml` | Firebase App ID, ví dụ `1:1234567890:android:abcdef` |
| `GEMINI_API_KEY` | — | `code_review.yml` | Tạo tại <https://aistudio.google.com/app/apikey> |
| `GITHUB_TOKEN` | — | `code_review.yml` | GitHub tự cấp — không cần tự tạo |

Thêm tại **Settings → Secrets and variables → Actions → New repository secret**.

Các secret keystore là **bắt buộc** với prod: thiếu `key.properties`, Gradle sẽ âm thầm ký bản prod bằng keystore dev đã commit ([`02_fastlane_release.md` §4](02_fastlane_release.md#4-ký-ứng-dụng)), nên workflow từ chối build thay vì để chuyện đó xảy ra. Đường dẫn tương đối trong `Config.yaml` được giải theo `apps/mobile/`, đúng như cách các lane giải.

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

`FIREBASE-ANDROID-ID` là biến pipeline.

---

## 8. Tái hiện CI ở local

Chạy những lệnh này trước khi push; chúng đúng là những lệnh pipeline dùng.

```bash
# 1. Thiết lập toàn workspace — tương đương bước "Install Dependencies" của CI
#    (các pipeline phát hành chạy `flutter pub get --enforce-lockfile` trước)
dart tools/workspace_setup/configure.dart

# 2. Đúng các gate mà pr_quality_check.yml chạy, theo đúng thứ tự
dart tools/composer/composer.dart verify
dart tools/arch_check/check.dart
flutter analyze
dart tools/dependency_sync.dart --check
dart tools/docs_check/check.dart

# 3. Test theo từng package (gate 3 — xem §6)
(cd platform/storage && flutter test)
(cd platform/database && flutter test)
# ...lặp cho mọi package có thư mục test/

# 4. Đúng lệnh build release mà CI chạy — chú ý cd
cd apps/mobile
flutter build apk --flavor=dev --build-name=1.0.0 --build-number=1 \
  --dart-define-from-file=env.dev --obfuscate --split-debug-info=../../obfuscate/ \
  --no-tree-shake-icons
```

> [!NOTE]
> Ở local đường dẫn dart-define là `env.dev` (tương đối so với `apps/mobile/`). CI dùng đúng các file đó — `apps/mobile/env.<dev|stg|prod>` — nhưng trỏ tới bằng đường dẫn tuyệt đối, qua `$GITHUB_WORKSPACE` trên GitHub và `$(Build.SourcesDirectory)` trên Azure, vì việc đếm `../` từ thư mục app đã hỏng ngay khi app lùi xuống sâu hơn một cấp.

Build lần đầu trên máy sạch còn cần đã chạy `flutterfire configure` — các file `firebase_options_*.dart` và `google-services.json` sinh ra bị gitignore, mà `apps/mobile/lib/firebase/firebase_module.dart` import cả ba file options vô điều kiện. (`pr_quality_check.yml` tạo stub options cho mọi app có `lib/firebase/firebase_module.dart` — đủ cho analyze và test, nhưng không đủ cho một bản build thật; các pipeline phát hành khôi phục file thật từ secret — [§7](#7-secrets).) Xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 9. Danh sách việc cần sửa

Các mục còn mở, theo thứ tự ưu tiên tương đối:

- [ ] `flutter_build.yml` — chạy sáu gate của `pr_quality_check.yml` trước khi build, để một lần dispatch thủ công không thể ship code chưa kiểm
- [ ] `code_review.yml` — quyết định có bỏ comment `exit 1` hay không (chỉ sau khi tin tưởng tỷ lệ báo nhầm của nó)
- [ ] `flutter_build.yml` — cân nhắc `ubuntu-latest` thay cho `macos-latest` với build chỉ cho Android
- [ ] `flutter_build.yml` — tách `FIREBASE_ANDROID_APP_ID` theo flavor ([§2](#2-flutter_buildyml--build-and-distribute))
- [ ] `fastlane.yml` — thiết lập ký mã iOS (ví dụ `match`) nếu muốn build iOS trên runner GitHub-hosted

---

## Xem thêm

- [`02_fastlane_release.md`](02_fastlane_release.md) — lane, ký ứng dụng và quy trình phát hành
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — chạy lần đầu, khởi tạo Firebase, flavor
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — toàn bộ script trong `tools/`
