<!-- translated-from: docs/en/guides/13_app_composition.md@8240431 -->
# Ghép và cấu hình một app

## Mục tiêu

Bạn đọc một app và biết nó ghép gì, đăng ký gì, mỗi platform bật gì và nó được phép can thiệp vào đâu. Bạn đổi bất kỳ điều gì trong số đó ở đúng một file sở hữu nó, thêm, eject hay gỡ một platform và chứng minh nó boot được, thêm một capability, một pin, một ngôn ngữ hay một hook, và tạo app thứ ba bằng một lệnh.

## Điều kiện cần

- Một bản checkout đầy đủ build được — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).
- **Shell khởi động thế nào và resolve gì từ một app** — validate, đăng ký, DI, kiểm tra; catalog contract; các hook — [`../architecture/06_app_shell.md` § 2](../architecture/06_app_shell.md#2-vòng-đời-khởi-động). Guide này là phần cách làm; trang kia là phần vì sao.
- Các luật mà guide này phục vụ: RULE-80 (mọi thứ riêng của app được khai trong `apps/<id>/`), RULE-81 (mọi contract tuỳ chọn có một trạng thái được khai), RULE-82 (khác biệt giữa các platform là quyết định của app), RULE-83 (mọi platform đã khai đều tái tạo được và boot được) — [`../reference/01_rules.md` § 21](../reference/01_rules.md#21-app-và-composition).

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
  org: com.example             # reverse domain của bạn: application / bundle id của mọi runner được sinh
  entrypoint: lib/main.dart

flavors:                       # tập đóng: dev | staging | prod
  dev:                         # ssl_pinning mặc định là disabled
  staging:
    ssl_pinning: { disabled: "no SPKI pins provisioned yet" }
  prod:                        # ở đây bắt buộc có quyết định: windows pin được
    ssl_pinning: { disabled: "no SPKI pins provisioned yet" }

env:
  BASE_URL: { required_in: [prod] }
  APP_NAME: { }                # tuỳ chọn: tiêu đề rơi về app.name

platforms:
  windows: { runner: scaffold }  # do `composer runners` sinh, git bỏ qua
  macos:   { runner: scaffold }
  linux:   { runner: scaffold }  # secure_storage suy ra memory_fallback
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
| `app` | id (thư mục, package `<id>_app`, mọi `--app`), tên hiển thị, `org` (reverse domain mà `flutter create --org` nhận, mặc định `com.example`), điểm vào | bước kiểm tra boot (id), tiêu đề `MaterialApp` (tên; `APP_NAME` ghi đè theo flavor), `composer runners` (`org`), `describe`, `verify` (V12) |
| `flavors` | app được build thành những flavor nào trong `dev`, `staging`, `prod`; mỗi flavor có thể mang một quyết định `ssl_pinning`. Mọi app đều khai `dev`: CI boot mọi platform ở `dev`, với `env.dev` | facts, `validate` (`P02`), smoke test, V12 |
| `env` | các key `--dart-define` app đọc, và các flavor bắt buộc có từng key; `native_only: true` cho key chỉ Gradle hay Xcode đọc | `validate` (`P03`), V11 |
| `platforms` | app chạy ở đâu, và theo từng platform: `runner`, `splash`, `push`, `deep_links`, `secure_storage`, `orientation`, `window` | facts, `validate` (`P01`, `P05`), `composer runners`, V5–V8, V13 (vùng `.gitignore`) |
| `capabilities` | `provided`, hoặc `absent` kèm lý do, cho mọi contract tuỳ chọn mà shell resolve | `checkAppContract`, V2–V4, V14 |
| `di_groups`, `modules`, `extra_dependencies` | app ghép gì, theo thứ tự nào và vì sao | `sync`, `injection.dart`, path dependency của app |

Một key chỉ tồn tại cùng với code đọc nó: một test của tools fail khi một key nêu tên một consumer mà consumer đó không nhắc tới. `composer` từ chối `app.kind`, thứ không có gì đọc, kèm chỉ dẫn xoá dòng ấy.

**Runner** của mỗi platform là `committed` (thư mục được track, và bạn sở hữu mọi file native trong đó) hoặc `scaffold` (do `dart tools/composer/composer.dart runners` sinh, được liệt kê trong vùng `composer:managed:runners` của `apps/<id>/.gitignore`, không bao giờ commit). Một runner được sinh là template của Flutter cộng một bộ patch cố định, nên nó không mang native flavor, không thiết lập push và không URL scheme. Mỗi trạng thái mang gì và ai giữ nó: [`../reference/01_rules.md` § 21](../reference/01_rules.md#21-app-và-composition) (RULE-83); cách chuyển qua lại: § 7.

Khi một platform bỏ `splash`, `push`, `deep_links`, `secure_storage` hay `orientation`, facts được sinh mang một mặc định suy ra, và báo cáo nói rõ nó từ đâu (khớp đầu tiên thắng):

| Key | Giá trị suy ra |
|:--|:--|
| `splash` | native trên iOS; ở nơi khác là Dart khi capability `splash` là `provided`, còn lại là native (frame đầu được giữ đến khi boot xong) |
| `push` | tắt nơi `core_notifications` không được ghép, trên web (không có messaging service worker nào đi kèm), trên runner được sinh (không có `google-services.json`, không có `aps-environment`) và nơi `composition.push_platforms` của nó (`android`, `ios`, `macos`, `web`) thiếu platform; còn lại bật |
| `deep_links` | tắt trên web (thanh địa chỉ chính là deep link, và router đọc nó), trên runner được sinh (không URL scheme nào được đăng ký) và trên runner desktop đã commit cho đến khi scheme của nó được đăng ký; bật với runner Android hay iOS đã commit |
| `secure_storage` | `memory_fallback` trên Linux (một session có thể không chạy Secret Service); `required` ở nơi khác |
| `orientation` | `phones_portrait` (màn hình dưới ngưỡng điện thoại bị khoá dọc) |

`push: true` và `deep_links: true` bị từ chối trên runner được sinh, `push: true` ngoài `push_platforms` và `deep_links: true` trên web (V8). `secure_storage` nói secure store làm gì khi platform không có store nào: `required` dừng boot (B01) mà không xoá gì, `memory_fallback` giữ các giá trị secure của lần chạy này trong bộ nhớ, còn preference được niêm bằng một key mà store không còn trả lại được thì nằm nguyên trên đĩa trong khi lần chạy dùng giá trị mặc định — mỗi điều được nói một lần trong một WARNING. Chi tiết nằm ở [`06_storage.md`](06_storage.md). Facts luôn mang tường minh mọi trường, nên một app không bao giờ phụ thuộc vào một mặc định trong Dart.

## 4. Profile

`lib/app/app_profile.dart` chứa vùng `facts` được sinh và, bên dưới nó, profile viết tay. Mỗi phần là một `const` có kiểu với mặc định bằng đúng hành vi của template, và phần nào bạn bỏ qua là mặc định đó. Chính type ghi rõ khoảng giá trị của nó; bảng này chỉ nói nhìn ở đâu và mặc định là gì.

| Phần | Type | Tinh chỉnh | Mặc định |
|:--|:--|:--|:--|
| `display` | `DisplayProfile` | khung thiết kế, chính sách scale theo từng lớp cửa sổ, chế độ chia đôi màn hình, trần cỡ chữ của hệ điều hành, ngưỡng điện thoại | 375×812, `expanded` vẽ 1:1, `textScaleMax: 2.0` (một `const` assert từ chối giá trị dưới 2.0 và trên 4.0), ngưỡng điện thoại 600 |
| `router` | `RouterProfile` | khi nào dùng entry location (`firstLaunch`, `always`, `never`), vị trí fallback | chỉ lần chạy đầu, tab đầu tiên |
| `locale` | `LocaleProfile` | các ngôn ngữ cung cấp (`supported`; null = mọi ARB mà template đi kèm), ngôn ngữ fallback và ngôn ngữ lần chạy đầu | mọi ngôn ngữ đã có, `en`, ngôn ngữ của thiết bị |
| `theme` | `ThemeProfile` | chế độ theme lần chạy đầu mở ra, ghi đè palette theo `PaletteToken` (ARGB) | chế độ theo hệ thống, palette của template |
| `network` | `NetworkProfile` | timeout connect, receive và send của HTTP client mặc định, header thêm, redirect, và `authorizedHosts` (các host ngoài base URL của API được nhận bearer token) | mỗi loại 20 giây, không header thêm, không redirect, không host được uỷ quyền thêm |

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
    authorizedHosts: {'files.example.com'},
  ),
);
```

Điều một phần không được phép nói thì bị từ chối ở nơi có thể: `DisplayProfile(textScaleMax: 1.5)` không biên dịch được (`const_eval_throws_exception` — RULE-38), một header của `NetworkProfile` tên `authorization`, `cookie`, `set-cookie`, `proxy-authorization` hoặc `content-type` làm client mặc định ném lỗi lúc boot (RULE-66), và một `LocaleProfile` không cung cấp ngôn ngữ nào đã có hoặc có fallback mà nó không cung cấp thì ném lỗi lúc boot, nêu tên trường. `shadow` và `scrim` của palette, cùng gradient, không ghi đè được: gradient suy ra từ `primary` và `primaryContainer`.

`authorizedHosts` là một tập tên host trần (`files.example.com`: không scheme, port hay path). Bearer token chỉ đi tới host của `BASE_URL` và các host này; một request tới host khác (CDN, URL storage đã ký sẵn) ra đi mà không có thông tin đăng nhập ([`08_networking.md`](08_networking.md) § 6).

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

1. Xem cái gì chặn nó: mục *Not targeted — and what blocks it* của báo cáo nêu tên mọi package đã ghép mà `platforms:` trong pubspec không liệt kê nó. Hiện không package nào được phát hành khai `platforms:` — mỗi cái đều link được trên cả sáu; một package bọc SDK chỉ chạy native thì sẽ khai, và composer V7 khi đó từ chối platform.
2. Khai nó, `platforms.<p>: { runner: scaffold }`, và đặt `app.org` thành reverse domain của bạn nếu nó vẫn là `com.example` — application hay bundle ID của mọi runner được sinh đều bắt đầu bằng nó. Rồi `dart tools/composer/composer.dart sync --app <id>`: facts, báo cáo trong README và vùng `runners` của `apps/<id>/.gitignore` (một dòng `/<p>/`) được ghi lại.
3. Sinh runner: `dart tools/composer/composer.dart runners --app <id>`. Nó chạy `flutter create --no-pub` trong một thư mục tạm với `app.org` và tên pubspec của app, chỉ chép `<p>/` vào app, chạy `flutter pub get` trong app để runner có các file plugin của nó, và áp bộ patch (entitlement network-client của macOS; với app chạy web có link `core_database` thì thêm `sqlite3.wasm` và `drift_worker.js` — [`07_database.md`](07_database.md#13-trên-web)). git bỏ qua thư mục đó, và `dart tools/workspace_setup/configure.dart` sinh lại nó ở mọi bản clone mới (bước cuối cùng của nó).
4. Đặt thứ platform bật, nếu giá trị suy ra (mục 3) chưa đúng: `secure_storage`, `orientation`, và với platform desktop là `window: { initial: [1440, 900], min: [1024, 700] }`, cần hook `configureWindow` (không có thì `P05`). Push và deep link vẫn tắt trên runner được sinh — hãy eject nó trước (bên dưới). Một platform tắt push hay deep link sẽ log một dòng nêu tên key và không khởi tạo gì.
5. Chứng minh nó: `composer verify`, smoke test (nó boot graph trên mọi platform đã khai trừ web) và boot test trên platform đó (công thức kế tiếp). Một runner được sinh không có native flavor, nên bản build nêu flavor bằng `--dart-define=APP_FLAVOR=<flavor>`: shell đọc nó ở nơi công cụ Flutter không đặt flavor — web và mọi runner được sinh — và `--flavor` của công cụ vẫn thắng nơi có cả hai. (Công cụ từ chối `FLUTTER_APP_FLAVOR`, tên riêng của framework, làm define.) Define này được tính là một khai báo: ngoài web, một bản debug với `--dart-define=APP_FLAVOR=dev` có thể bỏ qua kiểm tra chứng chỉ cho một server tự ký ở local, như `--flavor dev` làm, và một bản build không khai flavor nào thì giữ kiểm tra bật và log một ERROR nêu tên cả hai cách ([`08_networking.md`](08_networking.md)). Trên web trình duyệt sở hữu TLS: cả hai đều không áp dụng, và lúc boot log điều đó một lần ở mức INFO.

### Chạy và boot một platform

Từ thư mục của app, khi các runner của nó đã có:

```bash
flutter run -d chrome --web-port 5310 --dart-define-from-file=env.dev --dart-define=APP_FLAVOR=dev   # admin; mobile dùng 5320
flutter run -d linux --dart-define-from-file=env.dev --dart-define=APP_FLAVOR=dev                     # hoặc macos, windows
flutter test integration_test/boot_test.dart -d linux --dart-define-from-file=env.dev --dart-define=APP_FLAVOR=dev
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/boot_test.dart \
  -d web-server --browser-name=chrome --headless --chrome-binary=<chrome> \
  --dart-define-from-file=env.dev --dart-define=APP_FLAVOR=dev
```

- **Boot test** (`integration_test/boot_test.dart`, RULE-83) chạy `main()` và đợi tối đa 60 s cho `debugBootStage()` báo `BootStage.shown`: app đã mount và các frame của nó tới được engine. Frame đầu vẫn bị hoãn (trang trắng) hay một màn hình lỗi boot sẽ làm nó fail kèm stage nó thấy. Runner Android hay iOS đã commit dùng `--flavor dev` thay cho define, trên thiết bị hay simulator (`-d <device>`).
- **Boot web** cần một chromedriver cùng bản build với Chrome mà nó điều khiển, lắng nghe ở cổng 4444 (`chromedriver --port=4444 &`), và `--chrome-binary` nêu tên đúng Chrome đó: công cụ không đọc `CHROME_EXECUTABLE` cho thiết bị `web-server`. CI lấy cặp khớp nhau từ `browser-actions/setup-chrome`.
- **Boot Linux** cần một màn hình và một Secret Service. CI chạy nó hai lần dưới `xvfb-run`: trong `dbus-run-session` với một `gnome-keyring-daemon` đã mở khoá, và với `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/bus`, nơi `secure_storage: memory_fallback` giữ các giá trị secure trong bộ nhớ. Các bước chính xác là job `platforms` của `.github/workflows/pr_quality_check.yml` ([`../operations/01_cicd.md`](../operations/01_cicd.md)).
- **Cổng web ổn định.** `localStorage`, IndexedDB và file storage của trình duyệt thuộc về một origin, và cổng là một phần của origin: cổng ngẫu nhiên của `flutter run -d chrome` khiến mỗi lần chạy là một lần khởi chạy đầu tiên. Admin dùng 5310 và mobile dùng 5320; `.vscode/launch.json` có *Admin (Web, Dev)*, *Admin (Desktop, Dev)*, *Mobile (Web, Dev)* và *Mobile (Linux, Dev)* với các cờ này.
- **Sau khi nâng Flutter**, sinh lại các runner từ template mới: `dart tools/composer/composer.dart runners --app <id> --force`. Lần chạy thứ hai không đổi gì thì không ghi gì và in `apps/<id>: up to date (<platforms>) — nothing written`.

### Eject một runner

Hãy sở hữu một runner được sinh khi app cần thiết lập native mà bộ patch không ghi — native flavor, file Firebase, URL scheme, signing, tiêu đề cửa sổ hay metadata PWA:

1. Đổi khai báo thành `platforms.<p>: { runner: committed }` và chạy `dart tools/composer/composer.dart sync --app <id>`. Vùng `runners` bỏ `/<p>/`, nên git thấy thư mục. Với runner Android hay iOS đã commit deep link suy ra bật, và push suy ra bật ở bất cứ đâu `core_notifications` được ghép và gửi push trên platform đó (Android, iOS, macOS), trong khi thư mục vẫn là thứ `flutter create` đã viết: lần sync đó cảnh báo một lần và nêu tên các dòng cần viết, `push: false` và `deep_links: false` dưới `platforms.<p>`, mà bạn giữ cho đến khi thiết lập native có và rồi xoá chúng.
2. `git add apps/<id>/<p>` và commit.
3. Làm thiết lập native. Với `android` hay `ios`, nối flavor trước ([Flavor native cho runner mobile mới](#flavor-native-cho-runner-mobile-mới)): V15 giờ giữ runner theo `flavors:`, và các bản build nêu flavor bằng `--flavor <f>`. Về deep link trên runner desktop, xem [Deep link trên runner đã commit](#deep-link-trên-runner-đã-commit).
4. Từ đó `composer runners` từ chối platform này: nêu tên nó bằng `--platform` là một lỗi, và `--force` không bao giờ đụng tới nó.

### Gỡ một platform

1. Xoá dòng `platforms.<p>` khỏi `apps/<id>/app_manifest.yaml`.
2. `dart tools/composer/composer.dart sync --app <id>`: nó ghi lại facts, báo cáo và vùng `.gitignore`, và cảnh báo rằng `apps/<id>/<p>/` giờ là runner của một platform mà app không khai (V6 — Flutter sẽ build nó, vấn đề boot `P01`).
3. Xoá thư mục: `rm -rf apps/<id>/<p>`.
4. `dart tools/composer/composer.dart verify` — nó fail khi thư mục còn tồn tại, và pass khi thư mục đã mất.

### Flavor native cho runner mobile mới

`flutter create` — và vì thế cả một runner mà `composer runners` đã sinh và bạn vừa eject — viết một runner không có flavor nào, nên `flutter run --flavor dev` fail trên nó, và `composer verify` (V15) từ chối một runner Android hay iOS đã commit mà thiếu một flavor mà `flavors:` khai — nó nêu tên flavor và mục này. Một runner được sinh (`scaffold`) không bị V15 giữ: nó không có native flavor, và các bản build của nó truyền `--dart-define=APP_FLAVOR=<f>`. `apps/mobile` là bản tham chiếu; mọi thứ dưới đây được chép từ file của nó. `flavors:` là một tập đóng (`dev`, `staging`, `prod`), và mỗi tên đồng thời là flavor Gradle, scheme Xcode và khoá của file env:

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

### Deep link trên runner đã commit

`deep_links` chỉ suy ra `true` với runner Android hay iOS đã commit — runner của `apps/mobile` đăng ký link của chúng (intent filter và `CFBundleURLSchemes` của công thức native flavor). Một runner desktop đã commit suy ra `false`: `app_links` (một dependency của `platform_app_shell`) chỉ giao được link ở đó khi runner đăng ký một scheme với hệ điều hành, và đó là việc native mà template không làm. Hãy đăng ký nó, rồi đặt `deep_links: true` dưới `platforms.<p>`:

| Platform | Runner cần gì |
|:--|:--|
| Linux | một file `.desktop`, cài cùng app, có `MimeType=` liệt kê `x-scheme-handler/<scheme>`, và ứng dụng GTK trong `linux/runner/` được gắn cờ `G_APPLICATION_HANDLES_OPEN`, để lần khởi chạy thứ hai chuyển URI của nó cho instance đang chạy |
| Windows | một protocol key cho scheme trong registry, do installer của bạn ghi, có `shell\open\command` khởi động app với URI, và xử lý single-instance trong `windows/runner/` để link tới được cửa sổ đang chạy |
| macOS | scheme dưới `CFBundleURLTypes` trong `macos/Runner/Info.plist` |

Các chỉnh sửa chính xác nằm trong README của package `app_links` cho phiên bản của nó; không điều nào ở đây được một test ở repo này chạy thử. `deep_links: true` vẫn bị từ chối trên web, nơi thanh địa chỉ là link, và trên runner được sinh (V8).

### Hosting cho web

Một bản build web là một thư mục file tĩnh (`flutter build web --release`, hoặc kèm `--wasm`); hosting nó là việc của server. Shell và template mong đợi gì ở nó:

- **Một sub-path.** Phục vụ dưới `/admin/` cần `flutter build web --base-href /admin/`. Các asset database được mở bằng URI tương đối, phân giải theo `<base href>`, nên chúng đi theo.
- **URL dạng path.** Router dùng URL hash (`/#/settings`). Để có URL dạng path, hãy gọi `usePathUrlStrategy()` (từ `flutter_web_plugins`) trong `ShellHooks.beforeDependencies`, và để server rewrite mọi path về `index.html`; không có rewrite thì reload một deep path là 404.
- **Không CDN.** Mặc định bản build nạp CanvasKit và các font mặc định từ server của Google; `--no-web-resources-cdn` đóng gói chúng, cho mạng chặn các host đó.
- **Một secure context.** `https` hay `localhost`: bản hiện thực web của secure store cần crypto API của trình duyệt, mà chỉ secure context mới có. Trình duyệt sở hữu TLS, nên không có gì được pin.
- **`application/wasm`.** Server gửi `sqlite3.wasm` (và các file `.wasm` của bản build `--wasm`) với content type đó, nếu không trình duyệt từ chối biên dịch nó.
- **Lưu trữ database** là bất cứ thứ gì trình duyệt cung cấp; lúc boot log nói thứ nào (`Web database "<file>": <implementation>`), kèm các tính năng trình duyệt mà nó thiếu.

### Pin chứng chỉ

Pinning chạy trên Android, iOS và các platform desktop — trên web trình duyệt sở hữu TLS — nên key bắt buộc ở nơi một platform đã khai báo pin được, và bị từ chối ở nơi không platform nào pin được. Trên desktop plugin chỉ thấy certificate leaf, nên hãy pin key của leaf và một key leaf dự phòng. Thay quyết định của staging hoặc prod trong manifest:

```yaml
flavors:
  prod:
    ssl_pinning: { pins: ["<leaf spki sha256 base64>", "<backup spki sha256 base64>"] }
```

Ít nhất hai pin, mỗi pin là base64 của 32 byte (V9). Cách tính: [`08_networking.md` § 10](08_networking.md#10-bật-ssl-pinning). Một flavor cố ý không pin thì ghi `ssl_pinning: { disabled: "lý do" }`, và báo cáo liệt kê nó ở mục các quyết định cần xem lại.

Các pin áp dụng cho **mọi host mà isolate chính chạm tới qua `dart:io`**, không chỉ API của bạn: một CDN ảnh, một host font hay endpoint SDK bên thứ ba có certificate không khớp pin nào cũng fail bắt tay TLS, nên hãy kiểm tra các host đó trước khi khai báo `pins:` (danh sách kiểm tra ở [`08_networking.md` § 10](08_networking.md#10-bật-ssl-pinning)). Bearer token là nửa còn lại của cùng quyết định: nó chỉ đi tới host của `BASE_URL` và `NetworkProfile.authorizedHosts` (mục 4), nên một API chia trên nhiều domain phải khai các host thêm ở đó — và phủ chúng bằng pin.

### Thêm hoặc gỡ một module

Thêm dòng vào `modules:` rồi chạy `sync`. Nếu module đăng ký một contract có trong catalog, `verify` giờ sẽ nói ra — *declared absent but ISessionState is registered at …* — và bạn khai nó là `provided`. Gỡ một module thì `verify` nêu tên key vừa mất nơi cung cấp và in dòng `absent` để dán — hoặc chạy `dart tools/composer/composer.dart reconcile --reason "module x removed"`, lệnh khai `absent` mọi capability `provided`, trong mọi manifest app, mà không còn gì đăng ký nữa (lý do là chữ của bạn, rồi đến thứ shell làm khi thiếu nó), rồi `sync`. `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` chạy cả hai cho bạn. Chiều ngược lại vẫn là việc của bạn: một module bạn thêm vào mà đăng ký một contract app đã khai `absent` sẽ khiến `verify` đòi `provided`.

### Cung cấp ngôn ngữ khác, đổi palette hay giới hạn

Đặt `locale`, `theme` hoặc `network` trong `appProfile` (mục 4). Một ngôn ngữ mới là một ARB trong `core_base_ui` và trong từng feature ([`09_localization_theming.md`](09_localization_theming.md)); app không nêu danh sách `supported` thì cung cấp mọi ngôn ngữ đã có, app nêu một danh sách thì giữ danh sách đó. Một `LocaleProfile.fallback` mà danh sách không chứa sẽ bị từ chối lúc boot.

### Thêm một hook

Thêm trường vào `appHooks` (mục 5). Một giá trị vừa với manifest hoặc profile thì thuộc về đó, nơi một gate đọc được.

## 8. App thứ ba bằng một lệnh

```bash
dart tools/composer/composer.dart new reports --name "Codebase Reports" --platforms web,windows --modules auth,settings --org com.acme
```

Lệnh render `tools/composer/app_template/` vào `apps/<id>/`: manifest, `pubspec.yaml`, một `README.md` có lộ trình đọc, `lib/main.dart`, `lib/app/app_profile.dart` và `app_hooks.dart`, `lib/di/injection.dart`, một smoke test và một profile test, boot test `integration_test/boot_test.dart` cùng web driver `test_driver/integration_test.dart` của nó (với `integration_test` là dev dependency), `env.dev` và một `.gitignore` (nó bỏ qua các file Firebase theo từng project: `firebase_options_*.dart`, `firebase.json` và `google-services.json`, giống `apps/admin/.gitignore`, và kết thúc bằng vùng `runners`, mỗi platform một dòng). `--org` được ghi thành `app.org` (mặc định `com.example`). Nó suy ra `capabilities:` từ những gì các module được yêu cầu đăng ký — `provided` ở nơi có thứ đăng ký contract, còn lại là `absent` kèm việc shell làm khi thiếu nó làm lý do, không bao giờ là `TODO` — rồi chạy `sync` và `verify`, nên app qua Gate 0 ngay.

- Nó từ chối, và không ghi gì, với một id đã là một app, một platform mà module được yêu cầu chặn (một package được liên kết có `platforms:` trong pubspec thiếu nó — không package nào được phát hành làm vậy), một module hay platform lạ, hoặc một tên sẽ làm hỏng các file nó được ghi vào.
- Nó **không sinh runner nào**: mỗi platform là `runner: scaffold`, và lệnh in ra các bước kế tiếp — `dart tools/composer/composer.dart runners --app <id>`, rồi một dòng boot test cho mỗi platform.
- Smoke test boot mọi platform đã khai trừ web, nhân với mọi flavor; một app chỉ chạy web thì boot graph của nó một lần cho mỗi flavor với facts của web thay vào, và boot test chứng minh chính web. Một app link `core_database` đã có sẵn test double `path_provider`.
- Nó không ghép `core_notifications` (push cần `FirebaseOptions`, một nhóm `notifications` và một runner đã commit — hãy theo mẫu của `apps/mobile`).

Sau đó, từ gốc repo: `flutter pub get`, `dart run build_runner build --workspace`, `cd apps/<id> && flutter test`, rồi `dart tools/composer/composer.dart runners --app <id>` và boot test của từng platform ([Chạy và boot một platform](#chạy-và-boot-một-platform)). Hai file bạn sửa để app khác đi là `apps/<id>/app_manifest.yaml` và `apps/<id>/lib/app/app_profile.dart`; không có gì dưới `platform/`, `modules/` hay app khác bị đổi.

## 9. Gate 0 kiểm tra những gì

`composer verify` sinh lại mọi file được sinh và fail khi có sai lệch (V13, cũng từ chối code nằm ngoài hai vùng được sinh của `lib/di/injection.dart`), đồng thời đối chiếu khai báo với mã nguồn: từ vựng và khoảng giá trị (V1, V14), trạng thái capability so với thứ các package đã ghép và app đăng ký (V2–V4), các công tắc platform so với thứ app ghép và thứ mỗi package hỗ trợ (V5–V8), quyết định pin theo flavor (V9), thứ một package đã ghép cần app đăng ký (V10), các file env (V11), điểm vào, smoke test (nó lặp trên `appFacts.platforms`, và biến lặp chạm tới `debugAppPlatformOverride`, `registerAppProfile` và `checkAppContract`), boot test (nó gọi `debugBootStage(`), web driver của app chạy web, và flavor `dev` cùng `env.dev` (V12), các runner native (V6: thư mục của runner đã commit tồn tại, và không có thư mục nào cho platform mà `platforms:` không khai; V15: một runner Android hay iOS đã commit có một flavor cho mỗi flavor mà manifest khai), vùng `runners` của `.gitignore` (V13), thứ tự nhóm DI (V16) và nút workspace duy nhất (V17, RULE-16). `dart tools/composer/composer.dart describe --catalog` in danh sách kiểm tra thật; hướng dẫn này không sao chép nó.

Đọc một thông báo từ trái sang phải: `<file>: <key>: <vấn đề> — <cách sửa>`. Phép quét đằng sau V3 và V10 đọc mã nguồn, không đọc graph — một `getIt.register…` viết tay vô hình với nó — nên `checkAppContract` vẫn là thẩm quyền cuối. V3, V10, V11, V12, V15, V16 và V17 (cùng code nằm ngoài các vùng của `injection.dart` ở V13, và thư mục runner không được khai ở V6) làm `verify` fail trong khi `sync` chỉ cảnh báo và vẫn ghi, để một chỉnh sửa dở dang vẫn sinh lại được và một platform có thể được gỡ; V7 và V8 từ chối ở cả hai, trước khi ghi bất cứ thứ gì, V6 cũng vậy với một runner đã commit mà thiếu thư mục.

## 10. Thứ còn bị khoá, và một lưu ý về DI

Muốn đổi những thứ này phải sửa package dùng chung, cho mọi app: breakpoint, component theme, page transition, chuỗi interceptor và chính sách retry mặc định của `Dio`, trang 404, màu shadow và scrim, channel và icon của push, allow-list của deep link, giới hạn của logger, overlay system-UI và tuỳ chọn secure-storage (việc store làm khi không có store của platform là theo từng platform: `secure_storage`). Mục cuối của báo cáo liệt kê chúng.

Thay một type do shell sở hữu bằng thứ tự đăng ký là không được hỗ trợ. `enableRegisteringMultipleInstancesOfOneType()` — được sinh vào `configureDependencies` — khiến GetIt giữ đăng ký **đầu tiên** của một type, nên đăng ký của app thắng một type đăng ký ở nhóm `after` và thua một type ở nhóm `before`, nơi bản gốc eager vẫn chạy. Profile và hook là các điểm gắn xoá đi lý do người ta từng nhờ tới nó.

---

## Kiểm tra

```bash
dart tools/composer/composer.dart verify                 # Gate 0 — khai báo, các vùng sinh ra, mã nguồn
dart tools/composer/composer.dart describe --app <id>    # báo cáo đọc lên đúng như bạn muốn
dart tools/arch_check/check.dart                         # R16 (catalog đầy đủ), R17 (nhánh theo platform), R22 (import chỉ-native)
cd apps/<id> && flutter test                             # smoke test (checkAppContract cho từng platform và flavor) và profile test
dart tools/composer/composer.dart runners --app <id>     # các runner được sinh; lần chạy thứ hai nói "up to date"
cd apps/<id> && flutter test integration_test/boot_test.dart -d linux --dart-define-from-file=env.dev --dart-define=APP_FLAVOR=dev
```

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `verify`: `declared provided but no composed package or apps/<id>/lib registers …` | Một module đã bị gỡ, hoặc chưa từng được ghép, trong khi manifest nói `provided` | Thêm module, hoặc khai contract là `absent` kèm lý do (thông báo in sẵn dòng cần dán) |
| `verify`: `declared absent but … is registered at <file>:<line>` | Một package đã ghép đăng ký nó | Khai nó là `provided`, hoặc thôi ghép thứ đăng ký nó |
| `verify`: `out of date: … (facts)` | Manifest đã đổi, hoặc vùng được sinh bị sửa tay | `dart tools/composer/composer.dart sync --app <id>`; không bao giờ sửa vùng `composer:managed` (RULE-16) |
| `verify`: `flavors.prod.ssl_pinning: decide …` | Một flavor của app có platform pin được (Android, iOS, Windows, macOS, Linux) chưa có quyết định pin | `pins: [...]` hoặc `disabled: "lý do"` (ở trên) |
| `verify`: `flavors.<f>: declared, but … has no productFlavor / scheme / build configuration named …` | Một runner mobile đã commit thiếu một flavor mà manifest khai | Nối nó (công thức ở trên), hoặc xoá flavor đó khỏi `flavors:` |
| `verify`: `<package> does not support <platform>` | Một package đã ghép, hoặc package nó liên kết, thiếu platform đó | Chỉ khai các platform mà mọi package được liên kết hỗ trợ, hoặc thôi phụ thuộc vào nó |
| Boot dừng: *`<id>` is running on `<platform>`, which its manifest does not declare* (`P01`) | Platform không nằm dưới `platforms:` — thường là thư mục runner bị bỏ lại sau khi gỡ, mà Flutter vẫn build | Khai nó và chạy `composer runners` (ở trên), xoá thư mục, chạy trên một platform đã khai, hoặc `--dart-define=ALLOW_UNDECLARED_PLATFORM=true` để chạy thử nhanh |
| `verify`: *`apps/<id>/<p>/`: a `<p>` runner, but `platforms:` does not declare `<p>`* | Thư mục runner của một platform không được khai (V6) | Xoá thư mục, hoặc khai platform |
| `verify` hoặc `sync`: `platforms.<p>.push` / `.deep_links`: *… the `<p>` runner is generated (`runner: scaffold`) …* | Một công tắc mà runner được sinh không mang được (V8) | Xoá key, hoặc eject runner và làm thiết lập native của nó trước |
| `sync` cảnh báo: *`apps/<id>/<p>/` is ejected (`runner: committed`) but is still the runner `flutter create` wrote* | Push hay deep link giờ suy ra bật cho runner đã eject (deep link trên Android hay iOS; push nơi `core_notifications` gửi push: Android, iOS, macOS) | Viết các dòng `push: false` / `deep_links: false` mà nó nêu cho đến khi thiết lập native có ([Eject một runner](#eject-một-runner)) |
| `composer runners`: `` `flutter pub get` failed `` | Không có mạng, hoặc một package thiếu trong pub cache dưới `--offline` | Chạy lại `composer runners --app <id>` khi có mạng: runner vẫn thiếu các file plugin của nó, nên lần chạy sau thử lại; cho đến lúc đó hãy build không có `--no-pub` |
| `composer runners`: `web database assets missing` (một cảnh báo) | `sqlite3.wasm` không tải được (offline, proxy) và không có bản cache | Chạy `dart tools/composer/composer.dart runners --app <id> --platform web` khi có mạng, hoặc tự đặt một `sqlite3.wasm` khớp vào ([`07_database.md`](07_database.md#13-trên-web)) |
| Một lần chạy Linux dừng ở prompt keyring, hoặc treo trước frame đầu | Keyring của session bị khoá hoặc còn mới, và libsecret đợi prompt trên platform thread | Trả lời prompt — không code nào bỏ qua được; trong CI, mở khoá một keyring trước hoặc trỏ session bus vào hư không (§ 7) |
| Cài đặt bị reset trong một lần chạy Linux, và log nói *Secure storage is unavailable* | Không có Secret Service trong session đó, dưới `secure_storage: memory_fallback` | Không mất gì: các giá trị đã lưu vẫn nằm trên đĩa và quay lại khi một Secret Service trả lời ([`06_storage.md`](06_storage.md)) |
| `flutter drive` trên web: *session not created* hoặc lỗi phiên bản | chromedriver không phải bản build của Chrome mà nó điều khiển | Dùng một cặp khớp nhau, và truyền `--chrome-binary` nêu tên đúng Chrome đó |
| `flutter test --platform chrome` không khởi động được Chrome | Công cụ không tìm thấy Chrome nào nó chạy được | Đặt `CHROME_EXECUTABLE` (khi chạy bằng root, trỏ tới một wrapper thêm `--no-sandbox`) |
| Boot test: *no first screen within 60 s* | Vẫn đang boot, hoặc frame đầu bị giữ — một màn hình trắng | Đọc log phía trên nó; một lần boot không bao giờ kết thúc thường đợi một prompt keyring hay một server |
| Boot dừng: `P03` trên bản release | Một `--dart-define` bắt buộc đang rỗng | Truyền `--dart-define-from-file=env.<flavor>` |
| Boot dừng: `P02` trên web hoặc một runner được sinh | Bản build không nêu flavor nào, nên bản release là `prod`, mà manifest có thể không khai | Truyền `--dart-define=APP_FLAVOR=<flavor>` (ở đó không có `--flavor`) |
| Boot kết thúc ở một màn hình có nút **Retry** và mã vấn đề `B01` | Chính lần boot đã ném lỗi — `configureDependencies`, một initializer hay một hook — không phải khai báo sai | Đọc lỗi (hiện ở flavor dev hoặc staging và ở bản debug, profile), sửa nguyên nhân, bấm Retry; cùng lỗi đó đã được báo cáo tới `onError` và `IErrorReporter` |
| Boot dừng trên platform desktop: `P05` | `window` được khai báo mà không đặt hook `configureWindow` | Thêm hook (mục 5), hoặc bỏ `window` |
| Smoke test: `C02` / `C03` | Graph không khớp với khai báo | Test nêu tên contract — sửa manifest hoặc composition |
| `new` từ chối | Id đã tồn tại, hoặc một platform bị module chặn | Thông báo nêu rõ cái nào; không có gì được ghi |
| `flutter analyze`: `const_eval_throws_exception` ở một `DisplayProfile` | `textScaleMax` dưới 2.0, hoặc một `SizeSpec` có cạnh không dương | Dùng 2.0 trở lên (RULE-38) |

## Liên quan

- Luật: RULE-80, RULE-81, RULE-82, RULE-83 (runner và boot test), RULE-16 (vùng được sinh), RULE-48 (pinning), RULE-63 (smoke test), RULE-67 (reporter) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — quá trình boot, catalog và các hook, và vì sao
- [`05_di.md`](05_di.md) — đăng ký một type và ghép một package
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — `composer` (kể cả `runners`), `arch_check` R16/R17/R22 và các tool khác
- [`../operations/01_cicd.md`](../operations/01_cicd.md) — job `platforms` và `platforms_full.yml`
- Skill: `.claude/skills/configure_app`
