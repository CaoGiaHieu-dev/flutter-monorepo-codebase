<!-- translated-from: docs/en/getting-started/01_setup.md@b65f8b3 -->
# 01 · Cài đặt & Chạy lần đầu

**Trang này trả lời:** cần cài gì, và gõ đúng những lệnh nào để đi từ `git clone` đến lúc app chạy được?

**Đọc xong bạn có thể:** chạy app trên thiết bị với flavor `dev`, và hiểu vì sao hai lỗi phổ biến nhất ở lần chạy đầu lại xảy ra.

---

## 1. Yêu cầu môi trường

| Thành phần | Phiên bản | Con số này lấy từ đâu |
| :--- | :--- | :--- |
| Flutter SDK | **3.47.4** trở lên | `pubspec.yaml` → `environment.flutter: ">=3.47.4"` |
| Dart SDK | **3.13.3** trở lên | `pubspec.yaml` → `environment.sdk: ">=3.13.3 <4.0.0"` |
| JDK | **17 trở lên** (build được trên 21) | `apps/mobile/android/app/build.gradle.kts` → `JavaVersion.VERSION_17` là mức bytecode đích, không phải giới hạn trên |
| Android SDK | compileSdk **37**, NDK `28.2.13676358` | `apps/mobile/android/app/build.gradle.kts` |
| Xcode + CocoaPods | iOS deployment target **15.0** | `apps/mobile/ios/Podfile` |
| Ruby ≥ 3.0 | chỉ cần cho Fastlane | xem [operations/02_fastlane_release.md](../operations/02_fastlane_release.md) |
| Node.js + npm, một tài khoản Google, một Firebase project | chỉ cần cho cấu hình Firebase **thật** (§3) | Firebase CLI là một package npm; nếu dùng stub ở §3 thì bỏ qua cả ba |

### FVM là tuỳ chọn

Repo có ghim sẵn phiên bản Flutter trong `.fvmrc`:

```json
{
  "flutter": "3.47.4"
}
```

Bạn dùng đường nào cũng được — chọn một và giữ nhất quán:

```bash
# Đường A — FVM (khuyến nghị khi làm nhóm, cả team dùng đúng 1 phiên bản)
dart pub global activate fvm
fvm install            # cài đúng phiên bản ghi trong .fvmrc
fvm flutter --version  # phải in ra 3.47.4

# Đường B — Flutter SDK cài toàn cục
flutter --version      # phải >= 3.47.4
```

> [!NOTE]
> Mọi lệnh trong bộ tài liệu này viết theo **Đường B** (`flutter` / `dart` trần).
> Nếu bạn dùng FVM, thêm tiền tố: `fvm flutter ...` và `fvm dart ...`.

---

## 2. Clone và dựng workspace

Đây là **Pub Workspace**. Toàn bộ 31 thành viên workspace (28 package, hai app, và `tools`) dùng chung **một** lần resolve dependency duy nhất. Một script setup chuẩn bị cho tất cả:

```bash
git clone <repo-url>
cd flutter-monorepo-codebase

dart tools/workspace_setup/configure.dart
```

**`configure.dart` chính là bước setup**. Nó không phải lối tắt cho `pub get` + `build_runner`. Script chạy lần lượt các bước sau và dừng ngay ở lỗi đầu tiên:

1. `dart pub global activate flutterfire_cli`. Chỉ nhánh Firebase thật ở [§3](#3-sinh-file-firebase-options-bắt-buộc--không-có-thì-repo-không-biên-dịch-được) dùng tới nó.
2. `flutter clean` tại root.
3. `flutter pub get` tại root. Bước này resolve cả workspace theo file `pubspec.lock` duy nhất ở root.
4. `flutter gen-l10n` trong mọi package có `l10n.yaml`. Hiện đó là `platform/ui/design_system` và các feature auth, home, onboarding, settings, splash.
5. `dart run build_runner build --workspace`, chạy injectable, freezed, json_serializable, retrofit, go_router_builder, drift và flutter_gen.
6. `dart tools/barrel_generator/generate.dart <package>/lib` cho mọi package có `lib/`. Các app được bỏ qua, vì `injection.dart` của chúng do composer sinh ra.

Script tự dùng `fvm` nếu máy bạn đã cài sẵn. Không có bản bọc `configure.sh` hay `configure.bat`, vì một script Dart chạy y hệt nhau trên mọi nền tảng.

> [!IMPORTANT]
> **Chỉ `flutter pub get` + `build_runner` thì chưa thành một bản setup chạy được.** `lib/src/src.dart` của `core_base_ui` và của mọi feature có bản dịch đều export `gen/gen.dart`. Barrel đó, cùng `gen/language/language.dart`, bị gitignore và chỉ được bước 6 ghi ra. Nếu dừng sau bước 5, `flutter analyze` báo khoảng 17 lỗi dạng:
>
> ```
> error • Target of URI doesn't exist: 'gen/gen.dart' • platform/ui/design_system/lib/src/src.dart:3:8 • uri_does_not_exist
> error • Undefined name 'AppLocalizations' • …
> error • Undefined name 'Assets' • …
> ```
>
> Cách sửa: chạy `dart tools/workspace_setup/configure.dart`.

Nếu muốn làm tay thì phải chạy đủ các bước sau, theo đúng thứ tự (ví dụ bằng bash). Lượt barrel phải chạy **sau** gen-l10n và build_runner, vì nó export những file hai bước đó ghi ra:

```bash
flutter pub get
# gen-l10n trong từng package có l10n.yaml
(cd platform/ui/design_system && flutter gen-l10n)
for f in auth home onboarding settings splash; do (cd modules/$f/feature && flutter gen-l10n); done
dart run build_runner build --workspace
# barrel cho mọi package có lib/, trừ các app
for d in platform/*/* modules/*/*; do [ -d "$d/lib" ] && dart tools/barrel_generator/generate.dart "$d/lib"; done
```

Những gì sẽ thấy ở một lần chạy sạch:

- build_runner in ra vài cảnh báo `W injectable_config_builder … Missing dependencies`. Đó là chuyện bình thường. DI module của mỗi micro-package được sinh riêng và nhắc tới những type do package khác đăng ký. `injection.config.dart` của app mới là nơi ghép chúng lại.
- **Chỉ một file lock, ở root, và được commit.** `pubspec.lock` được git theo dõi (`.gitignore` ở root bỏ ignore cho `/pubspec.lock`), nên mọi người resolve cùng một bộ version. Hãy commit nó khi thay đổi dependency làm nó đổi theo. Nếu thấy `pubspec.lock` xuất hiện trong package con, tức là có ai đó đã chạy `pub get` sai chỗ. Hãy xoá chúng đi, vì chỉ file ở root được dùng.

---

## 3. Sinh file Firebase options (bắt buộc — không có thì repo không biên dịch được)

> [!CAUTION]
> **Repo vừa clone về sẽ KHÔNG compile được.** Đây là lỗi thường gặp nhất ở lần chạy đầu tiên.

File `apps/mobile/lib/firebase/firebase_module.dart` import thẳng ba file theo tên:

```dart
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as stg;
```

Ba file đó được **sinh riêng cho từng dự án và bị git bỏ qua** (`apps/mobile/.gitignore` có dòng `firebase_options_*.dart`), vì chúng chứa định danh Firebase project của riêng bạn.

Chúng thuộc về **app**, không thuộc `platform/`: Firebase options gắn với một bundle ID, nên mỗi app dùng Firebase sở hữu thư mục `lib/firebase/` của riêng nó. Trước đây chúng nằm trong `core_common`, khiến mọi app khác trong workspace nhận luôn options của app mobile. Khi chưa có chúng, `flutter analyze` báo:

```
error • Target of URI doesn't exist: 'firebase_options_dev.dart' • apps/mobile/lib/firebase/firebase_module.dart:4:8 • uri_does_not_exist
error • Target of URI doesn't exist: 'firebase_options_prod.dart' • apps/mobile/lib/firebase/firebase_module.dart:5:8 • uri_does_not_exist
error • Target of URI doesn't exist: 'firebase_options_staging.dart' • apps/mobile/lib/firebase/firebase_module.dart:6:8 • uri_does_not_exist
```

Có hai lối ra: dùng Firebase project thật (§3.1), hoặc dùng stub chỉ để biên dịch (§3.2).

### 3.1 Khi đã có Firebase project — dùng script hỗ trợ

Cần chuẩn bị trước:

- **Node.js + npm**, và **Firebase CLI** cài global: `npm install -g firebase-tools`.
- Một **tài khoản Google** và một **Firebase project** bạn có quyền truy cập. Tạo project trên Firebase console.
- Đã chạy **`firebase login`** tương tác, trong một terminal mở được trình duyệt.

Sau đó chạy từ thư mục gốc repo:

```bash
dart tools/firebase/firebase_config.dart --app mobile
```

Script yêu cầu Firebase CLI đã được cài và đã đăng nhập. Nếu thiếu, script in hướng dẫn cài đặt rồi thoát với mã 1; nó thử `firebase login` tối đa hai lần, từ chối chạy khi không có terminal, và `--help` in ra cách dùng. `configure.dart` đã activate `flutterfire_cli` từ trước. Script hỏi ba thứ: **Firebase project ID**, **base bundle ID / package name** (`com.example.codebase`) và danh sách flavor (mặc định `dev staging prod`). Sau đó nó chạy `flutterfire configure` bên trong `apps/mobile/` cho mọi flavor và build mode. Các file được ghi ra là `lib/firebase/firebase_options_<flavor>.dart`, `ios/flavors/<flavor>/GoogleService-Info.plist` và `android/app/src/<flavor>/google-services.json`, đều tính tương đối với `apps/mobile/`. Package Android nhận hậu tố `.dev` / `.stg` / không hậu tố. Bundle ID iOS nhận `.dev` / `.staging` / không hậu tố. Có thể bỏ `--app` khi workspace chỉ có một app.

> [!NOTE]
> Script hỗ trợ đặt **mọi flavor vào cùng một project ID** mà bạn nhập. Muốn dev, staging và prod nằm ở các Firebase project riêng thì hãy chạy FlutterFire bằng tay, một lần cho mỗi môi trường, **từ `apps/mobile/`**:

```bash
cd apps/mobile

flutterfire configure \
  --project=<firebase-project-dev-cua-ban> \
  --out=lib/firebase/firebase_options_dev.dart \
  --android-package-name=com.example.codebase.dev \
  --android-out=android/app/src/dev/google-services.json

flutterfire configure \
  --project=<firebase-project-staging-cua-ban> \
  --out=lib/firebase/firebase_options_staging.dart \
  --android-package-name=com.example.codebase.stg \
  --android-out=android/app/src/staging/google-services.json

flutterfire configure \
  --project=<firebase-project-prod-cua-ban> \
  --out=lib/firebase/firebase_options_prod.dart \
  --android-package-name=com.example.codebase \
  --android-out=android/app/src/prod/google-services.json
```

Phải có đủ **cả ba** file Dart kể cả khi bạn chỉ định chạy `dev`. `firebase_module.dart` import cả ba một cách vô điều kiện, nên thiếu file `prod` là bản `dev` cũng gãy.

> [!IMPORTANT]
> Ba file Dart là đủ để **biên dịch**: analyze và test chạy qua được, và CI tạo stub đúng cho mục đích đó. **Build app Android** còn cần `apps/mobile/android/app/src/<flavor>/google-services.json`. Thiếu nó, plugin Gradle Google Services sẽ fail ở `process<Flavor>DebugGoogleServices`. Script hỗ trợ tự ghi file này. Các lệnh thủ công ở trên ghi được nó là nhờ cờ `--android-package-name` / `--android-out`.

### 3.2 Chưa có Firebase project? Dùng stub

Để app biên dịch được và build ra APK mà không cần tài khoản Firebase, hãy tự tạo các file thay thế. App **build được**, nhưng mọi thứ dựa trên Firebase (push notification, FCM token) sẽ không hoạt động, và các lời gọi Firebase lúc chạy có thể ghi log lỗi. Hãy thay stub bằng cấu hình thật (§3.1) trước khi dựa vào những tính năng đó.

Hoặc để script setup ghi giúp: `dart tools/workspace_setup/configure.dart --stub-firebase` ghi mọi file dưới đây — Dart options cho từng flavor và một `google-services.json` cho từng flavor Android, package name đọc từ `build.gradle.kts` — chỉ khi file chưa tồn tại, và liệt kê những gì đã stub.

**1. Ba file Dart.** Tạo chúng trong `apps/mobile/lib/firebase/`, đặt tên `firebase_options_dev.dart`, `firebase_options_staging.dart` và `firebase_options_prod.dart`, mỗi file có nội dung dưới đây. Đây đúng là stub mà `tools/workspace_setup/firebase_stubs.dart` ghi ra (thứ `configure.dart --stub-firebase` và CI dùng):

```dart
// CI-only stub. Not a real Firebase configuration: analysis and unit
// tests never initialise Firebase, they only need this to compile.
// Generate the real file with `flutterfire configure`.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
    apiKey: 'ci-stub',
    appId: 'ci-stub',
    messagingSenderId: 'ci-stub',
    projectId: 'ci-stub',
  );
}
```

**2. Mỗi flavor cần build có một `google-services.json`.** File nằm ở `apps/mobile/android/app/src/<flavor>/google-services.json`, và `package_name` phải trùng application ID của flavor đó. Với `dev` là `com.example.codebase.dev`, với `staging` là `com.example.codebase.stg`, với `prod` là `com.example.codebase` (`applicationId` + `applicationIdSuffix` trong `apps/mobile/android/app/build.gradle.kts`). File cho `dev`:

```json
{
  "project_info": {
    "project_number": "000000000000",
    "project_id": "local-stub"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:000000000000:android:0000000000000000",
        "android_client_info": {
          "package_name": "com.example.codebase.dev"
        }
      },
      "api_key": [
        { "current_key": "local-stub" }
      ]
    }
  ],
  "configuration_version": "1"
}
```

Có đủ các file đó thì `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev` chạy thành công. Tất cả các file này đều bị gitignore, nên không thể lỡ tay commit.

---

## 4. Code generation sau khi setup

`configure.dart` đã chạy trọn chuỗi codegen một lần. Từ đó về sau, chỉ cần chạy lại phần mà thay đổi của bạn đụng tới:

```bash
dart run build_runner build --workspace   # sau khi đổi annotation
```

- `--workspace` chạy builder cho **mọi** package trong workspace chỉ trong một lượt. Chạy build_runner bên trong từng package riêng lẻ không được hỗ trợ ở đây.
- **Đừng** truyền `-d` / `--delete-conflicting-outputs`. build_runner đã gỡ cờ này, giờ nó bị bỏ qua kèm cảnh báo `W These options have been removed and were ignored: --delete-conflicting-outputs`.
- Vừa thêm, đổi tên hay xoá file trong `lib/` của một package? Hãy chạy lại barrel generator cho package đó **sau** codegen: `dart tools/barrel_generator/generate.dart <package>/lib`. Xem [03_daily_workflow.md](03_daily_workflow.md).

> [!WARNING]
> Tuyệt đối không sửa tay các file `*.g.dart`, `*.freezed.dart`, `*.module.dart` hay `injection.config.dart`.
> Chúng bị ghi đè sau mỗi lần chạy. Muốn đổi thì sửa annotation ở file nguồn.

---

## 5. File môi trường và flavor

Template có sẵn ba flavor: `dev`, `staging`, `prod`. Giá trị đi vào Dart qua `--dart-define-from-file`, và đi vào Android qua đoạn giải mã `dart-defines` trong `apps/mobile/android/app/build.gradle.kts`.

| Flavor | File env | Hậu tố applicationId | Trạng thái |
| :--- | :--- | :--- | :--- |
| `dev` | `apps/mobile/env.dev` | `.dev` | ✅ có sẵn |
| `staging` | `apps/mobile/env.stg` | `.stg` | ✅ có sẵn |
| `prod` | `apps/mobile/env.prod` | *(không có)* | ❌ **bạn phải tự tạo** |

### Tạo `apps/mobile/env.prod`

File này không nằm trong repo — secret production là của bạn. Chép danh sách **tên key** dưới đây (giá trị đã ẩn; xem `apps/mobile/env.dev` để biết định dạng):

```properties
BASE_URL=
WEB_DOMAIN=
APP_LINK_MODE=
APP_NAME=
```

Ba trong số đó xuất hiện trong Dart qua `EnvConstants` (`platform/foundation/kernel/lib/src/utils/env_constants.dart`), đọc bằng `String.fromEnvironment`:

```dart
class EnvConstants {
  EnvConstants._();

  static const String BASE_URL = String.fromEnvironment('BASE_URL');
  static const String WEB_DOMAIN = String.fromEnvironment('WEB_DOMAIN');
  static const String APP_NAME = String.fromEnvironment('APP_NAME');
}
```

> [!NOTE]
> `APP_LINK_MODE` **không** được khai trong `EnvConstants`: chỉ entitlements iOS đọc nó (`applinks:$(WEB_DOMAIN)$(APP_LINK_MODE)` trong `apps/mobile/ios/Runner/Runner.entitlements`). Vẫn giữ nó trong file env dù Dart không đọc. `WEB_DOMAIN` còn là host của intent-filter App Links trên Android — giá trị rỗng sẽ thành `example.invalid` (tên miền dành riêng), không bao giờ thành "mọi link https" — xem [`04_routing.md` §9](../guides/04_routing.md#9-thiết-lập-deep-link). Key nào sản phẩm cần (API key bản đồ, URL socket) thì thêm đồng thời vào các file env và `EnvConstants`.

> [!WARNING]
> `apps/mobile/env.dev` và `apps/mobile/env.stg` được **commit có chủ đích** — clone mới phải build được — nên đừng để bí mật trong đó. `apps/mobile/env.prod` được ignore theo tên trong `apps/mobile/.gitignore` (mẫu `*.env` ở root không khớp với nó); chạy `git check-ignore -v apps/mobile/env.prod` để xác nhận trước khi đặt giá trị production vào.

---

## 6. Chạy app

Cả `flutter run` lẫn `flutter build` đều phải gọi **từ `apps/mobile/`**. Thư mục gốc workspace không có project `android/` hay `ios/`, nên chạy `-t apps/mobile/lib/main.dart` từ root không thể chạy được.

> [!NOTE]
> **`apps/mobile` chỉ dành cho Android + iOS.** Nó không commit runner `linux/`, `macos/`,
> `windows/` hay `web/`, nên `flutter run -d linux` hoặc `flutter build linux` ở đó dừng với
> *No Linux desktop project configured*. Muốn build desktop, hãy dùng app thứ hai:
> [`apps/admin/README.md`](../../../apps/admin/README.md) sinh runner desktop cho nó và chạy nó.
> Muốn thêm một nền tảng còn thiếu cho một app, chạy `flutter create --platforms=linux .` (hoặc
> `macos`, `windows`) **bên trong thư mục của app đó** — không bao giờ ở gốc workspace — rồi xoá
> `test/widget_test.dart` và `analysis_options.yaml` mà lệnh này sinh ra, như README đó giải thích.
> Repo này chỉ cấu hình `--flavor` cho Android và iOS; bỏ cờ này khi chạy desktop.

### Từ dòng lệnh

```bash
cd apps/mobile
flutter run --flavor dev --dart-define-from-file=env.dev
```

### Build APK

```bash
cd apps/mobile
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

> [!CAUTION]
> Chạy `flutter run` hay `flutter build apk` từ thư mục gốc sẽ báo lỗi rất khó hiểu, ví dụ
> `Target file "lib/main.dart" not found` (`lib\main.dart` trên Windows), hoặc
> `Flutter failed to read a file at ".../android/app/build.gradle"`.
> Project Android nằm ở `apps/mobile/android`, nên lệnh phải gọi từ trong `apps/mobile/`.
> Lưu ý đường dẫn env cũng đổi theo: `env.dev` (tương đối với `apps/mobile/`), không phải `apps/mobile/env.dev`.

File kết quả nằm ở `apps/mobile/build/app/outputs/flutter-apk/app-dev-debug.apk`.

### Android: Built-in Kotlin đang bật

`apps/mobile/android/gradle.properties` đặt `android.builtInKotlin=true`. Giữ nguyên, đừng tắt.

Flutter đang chuyển plugin từ Kotlin Gradle Plugin (KGP) sang phần hỗ trợ Kotlin
tích hợp sẵn trong Flutter Gradle plugin. Plugin nào đã migrate — lỗi này lộ ra ở
đây qua `google_sign_in_android`, trước khi sample auth thôi phụ thuộc vào nó — sẽ
biên dịch phần Java của nó dựa trên class sinh ra
từ chính Kotlin sources của nó. Khi tắt cờ này, phần Kotlin đó không được biên
dịch, và build chết ở những symbol trông như đáng lẽ phải tồn tại:

```
GoogleSignInPlugin.java:218: error: cannot find symbol
  ResultUtilsKt.completeWithValue(...)
```

Thông báo lỗi chỉ ra tên plugin chứ không nhắc tới cờ, nên rất dễ tưởng nhầm là
lỗi version dependency. Không phải — ghim plugin về version cũ hơn cũng không cứu được.

Tại thời điểm viết, `firebase_core` **chưa** migrate và vẫn dùng KGP (`firebase_auth`
và `photo_manager` cũng vậy, nhưng đã rời khỏi workspace). Plugin như thế hiện vẫn
build bình thường, chỉ cảnh báo:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): ...
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

Cảnh báo này là một deadline thật, không phải nhiễu. Khi một bản Flutter tương lai
biến nó thành lỗi, cách xử lý là nâng các plugin mà cảnh báo nêu tên lên version có
hỗ trợ Built-in Kotlin — không cần sửa gì trong repo này. Hãy tin danh sách trong cảnh
báo hơn danh sách ở trang này: nó được tính từ những gì bạn thực sự phụ thuộc.

### Android: sao lưu ứng dụng đang tắt

`apps/mobile/android/app/src/main/AndroidManifest.xml` đặt `android:allowBackup="false"`, `android:fullBackupContent="false"` và `android:dataExtractionRules="@xml/data_extraction_rules"`, với các rule loại mọi domain khỏi cả sao lưu đám mây **lẫn** chuyển dữ liệu giữa hai thiết bị (Android 12+ bỏ qua `allowBackup` cho trường hợp sau).

Lý do là tầng bảo mật của `core_storage`. `flutter_secure_storage` giữ bản mã hoá trong một file SharedPreferences, còn khoá giải mã nằm trong Android Keystore, thứ không bao giờ được sao lưu. Khôi phục sang máy mới sẽ mang về những giá trị app không còn giải mã được — nhẹ thì người dùng bị đăng xuất, nặng thì lỗi đọc.

Đánh đổi: cài lại hoặc đổi máy là app bắt đầu sạch — không còn preference, theme hay cờ onboarding. Muốn giữ preference thường, hãy bật lại backup và chỉ loại file của secure storage, ở cả `<cloud-backup>` và `<device-transfer>` trong `apps/mobile/android/app/src/main/res/xml/data_extraction_rules.xml`, kèm một file `fullBackupContent` tương ứng cho Android 11 trở xuống:

```xml
<exclude domain="sharedpref" path="FlutterSecureStorage.xml" />
```

Hãy xác nhận tên file trên thiết bị trước (`adb shell run-as <applicationId> ls shared_prefs`) — nó phụ thuộc phiên bản và tuỳ chọn của `flutter_secure_storage`.

### Từ VS Code

`.vscode/launch.json` đã định nghĩa sẵn ba cấu hình — **App (Dev)**, **App (Staging)**, **App (Prod)**. Chọn một trong panel Run and Debug. Mỗi cấu hình tự set `--flavor` và `--dart-define-from-file` (đường dẫn env tính tương đối với `apps/mobile/`, vì đó là nơi Dart extension neo project).

---

## 7. Kiểm tra lại setup

```bash
flutter analyze                     # kỳ vọng: No issues found!
cd platform/infra/storage && flutter test && cd ../..
```

Nếu `flutter analyze` chưa sạch:

| Bạn thấy | Nguyên nhân | Cách sửa |
| :--- | :--- | :--- |
| `Target of URI doesn't exist: 'firebase_options_dev.dart'` (và `_prod`, `_staging`) trong `firebase_module.dart` | Thiếu các file Firebase options bị gitignore | [Bước 3](#3-sinh-file-firebase-options-bắt-buộc--không-có-thì-repo-không-biên-dịch-được), dùng file thật hoặc stub |
| `Target of URI doesn't exist: 'gen/gen.dart'`, `Undefined name 'AppLocalizations'`, `Undefined name 'Assets'` (khoảng 17 lỗi) | Setup dừng trước lượt barrel, thường do chỉ chạy `pub get` + `build_runner` | Chạy `dart tools/workspace_setup/configure.dart` |
| `Undefined class '_$…'`, không tìm thấy `… .g.dart` / `.freezed.dart` | Codegen chưa chạy hoặc đã cũ | Chạy `dart tools/workspace_setup/configure.dart` (hoặc `dart run build_runner build --workspace` nếu đã setup một lần) |

---

## Đọc tiếp ở đâu

| Bạn muốn… | Đọc |
| :--- | :--- |
| Hiểu từng package làm gì | [02_project_tour.md](02_project_tour.md) |
| Biết khi nào chạy lệnh nào | [03_daily_workflow.md](03_daily_workflow.md) |
| Hiểu kiến trúc tổng thể | [../architecture/01_overview.md](../architecture/01_overview.md) |
| **Bước tiếp theo:** dựng, test rồi gỡ feature đầu tiên của bạn, từ đầu tới cuối | [04_first_feature_tutorial.md](04_first_feature_tutorial.md) |
| Viết một feature thật | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
