# 01 · Cài đặt & Chạy lần đầu

**Trang này trả lời:** cần cài gì, và gõ đúng những lệnh nào để đi từ `git clone` đến lúc app chạy được?

**Đọc xong bạn có thể:** chạy app trên thiết bị với flavor `dev`, và hiểu vì sao hai lỗi phổ biến nhất ở lần chạy đầu lại xảy ra.

---

## 1. Yêu cầu môi trường

| Thành phần | Phiên bản | Con số này lấy từ đâu |
| :--- | :--- | :--- |
| Flutter SDK | **3.47.1** trở lên | `pubspec.yaml` → `environment.flutter: ">=3.47.1"` |
| Dart SDK | **3.13.1** trở lên | `pubspec.yaml` → `environment.sdk: ">=3.13.1 <4.0.0"` |
| JDK | **17** | `app/android/app/build.gradle.kts` → `JavaVersion.VERSION_17` |
| Android SDK | compileSdk **37**, NDK `28.2.13676358` | `app/android/app/build.gradle.kts` |
| Xcode + CocoaPods | iOS deployment target **15.0** | `app/ios/Podfile` |
| Ruby ≥ 3.0 | chỉ cần cho Fastlane | xem [operations/02_fastlane_release.md](../operations/02_fastlane_release.md) |

### FVM là tuỳ chọn

Repo có ghim sẵn phiên bản Flutter trong `.fvmrc`:

```json
{
  "flutter": "3.47.1"
}
```

Bạn dùng đường nào cũng được — chọn một và giữ nhất quán:

```bash
# Đường A — FVM (khuyến nghị khi làm nhóm, cả team dùng đúng 1 phiên bản)
dart pub global activate fvm
fvm install            # cài đúng phiên bản ghi trong .fvmrc
fvm flutter --version  # phải in ra 3.47.1

# Đường B — Flutter SDK cài toàn cục
flutter --version      # phải >= 3.47.1
```

> [!NOTE]
> Mọi lệnh trong bộ tài liệu này viết theo **Đường B** (`flutter` / `dart` trần).
> Nếu bạn dùng FVM, thêm tiền tố: `fvm flutter ...` và `fvm dart ...`.

---

## 2. Clone và cài dependencies

Đây là **Pub Workspace**. Toàn bộ 23 package chỉ có **một** lần resolve dependency duy nhất, nên bạn chạy `pub get` **một lần, tại thư mục gốc** — tuyệt đối không chạy bên trong package con.

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

File `packages/core/common/lib/src/firebase/firebase_module.dart` import thẳng ba file theo tên:

```dart
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as stg;
```

Ba file đó được **sinh riêng cho từng dự án và bị git bỏ qua** (`packages/core/common/.gitignore` có dòng `firebase_options_*.dart`), vì chúng chứa định danh Firebase project của riêng bạn. Chưa sinh thì bạn sẽ gặp:

```
Target of URI doesn't exist: 'firebase_options_dev.dart'
Undefined name 'DefaultFirebaseOptions'
```

**Cách khắc phục — chạy FlutterFire một lần cho mỗi môi trường:**

```bash
dart pub global activate flutterfire_cli

# Lặp lại cho từng flavor, xuất vào core_common đúng tên file:
flutterfire configure \
  --project=<firebase-project-dev-cua-ban> \
  --out=packages/core/common/lib/src/firebase/firebase_options_dev.dart

flutterfire configure \
  --project=<firebase-project-staging-cua-ban> \
  --out=packages/core/common/lib/src/firebase/firebase_options_staging.dart

flutterfire configure \
  --project=<firebase-project-prod-cua-ban> \
  --out=packages/core/common/lib/src/firebase/firebase_options_prod.dart
```

Con co script ho tro: `dart tools/firebase/firebase_config.dart`.

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
> **Không hề tồn tại** `configure.sh` hay `configure.bat`. Tài liệu cũ có nhắc tới chúng; thực tế chỉ có `configure.dart`.

---

## 5. File môi trường và flavor

Template có sẵn ba flavor: `dev`, `staging`, `prod`. Giá trị đi vào Dart qua `--dart-define-from-file`, và đi vào Android qua đoạn giải mã `dart-defines` trong `app/android/app/build.gradle.kts`.

| Flavor | File env | Hậu tố applicationId | Trạng thái |
| :--- | :--- | :--- | :--- |
| `dev` | `app/env.dev` | `.dev` | ✅ có sẵn |
| `staging` | `app/env.stg` | `.stg` | ✅ có sẵn |
| `prod` | `app/env.prod` | *(không có)* | ❌ **bạn phải tự tạo** |

### Tạo `app/env.prod`

File này không nằm trong repo — secret production là của bạn. Chép danh sách **tên key** dưới đây (giá trị đã ẩn; xem `app/env.dev` để biết định dạng):

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

Phần lớn các key này xuất hiện trong Dart qua `EnvConstants` (`packages/core/common/lib/src/utils/env_constants.dart`), đọc bằng `String.fromEnvironment`:

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
> `APP_SCHEMA` và `APP_LINK_MODE` **không** được khai trong `EnvConstants`. Riêng `APP_SCHEMA` chỉ được phía Android dùng, dưới dạng `resValue` string trong `app/android/app/build.gradle.kts`. Vẫn phải giữ chúng trong file env dù Dart không đọc trực tiếp.

> [!WARNING]
> `app/env.dev` và `app/env.stg` hiện **đang được git theo dõi** — mẫu `*.env` trong `.gitignore` không khớp với tên file `env.dev`. Hãy coi nội dung của chúng là giá trị mẫu không bí mật, và đừng đặt credential production thật vào `app/env.prod` cho tới khi bạn xác nhận file đó đã được ignore.

---

## 6. Chạy app

### Từ dòng lệnh

```bash
flutter run -t app/lib/main.dart --flavor dev --dart-define-from-file=app/env.dev
```

### Build APK — bắt buộc `cd app` trước

```bash
cd app
flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

> [!CAUTION]
> Chạy `flutter build apk` từ thư mục gốc sẽ báo lỗi rất khó hiểu, ví dụ
> `Target file "lib\main.dart" not found`, hoặc
> `Flutter failed to read a file at ".../android/app/build.gradle"`.
> Project Android nằm ở `app/android`, nên lệnh build phải gọi từ trong `app/`.
> Lưu ý đường dẫn env cũng đổi theo: `env.dev` (tương đối với `app/`), không phải `app/env.dev`.

File kết quả nằm ở `app/build/app/outputs/flutter-apk/app-dev-debug.apk`.

### Từ VS Code

`.vscode/launch.json` đã định nghĩa sẵn ba cấu hình — **App (Dev)**, **App (Staging)**, **App (Prod)**. Chọn một trong panel Run and Debug. Mỗi cấu hình tự set `--flavor` và `--dart-define-from-file` (đường dẫn env tính tương đối với `app/`, vì đó là nơi Dart extension neo project).

---

## 7. Kiểm tra lại setup

```bash
flutter analyze                     # kỳ vọng: No issues found!
cd packages/core/storage && flutter test && cd ../../..
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
