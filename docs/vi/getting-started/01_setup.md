# 01 · Cài đặt & Chạy lần đầu

**Trang này trả lời:** cần cài gì, và gõ đúng những lệnh nào để đi từ `git clone` đến lúc app chạy được?

**Đọc xong bạn có thể:** chạy app trên thiết bị với flavor `dev`, và hiểu vì sao hai lỗi phổ biến nhất ở lần chạy đầu lại xảy ra.

---

## 1. Yêu cầu môi trường

| Thành phần | Phiên bản | Con số này lấy từ đâu |
| :--- | :--- | :--- |
| Flutter SDK | **3.47.4** trở lên | `pubspec.yaml` → `environment.flutter: ">=3.47.4"` |
| Dart SDK | **3.13.3** trở lên | `pubspec.yaml` → `environment.sdk: ">=3.13.3 <4.0.0"` |
| JDK | **17** | `apps/mobile/android/app/build.gradle.kts` → `JavaVersion.VERSION_17` |
| Android SDK | compileSdk **37**, NDK `28.2.13676358` | `apps/mobile/android/app/build.gradle.kts` |
| Xcode + CocoaPods | iOS deployment target **15.0** | `apps/mobile/ios/Podfile` |
| Ruby ≥ 3.0 | chỉ cần cho Fastlane | xem [operations/02_fastlane_release.md](../operations/02_fastlane_release.md) |

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

## 2. Clone và cài dependencies

Đây là **Pub Workspace**. Toàn bộ 26 thành viên workspace (23 package, hai app, và `tools`) chỉ có **một** lần resolve dependency duy nhất, nên bạn chạy `pub get` **một lần, tại thư mục gốc** — tuyệt đối không chạy bên trong package con.

```bash
git clone <repo-url>
cd flutter-monorepo-codebase

flutter pub get        # resolve cả workspace, sinh duy nhất 1 pubspec.lock ở root
```

Nếu bạn thấy các file `pubspec.lock` xuất hiện trong package con, tức là có ai đó đã chạy `pub get` sai chỗ — xoá chúng đi, chỉ file ở root mới đúng.

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

Chúng thuộc về **app**, không thuộc `platform/`: Firebase options gắn với một bundle ID, nên mỗi app dùng Firebase sở hữu thư mục `lib/firebase/` của riêng nó. Trước đây chúng nằm trong `core_common`, khiến mọi app khác trong workspace nhận luôn options của app mobile. Chưa sinh thì bạn sẽ gặp:

```
Target of URI doesn't exist: 'firebase_options_dev.dart'
Undefined name 'DefaultFirebaseOptions'
```

**Cách khắc phục — chạy script hỗ trợ từ thư mục gốc repo:**

```bash
dart tools/firebase/firebase_config.dart --app mobile
```

Script tìm app qua `app_manifest.yaml`, rồi chạy `flutterfire configure` bên trong `apps/mobile/` cho mọi flavor và build mode, ghi ra `lib/firebase/firebase_options_<flavor>.dart`, `ios/flavors/<flavor>/GoogleService-Info.plist` và `android/app/src/<flavor>/google-services.json`. Có thể bỏ `--app` khi workspace chỉ có một app.

Muốn làm tay thì chạy FlutterFire một lần cho mỗi môi trường, **từ `apps/mobile/`**:

```bash
dart pub global activate flutterfire_cli
cd apps/mobile

flutterfire configure \
  --project=<firebase-project-dev-cua-ban> \
  --out=lib/firebase/firebase_options_dev.dart

flutterfire configure \
  --project=<firebase-project-staging-cua-ban> \
  --out=lib/firebase/firebase_options_staging.dart

flutterfire configure \
  --project=<firebase-project-prod-cua-ban> \
  --out=lib/firebase/firebase_options_prod.dart
```

Phải có đủ **cả ba** file kể cả khi bạn chỉ định chạy `dev` — vì `firebase_module.dart` import cả ba một cách vô điều kiện, thiếu file `prod` là bản `dev` cũng gãy.

---

## 4. Chạy code generation

Dự án dùng codegen rất nhiều: `freezed`, `injectable`, `json_serializable`, `retrofit`, `drift`, `go_router_builder`, `flutter_gen`.

```bash
dart run build_runner build -d --workspace
```

- `-d` thay cho cờ `--delete-conflicting-outputs` đã lỗi thời.
- `--workspace` chạy builder cho **mọi** package trong workspace chỉ trong một lượt. Chạy build_runner bên trong từng package riêng lẻ không được hỗ trợ ở đây.

> [!WARNING]
> Tuyệt đối không sửa tay các file `*.g.dart`, `*.freezed.dart`, `*.module.dart` hay `injection.config.dart`.
> Chúng bị ghi đè sau mỗi lần chạy. Muốn đổi thì sửa annotation ở file nguồn.

### Hoặc gộp bước 2 + 4 làm một

```bash
dart tools/workspace_setup/configure.dart
```

Script đa nền tảng này chạy tuần tự: kích hoạt `flutterfire_cli` → `flutter clean` → `flutter pub get` → `gen-l10n` cho mọi package có file ARB → `build_runner build -d --workspace`.

> [!NOTE]
> `configure.dart` là điểm vào duy nhất — không có bản bọc `configure.sh` hay `configure.bat`. Một script Dart chạy y hệt nhau trên mọi nền tảng, nên không cần tới shell wrapper.

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
GOOGLE_MAP_API=
FACEBOOK_APP_ID=
FACEBOOK_TOKEN=
GOOGLE_APP=
BASE_URL=
SOCKET=
WEB_DOMAIN=
APP_LINK_MODE=
APP_SCHEMA=
APP_SCHEMA_VERSION=
APP_NAME=
```

Phần lớn các key này xuất hiện trong Dart qua `EnvConstants` (`platform/kernel/lib/src/utils/env_constants.dart`), đọc bằng `String.fromEnvironment`:

```dart
class EnvConstants {
  EnvConstants._();

  static const String GOOGLE_MAP_API = String.fromEnvironment('GOOGLE_MAP_API');
  static const String BASE_URL = String.fromEnvironment('BASE_URL');
  static const String SOCKET = String.fromEnvironment('SOCKET');
  // …
}
```

> [!NOTE]
> `APP_SCHEMA` và `APP_LINK_MODE` **không** được khai trong `EnvConstants`. Riêng `APP_SCHEMA` chỉ được phía Android dùng, dưới dạng `resValue` string trong `apps/mobile/android/app/build.gradle.kts`. Vẫn phải giữ chúng trong file env dù Dart không đọc trực tiếp.

> [!WARNING]
> `apps/mobile/env.dev` và `apps/mobile/env.stg` hiện **đang được git theo dõi** — mẫu `*.env` trong `.gitignore` không khớp với tên file `env.dev`. Hãy coi nội dung của chúng là giá trị mẫu không bí mật, và đừng đặt credential production thật vào `apps/mobile/env.prod` cho tới khi bạn xác nhận file đó đã được ignore.

---

## 6. Chạy app

### Từ dòng lệnh

```bash
flutter run -t apps/mobile/lib/main.dart --flavor dev --dart-define-from-file=apps/mobile/env.dev
```

### Build APK — bắt buộc `cd apps/mobile` trước

```bash
cd apps/mobile
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

> [!CAUTION]
> Chạy `flutter build apk` từ thư mục gốc sẽ báo lỗi rất khó hiểu, ví dụ
> `Target file "lib\main.dart" not found`, hoặc
> `Flutter failed to read a file at ".../android/app/build.gradle"`.
> Project Android nằm ở `apps/mobile/android`, nên lệnh build phải gọi từ trong `apps/mobile/`.
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

### Từ VS Code

`.vscode/launch.json` đã định nghĩa sẵn ba cấu hình — **App (Dev)**, **App (Staging)**, **App (Prod)**. Chọn một trong panel Run and Debug. Mỗi cấu hình tự set `--flavor` và `--dart-define-from-file` (đường dẫn env tính tương đối với `apps/mobile/`, vì đó là nơi Dart extension neo project).

---

## 7. Kiểm tra lại setup

```bash
flutter analyze                     # kỳ vọng: No issues found!
cd platform/storage && flutter test && cd ../../..
```

Nếu `flutter analyze` báo thiếu `firebase_options_*.dart`, quay lại [bước 3](#3-sinh-file-firebase-options-bắt-buộc--không-có-thì-repo-không-biên-dịch-được).

---

## Đọc tiếp ở đâu

| Bạn muốn… | Đọc |
| :--- | :--- |
| Hiểu từng package làm gì | [02_project_tour.md](02_project_tour.md) |
| Biết khi nào chạy lệnh nào | [03_daily_workflow.md](03_daily_workflow.md) |
| Hiểu kiến trúc tổng thể | [../architecture/01_overview.md](../architecture/01_overview.md) |
| Bắt tay viết feature đầu tiên | [../guides/01_new_feature.md](../guides/01_new_feature.md) |
