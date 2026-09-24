# Fastlane & Phát hành

Tài liệu này trả lời: **Fastlane trong repo được lắp ráp thế nào, có những lane nào và nhận tham số gì, app được ký ra sao, và quy trình phát hành đầy đủ gồm những bước nào.** Đọc xong bạn cấu hình được `Config.yaml`, chạy được mọi lane từ thư mục gốc, và đưa được bản build lên Firebase App Distribution, Google Play hoặc TestFlight.

> [!IMPORTANT]
> Có hai file bạn phải tự cung cấp, được mô tả bên dưới — **keystore release** (`key.properties`, thêm `key-stg.properties` cho staging), thiếu nó thì build release staging/prod từ chối chạy ([§4](#4-ký-ứng-dụng)), và **`apps/mobile/env.prod`**, thiếu nó thì build prod fail cứng ([§6](#6-flavor-và-file-env)). Đọc cả hai trước lần upload store đầu tiên.

---

## 1. Vì sao chạy được từ bất kỳ đâu

Fastlane vốn bắt bạn phải đứng đúng thư mục chứa `Fastfile`. Repo này gỡ ràng buộc đó bằng cơ chế proxy hai file.

```
Gemfile                        ← ở gốc: fastlane + cocoapods, nạp fastlane/Pluginfile
fastlane/Fastfile              ← proxy ở gốc
fastlane/Pluginfile            ← chuyển tiếp sang apps/mobile/fastlane/Pluginfile
apps/mobile/Gemfile            ← cùng bộ gem, dùng khi chạy từ apps/mobile/
apps/mobile/fastlane/Fastfile          ← entry point thật
apps/mobile/fastlane/Pluginfile        ← danh sách plugin DUY NHẤT
apps/mobile/fastlane/modules/
    helpers.rb                 ← nạp config + toàn bộ logic dùng chung
    android_lanes.rb           ← platform :android
    ios_lanes.rb               ← platform :ios
    flutter_lanes.rb           ← lane cross-platform
apps/mobile/fastlane/Config.yaml       ← config CỦA BẠN (gitignore, tự tạo)
apps/mobile/fastlane/Config.example.yaml
```

`fastlane/Fastfile` ở gốc chỉ import các module thật:

```ruby
ENV['FASTLANE_SKIP_DOCS'] = '1'

import "../apps/mobile/fastlane/modules/helpers.rb"
import "../apps/mobile/fastlane/modules/ios_lanes.rb"
import "../apps/mobile/fastlane/modules/android_lanes.rb"
import "../apps/mobile/fastlane/modules/flutter_lanes.rb"
```

Nó cố ý **không** gọi `Dir.chdir`. Fastlane parse Fastfile bên trong khối `chdir` của chính nó rồi khôi phục thư mục ngay sau đó, nên một lệnh `chdir` đặt ở đây bị huỷ trước khi bất kỳ lane nào chạy — lane chạy trong `<root>/fastlane`, còn action (`sh`, upload) chạy trong `<root>` — và Ruby chỉ in cảnh báo `conflicting chdir during another chdir block`. Thay vào đó, mọi đường dẫn bên trong các module được giải **tuyệt đối theo vị trí của chính file**, không phụ thuộc CWD của người gọi (`apps/mobile/fastlane/modules/helpers.rb`):

```ruby
FASTLANE_DIR = File.expand_path("..", __dir__)   # apps/mobile/fastlane
APP_DIR = File.expand_path("..", FASTLANE_DIR)   # apps/mobile
CONFIG_FILE = File.join(FASTLANE_DIR, "Config.yaml")
```

File dart-define, `ExportOptions.plist`, các artifact build, thư mục `ios/` cho CocoaPods và mọi đường dẫn credential trong `Config.yaml` đều được dựng từ `APP_DIR`, và `flutter build` chạy bên trong `APP_DIR`. Chính điều đó khiến `bundle exec fastlane android build …` chạy giống hệt nhau dù bạn đứng ở thư mục gốc hay trong `apps/mobile/`.

`ENV['FASTLANE_SKIP_DOCS'] = '1'` được đặt trong cả hai Fastfile: thiếu nó, sau mỗi lần chạy fastlane sẽ ghi đè `README.md` trong thư mục fastlane — tức file `apps/mobile/fastlane/README.md` viết tay đang được track, hoặc sinh ra một file lạc ở gốc. `fastlane/.gitignore` (ở gốc) và `apps/mobile/fastlane/.gitignore` bỏ qua những gì một lần chạy ghi ra (`report.xml`, …) cùng mọi file credential.

---

## 2. Cấu hình

`Config.yaml` là **bắt buộc** — `helpers.rb` dừng ngay nếu thiếu:

```ruby
UI.user_error!("Configuration file not found at #{CONFIG_FILE}. Copy Config.example.yaml next to it and fill it in.") unless File.exist?(CONFIG_FILE)
```

Tạo một lần:

```bash
cp apps/mobile/fastlane/Config.example.yaml apps/mobile/fastlane/Config.yaml
```

`apps/mobile/fastlane/.gitignore` bỏ qua `*.yaml` kèm ngoại lệ `!Config.example.yaml`, nên `Config.yaml` bạn điền — và mọi file credential `*.json` / `*.p8` bên cạnh — đều nằm ngoài git. Trên CI, `fastlane.yml` ghi file này ra từ secret `FASTLANE_CONFIG_YAML_B64` ([`01_cicd.md` §7](01_cicd.md#7-secrets)).

**Đường dẫn tương đối trong `Config.yaml` được giải theo `apps/mobile/`** — bất kể bạn chạy fastlane từ thư mục nào — nên `fastlane/firebase-auth.json` trong file mẫu nằm trong `apps/mobile/fastlane/`, cạnh `Config.yaml`. Đường dẫn tuyệt đối được giữ nguyên.

### Các trường cần điền

| Khoá | Ý nghĩa |
|:---|:---|
| `flutter.default_version` | Giá trị mặc định cho câu hỏi "Flutter version". `stable` = dùng Flutter mà máy này phân giải được (bản `.fvmrc` ghim nếu có cài fvm, không thì bản trên PATH); một phiên bản cụ thể thì phải khớp với Flutter đó — xem [§7](#7-thiết-lập-toolchain-bên-trong-lane) |
| `default_app_version` | Giá trị mặc định cho câu hỏi "app version" |
| `valid_flavors` | Danh sách flavor hợp lệ. `none` luôn được chấp nhận thêm ngoài danh sách này |
| `app_bundle_ids.ios` / `.android` | Bundle ID **gốc**, chưa có hậu tố flavor |
| `firebase.app_ids.<platform>.<flavor>` | Firebase App ID theo nền tảng và flavor, kèm khoá `default` cho build không flavor. Flavor không có mục riêng sẽ lùi về `default` kèm cảnh báo — tức là upload vào app mặc định, nên hãy cho mọi flavor bạn phân phối một mục riêng |
| `firebase.credentials_map.<flavor>` | Đường dẫn file JSON service-account của Firebase theo flavor; flavor không có mục riêng sẽ lùi về `default` (đúng cách lùi mà `fastlane.yml` dùng khi ghi file này) |
| `app_store_connect.api_key_id` / `.issuer_id` | Định danh API key của App Store Connect |
| `app_store_connect.username` / `.team_id` | Apple ID và team, dùng dự phòng cho các action không nhận API key |
| `app_store_connect.apple_ids.<flavor>` | Apple ID dạng số theo flavor — **bắt buộc**, bước upload TestFlight sẽ lỗi *"Unknown flavor for apple-id mapping"* nếu thiếu flavor tương ứng |
| `google_play.account_id` | Chỉ dùng để dựng link tới console |
| `paths.firebase_testers_file` | File text chứa email tester cho Firebase App Distribution |
| `paths.google_play_key_prod` / `_dev` | File JSON service-account của Google Play |
| `paths.app_store_connect_key_filepath` | File API key `.p8`. Tên file **bắt buộc là `AuthKey_<app_store_connect.api_key_id>.p8`** — đúng tên App Store Connect đặt cho file tải về. Bước upload TestFlight chạy `xcrun altool --apiKey <id>`, lệnh này không nhận đường dẫn key: nó chỉ tìm file có đúng tên đó, trong `$API_PRIVATE_KEYS_DIR` (lane đặt biến này thành thư mục chứa file) hoặc trong `./private_keys`, `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys`. Ở local, file đặt tên khác vẫn upload được, qua một bản sao tạm đã đổi tên kèm cảnh báo; `fastlane.yml` thì từ chối |

Hai khoá cũ `paths.change_log_android` / `_ios` đã bị bỏ (xem [§3](#3-danh-sách-lane)); nếu `Config.yaml` của bạn còn giữ chúng thì chúng bị bỏ qua.

### Gem và plugin

Plugin duy nhất, `fastlane-plugin-firebase_app_distribution`, đã có sẵn trong `apps/mobile/fastlane/Pluginfile`. Cài mọi thứ một lần và luôn chạy qua Bundler:

```bash
bundle install                         # từ thư mục gốc repo (hoặc từ apps/mobile/)
bundle exec fastlane android build …   # như nhau từ cả hai thư mục
```

**Các file `Gemfile.lock` đã được commit** — mỗi Gemfile một file bên cạnh, file ở gốc và `apps/mobile/Gemfile.lock` (`.gitignore` ở gốc bỏ qua `*.lock` nhưng có ngoại lệ cho chúng, giống `pubspec.lock`). Chúng ghim phiên bản fastlane, CocoaPods và plugin, nên mọi máy và mọi lần chạy CI đều cài cùng một bộ phiên bản thay vì bản mới nhất vào hôm đó. Hai Gemfile resolve cùng một danh sách gem nên hai lockfile **giống hệt nhau**; hãy giữ nguyên như vậy — sau khi chạy `bundle update` ở một thư mục, chạy đúng lệnh đó ở thư mục kia rồi kiểm tra bằng `cmp Gemfile.lock apps/mobile/Gemfile.lock`. Cả hai đều liệt kê các nền tảng có chạy lane (`bundle lock --add-platform x86_64-linux arm64-darwin x86_64-darwin`), nên `bundler-cache` trên runner GitHub chấp nhận chúng.

Chúng được sinh bởi **Bundler 4** (`BUNDLED WITH 4.0.9` ở cuối mỗi file); `ruby/setup-ruby` cài đúng bản Bundler đó, bản này cần Ruby 3.2 trở lên (`fastlane.yml` dùng 3.3). Nếu Bundler trên máy bạn cũ hơn, chạy `gem install bundler` trước.

Nếu `bundle exec fastlane` báo `bundler: command not found: fastlane` ngay sau một lần `bundle install` thành công, thì thư mục chứa file thực thi của gem chưa nằm trong `PATH` (hay gặp với rbenv khi không dùng shim): hãy thêm nó vào — `gem env | grep "EXECUTABLE DIRECTORY"` cho biết đó là thư mục nào.

Các lane không phụ thuộc locale: cả hai Fastfile đặt encoding ngoài mặc định của Ruby thành UTF-8 trước khi import bất cứ thứ gì, vì với locale C/POSIX (một container Linux trần, một số image CI) các module và `pubspec.yaml` bị đọc như US-ASCII và byte không phải ASCII đầu tiên làm lần chạy dừng với `invalid multibyte char (US-ASCII)`. Bản thân fastlane vẫn in `WARNING: fastlane requires your locale to be set to UTF-8`; `export LANG=C.UTF-8` (hoặc `en_US.UTF-8`) sẽ tắt cảnh báo này.

Đừng chạy `fastlane add_plugin`: plugin đã có sẵn, lệnh này cần tương tác (fail trên CI), và nó sửa Pluginfile của thư mục fastlane nơi nó được chạy. Muốn thêm plugin mới thì tự thêm vào `apps/mobile/fastlane/Pluginfile`; cả hai Gemfile đều nạp nó — Gemfile ở gốc nạp qua `fastlane/Pluginfile`, điều fastlane bắt buộc phải thấy mới coi là plugin đã được thiết lập.

---

## 3. Danh sách lane

Mọi lane đều tương tác: tham số nào bạn không truyền thì nó sẽ hỏi. Truyền sẵn trên dòng lệnh sẽ bỏ qua câu hỏi — đó là điều khiến các lane này dùng được trong CI.

Khi không có terminal — CI, một pipe, `< /dev/null` — fastlane không thể hỏi. Tham số bạn bỏ qua khi đó nhận giá trị mặc định và lane in ra điều đó (`Non-interactive: version not passed, using "1.0.0". Pass version:<value> to choose.`): `flutter_version` → `flutter.default_version`, `version` → `default_app_version`, `build_number` → `auto`, `build_type` → `apk`, `track` → `internal`, `change_log` → rỗng, và **`distribute_store` / `distribute_firebase` → `false`**, nên không có gì được upload nếu dòng lệnh không yêu cầu (câu hỏi tương tác vẫn mặc định chọn Firebase). `flavor` không có mặc định: lane dừng và yêu cầu `flavor:<giá trị>`. Trước đây, tham số đầu tiên bị bỏ qua làm lần chạy crash với `Could not retrieve response as fastlane runs in non-interactive mode` kèm backtrace Ruby.

Các giá trị trên dòng lệnh được kiểm tra trước khi bắt đầu setup: `version` phải gồm một đến ba số nguyên cách nhau bởi dấu chấm (`1.2.0`), `build_number` là số nguyên dương hoặc `auto`, `build_type` là `apk` hoặc `aab`, `flavor` thuộc `VALID_FLAVORS` — giá trị khác làm lane dừng ngay và liệt kê các giá trị hợp lệ.

### Android — `apps/mobile/fastlane/modules/android_lanes.rb`

| Lane | Làm gì | Tham số |
|:---|:---|:---|
| `android build` | Build APK hoặc AAB rồi phân phối | `flavor`, `build_type` (`apk`/`aab`), `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log`, `change_log_file`, `skip_setup`, `skip_build`, `flutter_upgrade` |
| `android upload` | Upload artifact **đã build sẵn** lên Play. Ép `skip_build:true`, `skip_setup:true`, `flutter_version:stable`, `distribute_store:true`, `distribute_firebase:false` | `flavor`, `build_type`, `version`, `track` |
| `android store` | Phát hành prod lên Play. Ép `flavor:prod`, `build_type:aab`, `distribute_store:true`, `distribute_firebase:false` | `version`, `build_number`, `track` |

### iOS — `apps/mobile/fastlane/modules/ios_lanes.rb`

| Lane | Làm gì | Tham số |
|:---|:---|:---|
| `ios build` | Build IPA rồi phân phối lên TestFlight và/hoặc Firebase | `flavor`, `version`, `build_number`, `flutter_version`, `distribute_store`, `distribute_firebase`, `change_log`, `change_log_file`, `skip_setup`, `skip_build`, `flutter_upgrade` |
| `ios upload` | Upload IPA có sẵn lên TestFlight, không build lại | `flavor`, `version` |
| `ios store` | Phát hành prod lên TestFlight. Ép `flavor:prod`, `distribute_store:true` | `version`, `build_number` |

### Cross-platform — `apps/mobile/fastlane/modules/flutter_lanes.rb`

| Lane | Làm gì | Tham số |
|:---|:---|:---|
| `flutter` | Hỏi một lần các tham số chung, thiết lập toolchain một lần, rồi gọi `fastlane ios build` trước, `fastlane android build` sau | `flavor`, `version`, `build_number`, `build_type`, `flutter_version`, `distribute_store`, `distribute_firebase`, `track`, `change_log`, `skip_setup`, `flutter_upgrade` |
| `store` | Cùng cách điều phối nhưng mặc định prod/store: `fastlane ios store` rồi `fastlane android store` | `version`, `build_number`, `track`, `flutter_version`, `change_log`, `skip_setup`, `flutter_upgrade` |

Cả hai lane cross-platform đều **chạy iOS trước và huỷ toàn bộ nếu iOS fail**, nên Android không bao giờ được build cho một bản release mà iOS không dựng nổi. Các tiến trình con chạy từ `apps/mobile/` (khi chạy dưới `bundle exec` chúng thừa hưởng cùng bundle).

**Mọi lane iOS — và vì thế cả `flutter` lẫn `store` — cần macOS có Xcode.** Trên máy khác, chúng dừng trước câu hỏi đầu tiên với một lỗi nêu tên lane và máy (`… needs macOS with Xcode (flutter build ipa, CocoaPods, xcrun altool); this machine is x86_64-linux`), thay vì chạy hết phần setup toolchain rồi mới fail bên trong `pod` hoặc `xcrun`. Trên Linux, hãy build Android bằng `android build` / `android store`.

### Change log

Một lane lấy change log theo thứ tự sau:

1. `change_log:` — luôn được ưu tiên;
2. `change_log_file:` — một file mà đường dẫn được truyền **tường minh**. Các lane cross-platform ghi change log một lần vào thư mục tạm **nằm ngoài repo**, truyền nó cho cả hai lane con dưới dạng `change_log_file:`, rồi xoá trong khối `ensure` dù lần chạy thành công hay không;
3. hỏi tương tác.

Không có gì được đọc ngầm và cũng không có gì được ghi ngược lại. (Trước đây các lane đọc một file cố định `change_log_<platform>.txt` *trước cả khi* xét `change_log:`, nên một file còn sót lại từ lần chạy bị ngắt giữa chừng sẽ âm thầm thay thế change log bạn truyền vào.)

Giá trị hợp lệ do `helpers.rb` kiểm soát:

- `VALID_TRACKS` = `internal`, `alpha` (closed testing), `beta` (open testing), `production` — các track có sẵn của Play Console. `closed` không phải tên track mà Play API chấp nhận. Track closed testing tự tạo trong Play Console được gọi bằng đúng tên của nó: truyền `track:<tên>` trên dòng lệnh, lane nhận nguyên văn; chỉ câu hỏi tương tác mới bị giới hạn trong danh sách này
- `VALID_BUILD_TYPES` = `apk`, `aab`
- `VALID_FLAVORS` = danh sách trong `Config.yaml`, cộng thêm `none`

### Ví dụ

```bash
# APK dev cho tester qua Firebase
bundle exec fastlane android build flavor:dev build_type:apk distribute_firebase:true change_log:"Fix login bug"

# Chỉ build local — không phân phối, không setup toolchain (nhanh nhất)
bundle exec fastlane android build flavor:dev build_type:apk distribute_firebase:false distribute_store:false skip_setup:true

# AAB prod lên track internal của Play
bundle exec fastlane android store version:1.2.0 build_number:45 track:internal

# IPA prod lên TestFlight
bundle exec fastlane ios store version:1.2.0 build_number:45

# Cả hai nền tảng, flavor dev, chỉ Firebase
bundle exec fastlane flutter flavor:dev version:1.2.0 build_number:auto distribute_firebase:true distribute_store:false

# Cả hai nền tảng, prod, lên cả hai store
bundle exec fastlane store version:1.2.0 build_number:auto track:internal
```

### Build number

`build_number` nhận một số nguyên dương hoặc `auto`; giá trị **rỗng** (`build_number:` — thứ mà một input CI để trống sinh ra) cũng có nghĩa là `auto`. Mọi giá trị khác (`0`, `abc`) làm lane dừng lại: trước đây nó thành `"".to_i` = `0` và được build ra với `--build-number=0`. Với `auto`, `determine_build_number` tự tính:

| Phân phối | `auto` thành |
|:---|:---|
| store, iOS | build **TestFlight** mới nhất của version đó + 1 |
| store, Android | version code cao nhất trên track của **Google Play** + 1 |
| chỉ Firebase | bản phát hành **Firebase App Distribution** mới nhất + 1 |
| không phân phối (build local) | build number trong `apps/mobile/pubspec.yaml` (`version: 1.0.0+N` → `N`) — không cần credential, không có gì để trùng |

`fastlane.yml` gửi `build_number:auto` khi input của nó để trống.

Khi `auto` cần tới store hoặc Firebase mà việc tra cứu thất bại (thiếu file credential, `Config.yaml` vẫn còn placeholder mẫu như `YOUR_FIREBASE_APP_ID_ANDROID_DEV`), lane dừng trước mọi bước setup, nêu nguyên nhân và cách xử lý — truyền `build_number:<n>`. Ở đây nó không bao giờ lùi về số trong pubspec: số đó sẽ trùng với một bản release đã upload. `android upload` / `ios upload` hoàn toàn không tra số: artifact đã mang sẵn version code của nó.

`versionCode` và `versionName` **không** lấy từ `apps/mobile/pubspec.yaml` khi build qua Fastlane. `apps/mobile/android/app/build.gradle.kts` gắn chúng vào Flutter:

```kotlin
versionCode = flutter.versionCode
versionName = flutter.versionName
```

nghĩa là `--build-number` / `--build-name` mà lane truyền vào sẽ quyết định. Dòng `version: 1.0.0+1` trong `apps/mobile/pubspec.yaml` chỉ là giá trị dự phòng khi chạy `flutter build` trần không kèm cờ.

---

## 4. Ký ứng dụng

`apps/mobile/android/app/build.gradle.kts` khai ba signing config, mỗi cái đọc một file properties khác nhau trong `apps/mobile/android/`:

| Config | File properties | Flavor sử dụng |
|:---|:---|:---|
| `dev` | `key-dev.properties` | `dev` |
| `staging` | `key-stg.properties` | `staging` |
| `prod` | `key.properties` | `prod` |

### Build release từ chối key dev

Khi thiếu `key-stg.properties` / `key.properties`, mỗi build type xử lý khác nhau:

| Build | Flavor `staging` / `prod` thiếu file properties của nó |
|:---|:---|
| `--debug`, `--profile` | Ký bằng key dev đã commit, để clone về là chạy được mọi flavor |
| `--release` (APK hoặc AAB) | **Fail** ở `pre<Flavor>ReleaseBuild`, sớm trong quá trình build, trước khi đóng gói hay ký |

Thông báo lỗi nêu tên file bị thiếu và trỏ về mục này:

```text
Execution failed for task ':app:preProdReleaseBuild'.
> Refusing to build the prod release: …/apps/mobile/android/key.properties is missing.
  Without it this build would be signed with the committed, public dev keystore
  (keystore-dev.jks), and a Play listing's signing key can never change afterwards.
```

Phần chặn nằm ở cuối `apps/mobile/android/app/build.gradle.kts`. Nó gắn vào task `pre…ReleaseBuild` mà mọi đường build release đều chạy — `flutter build apk|appbundle`, các lane Fastlane, `./gradlew assemble…|bundle…` — nên không đường nào tạo ra được bản release ký bằng key công khai.

Các lane Android kiểm tra đúng điều này **trước** mọi thứ khác — trước change log, việc tra build number và phần setup toolchain — nên khi thiếu file, `android build flavor:prod|staging` và `android store` dừng trong khoảng hai giây với `Refusing to build the prod release: apps/mobile/android/key.properties is missing …`, thay vì sau phần setup và một phút Gradle, chìm trong output của `flutter build --verbose`. Lối thoát cho staging bên dưới cũng được tôn trọng ở đây (`ORG_GRADLE_PROJECT_allowDevKeystoreForStaging`, hoặc `allowDevKeystoreForStaging=true` trong `apps/mobile/android/gradle.properties` hay `~/.gradle/gradle.properties`).

> [!NOTE]
> **Chỉ staging** có lối thoát tường minh, cho pipeline cố ý phát staging tới tester bằng key dev: Gradle property `allowDevKeystoreForStaging=true`.
> ```bash
> flutter build apk --flavor staging -PallowDevKeystoreForStaging=true --dart-define-from-file=env.stg
> # hoặc, cho cả một job CI:
> export ORG_GRADLE_PROJECT_allowDevKeystoreForStaging=true
> ```
> Prod không có. Ai cũng ký được bản cập nhật cho một app staging ký bằng key dev, nên hãy ưu tiên một `key-stg.properties` thật (một upload key riêng, tạo giống như bên dưới).

Bản release `dev` vẫn dùng `key-dev.properties`: flavor dev không bao giờ là một listing trên store.

### Keystore dev đang nằm trong git

`apps/mobile/android/key-dev.properties` và `apps/mobile/android/keystore-dev.jks` **được track trong git** để clone về là build chạy ngay không cần cấu hình. Với một template thì đó là chủ đích, và dùng cho `dev` thì không sao. `apps/mobile/android/.gitignore` bỏ qua mọi `*.jks`, `*.keystore`, `key.properties` và `key-*.properties` khác và chỉ un-ignore đúng hai file này; `.gitignore` ở gốc lặp lại cùng các pattern đó (thêm `google-services.json` / `GoogleService-Info.plist`) ở mọi độ sâu, với đúng hai ngoại lệ ấy.

> [!CAUTION]
> **Tuyệt đối không phát hành production bằng keystore dev.** Nó công khai trong repo — bất kỳ ai clone được cũng ký được một APK mà hệ điều hành coi là bản cập nhật của app bạn.

Tạo khoá release riêng:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Rồi tạo `apps/mobile/android/key.properties` (đã được `.gitignore` che):

```properties
storePassword=<mật khẩu store của bạn>
keyPassword=<mật khẩu key của bạn>
keyAlias=upload
storeFile=/duong/dan/tuyet/doi/toi/upload-keystore.jks
```

Staging đọc `key-stg.properties`, nằm cạnh nó và cùng định dạng — tốt nhất trỏ tới một key thứ hai, để key staging có lộ cũng không ký được prod.

Giữ file `.jks` **ngoài** repo, và sao lưu ở nơi bền vững — mất nó đồng nghĩa với việc không bao giờ publish được bản cập nhật cho listing Play đó nữa.

---

## 5. Bundle ID

`helpers.rb` sinh bundle ID bằng cách thêm hậu tố theo flavor. Hậu tố staging khác nhau theo nền tảng — Gradle dùng `.stg`, project Xcode dùng `.staging` — nên helper nhận thêm platform và khớp chính xác với từng project native:

```ruby
def get_bundle_id_with_suffix(base_bundle_id, flavor, platform)
  return base_bundle_id if flavor.nil? || flavor.empty?
  case flavor
  when 'dev' then "#{base_bundle_id}.dev"
  when 'staging' then platform == :ios ? "#{base_bundle_id}.staging" : "#{base_bundle_id}.stg"
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

| Flavor | Android: `applicationIdSuffix` của Gradle | Android: Bundle ID Fastlane tính | iOS: `PRODUCT_BUNDLE_IDENTIFIER` của Xcode | iOS: Bundle ID Fastlane tính | Khớp |
|:---|:---|:---|:---|:---|:---|
| `dev` | `.dev` | `<base>.dev` | `com.example.codebase.dev` | `<base>.dev` | ✅ |
| `staging` | `.stg` | `<base>.stg` | `com.example.codebase.staging` | `<base>.staging` | ✅ |
| `prod` | *(không có)* | `<base>` | `com.example.codebase` | `<base>` | ✅ |

`<base>` là `app_bundle_ids.android` / `app_bundle_ids.ios` trong `Config.yaml`. Các identifier của Xcode được đặt theo từng build configuration (`Debug-<flavor>`, `Release-<flavor>`, `Profile-<flavor>`) trong `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`, và `tools/firebase/firebase_config.dart` cũng đăng ký đúng ID iOS `.staging` đó.

> [!NOTE]
> Các danh sách này được duy trì độc lập và không có gì kiểm tra xem chúng có khớp nhau hay không. Nếu Fastlane tính ra `.staging` trong khi Gradle sinh `.stg` — hoặc `.stg` trong khi Xcode sinh `.staging`, như trước khi helper nhận thêm platform — một lần upload staging sẽ tra tới một store listing không khớp artifact. Nếu thêm flavor hay đổi hậu tố, hãy sửa helper, Gradle **và** Xcode trong cùng một commit.

---

## 6. Flavor và file env

| Flavor | Hậu tố applicationId | File dart-define Fastlane mong đợi | Có sẵn |
|:---|:---|:---|:---|
| `dev` | `.dev` | `apps/mobile/env.dev` | ✅ |
| `staging` | `.stg` | `apps/mobile/env.stg` | ✅ |
| `prod` | *(không có)* | `apps/mobile/env.prod` | ❌ **bạn phải tự tạo** |

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

và từ chối build khi file đó không tồn tại — đường dẫn là tuyệt đối, dựng từ `APP_DIR`, nên dù chạy từ entry point nào cũng là cùng một file:

```ruby
dart_define_file = File.join(APP_DIR, get_dart_define_file(flavor))
unless File.exist?(dart_define_file)
  UI.user_error!(
    "Dart define file '#{display_path(dart_define_file)}' not found for flavor " \
    "'#{flavor}'. Building without it would ship empty " \
    "String.fromEnvironment values (API base URL, keys), so this is " \
    "a hard failure. Create the file first."
  )
end
build_command += " --dart-define-from-file=#{dart_define_file.shellescape}"
```

> [!IMPORTANT]
> **Không build được bản prod cho tới khi bạn tạo `apps/mobile/env.prod`.** Đó là có chủ đích. Phương án còn lại — bỏ qua cờ này kèm một cảnh báo — sẽ khiến build prod vẫn *thành công* trong khi mọi `String.fromEnvironment` trong `platform/kernel/lib/src/utils/env_constants.dart` rơi về giá trị rỗng, cho ra một APK trỏ tới API URL rỗng và key rỗng, đã ký và phát hành mà không cảnh báo gì. Fail to là đánh đổi an toàn hơn.
>
> Sao chép danh sách key từ `apps/mobile/env.dev`; `.vscode/launch.json` vốn đã trỏ cấu hình Prod vào `env.prod`.

> [!NOTE]
> `env.prod` vốn đã được ignore — `apps/mobile/.gitignore` liệt kê nó tường minh (mẫu `*.env` trong `.gitignore` ở gốc thì không khớp được: dấu chấm nằm sai phía). `env.dev` và `env.stg` được commit **có chủ đích**: chúng không chứa bí mật nào và một bản clone mới phải build được. Đừng đặt credential thật vào hai file đó. Trên CI, bản build prod nhận `env.prod` từ secret `ENV_PROD_B64`.

---

## 7. Thiết lập toolchain bên trong lane

Trừ khi bạn truyền `skip_setup:true`, mọi lane đều gọi `setup_flutter_environment`. **FVM là tuỳ chọn**: nó chỉ được dùng khi workspace ghim phiên bản (`.fvmrc`) **và** máy có cài `fvm` — cùng quy tắc với `tools/shared/toolchain.dart`. Biến `FASTLANE_USE_FVM=true|false` ghi đè kết quả dò này.

| `flutter_version` | Có FVM | Không có FVM |
|:---|:---|:---|
| `stable` (hoặc rỗng) | `fvm install` — bản `.fvmrc` ghim | `flutter` trên PATH, giữ nguyên |
| cụ thể, ví dụ `3.47.4` | phải bằng bản `.fvmrc` ghim, không thì lane dừng (chuyển phiên bản sẽ ghi đè `.fvmrc` đang được track) | phải bằng `flutter --version`, không thì lane dừng |

Không có gì bị nâng cấp ngầm. `flutter_upgrade:true` (phải tự bật, chỉ khi không dùng FVM) chạy `flutter channel stable` + `flutter upgrade --force` trước — trước đây lệnh này chạy ở mọi bản build `stable`, âm thầm thay đổi toolchain của máy. `flutter precache --ios` chỉ chạy cho bản build iOS trên macOS.

Sau đó nó chạy `install_dependencies`, thêm `fvm ` trước `dart` / `flutter` khi dùng FVM:

```ruby
sh "#{dart_cmd} pub global activate flutterfire_cli"
sh "#{dart_cmd} pub global activate flutter_gen"
sh "#{flutter_cmd} clean"
sh "#{flutter_cmd} pub get --enforce-lockfile"
# ...rồi flutter gen-l10n cho mọi l10n.yaml trong cây thư mục
sh "#{dart_cmd} run build_runner build --workspace"
# ...rồi, với mỗi package có lib/ (bỏ qua app), chạy từ gốc workspace:
sh "#{dart_cmd} tools/barrel_generator/generate.dart <package>/lib"
```

`--enforce-lockfile` build đúng theo `pubspec.lock` của workspace đã commit, và fail khi lockfile không còn khớp các pubspec thay vì resolve lại.

Lượt sinh barrel chạy cuối cùng vì barrel còn export cả các file được sinh ra, và các barrel `lib/src/gen/gen.dart` nằm trong gitignore — nó làm y như bước 6 của `tools/workspace_setup/configure.dart`.


Vì bước này chạy `flutter clean` và `build_runner` cho cả workspace nên rất chậm. Dùng `skip_setup:true` khi build đi build lại ở local.

---

## 8. Quy trình phát hành

1. **Chốt version.** Quyết định `version` (build name). Dùng `build_number:auto` trừ khi bạn cần một số cụ thể.
2. **Kiểm tra ký ứng dụng.** `test -f apps/mobile/android/key.properties` — thiếu nó thì build release dừng ở `preProdReleaseBuild` ([§4](#4-ký-ứng-dụng)).
3. **Kiểm tra file env của flavor tương ứng có tồn tại không** — xem [§6](#6-flavor-và-file-env). Với prod bạn phải tạo `apps/mobile/env.prod` trước; thiếu nó lane fail cứng.
4. **Xác nhận `Config.yaml` đã điền đủ**, đặc biệt `firebase.app_ids`, `app_store_connect.apple_ids` và các đường dẫn credential.
5. **Chạy thử ở local**, không phân phối:
   ```bash
   bundle exec fastlane android build flavor:prod build_type:aab \
     distribute_store:false distribute_firebase:false skip_setup:true
   ```
6. **Phát hành.**
   ```bash
   # Cho tester trước
   bundle exec fastlane android build flavor:prod build_type:apk distribute_firebase:true \
     version:1.2.0 build_number:auto change_log:"…"

   # Rồi lên store
   bundle exec fastlane store version:1.2.0 build_number:auto track:internal
   ```
7. **Promote** từ `internal` lên `production` trong Play Console sau khi kiểm thử xong. Lane upload với `release_status: 'draft'`, nên không có gì lên live nếu bạn không chủ động promote.
8. **Lưu trữ symbol obfuscation.** Mọi lane đều build với `--obfuscate --split-debug-info=apps/mobile/obfuscate` và in đường dẫn đó ra sau khi build. Các file symbol không nằm trong APK/AAB/IPA, và thiếu chúng thì `flutter symbolize` không đọc được một stack trace crash nào của bản phát hành này — hãy lưu chúng cùng bản phát hành (`fastlane.yml` upload chúng thành artifact của workflow). Lần build sau sẽ ghi đè lên chúng.

### Checklist trước khi phát hành

- [ ] `apps/mobile/android/key.properties` tồn tại và trỏ tới keystore **release** của bạn
- [ ] Keystore release đã được sao lưu ngoài repo
- [ ] File env của flavor đích đã có (`apps/mobile/env.prod` cho prod — xem [§6](#6-flavor-và-file-env))
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
- Nếu `flutter build ipa` archive thành công nhưng export lỗi, nó thử lại `xcrun xcodebuild -exportArchive -exportOptionsPlist <file đó>` tối đa ba lần — **chỉ khi file đó tồn tại**. Không có nó thì chẳng có gì để thử lại, nên lane dừng với lỗi nêu rõ đường dẫn còn thiếu. Hãy tạo nó cạnh flavor (`ios/flavors/<flavor>/ExportOptions.plist`, hoặc `ios/ExportOptions.plist` cho build không flavor) với tối thiểu `method` (ví dụ `app-store-connect`), `teamID` và, nếu ký thủ công, `provisioningProfiles`; file `ExportOptions.plist` nằm trong một lần export *Distribute App* thành công của Xcode là điểm xuất phát dùng được.
- `distribute_to_app_store` bỏ qua `upload_to_testflight` của Fastlane và gọi thẳng `xcrun altool --upload-app`, kèm comment giải thích wrapper altool của Fastlane không tương thích với Xcode 26. altool được chạy với `API_PRIVATE_KEYS_DIR` là thư mục chứa `paths.app_store_connect_key_filepath`, vì nó chỉ tìm key theo tên `AuthKey_<api_key_id>.p8` ([§2](#các-trường-cần-điền)).

Những phần **chưa** được nối:

- Bước build và distribute iOS trong `azure-ci-cd.yml` bị comment toàn bộ.
- Bước build iOS trong `.github/workflows/flutter_build.yml` bị comment; chỉ Android được build và phân phối.
- Build iOS cần macOS, nên tuỳ chọn `self-hosted` trong `fastlane.yml` bắt buộc phải là máy Mac — và keychain của máy đó phải có sẵn chứng chỉ ký cùng provisioning profile; không workflow nào cài chúng. Chọn `platform: android` trong `fastlane.yml` để chỉ build Android.
- `ios/flavors/<flavor>/GoogleService-Info.plist` bị gitignore; `fastlane.yml` khôi phục nó từ `GOOGLE_SERVICE_INFO_<FLAVOR>_PLIST_B64` khi secret đó được đặt.

---

## Xem thêm

- [`01_cicd.md`](01_cicd.md) — pipeline, secret, và các lỗi liệt kê ở đó
- [`../getting-started/01_setup.md`](../getting-started/01_setup.md) — flavor, file env, khởi tạo Firebase
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — các script trong `tools/` mà Fastlane gọi
