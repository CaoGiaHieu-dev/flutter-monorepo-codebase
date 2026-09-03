# Fastlane & Phát hành

Tài liệu này trả lời: **Fastlane trong repo được lắp ráp thế nào, có những lane nào và nhận tham số gì, app được ký ra sao, và quy trình phát hành đầy đủ gồm những bước nào.** Đọc xong bạn cấu hình được `Config.yaml`, chạy được mọi lane từ thư mục gốc, và đưa được bản build lên Firebase App Distribution, Google Play hoặc TestFlight.

> [!IMPORTANT]
> Có hai cái bẫy trong thiết lập này, được mô tả bên dưới — cơ chế **âm thầm lùi về keystore dev đã commit sẵn** ([§4](#4-ký-ứng-dụng)) và **file `app/env.prod` bắt buộc phải có**, thiếu nó thì build prod fail cứng ([§6](#6-flavor-và-file-env)). Đọc cả hai trước lần upload store đầu tiên.

---

## 1. Vì sao chạy được từ bất kỳ đâu

Fastlane vốn bắt bạn phải đứng đúng thư mục chứa `Fastfile`. Repo này gỡ ràng buộc đó bằng cơ chế proxy hai file.

```
fastlane/Fastfile              ← proxy ở gốc
app/fastlane/Fastfile          ← entry point thật
app/fastlane/modules/
    helpers.rb                 ← nạp config + toàn bộ logic dùng chung
    android_lanes.rb           ← platform :android
    ios_lanes.rb               ← platform :ios
    flutter_lanes.rb           ← lane cross-platform
app/fastlane/Config.yaml       ← config CỦA BẠN (gitignore, tự tạo)
app/fastlane/Config.example.yaml
```

`fastlane/Fastfile` ở gốc làm đúng hai việc:

```ruby
# Change directory to app/fastlane to align working directories with the app configuration
Dir.chdir("../app/fastlane")

import "../app/fastlane/modules/helpers.rb"
import "../app/fastlane/modules/ios_lanes.rb"
import "../app/fastlane/modules/android_lanes.rb"
import "../app/fastlane/modules/flutter_lanes.rb"
```

Đường dẫn bên trong các module sau đó được giải **tuyệt đối theo vị trí của chính file**, không phụ thuộc CWD của người gọi (`app/fastlane/modules/helpers.rb`):

```ruby
CONFIG_FILE = File.expand_path("../Config.yaml", __dir__)
APP_DIR     = File.expand_path("../..", __dir__)
```

Chính điều đó khiến `fastlane android build …` chạy giống hệt nhau dù bạn đứng ở thư mục gốc hay trong `app/`.

---

## 2. Cấu hình

`Config.yaml` là **bắt buộc** — `helpers.rb` dừng ngay nếu thiếu:

```ruby
UI.user_error!("Configuration file not found at #{CONFIG_FILE}") unless File.exist?(CONFIG_FILE)
```

Tạo một lần:

```bash
cp app/fastlane/Config.example.yaml app/fastlane/Config.yaml
```

`app/fastlane/.gitignore` bỏ qua `*.yaml` kèm ngoại lệ `!Config.example.yaml`, nên `Config.yaml` bạn điền — và mọi file credential `*.json` bên cạnh — đều nằm ngoài git.

### Các trường cần điền

| Khoá | Ý nghĩa |
|:---|:---|
| `flutter.default_version` | Giá trị mặc định cho câu hỏi "Flutter version". `stable` dùng Flutter hệ thống; giá trị khác sẽ chạy qua `fvm` |
| `default_app_version` | Giá trị mặc định cho câu hỏi "app version" |
| `valid_flavors` | Danh sách flavor hợp lệ. `none` luôn được chấp nhận thêm ngoài danh sách này |
| `app_bundle_ids.ios` / `.android` | Bundle ID **gốc**, chưa có hậu tố flavor |
| `firebase.app_ids.<platform>.<flavor>` | Firebase App ID theo nền tảng và flavor, kèm khoá `default` cho build không flavor |
| `firebase.credentials_map.<flavor>` | Đường dẫn file JSON service-account của Firebase theo flavor |
| `app_store_connect.api_key_id` / `.issuer_id` | Định danh API key của App Store Connect |
| `app_store_connect.username` / `.team_id` | Apple ID và team, dùng dự phòng cho các action không nhận API key |
| `app_store_connect.apple_ids.<flavor>` | Apple ID dạng số theo flavor — **bắt buộc**, bước upload TestFlight sẽ lỗi *"Unknown flavor for apple-id mapping"* nếu thiếu flavor tương ứng |
| `google_play.account_id` | Chỉ dùng để dựng link tới console |
| `paths.firebase_testers_file` | File text chứa email tester cho Firebase App Distribution |
| `paths.google_play_key_prod` / `_dev` | File JSON service-account của Google Play |
| `paths.app_store_connect_key_filepath` | File API key `.p8` |
| `paths.change_log_android` / `_ios` | File tạm để Fastlane truyền changelog giữa các lane |

Cài plugin bắt buộc duy nhất:

```bash
fastlane add_plugin firebase_app_distribution
```

---

## 3. Danh sách lane

Mọi lane đều tương tác: tham số nào bạn không truyền thì nó sẽ hỏi. Truyền sẵn trên dòng lệnh sẽ bỏ qua câu hỏi — đó là điều khiến các lane này dùng được trong CI.

### Android — `app/fastlane/modules/android_lanes.rb`

| Lane | Làm gì | Tham số |
|:---|:---|:---|
| `android build` | Build APK hoặc AAB rồi phân phối | `flavor`, `build_type` (`apk`/`aab`), `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log`, `skip_setup`, `skip_build` |
| `android upload` | Upload artifact **đã build sẵn** lên Play. Ép `skip_build:true`, `skip_setup:true`, `flutter_version:stable`, `distribute_store:true`, `distribute_firebase:false` | `flavor`, `build_type`, `version`, `track` |
| `android store` | Phát hành prod lên Play. Ép `flavor:prod`, `build_type:aab`, `distribute_store:true`, `distribute_firebase:false` | `version`, `build_number`, `track` |

### iOS — `app/fastlane/modules/ios_lanes.rb`

| Lane | Làm gì | Tham số |
|:---|:---|:---|
| `ios build` | Build IPA rồi phân phối lên TestFlight và/hoặc Firebase | `flavor`, `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `change_log`, `skip_setup`, `skip_build` |
| `ios upload` | Upload IPA có sẵn lên TestFlight, không build lại | `flavor`, `version` |
| `ios store` | Phát hành prod lên TestFlight. Ép `flavor:prod`, `distribute_store:true` | `version`, `build_number` |

### Cross-platform — `app/fastlane/modules/flutter_lanes.rb`

| Lane | Làm gì | Tham số |
|:---|:---|:---|
| `flutter` | Hỏi một lần các tham số chung, thiết lập toolchain một lần, rồi gọi `fastlane ios build` trước, `fastlane android build` sau | `flavor`, `version`, `build_number`, `build_type`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log` |
| `store` | Cùng cách điều phối nhưng mặc định prod/store: `fastlane ios store` rồi `fastlane android store` | `version`, `build_number`, `track`, `flutter_version`, `change_log` |

Cả hai lane cross-platform đều **chạy iOS trước và huỷ toàn bộ nếu iOS fail**, nên Android không bao giờ được build cho một bản release mà iOS không dựng nổi. Chúng cũng ghi changelog ra hai file tạm ngay từ đầu để lane con đọc lại thay vì hỏi lại, và xoá các file đó trong khối `ensure`.

Giá trị hợp lệ do `helpers.rb` kiểm soát:

- `VALID_TRACKS` = `production`, `internal`, `closed`
- `VALID_BUILD_TYPES` = `apk`, `aab`
- `VALID_FLAVORS` = danh sách trong `Config.yaml`, cộng thêm `none`

### Ví dụ

```bash
# APK dev cho tester qua Firebase
fastlane android build flavor:dev build_type:apk distribute_firebase:true change_log:"Fix login bug"

# Chỉ build local — không phân phối, không setup toolchain (nhanh nhất)
fastlane android build flavor:dev build_type:apk distribute_firebase:false distribute_store:false skip_setup:true

# AAB prod lên track internal của Play
fastlane android store version:1.2.0 build_number:45 track:internal

# IPA prod lên TestFlight
fastlane ios store version:1.2.0 build_number:45

# Cả hai nền tảng, flavor dev, chỉ Firebase
fastlane flutter flavor:dev version:1.2.0 build_number:auto distribute_firebase:true distribute_store:false

# Cả hai nền tảng, prod, lên cả hai store
fastlane store version:1.2.0 build_number:auto track:internal
```

### Build number

`build_number` nhận một con số hoặc chuỗi `auto`. Với `auto`, `determine_build_number` lấy số cao nhất hiện tại rồi cộng một — từ **TestFlight** (iOS + store), **Google Play** theo track đã chọn (Android + store), hoặc **Firebase App Distribution** trong các trường hợp còn lại. Nếu bạn chọn `auto` mà không đặt đích phân phối nào, nó lùi về hỏi Firebase.

`versionCode` và `versionName` **không** lấy từ `app/pubspec.yaml` khi build qua Fastlane. `app/android/app/build.gradle.kts` gắn chúng vào Flutter:

```kotlin
versionCode = flutter.versionCode
versionName = flutter.versionName
```

nghĩa là `--build-number` / `--build-name` mà lane truyền vào sẽ quyết định. Dòng `version: 1.0.0+1` trong `app/pubspec.yaml` chỉ là giá trị dự phòng khi chạy `flutter build` trần không kèm cờ.

---

## 4. Ký ứng dụng

`app/android/app/build.gradle.kts` khai ba signing config, mỗi cái đọc một file properties khác nhau trong `app/android/`:

| Config | File properties | Flavor sử dụng |
|:---|:---|:---|
| `dev` | `key-dev.properties` | `dev` |
| `staging` | `key-stg.properties` | `staging` |
| `prod` | `key.properties` | `prod` |

### Cơ chế fallback im lặng — và nguy hiểm

Mỗi khối chỉ nạp file **nếu file tồn tại**, không thì copy nguyên bộ properties của dev:

```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile: File = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { fis -> keystoreProperties.load(fis) }
} else {
    keystoreProperties.putAll(keystoreDevProperties)   // ← lùi về keystore DEV
}
```

> [!CAUTION]
> **Nếu thiếu `key.properties`, bản build prod sẽ được ký bằng keystore dev đã commit sẵn, và build vẫn báo thành công.** Không có cảnh báo nào. Một bản release ký sai khoá thì sau này **không thể cập nhật** trên Play Store — chữ ký gắn vĩnh viễn với listing đó.
>
> Trước mọi lần build production, hãy kiểm tra file có tồn tại và trỏ đúng chỗ không:
> ```bash
> test -f app/android/key.properties && echo OK || echo "THIẾU — prod sẽ dùng key dev"
> ```

### Keystore dev đang nằm trong git

`app/android/key-dev.properties` và `app/android/keystore-dev.jks` **được track trong git** để clone về là build chạy ngay không cần cấu hình. Với một template thì đó là chủ đích, và dùng cho `dev` thì không sao.

> [!CAUTION]
> **Tuyệt đối không phát hành production bằng keystore dev.** Nó công khai trong repo — bất kỳ ai clone được cũng ký được một APK mà hệ điều hành coi là bản cập nhật của app bạn.

Tạo khoá release riêng:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Rồi tạo `app/android/key.properties` (đã được `.gitignore` che):

```properties
storePassword=<mật khẩu store của bạn>
keyPassword=<mật khẩu key của bạn>
keyAlias=upload
storeFile=/duong/dan/tuyet/doi/toi/upload-keystore.jks
```

Giữ file `.jks` **ngoài** repo, và sao lưu ở nơi bền vững — mất nó đồng nghĩa với việc không bao giờ publish được bản cập nhật cho listing Play đó nữa.

---

## 5. Bundle ID

`helpers.rb` sinh bundle ID bằng cách thêm hậu tố theo flavor, và các hậu tố khớp Gradle chính xác:

```ruby
def get_bundle_id_with_suffix(base_bundle_id, flavor)
  return base_bundle_id if flavor.nil? || flavor.empty?
  case flavor
  when 'dev' then "#{base_bundle_id}.dev"
  when 'staging' then "#{base_bundle_id}.stg"
  else base_bundle_id
  end
end
```

```kotlin
create("staging") {
    dimension = "environment"
    applicationIdSuffix = ".stg"
    signingConfig = signingConfigs.getByName("staging")
}
```

| Flavor | `applicationIdSuffix` của Gradle | Bundle ID Fastlane tính | Khớp |
|:---|:---|:---|:---|
| `dev` | `.dev` | `<base>.dev` | ✅ |
| `staging` | `.stg` | `<base>.stg` | ✅ |
| `prod` | *(không có)* | `<base>` | ✅ |

> [!NOTE]
> Hai danh sách này được duy trì độc lập và không có gì kiểm tra xem chúng có khớp nhau hay không. Nếu Fastlane tính ra `.staging` trong khi Gradle sinh `.stg`, một lần upload staging sẽ tra tới một Play listing không khớp artifact. Nếu thêm flavor mới, hãy sửa **cả hai** phía trong cùng một commit.

---

## 6. Flavor và file env

| Flavor | Hậu tố applicationId | File dart-define Fastlane mong đợi | Có sẵn |
|:---|:---|:---|:---|
| `dev` | `.dev` | `app/env.dev` | ✅ |
| `staging` | `.stg` | `app/env.stg` | ✅ |
| `prod` | *(không có)* | `app/env.prod` | ❌ **bạn phải tự tạo** |

`helpers.rb` ánh xạ flavor sang file:

```ruby
def get_dart_define_file(flavor)
  case flavor
  when 'dev' then "env.dev"
  when 'staging' then "env.stg"
  else "env.prod"
  end
end
```

và từ chối build khi file đó không tồn tại:

```ruby
unless File.exist?("../#{dart_define_file}")
  UI.user_error!(
    "Dart define file 'app/#{dart_define_file}' not found for flavor "     "'#{flavor}'. Building without it would ship empty "     "String.fromEnvironment values (API base URL, keys), so this is "     "a hard failure. Create the file first."
  )
end
build_command += " --dart-define-from-file=#{dart_define_file}"
```

> [!IMPORTANT]
> **Không build được bản prod cho tới khi bạn tạo `app/env.prod`.** Đó là có chủ đích. Phương án còn lại — bỏ qua cờ này kèm một cảnh báo — sẽ khiến build prod vẫn *thành công* trong khi mọi `String.fromEnvironment` trong `packages/core/common/lib/src/utils/env_constants.dart` rơi về giá trị rỗng, cho ra một APK trỏ tới API URL rỗng và key rỗng, đã ký và phát hành mà không cảnh báo gì. Fail to là đánh đổi an toàn hơn.
>
> Sao chép danh sách key từ `app/env.dev`; `.vscode/launch.json` vốn đã trỏ cấu hình Prod vào `env.prod`.

> [!WARNING]
> Mẫu `*.env` trong `.gitignore` **không** khớp `env.dev` / `env.stg` / `env.prod` — dấu chấm nằm sai phía — nên `env.dev` và `env.stg` hiện đang bị track trong git. Hãy thêm dòng ignore tường minh trước khi đặt credential thật vào `env.prod`.

---

## 7. Thiết lập toolchain bên trong lane

Trừ khi bạn truyền `skip_setup:true`, mọi lane đều gọi `setup_flutter_environment` — hàm này hoặc chuyển Flutter hệ thống sang stable rồi upgrade, hoặc kích hoạt `fvm` và ghim đúng phiên bản yêu cầu. Sau đó nó chạy `install_dependencies`:

```ruby
sh "#{prefix}dart pub global activate flutterfire_cli"
sh "#{prefix}dart pub global activate flutter_gen"
sh "#{prefix}flutter clean"
sh "#{prefix}flutter pub get"
# ...rồi flutter gen-l10n cho mọi packages/**/l10n.yaml
sh "#{prefix}dart run build_runner build -d --workspace"
```


Vì bước này chạy `flutter clean` và `build_runner` cho cả workspace nên rất chậm. Dùng `skip_setup:true` khi build đi build lại ở local.

---

## 8. Quy trình phát hành

1. **Chốt version.** Quyết định `version` (build name). Dùng `build_number:auto` trừ khi bạn cần một số cụ thể.
2. **Kiểm tra ký ứng dụng.** `test -f app/android/key.properties` — xem cảnh báo ở [§4](#4-ký-ứng-dụng).
3. **Kiểm tra file env của flavor tương ứng có tồn tại không** — xem [§6](#6-flavor-và-file-env). Với prod bạn phải tạo `app/env.prod` trước; thiếu nó lane fail cứng.
4. **Xác nhận `Config.yaml` đã điền đủ**, đặc biệt `firebase.app_ids`, `app_store_connect.apple_ids` và các đường dẫn credential.
5. **Chạy thử ở local**, không phân phối:
   ```bash
   fastlane android build flavor:prod build_type:aab \
     distribute_store:false distribute_firebase:false skip_setup:true
   ```
6. **Phát hành.**
   ```bash
   # Cho tester trước
   fastlane android build flavor:prod build_type:apk distribute_firebase:true \
     version:1.2.0 build_number:auto change_log:"…"

   # Rồi lên store
   fastlane store version:1.2.0 build_number:auto track:internal
   ```
7. **Promote** từ `internal` lên `production` trong Play Console sau khi kiểm thử xong. Lane upload với `release_status: 'draft'`, nên không có gì lên live nếu bạn không chủ động promote.

### Checklist trước khi phát hành

- [ ] `app/android/key.properties` tồn tại và trỏ tới keystore **release** của bạn
- [ ] Keystore release đã được sao lưu ngoài repo
- [ ] File env của flavor đích đã có (`app/env.prod` cho prod — xem [§6](#6-flavor-và-file-env))
- [ ] `Config.yaml` đầy đủ; các file JSON/`.p8` credential có mặt đúng đường dẫn đã cấu hình
- [ ] `flutter analyze` sạch và test các package pass — `pr_quality_check.yml` chặn ở PR, nhưng các pipeline phát hành thì không (xem [`01_cicd.md`](01_cicd.md#6-quality-gate))
- [ ] `sslPinningHashes` đã điền nếu bản build này chạy với traffic production — mặc định nó là `const []`, tức tắt hoàn toàn pinning
- [ ] Đã viết changelog
- [ ] Build number không trùng với bản release đã có

---

## 9. Hiện trạng iOS

Các lane iOS là thật và khá hoàn chỉnh, không phải stub:

- `run_flutter_build` xoá `Podfile.lock` và chạy `pod deintegrate && pod install --repo-update` trước mỗi lần build iOS, ép giải lại dependency từ đầu.
- Nó chọn `ios/flavors/<flavor>/ExportOptions.plist` khi có flavor, `ios/ExportOptions.plist` khi không, và chỉ cảnh báo chứ không fail nếu thiếu cả hai.
- Nếu `flutter build ipa` archive thành công nhưng export lỗi, nó thử lại `xcrun xcodebuild -exportArchive` tối đa ba lần.
- `distribute_to_app_store` bỏ qua `upload_to_testflight` của Fastlane và gọi thẳng `xcrun altool --upload-app`, kèm comment giải thích wrapper altool của Fastlane không tương thích với Xcode 26.

Những phần **chưa** được nối:

- Bước build và distribute iOS trong `azure-ci-cd.yml` bị comment toàn bộ.
- Bước build iOS trong `.github/workflows/flutter_build.yml` bị comment; chỉ Android được build và phân phối.
- Build iOS cần macOS, nên tuỳ chọn `self-hosted` trong `fastlane.yml` bắt buộc phải là máy Mac.

---

## Xem thêm

- [`01_cicd.md`](01_cicd.md) — pipeline, secret, và các lỗi liệt kê ở đó
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — flavor, file env, khởi tạo Firebase
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — các script trong `tools/` mà Fastlane gọi
