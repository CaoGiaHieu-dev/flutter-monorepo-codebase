# CI/CD

Tài liệu này trả lời: **có những pipeline nào, mỗi cái làm gì, cần secret gì, và hiện đang hỏng chỗ nào.** Đọc xong bạn cấu hình được secret cho repo, chạy được build, và tái hiện được mọi bước CI ở máy local trước khi push.

> [!IMPORTANT]
> Một số pipeline trong repo này **đang hỏng thật sự**. Tài liệu mô tả đúng hiện trạng kèm cách sửa từng chỗ. Đừng cho rằng chúng đang chạy xanh khi bạn chưa tự chạy thử.

---

## 1. Danh sách pipeline

Template có **bốn** pipeline — ba trên GitHub Actions, một trên Azure DevOps.

| Pipeline | File | Kích hoạt | Đầu ra |
|:---|:---|:---|:---|
| Build and Distribute | `.github/workflows/flutter_build.yml` | Thủ công (`workflow_dispatch`) | APK release đã ký → Firebase App Distribution |
| AI Code Review | `.github/workflows/code_review.yml` | PR vào `main`/`develop`/`master` + thủ công | Báo cáo Markdown + comment trên PR |
| Fastlane build and distribute | `.github/workflows/fastlane.yml` | Thủ công (`workflow_dispatch`) | Uỷ quyền cho các lane Fastlane |
| Azure Build + Distribute | `azure-ci-cd.yml` | `trigger: none` (chỉ chạy tay) | APK prod → Firebase |

> [!WARNING]
> `.github/workflows/README.md` mô tả một workflow thứ tư tên `pr_quality_check.yml` chạy analyze, test và coverage như một "quality gate". **File đó không tồn tại.** Thư mục chỉ có `code_review.yml`, `fastlane.yml` và `flutter_build.yml`. Hiện **không có cổng kiểm tra chất lượng tự động nào** trên pull request — xem [§6](#6-thiếu-quality-gate).

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
3. **Set Up Flutter** — `subosito/flutter-action@v2`, ghim **`3.47.1`**, kênh `stable`, bật cache.
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

### Hai lỗi khiến workflow này không chạy được

> [!CAUTION]
> **Workflow này fail ở bước "Get dependencies" mọi lần chạy.**
>
> ```yaml
> - name: 📦 Get dependencies
>   run: |
>       chmod +x tools/workspace_setup/configure.sh
>       ./tools/workspace_setup/configure.sh
> ```
>
> `tools/workspace_setup/configure.sh` **không tồn tại** — thư mục chỉ có `configure.dart`. Thay cả hai dòng bằng:
>
> ```yaml
> - name: 📦 Get dependencies
>   run: dart tools/workspace_setup/configure.dart
> ```
>
> (`flutter_build.yml` đã được sửa theo cách này rồi; workflow này bị bỏ sót.)

> [!WARNING]
> **Phiên bản Flutter mặc định thấp hơn yêu cầu.** `flutter_version` mặc định `"3.47.0"`, trong khi `pubspec.yaml` gốc yêu cầu `flutter: ">=3.47.1"`. Chạy tay mà giữ mặc định sẽ fail ở `pub get`. Đổi mặc định thành `3.47.1`.
>
> Thêm nữa, tham số này chỉ có khi sự kiện là `workflow_dispatch`. Với sự kiện `pull_request`, `github.event.inputs.flutter_version` rỗng, nên `subosito/flutter-action@v2` nhận `flutter-version` rỗng và tự lấy bản stable mới nhất.

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

> [!CAUTION]
> **Workflow này gọi một lane không tồn tại.**
>
> ```yaml
> run: |
>   fastlane flutter_build \
>     flutter_version:... version:... flavor:... \
>     auto_increment:... build_number:...
> ```
>
> Không có lane nào tên `flutter_build`. Lane cross-platform thật tên là **`flutter`** (khai trong `app/fastlane/modules/flutter_lanes.rb` là `lane :flutter do |options|`). Fastlane sẽ dừng với lỗi *"Could not find lane 'flutter_build'"*.
>
> Nó còn truyền `auto_increment:` mà **không lane nào đọc**. Tự tăng build number được kích hoạt bằng cách truyền `build_number:auto` — xem [`02_fastlane_release.md`](02_fastlane_release.md#build-number).
>
> Lệnh đúng:
> ```yaml
> run: |
>   fastlane flutter \
>     flutter_version:${{ inputs.flutter_version }} \
>     version:${{ inputs.version }} \
>     flavor:${{ inputs.flavor }} \
>     change_log:"${{ inputs.change_log }}" \
>     build_type:${{ inputs.build_type }} \
>     distribute_store:${{ inputs.distribute_store }} \
>     distribute_firebase:${{ inputs.distribute_firebase }} \
>     build_number:${{ inputs.build_number || 'auto' }}
> ```

Tham số `flutter_version` cũng mặc định `"3.47.0"` — cùng vấn đề với `code_review.yml`. Và vì bước setup Flutter chỉ truyền `channel: stable` mà không truyền `flutter-version`, tham số này thực ra không tới được toolchain; nó được chuyển tiếp cho Fastlane để quyết định có dùng `fvm` hay không.

---

## 5. `azure-ci-cd.yml` — Azure DevOps

Hai stage trên pool self-hosted tên `codebase`. `trigger: none` nên chỉ chạy khi kích hoạt tay hoặc từ release.

**Stage `Build`**: lấy SHA commit ngắn vào `commitTag` → cài Flutter phiên bản `$(flutter-version)` → `flutter clean` → `flutter pub get` → "Flutter Config" → tải `key.properties` và `keystore.jks` dạng *secure file* của Azure vào `app/android/` → build APK prod → publish thành artifact `android`.

**Stage `Distribute`**: tải artifact về rồi `firebase appdistribution:distribute`.

Các biến pipeline phải khai trong tab Variables của Azure: `flutter-version`, `flutterPath`, `version`, `numberBuild`, `note`, và `FIREBASE-ANDROID-ID`.

### Ba lỗi

> [!CAUTION]
> **1 — Bước distribute upload một tên file không bao giờ được tạo ra.**
>
> Bước build publish `app-prod-release.apk` (đúng, vì build truyền `--flavor=prod`), nhưng stage Distribute lại chạy:
>
> ```bash
> firebase appdistribution:distribute app-release.apk --app $(FIREBASE-ANDROID-ID) ...
> ```
>
> `app-release.apk` không tồn tại trong artifact vừa tải. Sửa thành `app-prod-release.apk`.

> [!CAUTION]
> **2 — "Flutter Config" gọi đúng cái script không tồn tại đó, và còn viết sai cú pháp.**
>
> ```yaml
> script: >-
>   chmod +x tools/workspace_setup/configure.sh
>   ./tools/workspace_setup/configure.sh
> ```
>
> Hai vấn đề. `configure.sh` không tồn tại. Và `>-` là *folded scalar* của YAML — nó nối hai dòng bằng dấu cách thành một lệnh duy nhất `chmod +x tools/workspace_setup/configure.sh ./tools/workspace_setup/configure.sh`, nên kể cả nếu file có tồn tại thì nó cũng chỉ được chmod chứ không bao giờ được chạy. Thay toàn bộ phần `script:` bằng `dart tools/workspace_setup/configure.dart`.

> [!WARNING]
> **3 — `.env` không bao giờ được tạo, nhưng build lại cần nó.**
>
> Bước build truyền `--dart-define-from-file=../.env`, nhưng không bước nào trong pipeline sinh ra `.env`. Hai task `DownloadSecureFile@1` chỉ lấy `key.properties` và `keystore.jks`. Cần thêm một secure file thứ ba cho `.env` (và copy nó về `$(Build.SourcesDirectory)`), tương tự cách `flutter_build.yml` xử lý `secrets.ENV`.

Phần build iOS và distribute iOS có sẵn nhưng bị comment toàn bộ.

---

## 6. Thiếu quality gate

> [!WARNING]
> **Không pipeline nào chạy `flutter analyze` hay `flutter test` trước khi build và phát hành.**
>
> `flutter_build.yml` đi thẳng từ cài dependency sang `flutter build apk` rồi gửi artifact cho tester. Một thay đổi làm hỏng analyze hoặc vỡ toàn bộ test vẫn sẽ được build, ký và phân phối. File `pr_quality_check.yml` mà `.github/workflows/README.md` quảng cáo là lo việc này thì không tồn tại.

Thêm hai bước sau vào `flutter_build.yml`, nằm giữa bước 4 (Install Dependencies) và bước 7 (Build APK):

```yaml
      - name: Analyze
        run: flutter analyze

      - name: Test
        run: |
          set -e
          for pkg in packages/core/* packages/data/* packages/domain/* packages/features/*; do
            if [ -d "$pkg/test" ]; then
              echo "::group::flutter test $pkg"
              (cd "$pkg" && flutter test)
              echo "::endgroup::"
            fi
          done
```

Phải dùng vòng lặp vì đây là Pub Workspace: test nằm riêng theo từng package tại `packages/<layer>/<pkg>/test/`, chạy `flutter test` một lần ở gốc sẽ không quét tới.

Nên thêm luôn bước kiểm tra lệch version catalog — rẻ mà chặn được cả một nhóm lỗi merge:

```yaml
      - name: Check dependency catalog
        run: dart tools/dependency_sync.dart --check
```

`--check` trả mã lỗi khác 0 khi version ở package nào đó lệch khỏi `pubspec_dependencies.yaml`.

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

# 2. Quality gate mà CI đang thiếu
flutter analyze
dart tools/dependency_sync.dart --check

# 3. Test theo từng package (đúng vòng lặp đề xuất ở §6)
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

Tổng hợp mọi thứ ở trên thành checklist:

- [ ] `code_review.yml` — thay `configure.sh` bằng `dart tools/workspace_setup/configure.dart`
- [ ] `code_review.yml` — nâng mặc định `flutter_version` lên `3.47.1`
- [ ] `code_review.yml` — quyết định có bỏ comment `exit 1` hay không
- [ ] `fastlane.yml` — đổi lane `flutter_build` → `flutter`, bỏ `auto_increment:`
- [ ] `fastlane.yml` — nâng mặc định `flutter_version` lên `3.47.1`
- [ ] `azure-ci-cd.yml` — distribute `app-prod-release.apk`, không phải `app-release.apk`
- [ ] `azure-ci-cd.yml` — thay script `configure.sh` bị folded bằng `dart tools/workspace_setup/configure.dart`
- [ ] `azure-ci-cd.yml` — thêm secure file + bước copy cho `.env`
- [ ] `flutter_build.yml` — thêm bước analyze + test trước khi build
- [ ] `flutter_build.yml` — cân nhắc `ubuntu-latest` thay cho `macos-latest`
- [ ] `.github/workflows/README.md` — xoá phần `pr_quality_check.yml`, hoặc bổ sung workflow đó

---

## Xem thêm

- [`02_fastlane_release.md`](02_fastlane_release.md) — lane, ký ứng dụng và quy trình phát hành
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — chạy lần đầu, khởi tạo Firebase, flavor
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — toàn bộ script trong `tools/`
