# CI/CD

Tài liệu này trả lời: **có những pipeline nào, mỗi cái làm gì, cần secret gì, và hiện đang hỏng chỗ nào.** Đọc xong bạn cấu hình được secret cho repo, chạy được build, và tái hiện được mọi bước CI ở máy local trước khi push.

> [!IMPORTANT]
> Một số pipeline trong repo này **đang hỏng thật sự**. Tài liệu mô tả đúng hiện trạng kèm cách sửa từng chỗ. Đừng cho rằng chúng đang chạy xanh khi bạn chưa tự chạy thử.

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

`pr_quality_check.yml` là pipeline duy nhất chặn được merge. Nó chạy bốn gate chặn theo thứ tự — luật kiến trúc, `flutter analyze`, test từng package, lệch catalog — cộng một audit chỉ cảnh báo. Xem [§6](#6-quality-gate).

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
2. **Set Up Java** — bản Oracle, **Java 17**. Khớp với `sourceCompatibility`/`targetCompatibility` trong `app/android/app/build.gradle.kts`.
3. **Set Up Flutter** — `subosito/flutter-action@v2`, ghim **`3.47.2`**, kênh `stable`, bật cache.
4. **Install Dependencies** — `dart tools/workspace_setup/configure.dart`. Script Dart này làm trọn gói: pub get, sinh l10n, và `build_runner` cho cả workspace.
5. **Decode Env** — `echo -n ${{ secrets.ENV }} | base64 -d > .env` (ghi ra **thư mục gốc repo**).
6. **Decode Keystore** — `secrets.KEYSTORE_BASE64` → `app/android/keystore.jks`.
7. **Create key.properties** — ghi `storePassword`, `keyPassword`, `keyAlias` và `storeFile=../keystore.jks` cố định vào `app/android/key.properties`.
8. **Build APK** — chú ý dòng `cd app` đứng riêng phía trước:
   ```bash
   cd app
   flutter build apk --flavor=$FLAVOR --build-name=$VERSION --build-number=$RUN_NUMBER \
     --dart-define-from-file=../.env --obfuscate --split-debug-info=../obfuscate/ \
     --no-tree-shake-icons --verbose
   ```
9. **Upload and Distribute** — `nickwph/firebase-app-distribution-action@v1`, tải lên `app/build/app/outputs/flutter-apk/app-<flavor>-release.apk`.

> [!NOTE]
> **`cd app` không phải tuỳ chọn.** Chạy `flutter build apk` từ thư mục gốc sẽ lỗi khó hiểu `android/app/build.gradle not found`, vì project Flutter nằm trong `app/` chứ không ở gốc workspace. Build ở local cũng vậy — xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

Tên artifact có nội suy flavor (`app-${{ inputs.flavor }}-release.apk`) nên đúng cho cả ba flavor. Đó là cách làm đúng; Azure **không** làm vậy — xem [§5](#5-azure-ci-cdyml--azure-devops).

### Lưu ý chi phí

Job chạy trên `macos-latest` dù chỉ build Android. Runner macOS bị tính phí theo hệ số cao hơn hẳn Linux trên các gói GitHub-hosted. Trừ khi bạn định bật lại phần build iOS (hiện đang comment) trong cùng job này, `ubuntu-latest` build Android tốt tương đương và rẻ hơn nhiều.

---

## 3. `code_review.yml` — AI Code Review

Chạy chính công cụ review dùng Gemini của repo (`tools/code_review/code_review.dart`) rồi trả kết quả về pull request.

**Kích hoạt**: pull request vào `main` / `develop` / `master` có đụng `app/lib/**/*.dart` hoặc `packages/**/*.dart` (trừ file generated), cộng thêm chạy tay với bộ chọn phạm vi (`changed` / `all` / `domain` / `data` / `presentation`) và ngôn ngữ báo cáo (`en` / `vi` / `ja` / `ko` / `zh`).

**Nó làm gì**: lấy danh sách file thay đổi bằng `tj-actions/changed-files`, chạy reviewer, upload báo cáo Markdown làm artifact (giữ 30 ngày), rồi phân tích báo cáo đó và đăng **comment inline đúng dòng** khi dòng đó nằm trong diff của PR. Phát hiện nằm ngoài diff được gom thành comment riêng theo từng file.

### Ghim phiên bản Flutter

Bước cài dependency chạy `dart tools/workspace_setup/configure.dart`, và `flutter_version` mặc định `3.47.2`, khớp ràng buộc trong `pubspec.yaml` gốc.

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

Chạy tay, giao toàn bộ việc build cho Fastlane. Cài Java 17, Ruby 3.3 (bỏ qua nếu `self-hosted`), Flutter (kênh `stable`, **không ghim phiên bản**), cài Fastlane và plugin `firebase_app_distribution`, rồi gọi một lane.

Nó gọi lane cross-platform `fastlane flutter` (khai trong `app/fastlane/modules/flutter_lanes.rb` dạng `lane :flutter do |options|`), và `flutter_version` mặc định `3.47.2`.

> [!WARNING]
> Lệnh gọi vẫn truyền `auto_increment:` (`fastlane.yml:99`), và **không lane nào đọc nó** — `grep -rn auto_increment app/fastlane/` không trả về gì. Auto-increment được kích hoạt bằng cách truyền `build_number:auto`; xem [`02_fastlane_release.md`](02_fastlane_release.md). Tham số này bị bỏ qua âm thầm, nên một lần dispatch trông cậy vào nó sẽ nhận đúng `build_number` đã truyền chứ không phải số đã tăng.

Vì bước setup Flutter chỉ truyền `channel: stable` mà không truyền `flutter-version`, tham số `flutter_version` không tới được toolchain; nó được chuyển tiếp cho Fastlane để quyết định có dùng `fvm` hay không.

---

## 5. `azure-ci-cd.yml` — Azure DevOps

Hai stage trên pool self-hosted tên `codebase`. `trigger: none` nên chỉ chạy khi kích hoạt tay hoặc từ release.

**Stage `Build`**: lấy SHA commit ngắn vào `commitTag` → cài Flutter phiên bản `$(flutter-version)` → `flutter clean` → `flutter pub get` → "Flutter Config" → tải `key.properties` và `keystore.jks` dạng *secure file* của Azure vào `app/android/` → build APK prod → publish thành artifact `android`.

**Stage `Distribute`**: tải artifact về rồi `firebase appdistribution:distribute`.

Các biến pipeline phải khai trong tab Variables của Azure: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, và `FIREBASE-ANDROID-ID`.

### Một lỗi

Tên file artefact và lệnh gọi `configure.dart` thì nhất quán: build publish `app-prod-release.apk`, stage Distribute tải về và upload đúng tên đó, còn "Flutter Config" chạy `dart tools/workspace_setup/configure.dart`. Chỉ thiếu đúng một thứ.

> [!WARNING]
> **`.env` không bao giờ được tạo, nhưng build lại cần nó.**
>
> Build truyền `--dart-define-from-file=../.env` (`azure-ci-cd.yml:104`), nhưng không bước nào trong pipeline sinh ra `.env`. Hai task `DownloadSecureFile@1` chỉ lấy `key.properties` và `keystore.jks`. Hãy thêm một secure file thứ ba cho `.env` rồi copy vào `$(Build.SourcesDirectory)`, giống cách `flutter_build.yml` làm với `secrets.ENV`. Thiếu nó thì mọi `String.fromEnvironment` rơi về giá trị rỗng mặc định.

Các task build và distribute cho iOS có mặt nhưng đã bị comment toàn bộ.

---

## 6. Quality gate

`pr_quality_check.yml` chạy trên mọi pull request vào `main`, `develop` hoặc `master`. Đây là pipeline duy nhất có thể chặn merge.

| # | Gate | Lệnh | Chặn merge |
|:--|:---|:---|:---|
| 1 | Luật kiến trúc | `dart tools/arch_check/check.dart` | có |
| 2 | Phân tích tĩnh | `flutter analyze` | có |
| 3 | Test theo từng package | `flutter test` trong mỗi `packages/*/*/test` | có |
| 4 | Lệch catalog version | `dart tools/dependency_sync.dart --check` | có |
| — | Audit dependency thừa | `dart tools/unused_checker/check_unused_packages.dart` | không (chỉ cảnh báo) |

Gate 1 chạy đầu tiên là có chủ đích: nó chỉ đọc import và pubspec, không cần codegen, xong trong khoảng 200 ms — nên lỗi phân tầng fail sau vài giây thay vì sau cả chu kỳ analyze và test. Nó cũng là gate **duy nhất** nhìn thấy được phân tầng; không có gì trong `analysis_options.yaml` biết rằng core không được import feature.

Gate 3 phải lặp theo từng package vì đây là Pub Workspace: test nằm ở `packages/<layer>/<pkg>/test/`, chạy một lệnh `flutter test` ở gốc sẽ không thấy chúng.

> [!IMPORTANT]
> `flutter analyze` sạch **không** chứng minh app build được. `analysis_options.yaml` loại trừ `**.freezed.dart`, `**.g.dart`, `**.config.dart` và `**.module.dart`, nên analyzer không bao giờ nhìn vào code sinh ra. Chuyển một type sang package khác là đủ để một file `.freezed.dart` tham chiếu tới symbol nó không thấy được: analyze vẫn xanh trong khi build APK fail. Chỉ build thật mới bắt được loại lỗi đó.

**Vẫn còn thiếu:** các pipeline phát hành (`flutter_build.yml`, `fastlane.yml`, `azure-ci-cd.yml`) đều là `workflow_dispatch` và **không** chạy gate nào của riêng chúng. Một lần dispatch thủ công từ nhánh chưa từng mở PR vẫn sẽ build, ký và phân phối code chưa được kiểm. Nếu điều đó quan trọng với bạn, hãy thêm gate 1–4 vào `flutter_build.yml` giữa "Install Dependencies" và "Build APK", hoặc quy định chỉ phát hành từ nhánh đã merge.

---

## 7. Secrets

### GitHub Actions

| Secret | Dùng bởi | Cách tạo giá trị |
|:---|:---|:---|
| `ENV` | `flutter_build.yml` | Base64 của file env dart-define: `base64 -w0 app/env.prod` (macOS: `base64 -i app/env.prod`) |
| `KEYSTORE_BASE64` | `flutter_build.yml` | Base64 của keystore release: `base64 -w0 upload-keystore.jks` |
| `KEYSTORE_PASSWORD` | `flutter_build.yml` | Mật khẩu keystore |
| `KEY_PASSWORD` | `flutter_build.yml` | Mật khẩu key |
| `KEY_ALIAS` | `flutter_build.yml` | Alias của key |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | `flutter_build.yml` | Nội dung file JSON service-account của Firebase |
| `FIREBASE_ANDROID_APP_ID` | `flutter_build.yml` | Firebase App ID, ví dụ `1:1234567890:android:abcdef` |
| `GEMINI_API_KEY` | `code_review.yml` | Tạo tại <https://aistudio.google.com/app/apikey> |
| `GITHUB_TOKEN` | `code_review.yml` | GitHub tự cấp — không cần tự tạo |

Thêm tại **Settings → Secrets and variables → Actions → New repository secret**.

> [!CAUTION]
> `base64` không có `-w0` sẽ chèn xuống dòng trên Linux, làm `base64 -d` trong workflow hỏng. Trên macOS, `base64 -i <file>` vốn đã cho một dòng duy nhất. Luôn tự kiểm tra bằng `base64 -d` ở local trước khi dán vào.

### Azure DevOps

Azure dùng thư viện **Secure files** thay vì secret cho file nhị phân: upload `key.properties`, `keystore.jks` và (sau khi bạn thêm bước còn thiếu) `.env` tại **Pipelines → Library → Secure files**. `FIREBASE-ANDROID-ID` là biến pipeline.

---

## 8. Tái hiện CI ở local

Chạy những lệnh này trước khi push; chúng đúng là những lệnh pipeline dùng.

```bash
# 1. Thiết lập toàn workspace — tương đương bước "Install Dependencies" của CI
dart tools/workspace_setup/configure.dart

# 2. Đúng các gate mà pr_quality_check.yml chạy, theo đúng thứ tự
dart tools/arch_check/check.dart
flutter analyze
dart tools/dependency_sync.dart --check

# 3. Test theo từng package (gate 3 — xem §6)
(cd packages/core/storage && flutter test)
(cd packages/core/database && flutter test)
# ...lặp cho mọi package có thư mục test/

# 4. Đúng lệnh build release mà CI chạy — chú ý cd
cd app
flutter build apk --flavor=dev --build-name=1.0.0 --build-number=1 \
  --dart-define-from-file=env.dev --obfuscate --split-debug-info=../obfuscate/ \
  --no-tree-shake-icons
```

> [!NOTE]
> Ở local đường dẫn dart-define là `env.dev` (tương đối so với `app/`), còn CI ghi file env ra thư mục gốc nên truyền `../.env`. Cùng cơ chế, khác vị trí.

Build lần đầu trên máy sạch còn cần đã chạy `flutterfire configure` — các file `firebase_options_*.dart` sinh ra bị gitignore, mà `packages/core/common/lib/src/firebase/firebase_module.dart` import cả ba file đó vô điều kiện. Xem [`../getting-started/01_setup.md`](../getting-started/01_setup.md).

---

## 9. Danh sách việc cần sửa

Các mục còn mở, theo thứ tự ưu tiên tương đối:

- [ ] `azure-ci-cd.yml` — thêm secure file + bước copy cho `.env`; build prod hiện không nhận được dart-define nào
- [ ] `fastlane.yml` — bỏ tham số `auto_increment:` đang bị bỏ qua, hoặc cho một lane đọc nó
- [ ] `flutter_build.yml` — chạy bốn gate của `pr_quality_check.yml` trước khi build, để một lần dispatch thủ công không thể ship code chưa kiểm
- [ ] `code_review.yml` — quyết định có bỏ comment `exit 1` hay không (chỉ sau khi tin tưởng tỷ lệ báo nhầm của nó)
- [ ] `flutter_build.yml` — cân nhắc `ubuntu-latest` thay cho `macos-latest` với build chỉ cho Android

---

## Xem thêm

- [`02_fastlane_release.md`](02_fastlane_release.md) — lane, ký ứng dụng và quy trình phát hành
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — chạy lần đầu, khởi tạo Firebase, flavor
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — toàn bộ script trong `tools/`
