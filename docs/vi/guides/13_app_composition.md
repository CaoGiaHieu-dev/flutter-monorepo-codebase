<!-- translated-from: docs/en/guides/13_app_composition.md@e5b7f09 -->
# Ghép và cấu hình một app

## Mục tiêu

Bạn đọc một app và biết nó ghép gì, đăng ký gì, mỗi platform bật gì và nó được phép can thiệp vào đâu. Bạn đổi bất kỳ điều gì trong số đó ở đúng một file sở hữu nó, thêm một platform, một capability, một pin, một ngôn ngữ hay một hook, và tạo app thứ ba bằng một lệnh.

## Điều kiện cần

- Một bản checkout đầy đủ build được — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).
- **Shell khởi động thế nào và resolve gì từ một app** — validate, đăng ký, DI, kiểm tra; catalog contract; các hook — [`../architecture/06_app_shell.md` § 2](../architecture/06_app_shell.md#2-vòng-đời-khởi-động). Guide này là phần cách làm; trang kia là phần vì sao.
- Các luật mà guide này phục vụ: RULE-80 (mọi thứ riêng của app được khai trong `apps/<id>/`), RULE-81 (mọi contract tuỳ chọn có một trạng thái được khai), RULE-82 (khác biệt giữa các platform là quyết định của app) — [`../reference/01_rules.md` § 21](../reference/01_rules.md#21-app-và-composition).

---

## 1. Đọc một app trong mười phút

Mỗi `apps/<id>/` mang theo lộ trình đọc của riêng nó, và điểm dừng đầu tiên được sinh từ manifest, nên không thể lệch với nó:

1. **`README.md`, vùng report** — app là gì: danh tính và flavor, các platform và thứ mỗi platform bật (mỗi ô ghi `giá trị (nguồn)`: `manifest`, `default` hoặc `derived: lý do`), composition theo thứ tự boot kèm lý do của từng nhóm, những gì shell resolve từ app (dòng bắt buộc, dòng tuỳ chọn, package nào hiện thực từng dòng, chuyện gì xảy ra nếu một dòng vắng mặt), và các quyết định cần xem lại trước khi phát hành.
2. **`app_manifest.yaml`** — phần khai báo, và composition: app *là* gì và nó *ghép* gì.
3. **`lib/app/app_profile.dart`** — vùng `facts` được sinh (manifest dưới dạng const Dart) và `appProfile` viết tay, tức shell *cư xử* ra sao với app này.
4. **`lib/app/app_hooks.dart`** — code app chạy tại các điểm cố định của quá trình boot.

```bash
dart tools/composer/composer.dart describe --app <id>   # báo cáo ra stdout (đúng nội dung vùng trong README)
dart tools/composer/composer.dart describe --catalog    # mọi key của manifest, catalog contract của shell, các mặc định suy ra
dart tools/composer/composer.dart list                  # mọi app: flavor, platform, nhóm DI
```

`describe --catalog` là tài liệu tham khảo về key: bảng key manifest nó in ra chính là bảng mà parser dùng để kiểm tra, nên guide này không chép lại và không thể lỗi thời so với nó.

## 2. Bốn kênh, một nguyên tắc

| Kênh | Chứa | Nằm ở |
|:--|:--|:--|
| Manifest | sự thật mà tool phải thấy trước khi code biên dịch: danh tính, flavor (và quyết định SSL pin của từng flavor), key env, platform và thứ mỗi platform bật, capability, composition | `app_manifest.yaml`, được sinh vào vùng `facts` của `lib/app/app_profile.dart` |
| Profile | shell cư xử thế nào: display, router, locale, theme, giới hạn mạng | `lib/app/app_profile.dart`, bên dưới vùng được sinh |
| Hook | code tại các điểm cố định của quá trình boot | `lib/app/app_hooks.dart` |
| Contract | interface của `core_di` mà app hoặc module đăng ký và shell resolve | module, và `lib/app/*.dart` cho những gì app tự hiện thực |

**Nguyên tắc:** manifest nói app **là** gì và chạy ở đâu; profile nói shell **cư xử** ra sao; hook là **code**. Mọi thứ theo từng platform nằm trong manifest, nên ma trận platform hiệu lực suy ra được và được in ra. Mọi thứ là một con số tinh chỉnh là Dart có kiểu, nên không có bộ máy YAML nào chen giữa bạn và một giá trị. Chọn kênh bằng cách hỏi một gate có phải đọc nó trước khi code biên dịch không (manifest), nó là một giá trị (profile) hay là hành vi (hook).

## 3. Manifest

```yaml
app:
  id: admin
  name: Codebase Admin
  entrypoint: lib/main.dart

flavors:                       # tập đóng: dev | staging | prod
  dev:
  staging:
  prod:                        # ssl_pinning chỉ ở nơi một platform đã khai báo có thể pin

env:
  BASE_URL: { required_in: [prod] }
  APP_NAME: { }                # tuỳ chọn: tiêu đề rơi về app.name

platforms:
  windows: { runner: scaffold }
  web:     { runner: scaffold }

capabilities:
  session: provided
  splash:  { state: absent, reason: "native splash is kept through boot" }
  # … mỗi contract tuỳ chọn của catalog một dòng

di_groups: [ … ]               # có thứ tự; `why:` ghi lại lý do của vị trí
modules:
  - { id: auth,     layers: [api, domain, data, feature] }
  - { id: settings, layers: [feature] }
```

| Mục | Nói gì | Được đọc bởi |
|:--|:--|:--|
| `app` | id (thư mục, package `<id>_app`, mọi `--app`), tên hiển thị, điểm vào | bước kiểm tra boot (id), tiêu đề `MaterialApp` (tên; `APP_NAME` ghi đè theo flavor), `describe`, `verify` (V12) |
| `flavors` | app được build thành những flavor nào trong `dev`, `staging`, `prod`; mỗi flavor có thể mang một quyết định `ssl_pinning` | facts, `validate` (`P02`), smoke test |
| `env` | các key `--dart-define` app đọc, và các flavor bắt buộc có từng key; `native_only: true` cho key chỉ Gradle hay Xcode đọc | `validate` (`P03`), V11 |
| `platforms` | app chạy ở đâu, và theo từng platform: `runner`, `splash`, `push`, `deep_links`, `orientation`, `window` | facts, `validate` (`P01`, `P05`), V5–V8 |
| `capabilities` | `provided`, hoặc `absent` kèm lý do, cho mọi contract tuỳ chọn mà shell resolve | `checkAppContract`, V2–V4, V14 |
| `di_groups`, `modules`, `extra_dependencies` | app ghép gì, theo thứ tự nào và vì sao | `sync`, `injection.dart`, path dependency của app |

Một key chỉ tồn tại cùng với code đọc nó: một test của tools fail khi một key nêu tên một consumer mà consumer đó không nhắc tới. `composer` từ chối `app.kind`, thứ không có gì đọc, kèm chỉ dẫn xoá dòng ấy.

Khi một platform bỏ `splash`, `push`, `deep_links` hay `orientation`, facts được sinh mang một mặc định suy ra, và báo cáo nói rõ nó từ đâu: `splash` là native trên iOS và, ở nơi khác, là Dart khi capability `splash` là `provided`; `push` bật khi `core_notifications` được ghép và hỗ trợ platform (không bao giờ trên web — không có service worker nào đi kèm); `deep_links` bật; `orientation` là `phones_portrait` (màn hình dưới ngưỡng điện thoại bị khoá dọc). Facts luôn mang tường minh mọi trường, nên một app không bao giờ phụ thuộc vào một mặc định trong Dart.

## 4. Profile

`lib/app/app_profile.dart` chứa vùng `facts` được sinh và, bên dưới nó, profile viết tay. Mỗi phần là một `const` có kiểu với mặc định bằng đúng hành vi của template, và phần nào bạn bỏ qua là mặc định đó. Chính type ghi rõ khoảng giá trị của nó; bảng này chỉ nói nhìn ở đâu và mặc định là gì.

| Phần | Type | Tinh chỉnh | Mặc định |
|:--|:--|:--|:--|
| `display` | `DisplayProfile` | khung thiết kế, chính sách scale theo từng lớp cửa sổ, chế độ chia đôi màn hình, trần cỡ chữ của hệ điều hành, ngưỡng điện thoại | 375×812, `expanded` vẽ 1:1, `textScaleMax: 2.0` (một `const` assert từ chối giá trị dưới 2.0 và trên 4.0), ngưỡng điện thoại 600 |
| `router` | `RouterProfile` | khi nào dùng entry location (`firstLaunch`, `always`, `never`), vị trí fallback | chỉ lần chạy đầu, tab đầu tiên |
| `locale` | `LocaleProfile` | các ngôn ngữ cung cấp (`supported`; null = mọi ARB mà template đi kèm), ngôn ngữ fallback và ngôn ngữ lần chạy đầu | mọi ngôn ngữ đã có, `en`, ngôn ngữ của thiết bị |
| `theme` | `ThemeProfile` | chế độ theme lần chạy đầu mở ra, ghi đè palette theo `PaletteToken` (ARGB) | chế độ theo hệ thống, palette của template |
| `network` | `NetworkProfile` | timeout connect, receive và send của HTTP client mặc định, header thêm, redirect | mỗi loại 20 giây, không header thêm, không redirect |

```dart
const AppProfile appProfile = AppProfile(
  facts: appFacts,
  display: DisplayProfile(
    designSize: SizeSpec(1440, 900),
    textScaleMax: 2.5,
    scale: {
      WindowClass.expanded: ScalePolicy.fixed(),
      WindowClass.large: ScalePolicy.fixed(),
    },
  ),
  locale: LocaleProfile(supported: ['vi'], fallback: 'vi', initial: 'vi'),
  theme: ThemeProfile(
    mode: ThemeModeSetting.dark,
    dark: {PaletteToken.primary: 0xFFF97316},
  ),
  network: NetworkProfile(
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 60),
    headers: {'x-client': 'reports'},
  ),
);
```

Điều một phần không được phép nói thì bị từ chối ở nơi có thể: `DisplayProfile(textScaleMax: 1.5)` không biên dịch được (`const_eval_throws_exception` — RULE-38), một header của `NetworkProfile` tên `authorization`, `cookie`, `set-cookie`, `proxy-authorization` hoặc `content-type` làm client mặc định ném lỗi lúc boot (RULE-66), và một `LocaleProfile` không cung cấp ngôn ngữ nào đã có hoặc có fallback mà nó không cung cấp thì ném lỗi lúc boot, nêu tên trường. `shadow` và `scrim` của palette, cùng hai gradient, không ghi đè được: gradient suy ra từ `primary`, `primaryContainer`, `info` và `error`.

Sau khi sửa profile, chạy `composer sync`: § 5 của báo cáo trong README in ra các section app đã đặt, và `verify` (V13) đọc lại file để giữ nó cập nhật. `test/app_profile_test.dart` của mỗi app là nơi bạn khẳng định điều mình đã đổi, để một lần sửa sau làm nó dịch chuyển sẽ thấy rõ. Mỗi section có nghĩa gì với một màn hình: [`09_localization_theming.md`](09_localization_theming.md) (`locale`, `theme`) và [`11_design_system.md`](11_design_system.md) (`display`, `theme`).

## 5. Hook

```dart
// lib/app/app_hooks.dart
import 'package:core_common/core_common.dart'; // AppRuntime, WindowFacts
import 'package:platform_app_shell/platform_app_shell.dart';

const ShellHooks appHooks = ShellHooks(
  beforeDependencies: _initCrashReporting, // hàm top-level: const
  configureWindow: _sizeTheWindow,
);

Future<void> _initCrashReporting(AppRuntime runtime) async {
  // ví dụ SentryFlutter.init — chạy trước DI; chưa resolve được gì.
}

Future<void> _sizeTheWindow(AppRuntime runtime, WindowFacts window) async {
  // Áp window.initial / window.min bằng plugin cửa sổ của chính app.
}
```

Hook nào nhắc tới `AppRuntime` hoặc `WindowFacts` cần import `core_common`, mà file được sinh không có sẵn. Gõ `const ShellHooks(` là IDE liệt kê bảy hook, mỗi hook được ghi rõ chạy khi nào và không được làm gì: `onError`, `onNonFatalError`, `beforeDependencies`, `afterBoot`, `navigatorObservers`, `redirect`, `configureWindow` (bảng nằm trong [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md#các-hook)). Một hook ném lỗi được báo cáo như mọi lỗi trong zone của app và dừng boot tại nơi nó chạy. Template không đi kèm plugin cửa sổ nào (RULE-74: catalog chỉ có thêm khi một app dùng tới), nên app nào muốn đặt kích thước cửa sổ desktop thì tự thêm plugin vào dependency của mình.

## 6. Contract: shell đòi gì ở một app

Shell resolve các contract qua một catalog duy nhất, `SHELL_CONTRACTS` (`platform/shell/app_shell/lib/src/utils/shell_contract_constants.dart`): các dòng **bắt buộc** do chính các package của shell đăng ký — app ghép nhóm `shell` và `ui` là có — và các dòng **tuỳ chọn** do app hoặc module đóng góp (`describe --catalog` in bảng thật). App khai từng dòng tuỳ chọn, và `describe --catalog` liệt kê chúng cùng việc shell làm khi thiếu từng dòng:

```yaml
capabilities:
  session: provided      # một bundle: ISessionState, ISessionGateway, ISessionRefreshListenable, ISignInLocation
  error_reporter:
    state: absent
    reason: "no crash backend chosen: errors are printed and sent nowhere (RULE-67)"
```

Sự vắng mặt là một quyết định kèm lý do: `composer verify` từ chối lý do rỗng, `TODO` hoặc `TBD` (V14), và báo cáo liệt kê một `error_reporter` hay `analytics` đang `absent` ở mục *các quyết định cần xem lại trước khi phát hành*. Một contract mà app tự hiện thực — một crash reporter — là một class dưới `lib/app/`:

```dart
@LazySingleton(as: IErrorReporter)
class CrashlyticsErrorReporter implements IErrorReporter { … }
```

Sau đó, khai nó là `provided`. Khai một contract mà code không đăng ký, hoặc đăng ký một contract mà manifest nói là `absent`, đều fail ở ba nơi: `composer verify` (V3, tĩnh, nêu tên file), smoke test (`checkAppContract`, từ graph app dựng) và lúc boot của flavor dev, staging hay bản debug, nơi `checkAppContract` chạy sau DI.

Tab có thêm một quy tắc. Một app ghép **hai** `INavDestinationModule` trở lên cần một `dashboard` (`IDashboardRouteModule`, mẫu là `feature_dashboard`): nó vẽ khung chrome để chuyển giữa các tab, và thiếu nó thì chỉ tab đầu truy cập được. `checkAppContract` báo điều đó (`C12`) trong smoke test và ở lần boot debug. Một tab thì chạy tốt không cần dashboard (`apps/admin`). Để thêm dashboard: `- { id: dashboard, layers: [feature] }` dưới `modules:`, `dashboard: provided` dưới `capabilities:`, rồi `composer sync`.

Thứ app phải đăng ký cho một package nó ghép — `FirebaseOptions` cho `core_notifications`, mỗi flavor một cái — được liệt kê trong báo cáo ở mục *This app must provide*, và V10 fail nếu thiếu. Thiết lập native (`google-services.json`, `aps-environment`) được ghi ở đó và không được kiểm tra.

## 7. Công thức

### Thêm một platform

1. Xem cái gì chặn nó: mục *Not targeted — and what blocks it* của báo cáo nêu tên mọi package đã ghép mà `platforms:` trong pubspec không liệt kê nó (`core_database` không có web, `core_notifications` không có Windows hay Linux).
2. Khai nó, runner còn chờ được tạo: `platforms.<p>: { runner: scaffold }`, rồi `dart tools/composer/composer.dart sync --app <id>`.
3. Tạo runner một lần, bằng dòng lệnh báo cáo in ra, ví dụ `cd apps/<id> && flutter create --platforms=windows --org com.example --project-name <id>_app .` (hãy đặt reverse domain của riêng bạn vào `--org`: platform nào có application ID hoặc bundle ID thì dựng nó từ giá trị này), rồi đổi khai báo thành `runner: committed`. Runner khai `committed` cần có thư mục của nó, runner `scaffold` thì không được có (V6). Với `android` hay `ios`, runner mà `flutter create` viết ra chưa có flavor nào: nối chúng trước lần build `--flavor` đầu tiên ([Flavor native cho runner mobile mới](#flavor-native-cho-runner-mobile-mới)); V15 từ chối một runner đã commit mà thiếu một flavor.
4. Đặt thứ platform bật, nếu mặc định chưa đúng: `push`, `deep_links`, `orientation`, và với platform desktop là `window: { initial: [1440, 900], min: [1024, 700] }`, cần hook `configureWindow` (không có thì `P05`). Một platform tắt push hay deep link sẽ log một dòng nêu tên key và không khởi tạo gì.
5. Chạy `composer verify` và smoke test. Trên web không có tuỳ chọn `--flavor`: truyền `--dart-define=APP_FLAVOR=<flavor>` — công cụ Flutter từ chối `FLUTTER_APP_FLAVOR`, tên riêng của framework, và shell chỉ đọc `APP_FLAVOR` trên web.

### Flavor native cho runner mobile mới

`flutter create` viết một runner không có flavor nào, nên `flutter run --flavor dev` fail trên nó, và `composer verify` (V15) từ chối một runner Android hay iOS đã commit mà thiếu một flavor mà `flavors:` khai — nó nêu tên flavor và mục này. `apps/mobile` là bản tham chiếu; mọi thứ dưới đây được chép từ file của nó. `flavors:` là một tập đóng (`dev`, `staging`, `prod`), và mỗi tên đồng thời là flavor Gradle, scheme Xcode và khoá của file env:

| Flavor | `applicationIdSuffix` Android | `PRODUCT_BUNDLE_IDENTIFIER` iOS | File env | Scheme Xcode, configuration |
|:--|:--|:--|:--|:--|
| `dev` | `.dev` | `<id>.dev` | `env.dev` | `dev`, `Debug-dev` / `Profile-dev` / `Release-dev` |
| `staging` | `.stg` | `<id>.staging` | `env.stg` | `staging`, `Debug-staging` / `Profile-staging` / `Release-staging` |
| `prod` | không có | `<id>` | `env.prod` | `prod`, `Debug-prod` / `Profile-prod` / `Release-prod` |

1. **File env.** Tạo `apps/<id>/env.dev`, `env.stg` và `env.prod` với các key mà `env:` khai (V11); `composer new` chỉ ghi `env.dev`, còn `env.prod` bị gitignore trong `apps/mobile`. Truyền một file bằng `--dart-define-from-file=env.<file>`.
2. **Android, `android/app/build.gradle.kts`.** Chép từ `apps/mobile`: `buildFeatures { resValues = true }`; map `envs` ở đầu file, giải mã `-Pdart-defines`; trong `defaultConfig`, các dòng `resValue("string", "WEB_DOMAIN", …)` và `resValue("string", "app_name", …)` mà `AndroidManifest.xml` đọc dưới dạng `@string/WEB_DOMAIN` và `@string/app_name`; và các flavor, mỗi flavor một `DEEP_LINK_SCHEME` — scheme của intent filter deep link trong manifest (`@string/DEEP_LINK_SCHEME`), để ba bản cài không tranh nhau một liên kết:

```kotlin
flavorDimensions += "environment"

productFlavors {
    create("dev") {
        dimension = "environment"
        applicationIdSuffix = ".dev"
        resValue("string", "DEEP_LINK_SCHEME", "myapp-dev")
    }
    create("staging") {
        dimension = "environment"
        applicationIdSuffix = ".stg"
        resValue("string", "DEEP_LINK_SCHEME", "myapp-stg")
    }
    create("prod") {
        dimension = "environment"
        resValue("string", "DEEP_LINK_SCHEME", "myapp")
    }
}
```

   `apps/mobile` còn cho mỗi flavor một `signingConfig` (một file properties cho mỗi flavor, cùng một chốt chặn từ chối bản release staging hay prod bị ký bằng khoá dev công khai — [`02_fastlane_release.md` § 4](../operations/02_fastlane_release.md)) và một thư mục `android/app/src/<flavor>/` chứa `google-services.json` và icon launcher của flavor đó; hãy chép chúng khi app có ký hoặc dùng Firebase.
3. **iOS, Xcode** (mở `ios/Runner.xcworkspace`). *Project → Info → Configurations*: nhân đôi `Debug`, `Profile` và `Release` cho mỗi flavor rồi đặt tên bản sao là `Debug-dev`, `Profile-dev`, `Release-dev`, v.v. `Debug-<flavor>` lấy `Flutter/Debug.xcconfig` làm base configuration, `Profile-<flavor>` và `Release-<flavor>` lấy `Flutter/Release.xcconfig` (các file do Pods sinh ra đến sau `pod install`). Trên target *Runner*, đặt theo từng configuration `PRODUCT_BUNDLE_IDENTIFIER` (bảng trên), `APP_DISPLAY_NAME` và `DEEP_LINK_SCHEME`, mà `Info.plist` đọc dưới dạng `$(APP_DISPLAY_NAME)` và trong `CFBundleURLSchemes`; `apps/mobile` còn đặt `LAUNCH_SCREEN_STORYBOARD` theo flavor. *Product → Scheme → Manage Schemes*: nhân đôi `Runner` thành `dev`, `staging` và `prod`, tick **Shared** (chúng được lưu dưới `ios/Runner.xcodeproj/xcshareddata/xcschemes/`, nơi V15 đọc) và trong từng scheme trỏ Run và Test vào `Debug-<flavor>`, Profile vào `Profile-<flavor>`, Analyze vào `Debug-<flavor>` và Archive vào `Release-<flavor>`. Chép "Run Script" ở *Build → Pre-actions* của `dev.xcscheme` trong `apps/mobile` vào mỗi scheme: nó ghi `Flutter/Environment.xcconfig` từ `$DART_DEFINES` (`WEB_DOMAIN`, `APP_LINK_MODE`), mà `Flutter/Debug.xcconfig` và `Flutter/Release.xcconfig` include bằng `#include?`; thêm cùng dòng include đó vào cả hai file của bạn.
4. **CocoaPods, `ios/Podfile`.** CocoaPods coi một configuration nó không được báo là release, nên hãy nêu tên từng cái, như `apps/mobile/ios/Podfile` làm, rồi chạy `pod install` trong `ios/`:

```ruby
project 'Runner', {
  'Debug' => :debug, 'Debug-dev' => :debug, 'Debug-staging' => :debug, 'Debug-prod' => :debug,
  'Profile' => :release, 'Profile-dev' => :release, 'Profile-staging' => :release, 'Profile-prod' => :release,
  'Release' => :release, 'Release-dev' => :release, 'Release-staging' => :release, 'Release-prod' => :release,
}
```

5. **fastlane, nếu bạn phát hành app bằng nó.** Các lane nằm trong `apps/mobile/fastlane` và đọc flavor từ `Config.yaml`; hãy chép thư mục cho app khác và đặt hai key trong `Config.yaml` của nó: `valid_flavors` liệt kê các flavor bạn đã nối và `app_bundle_ids` giữ ID gốc cho mỗi platform. Hậu tố và tên file env được cố định trong `apps/mobile/fastlane/modules/helpers.rb` (`get_bundle_id_with_suffix`, `get_dart_define_file`): các lane nối thêm hậu tố của bảng trên (`.dev`, `.stg` trên Android, `.staging` trên iOS, prod không có gì) rồi truyền `env.dev`, `env.stg` hoặc `env.prod`. Một hậu tố khác với hậu tố trong Gradle hay Xcode sẽ upload nhầm application.
6. **Kiểm tra.** `dart tools/composer/composer.dart verify` (V15 đối chiếu các flavor Gradle, các scheme shared và ba configuration mỗi flavor với `flavors:`), rồi `cd apps/<id> && flutter run --flavor dev --dart-define-from-file=env.dev`. V15 đọc file như văn bản — nó không thấy được base configuration sai hay thiếu mục Podfile, chỉ lần build mới thấy.

### Pin chứng chỉ

Pinning chỉ chạy trên Android và iOS — trên web trình duyệt sở hữu TLS, và plugin pinning không có implementation cho desktop — nên key chỉ bắt buộc ở nơi một platform đã khai báo pin được, và bị từ chối ở nơi không platform nào pin được. Thay quyết định của staging hoặc prod trong manifest:

```yaml
flavors:
  prod:
    ssl_pinning: { pins: ["<leaf spki sha256 base64>", "<backup spki sha256 base64>"] }
```

Ít nhất hai pin, mỗi pin là base64 của 32 byte (V9). Cách tính: [`08_networking.md` § 10](08_networking.md#10-bật-ssl-pinning). Một flavor cố ý không pin thì ghi `ssl_pinning: { disabled: "lý do" }`, và báo cáo liệt kê nó ở mục các quyết định cần xem lại.

### Thêm hoặc gỡ một module

Thêm dòng vào `modules:` rồi chạy `sync`. Nếu module đăng ký một contract có trong catalog, `verify` giờ sẽ nói ra — *declared absent but ISessionState is registered at …* — và bạn khai nó là `provided`. Gỡ một module thì `verify` nêu tên key vừa mất nơi cung cấp và in dòng `absent` để dán — hoặc chạy `dart tools/composer/composer.dart reconcile --reason "module x removed"`, lệnh khai `absent` mọi capability `provided`, trong mọi manifest app, mà không còn gì đăng ký nữa (lý do là chữ của bạn, rồi đến thứ shell làm khi thiếu nó), rồi `sync`. `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` chạy cả hai cho bạn. Chiều ngược lại vẫn là việc của bạn: một module bạn thêm vào mà đăng ký một contract app đã khai `absent` sẽ khiến `verify` đòi `provided`.

### Cung cấp ngôn ngữ khác, đổi palette hay giới hạn

Đặt `locale`, `theme` hoặc `network` trong `appProfile` (mục 4). Một ngôn ngữ mới là một ARB trong `core_base_ui` và trong từng feature ([`09_localization_theming.md`](09_localization_theming.md)); app không nêu danh sách `supported` thì cung cấp mọi ngôn ngữ đã có, app nêu một danh sách thì giữ danh sách đó. Một `LocaleProfile.fallback` mà danh sách không chứa sẽ bị từ chối lúc boot.

### Thêm một hook

Thêm trường vào `appHooks` (mục 5). Một giá trị vừa với manifest hoặc profile thì thuộc về đó, nơi một gate đọc được.

## 8. App thứ ba bằng một lệnh

```bash
dart tools/composer/composer.dart new reports --name "Codebase Reports" --platforms web,windows --modules auth,settings
```

Lệnh render `tools/composer/app_template/` vào `apps/<id>/`: manifest, `pubspec.yaml`, một `README.md` có lộ trình đọc, `lib/main.dart`, `lib/app/app_profile.dart` và `app_hooks.dart`, `lib/di/injection.dart`, một smoke test và một profile test, `env.dev` và một `.gitignore` (nó bỏ qua các file Firebase theo từng project: `firebase_options_*.dart`, `firebase.json` và `google-services.json`, giống `apps/admin/.gitignore`). Nó suy ra `capabilities:` từ những gì các module được yêu cầu đăng ký — `provided` ở nơi có thứ đăng ký contract, còn lại là `absent` kèm việc shell làm khi thiếu nó làm lý do, không bao giờ là `TODO` — rồi chạy `sync` và `verify`, nên app qua Gate 0 ngay.

- Nó từ chối, và không ghi gì, với một id đã là một app, một platform mà module được yêu cầu chặn (`--platforms web` với module mở một database), một module hay platform lạ, hoặc một tên sẽ làm hỏng các file nó được ghi vào.
- Nó **không bao giờ chạy `flutter create`**: mỗi platform là `runner: scaffold`, và lệnh in ra dòng cần chạy khi bạn muốn có runner.
- Nó không ghép `core_notifications` (push cần `FirebaseOptions` và một nhóm `notifications` — hãy theo mẫu của `apps/mobile`), và một app liên kết `core_database` thì chép các test double trong smoke test của `apps/mobile`.

Sau đó, từ gốc repo: `flutter pub get`, `dart run build_runner build --workspace`, `cd apps/<id> && flutter test`. Hai file bạn sửa để app khác đi là `apps/<id>/app_manifest.yaml` và `apps/<id>/lib/app/app_profile.dart`; không có gì dưới `platform/`, `modules/` hay app khác bị đổi.

## 9. Gate 0 kiểm tra những gì

`composer verify` sinh lại mọi file được sinh và fail khi có sai lệch (V13, cũng từ chối code nằm ngoài hai vùng được sinh của `lib/di/injection.dart`), đồng thời đối chiếu khai báo với mã nguồn: từ vựng và khoảng giá trị (V1, V14), trạng thái capability so với thứ các package đã ghép và app đăng ký (V2–V4), các công tắc platform so với thứ app ghép và thứ mỗi package hỗ trợ (V5–V8), quyết định pin theo flavor (V9), thứ một package đã ghép cần app đăng ký (V10), các file env (V11), điểm vào và smoke test (V12), các runner native (V6, và V15: một runner Android hay iOS đã commit có một flavor cho mỗi flavor mà manifest khai), thứ tự nhóm DI (V16) và nút workspace duy nhất (V17, RULE-16). `dart tools/composer/composer.dart describe --catalog` in danh sách kiểm tra thật; hướng dẫn này không sao chép nó.

Đọc một thông báo từ trái sang phải: `<file>: <key>: <vấn đề> — <cách sửa>`. Phép quét đằng sau V3 và V10 đọc mã nguồn, không đọc graph — một `getIt.register…` viết tay vô hình với nó — nên `checkAppContract` vẫn là thẩm quyền cuối. V3, V10, V11, V12, V15, V16 và V17 (cùng code nằm ngoài các vùng của `injection.dart` ở V13) làm `verify` fail trong khi `sync` chỉ cảnh báo và vẫn ghi, để một chỉnh sửa dở dang vẫn sinh lại được; V7 và V8 từ chối ở cả hai, trước khi ghi bất cứ thứ gì.

## 10. Thứ còn bị khoá, và một lưu ý về DI

Muốn đổi những thứ này phải sửa package dùng chung, cho mọi app: breakpoint, component theme, page transition, chuỗi interceptor và chính sách retry mặc định của `Dio`, trang 404, màu shadow và scrim, channel và icon của push, allow-list của deep link, giới hạn của logger, overlay system-UI và tuỳ chọn secure-storage. Mục cuối của báo cáo liệt kê chúng.

Thay một type do shell sở hữu bằng thứ tự đăng ký là không được hỗ trợ. `enableRegisteringMultipleInstancesOfOneType()` — được sinh vào `configureDependencies` — khiến GetIt giữ đăng ký **đầu tiên** của một type, nên đăng ký của app thắng một type đăng ký ở nhóm `after` và thua một type ở nhóm `before`, nơi bản gốc eager vẫn chạy. Profile và hook là các điểm gắn xoá đi lý do người ta từng nhờ tới nó.

---

## Kiểm tra

```bash
dart tools/composer/composer.dart verify                 # Gate 0 — khai báo, các vùng sinh ra, mã nguồn
dart tools/composer/composer.dart describe --app <id>    # báo cáo đọc lên đúng như bạn muốn
dart tools/arch_check/check.dart                         # R16 (catalog đầy đủ), R17 (nhánh theo platform)
cd apps/<id> && flutter test                             # smoke test (checkAppContract cho từng flavor) và profile test
```

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `verify`: `declared provided but no composed package or apps/<id>/lib registers …` | Một module đã bị gỡ, hoặc chưa từng được ghép, trong khi manifest nói `provided` | Thêm module, hoặc khai contract là `absent` kèm lý do (thông báo in sẵn dòng cần dán) |
| `verify`: `declared absent but … is registered at <file>:<line>` | Một package đã ghép đăng ký nó | Khai nó là `provided`, hoặc thôi ghép thứ đăng ký nó |
| `verify`: `out of date: … (facts)` | Manifest đã đổi, hoặc vùng được sinh bị sửa tay | `dart tools/composer/composer.dart sync --app <id>`; không bao giờ sửa vùng `composer:managed` (RULE-16) |
| `verify`: `flavors.prod.ssl_pinning: decide …` | Một flavor của app có platform Android hoặc iOS chưa có quyết định pin | `pins: [...]` hoặc `disabled: "lý do"` (ở trên) |
| `verify`: `flavors.<f>: declared, but … has no productFlavor / scheme / build configuration named …` | Một runner mobile đã commit thiếu một flavor mà manifest khai | Nối nó (công thức ở trên), hoặc xoá flavor đó khỏi `flavors:` |
| `verify`: `<package> does not support <platform>` | Một package đã ghép, hoặc package nó liên kết, thiếu platform đó | Chỉ khai các platform mà mọi package được liên kết hỗ trợ, hoặc thôi phụ thuộc vào nó |
| Boot dừng: *`<id>` is running on `<platform>`, which its manifest does not declare* | Platform không nằm dưới `platforms:` | Khai nó (ở trên), chạy trên một platform đã khai, hoặc `--dart-define=ALLOW_UNDECLARED_PLATFORM=true` để chạy thử nhanh |
| Boot dừng: `P03` trên bản release | Một `--dart-define` bắt buộc đang rỗng | Truyền `--dart-define-from-file=env.<flavor>` |
| Boot dừng trên platform desktop: `P05` | `window` được khai báo mà không đặt hook `configureWindow` | Thêm hook (mục 5), hoặc bỏ `window` |
| Smoke test: `C02` / `C03` | Graph không khớp với khai báo | Test nêu tên contract — sửa manifest hoặc composition |
| `new` từ chối | Id đã tồn tại, hoặc một platform bị module chặn | Thông báo nêu rõ cái nào; không có gì được ghi |
| `flutter analyze`: `const_eval_throws_exception` ở một `DisplayProfile` | `textScaleMax` dưới 2.0, hoặc một `SizeSpec` có cạnh không dương | Dùng 2.0 trở lên (RULE-38) |

## Liên quan

- Luật: RULE-80, RULE-81, RULE-82, RULE-16 (vùng được sinh), RULE-48 (pinning), RULE-63 (smoke test), RULE-67 (reporter) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — quá trình boot, catalog và các hook, và vì sao
- [`05_di.md`](05_di.md) — đăng ký một type và ghép một package
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — `composer`, `arch_check` R16/R17 và các tool khác
- Skill: `.claude/skills/configure_app`
