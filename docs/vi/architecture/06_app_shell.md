<!-- translated-from: docs/en/architecture/06_app_shell.md@a5b62df -->
# App Shell (`platform/shell/` + `apps/<id>/`)

Tài liệu này trả lời câu hỏi **"từ lúc chạm icon đến khi thấy màn hình đầu tiên, chuyện gì xảy ra, và ai lắp ráp mọi thứ lại?"**. Đọc xong bạn sẽ gỡ được lỗi khởi động, thêm được adapter cho shell, và hiểu vì sao thứ tự các nhóm DI trong `app_manifest.yaml` không hề tuỳ tiện.

Shell được tách làm hai, có chủ đích:

- **`apps/<id>/`** là **điểm lắp ráp (composition root)** — nơi duy nhất được phép phụ thuộc mọi tầng, và nơi duy nhất biết danh sách đầy đủ các module. Nó chỉ chứa những gì thực sự khác nhau giữa các app, ngoài ra không có gì khác.
- **`platform/shell/app_shell/`** (`platform_app_shell`) là mọi thứ app nào cũng cần và lẽ ra phải copy: boot scope, lắp ráp router, material wrapper và các provider cấp app. Các adapter hạ tầng của nó — storage adapter, `AppBootStorage` và `NetworkConfigImpl` — nằm ngay cạnh trong **`platform/shell/adapters/`** (`platform_shell_adapters`), để package shell chỉ giữ phần lắp ráp, UI và state cấp app; `platform_app_shell` phụ thuộc package adapter, không bao giờ ngược lại. Cả hai đều không import module nào — `arch_check` R1 giữ điều đó, vì cả hai là package `platform/`.

Trước khi tách, thêm app thứ hai nghĩa là copy 1.369 dòng qua 24 file. Giờ một app là một manifest nói nó là gì và nó ghép gì, một profile cùng các hook nói shell cư xử ra sao với nó, một `injection.dart` được sinh ra, một `main.dart` chỉ gọi một lệnh, và những gì định danh chính nó — ở app mẫu là Firebase options. App thứ ba là `dart tools/composer/composer.dart new <id> --platforms <a,b> --modules <x,y>`: lệnh này viết toàn bộ những thứ đó và để manifest cùng `lib/app/app_profile.dart` là hai file bạn sửa ([`../guides/13_app_composition.md`](../guides/13_app_composition.md)).

---

## 1. Cái gì nằm ở đâu

```
apps/mobile/                         điểm lắp ráp
├── app_manifest.yaml                app là gì (danh tính, flavor, env, platform, capability) và nó ghép gì
├── README.md                        lộ trình đọc + một báo cáo được sinh ra: app, trong mười phút
├── lib/
│   ├── main.dart                    một lời gọi: runShellApp(profile: …, hooks: …, configureDependencies: …)
│   ├── app/
│   │   ├── app_profile.dart         vùng `facts` được sinh + `appProfile` viết tay (tinh chỉnh có kiểu)
│   │   └── app_hooks.dart           code của app tại các điểm cố định của quá trình boot (ShellHooks)
│   ├── di/injection.dart            do composer sinh — không bao giờ sửa tay
│   └── firebase/firebase_module.dart FirebaseOptions của app này (file options bị git-ignore)
├── test/                            di_smoke_test.dart, app_profile_test.dart
├── android/  ios/  fastlane/        project native và lane phát hành
└── env.dev  env.stg                 giá trị theo flavor (env.prod bạn tự tạo)

platform/shell/app_shell/lib/              dùng chung cho mọi app
├── di/module.dart                   @InjectableInit.microPackage — AppRouter, DeeplinkProvider
└── src/
    ├── bootstrap.dart               runShellApp — error hook, kiểm tra profile, DI, splash, init
    ├── shell_hooks.dart             ShellHooks — code của app tại các điểm cố định của quá trình boot
    ├── boot/boot_error_app.dart     màn hình hiện ra khi boot bị dừng
    ├── composition/                 shell_contracts.dart (catalog), composition_check.dart
    ├── main_scope.dart              splash → init → chuyển sang root
    ├── root_app.dart                MaterialApp có router
    ├── app_material_wrapper.dart    cấu hình MaterialApp dùng chung
    ├── navigation/app_router.dart   lắp ráp GoRouter
    ├── provider/                    DeeplinkProvider
    └── widgets/                     NavigatorWrapperWidget, UndefinedRouteWidget

platform/shell/adapters/lib/               adapter hạ tầng của shell (platform_shell_adapters)
├── di/
│   ├── module.dart                  @InjectableInit.microPackage — đứng đầu nhóm DI `shell`
│   └── network_binding_module.dart  binding SslPinningConfig
└── src/
    ├── theme_storage_impl.dart      IThemeStorage    → StorageValue<ThemeMode>
    ├── language_storage_impl.dart   ILanguageStorage → StorageValue<String>
    ├── app_boot_storage.dart        cờ khởi động    → StorageValue<bool>
    ├── network_config_impl.dart     NetworkConfig
    └── utils/                       storage key do adapter sở hữu

platform/foundation/kernel/lib/src/profile/   những gì một app khai báo (platform_kernel)
├── app_profile.dart                 AppProfile + validate (P01–P05)
├── app_facts.dart                   AppFacts — platform, flavor, env key, capability, SSL pinning
├── platform_facts.dart              PlatformFacts — những gì một platform bật cho app
├── ssl_pinning.dart                 SslPinning, SslPinningPolicy
├── display_profile.dart  router_profile.dart  locale_profile.dart
│   theme_profile.dart  network_profile.dart   các phần có thể tinh chỉnh
└── register_app_profile.dart        registerAppProfile — gắn từng phần theo đúng type của nó
```

### App thứ hai: `apps/admin`

[`apps/admin`](../../../apps/admin/README.md) là cùng shell này ghép một tập con khác — `auth` và `settings`, không có dashboard, splash, onboarding, home hay Firebase — trên các platform khác: web và desktop, chưa cái nào được tạo (`runner: scaffold`). `lib/` của nó là `main.dart`, `app/` và `di/injection.dart` được sinh ra. Mọi lookup tuỳ chọn trong package này đều thiếu đóng góp ở đó, được khai là `absent` kèm lý do trong manifest của nó, nên các fallback mô tả bên dưới có một bản ghép thật dựa vào chúng; smoke test của nó boot graph cho mọi flavor. CI không build binary nào của nó.

---

## 2. Vòng đời khởi động

Mọi app truyền cho `runShellApp` ba thứ — `AppProfile`, `ShellHooks` và `configureDependencies` được sinh cho nó — và shell lo phần còn lại, theo đúng thứ tự dưới đây. Profile là bắt buộc: một app không nói mình chạy ở đâu và cung cấp gì chính là vấn đề mà phần khai báo sinh ra để xoá bỏ.

```mermaid
sequenceDiagram
    autonumber
    participant M as runShellApp()
    participant V as AppProfile.validate()
    participant DI as configureDependencies()
    participant C as checkAppContract()
    participant P as AppInitializer.initBeforeRunApp()
    participant S as MainScope.run()
    participant N as FlutterNativeSplash
    participant I as AppInitializer.init()
    participant R as RootApp / AppRouter

    M->>M: runZonedGuarded(...)
    M->>M: WidgetsFlutterBinding.ensureInitialized()
    M->>V: platform và flavor của bản build này
    Note over V: P01–P05, Dart thuần, trước mọi DI —<br/>có vấn đề thì hiện màn hình boot-error và dừng
    M->>M: registerAppProfile(...) + ShellHooks
    M->>DI: beforeDependencies, rồi await configureDependencies()
    Note over DI: mọi module được đăng ký<br/>trước khi có bất kỳ UI nào
    DI-->>M: container sẵn sàng
    M->>C: các capability đã khai báo so với graph
    Note over C: C01–C09 — flavor dev hoặc staging, hay bản debug,<br/>thì dừng; bản release production thì log rồi đi tiếp
    M->>P: logger + HttpOverrides.global (pinning)
    Note over P: đồng bộ, trước mọi widget —<br/>tree wrapper của splash có thể đã mở một kết nối
    M->>S: MainScope(splashScreen, root, initService).run()

    alt splashScreen == null (iOS, hoặc không ghép splash)
        S->>N: preserve()
        S->>I: await initService()
        S->>N: remove()
        S->>R: runApp(root)
    else splashScreen != null
        S->>N: remove()
        S->>S: runApp(AppMaterialWrapper(home: splash))
        S->>S: await endOfFrame
        S->>I: await initService()
        S->>R: widget.value = root  (AnimatedSwitcher fade)
    end

    R->>R: AppRouter.router dựng lười khi truy cập lần đầu
```

### Từng bước

Trình tự này nằm trong `runShellApp()` ([`platform/shell/app_shell/lib/src/bootstrap.dart`](../../../platform/shell/app_shell/lib/src/bootstrap.dart)); `main.dart` của app chỉ gọi nó với profile, hook và `configureDependencies` được sinh của chính app đó.

1. **`runZonedGuarded`** bọc toàn bộ để lỗi bất đồng bộ không bắt được vẫn được báo cáo thay vì mất tăm.
2. **`WidgetsFlutterBinding.ensureInitialized()`** — bắt buộc trước mọi lời gọi plugin — rồi **`installShellErrorHooks`**, dồn mọi lỗi không bắt được về một chỗ (xem [Lỗi và crash reporting](#lỗi-và-crash-reporting) bên dưới). Nó chạy trước `configureDependencies`, nên lỗi DI cũng được báo cáo.
3. **Validate, trước DI.** `AppProfile.validate` chạy cho platform và flavor của bản build này. Bất kỳ vấn đề nào cũng dừng boot ở màn hình boot-error và `configureDependencies` không bao giờ được gọi ([Hồ sơ app](#hồ-sơ-app)).
4. **Đăng ký, vẫn trước DI.** `registerAppProfile` gắn profile cùng các phần của nó, và shell gắn `ShellHooks` của app, mỗi thứ theo đúng type của nó. Tiếp theo `hooks.beforeDependencies` chạy.
5. **`await configureDependencies()`** chạy *trước* `MainScope`. Đến lúc widget đầu tiên build, cả container đã phân giải xong.
6. **Kiểm tra, sau DI.** `checkAppContract` đối chiếu khai báo `capabilities:` của app với những gì graph đã đăng ký.
7. **`AppInitializer.initBeforeRunApp()`** cấu hình logger và cài `HttpOverrides.global` — certificate pinning theo quyết định manifest dành cho flavor này, hoặc bypass khi build debug + flavor `dev` — một cách đồng bộ, trước khi có bất kỳ widget nào. Không thể đợi tới `initService`: splash đã được bọc trong `IAppTreeWrapper` của mọi feature, nên một controller tạo ở đó (`AuthProvider` của auth, khôi phục phiên bằng một lần refresh token) có thể mở kết nối đầu tiên khi `initService` còn đang chạy, và `IOHttpClientAdapter` của Dio giữ lại `HttpClient` nó tạo đầu tiên — một client không pin sẽ phục vụ cả phiên. Lời gọi này idempotent; `AppInitializer.init` gọi lại và lần thứ hai không cài gì. `platform/shell/app_shell/test/boot_order_test.dart` giữ thứ tự này. Pinning chỉ áp dụng ở nơi platform làm được (Android, iOS): trên **web** trình duyệt tự xác thực chứng chỉ và không có `HttpClient` nào để pin, còn trên desktop plugin pinning không có implementation — cả hai ghi một dòng `INFO` nói rõ điều đó (xem [hiện trạng web của tầng core](02_core.md)).
8. **`MainScope`** được dựng với splash widget (nếu `splash` mà platform khai báo là `dart` và có module đăng ký một cái), widget gốc, `DisplayProfile` của app và `initService` — ở đây là `AppInitializer.init(routeObserver: getIt<AppRouter>().routeObserver, …)`, lo phần còn lại: URL reflection của GoRouter, `AppInfoHelper`, trao route observer cho `RouteAwareWidget`, hướng màn hình và system UI theo `orientation` mà platform đã khai báo — tiếp theo là `ShellHooks.configureWindow` (trên platform khai báo `window`) và `ShellHooks.afterBoot`.
9. **`mainScope.run()`** rẽ nhánh tuỳ theo có truyền splash widget Dart hay không.

### Hồ sơ app

Một `AppProfile` ([`lib/src/profile/` của `platform_kernel`](../../../platform/foundation/kernel/lib/src/profile/)) là đối tượng duy nhất nói app là gì. Nó có hai nửa, đến từ hai file trong `apps/<id>/`:

- **`facts`** — `AppFacts`, được **sinh** từ `app_manifest.yaml` vào vùng `facts` của `lib/app/app_profile.dart`: `id` và `name` của app; các `flavors`; các `platforms` nó chạy trên, mỗi platform kèm một `PlatformFacts` (runner, chế độ splash, chính sách hướng màn hình, deep link, push, cửa sổ desktop); các key `--dart-define` nó đọc (`EnvRule`, kèm các flavor bắt buộc có key đó); một khai báo `capabilities` cho mọi contract tuỳ chọn mà shell resolve — `CapabilityExpectation.provided()`, hoặc `.absent(reason)`; và một quyết định certificate pinning cho mỗi flavor — `SslPinning.pinned(leaf, backup)` hoặc `SslPinning.disabled(reason)`. Đây là những gì một gate phải đọc được trước khi có bất kỳ code nào được biên dịch, nên chúng nằm trong manifest.
- **các phần (section)** — `display` (`DisplayProfile`: khung thiết kế, chính sách scale của từng lớp cửa sổ, trần cỡ chữ của hệ điều hành), `router` (`RouterProfile`: khi nào dùng entry location, vị trí fallback), `locale` (`LocaleProfile`), `theme` (`ThemeProfile`) và `network` (`NetworkProfile`), viết tay dưới dạng Dart `const` có kiểu bên dưới vùng được sinh. Mỗi phần ghi rõ mặc định và khoảng giá trị của nó, và phần nào bỏ qua thì là hành vi của template.

```dart
void runShellApp({
  required AppProfile profile,
  required Future<void> Function() configureDependencies,
  ShellHooks hooks = const ShellHooks(),
})
```

`registerAppProfile` gắn `AppProfile`, `AppPlatform` (platform của lần chạy này), `PlatformFacts` của platform đó, `SslPinningPolicy` và các phần `RouterProfile`, `LocaleProfile`, `ThemeProfile`, `NetworkProfile`, mỗi thứ theo đúng type của nó (RULE-14). Nó chạy trước `configureDependencies`, nên một class mà graph dựng có thể nhận một phần làm tham số constructor tuỳ chọn — kể cả eager singleton, không bao giờ vướng RULE-13 — còn class dựng tay trong test thì rơi về cùng những mặc định đó. Quá trình khởi động có thêm ba bước bao quanh những bước app nào cũng đã có:

1. **Validate, trước DI.** `AppProfile.validate` — Dart thuần — chạy cho platform (`resolveAppPlatform()` trong `core_common`, chỗ rẽ nhánh chính sách duy nhất theo `kIsWeb` / `defaultTargetPlatform`) và flavor của bản build này. Bất kỳ vấn đề nào cũng dừng boot ở màn hình boot-error, và `configureDependencies` không bao giờ được gọi: khởi động trên một platform mà manifest không khai báo từng chỉ cho ra một cửa sổ trống, không có lỗi nào.
2. **Đăng ký, vẫn trước DI.** `registerAppProfile` như trên, rồi shell gắn `ShellHooks` của app và một `AppRuntime` (`profile`, `flavor`, `platform`, `isDebug`) mà các hook và router đọc. Tiếp theo `ShellHooks.beforeDependencies` chạy.
3. **Kiểm tra, sau DI.** `checkAppContract` resolve mọi dòng của catalog bên dưới và đối chiếu khai báo `capabilities` của app với những gì graph đã đăng ký. `handleCompositionReport` quyết định dừng hay đi tiếp.

| Mã | `AppProfile.validate` dừng boot khi |
|:--|:--|
| `P01` | platform không được khai báo dưới `platforms` |
| `P02` | flavor không được khai báo dưới `flavors` |
| `P03` | một `--dart-define` bắt buộc ở flavor này đang rỗng (chỉ kiểm ở bản build non-debug — `flutter run` thường không cần file env) |
| `P04` | flavor chưa có quyết định pinning và platform có thể pin TLS (Android, iOS) |
| `P05` | platform khai báo `window` mà app không truyền `ShellHooks.configureWindow` |

| Mã | `checkAppContract` tìm thấy, sau DI |
|:--|:--|
| `C01` | một contract bắt buộc chưa được đăng ký |
| `C02` | một contract khai báo `provided` nhưng không có đăng ký nào |
| `C03` | một contract khai báo `absent` nhưng lại được đăng ký |
| `C04` | các thành viên của một bundle (`session`) được khai báo khác nhau |
| `C05` | không đóng góp route nào và tab nào — app không có màn hình |
| `C06` | hai `INavDestinationModule` dùng chung một `order` (RULE-24) |
| `C07` | `AppRouter.router` không lắp ráp được |
| `C08` | `DioFailureClassifier` chưa được móc vào `ErrorHandler` |
| `C09` | một contract tuỳ chọn hoàn toàn không có khai báo |

Mỗi vấn đề là một `ProfileProblem`: một `code`, một `Description:` nêu tên file và key trong manifest, và một `Action:` có thể dán nguyên xi khi đó là một dòng YAML hay một lệnh. **Nơi nó hiện ra tuỳ thuộc vào bản build.** Ở flavor dev hoặc staging, hoặc bản build debug hay profile, màn hình boot-error (`BootErrorApp` — một app tối giản không cần DI, router hay theme provider, vì chưa cái nào tồn tại) liệt kê đầy đủ mọi vấn đề, và một sai lệch phát hiện sau DI cũng dừng boot theo cách đó. Ở bản release production, vấn đề phát hiện trước DI chỉ hiện một thông báo chung, còn sai lệch phát hiện sau DI được log mức `ERROR` và báo cáo là non-fatal (`onNonFatalError`, rồi `IErrorReporter`) trong khi app vẫn khởi động — một module đã bị gỡ vẫn phải chạy được (RULE-05). Bản release không bao giờ là nơi gặp sai lệch đầu tiên: smoke test của mỗi app gọi `checkAppContract` cho mọi flavor (RULE-63), nên CI làm PR fail trước khi có bản release.

`--dart-define=ALLOW_UNDECLARED_PLATFORM=true` là cách để lập trình viên chạy thử nhanh trên một platform manifest không liệt kê: `P01` trở thành một cảnh báo được log và platform đó nhận `PlatformFacts.today()` — hành vi template từng có trước khi app có thể khai báo bất cứ điều gì. Nó không bỏ qua cho một flavor chưa khai báo.

Splash Dart được chọn theo `splash` mà platform đã khai báo thay vì theo `Platform.isIOS` ([bên dưới](#hai-đường-splash)). Một platform tắt một tính năng sẽ nói rõ đúng một lần, kèm tên key trong manifest: tắt push trên một platform thì log `platforms.<p>.push in apps/<id>/app_manifest.yaml is false` và không khởi tạo gì, deep link cũng vậy. Cách đọc, mở rộng và kiểm chứng toàn bộ phần này, theo từng app: [`../guides/13_app_composition.md`](../guides/13_app_composition.md).

### Shell resolve những gì từ một app

App phải có những contract nào được đăng ký, và được phép bỏ qua những contract nào? Một bảng trả lời tất cả: `kShellContracts` ([`shell_contracts.dart`](../../../platform/shell/app_shell/lib/src/composition/shell_contracts.dart)), 22 dòng — 8 bắt buộc, 14 tuỳ chọn. Mỗi dòng là một `ShellContract`: một `id` ổn định, shell có cần nó hay không, shell gom bao nhiêu implementation, shell làm gì khi không có gì được đăng ký, và `consumer`, tức `path:line` của mọi lời gọi tra cứu. `shell_contracts_test.dart` đọc từng dòng đó và fail khi một dòng không còn nhắc đúng contract của nó, nên sửa một file phía trên một lời tra cứu đã có trong catalog nghĩa là phải cập nhật dòng của nó trong cùng thay đổi, và `arch_check` R16 làm fail một lời tra cứu của shell không có dòng nào trong catalog. Mọi lời tra cứu vẫn là `getItOrNull` / `getAllOrEmpty` kèm fallback (RULE-12), đó là điều giúp một app ghép thiếu module đóng góp vẫn boot được. Điều catalog thêm vào là *khai báo* của app: một contract tuỳ chọn hoặc là `provided`, hoặc là `absent` kèm lý do (RULE-81), và `checkAppContract` cùng `composer verify` đối chiếu nó với code.

Các dòng **bắt buộc** do chính các package của shell đăng ký — nhóm DI `shell` và `ui` — nên app chỉ cần ghép các nhóm đó. Các dòng **tuỳ chọn** là những gì một app hoặc một module đóng góp:

| `id` | Contract | Mức cần | Nếu không có gì đăng ký |
|:--|:--|:--|:--|
| `language_storage` | `ILanguageStorage` | bắt buộc | boot ném "ILanguageStorage is not registered" |
| `theme_storage` | `IThemeStorage` | bắt buộc | boot ném "IThemeStorage is not registered" |
| `boot_storage` | `AppBootStorage` | bắt buộc | quy tắc lần khởi động đầu không chạy được |
| `ssl_pinning` | `SslPinningConfig` | bắt buộc | certificate pinning bị bỏ qua và một ERROR được log; phải bind riêng đúng type của nó, không bao giờ qua supertype (RULE-14) |
| `app_router` | `AppRouter` | bắt buộc | boot ném "AppRouter is not registered" |
| `deeplink_provider` | `DeeplinkProvider` | bắt buộc | boot ném "DeeplinkProvider is not registered" |
| `theme_provider` | `ThemeProvider` | bắt buộc | boot ném "ThemeProvider is not registered" |
| `language_provider` | `LanguageProvider` | bắt buộc | boot ném "LanguageProvider is not registered" |
| `session_state` | `ISessionState` | tuỳ chọn, bundle `session` | navigation wrapper coi app là chưa đăng nhập, mọi deep link đều được điều hướng, và mất phiên là no-op |
| `session_gateway` | `ISessionGateway` | tuỳ chọn, bundle `session` | request không mang bearer token và không gì làm mới nó |
| `session_refresh` | `ISessionRefreshListenable` | tuỳ chọn, bundle `session` | router không bao giờ phân giải lại location khi phiên đổi |
| `sign_in` | `ISignInLocation` | tuỳ chọn, bundle `session` | shell không bao giờ chuyển người dùng chưa đăng nhập đi đâu |
| `routes` | `IFeatureRouteModule` | tuỳ chọn, gom nhiều | router không có route nào trên ngăn xếp |
| `tabs` | `INavDestinationModule` | tuỳ chọn, gom nhiều | router mở một route giữ chỗ (`/_empty_dashboard`) |
| `dashboard` | `IDashboardRouteModule` | tuỳ chọn | các destination hiển thị không có khung chrome |
| `entry` | `IAppEntryLocation` | tuỳ chọn | không có điểm vào lần đầu; boot đi thẳng tới bước kiểm tra đăng nhập |
| `post_sign_in` | `IPostSignInLocation` | tuỳ chọn | sau khi đăng nhập router mở fallback của nó, tab đầu tiên |
| `splash` | `IAppSplashScreen` | tuỳ chọn | splash native được giữ suốt quá trình boot |
| `tree_wrappers` | `IAppTreeWrapper` | tuỳ chọn, gom nhiều | cây widget được dựng không có wrapper |
| `localization` | `IFeatureLocalization` | tuỳ chọn, gom nhiều | chỉ chuỗi của chính `core_base_ui` được dịch |
| `error_reporter` | `IErrorReporter` | tuỳ chọn | lỗi được in ra và không gửi đi đâu (RULE-67) |
| `analytics` | `IAnalytics` | tuỳ chọn | không có sự kiện màn hình nào được gửi |

Một contract *gom nhiều* có thể có bao nhiêu implementation tuỳ ý (`getAllOrEmpty`). Một *bundle* được khai báo như một khối: `session` là `provided` hoặc `absent` cho cả bốn thành viên cùng lúc (`C04` khi chúng khác nhau). `ISessionStatusStream` không nằm trong catalog — chỉ `feature_home` tra cứu nó, và các lời tra cứu riêng của một module là việc của module đó. Bảng này là bản sao của hằng số Dart; khi hai bên lệch nhau thì code là chuẩn, và `shell_contracts_test.dart` giữ số dòng. `dart tools/composer/composer.dart describe --catalog` in catalog hiện hành, còn `describe --app <id>` thêm, cho từng app, trạng thái đã khai báo và các package đăng ký mỗi dòng.

### Các hook

`ShellHooks` ([`shell_hooks.dart`](../../../platform/shell/app_shell/lib/src/shell_hooks.dart)) là code của app tại các điểm cố định của quá trình boot. Mọi hook đều tuỳ chọn và cả đối tượng là `const`, nên app giữ một `const ShellHooks` trong `lib/app/app_hooks.dart` và truyền vào `runShellApp(hooks: …)`:

| Hook | Chạy | Dùng để |
|:--|:--|:--|
| `onError` | khi một lỗi thoát khỏi zone, framework hoặc engine | kênh lỗi fatal |
| `onNonFatalError` | khi `ErrorHandler` không phân loại được một failure | kênh non-fatal (xem [Lỗi và crash reporting](#lỗi-và-crash-reporting)) |
| `beforeDependencies(AppRuntime)` | sau error hook và việc đăng ký profile, trước DI | thiết lập mà graph cần có sẵn — `Sentry.init`, `Firebase.initializeApp`; nó không resolve được gì từ DI, vì DI chưa tồn tại |
| `afterBoot(AppRuntime)` | sau DI, `AppInitializer.init` và `configureWindow`, vẫn đang sau splash | resolve được mọi thứ graph đã đăng ký; giữ cho ngắn, splash vẫn hiện cho tới khi nó xong |
| `navigatorObservers(AppRuntime)` | một lần, khi `AppRouter` dựng `GoRouter` | các `NavigatorObserver` thêm vào sau `routeObserver` của chính shell |
| `redirect(context, state)` | ở mỗi lần điều hướng | một guard `GoRouter` áp dụng toàn app; guard riêng của module vẫn nằm trong `GoRouteData.redirect` của nó |
| `configureWindow(AppRuntime, WindowFacts)` | trên platform mà manifest khai báo `window`, sau `AppInitializer.init` | kích thước và tiêu đề cửa sổ desktop — app tự mang plugin cửa sổ; khai báo `window` mà không có hook là `P05` |

Một hook ném lỗi sẽ được báo cáo qua các error hook như mọi lỗi khác trong zone của app, và dừng boot tại điểm nó chạy. Hook là *code*: một giá trị vừa với manifest (platform, flavor, capability) hoặc các phần của profile thì thuộc về đó, nơi một gate đọc được.

### Lỗi và crash reporting

Có ba loại lỗi lọt qua mọi thứ khác, và shell móc vào cả ba:

| Hook | Bắt được |
|:--|:--|
| handler của `runZonedGuarded` | lỗi bất đồng bộ thoát khỏi zone của app — một `Future` không được await mà throw |
| `FlutterError.onError` | lỗi framework bắt được: build, layout, paint, giải mã ảnh, gesture |
| `PlatformDispatcher.instance.onError` | lỗi thoát ra tới engine — callback của platform channel, timer nằm ngoài zone |

Cả ba đổ về cùng một chỗ. Handler của zone và hook của dispatcher ném lại qua `FlutterError.reportError`; hook `FlutterError.onError` trước hết gọi handler đã có trước nó — mặc định là `FlutterError.presentError`, bản dump đỏ trên console ở debug — rồi báo lỗi **một lần**: tới callback fatal (tuỳ chọn) của app (`ShellHooks.onError`), rồi tới `getItOrNull<IErrorReporter>()` với `fatal: true`. Hook của dispatcher trả về `true`: lỗi đã được xử lý, engine không log thêm lần nữa.

`IErrorReporter` và `IAnalytics` là các contract tuỳ chọn trong `core_di` ([`src/observability/`](../../../platform/foundation/contracts/lib/src/observability/)). Template không implement cái nào, nên cả hai lookup trả `null` và không gửi gì đi. Reporter được resolve lúc lỗi xảy ra, không phải lúc boot, nên reporter do `configureDependencies` đăng ký vẫn được dùng, và lỗi do *chính* `configureDependencies` ném ra vẫn tới được `onError`. Reporter hay callback nào tự throw sẽ bị nuốt — không bao giờ bị báo cáo qua chính nó.

Còn một đường thứ ba, non-fatal. `ErrorHandler` (`platform_kernel`) chuyển mọi exception của repository thành `AppFailure`; những cái nó không phân loại được — một `TypeError` trong `fromJson`, một exception của plugin — thành lỗi chung "Unknown error occurred" và thường là bug. Shell trỏ `ErrorHandler.onUnclassifiedError` tới `ShellHooks.onNonFatalError` rồi tới reporter với `fatal: false`, nên những lỗi đó được ghi lại trong khi người dùng vẫn nhận một failure đã được xử lý. Failure đã phân loại (mất mạng, 401, timeout) không được báo cáo.

**Gắn Crashlytics hay Sentry** chỉ là một lần đăng ký trong app — trong `lib/` của chính nó, cạnh `firebase/firebase_module.dart`, hoặc trong một package mà app ghép vào. Không phải sửa code shell:

```dart
// apps/mobile/lib/observability/crashlytics_error_reporter.dart
@LazySingleton(as: IErrorReporter)
class CrashlyticsErrorReporter implements IErrorReporter {
  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) => FirebaseCrashlytics.instance.recordError(
    error,
    stack,
    fatal: fatal,
    reason: reason,
  );

  @override
  void log(String message) => FirebaseCrashlytics.instance.log(message);
}
```

Với Sentry, `recordError` gọi `Sentry.captureException(error, stackTrace: stack)` và `log` thêm một breadcrumb; khởi tạo SDK trong app (`SentryFlutter.init` bọc `main`, trước `runShellApp`). **Đừng** tự gán `FlutterError.onError` nữa — hook của shell đã chuyển tiếp nó, và nối tiếp handler nào đã được cài trước `runShellApp`. `IAnalytics` hoạt động y như vậy: đăng ký một implementation là mọi trang `GoRouteDataCustom` báo màn hình của nó qua `setCurrentScreen` (`RouteAwareWidget`, khi push và khi route phía trên pop). `platform/shell/app_shell/test/error_hooks_test.dart` giữ phần nối dây này.

### Hai đường splash

`runShellApp` chọn splash theo nền tảng, và lấy nó từ module nào đã đăng ký `IAppSplashScreen` — ở app mẫu là `feature_splash`:

```dart
// The platform's declared `splash` decides — iOS keeps its native splash
// for the whole boot by default, so no Dart splash is built there.
final usesDartSplash = platformFacts.splash == SplashMode.dart;
// ...
splashScreen: usesDartSplash
    ? getItOrNull<IAppSplashScreen>()?.build()
    : null,
```

`platforms.<p>.splash` trong manifest là `dart` hoặc `native`; bỏ qua thì mặc định là `native` trên iOS và, ở nơi khác, là `dart` khi app khai báo capability `splash` là `provided`, còn không là `native` (`composer verify` từ chối `dart` khi thiếu capability đó, V5).

| `splashScreen` | Hành vi |
|:--|:--|
| `null` (`splash: native`, hoặc không ghép splash nào) | Splash native được **giữ lại** suốt quá trình init rồi mới gỡ. Không có splash Dart nào được vẽ. Đây là mặc định của iOS. |
| `IAppSplashScreen.build()` (`splash: dart`) | Splash native gỡ ngay lập tức; splash đã đăng ký được vẽ thay thế, rồi mờ dần sang `RootApp` qua `AnimatedSwitcher`. |

Cả hai đường chỉ chờ `initService()` và không chờ gì khác: splash hiện đúng bằng thời gian khởi tạo, không có mức tối thiểu nhân tạo nào.

> [!NOTE]
> `SplashPage` do `MainScope` hiển thị, **không** phải do GoRouter. Nó không có route và không bao giờ xuất hiện trong ngăn xếp điều hướng.

> [!NOTE]
> **Web:** `MainScope` không bao giờ gọi `FlutterNativeSplash.remove()` trên web — chưa app nào ở đây sinh splash web, nên plugin không có phần web và lệnh gọi sẽ ném `PlatformException(… removeSplashFromWeb …)`, đẩy lỗi tới `IErrorReporter` ở mỗi lần mở.

### `_ResponsiveWrapper`

Cả hai đường đều bọc cây widget trong **`ResponsiveInit`** (từ `core_responsive`). Nó nằm ở đúng gốc cây, nên mọi widget phía dưới đều gọi được `context.w(x)` / `context.h(x)` / `context.sp(x)` / `context.r(x)`. Cấu hình này là `DisplayProfile` của app (`AppProfile.display`), và mặc định của nó là chính sách scale của template:

| Thiết lập | Mặc định | Tác dụng |
|:--|:--|:--|
| `designSize` | 375×812 | Khung điện thoại mà mọi lớp cửa sổ bắt đầu từ đó |
| `scale` — lớp không được liệt kê | `ScalePolicy.downOnly()` | Cửa sổ nhỏ hơn khung thì thiết kế thu nhỏ; cửa sổ lớn hơn — tablet, cửa sổ desktop — vẽ 1:1 và để chỗ dư cho layout |
| `scale` — `WindowClass.expanded` | `ScalePolicy.fixed()` | Từ rộng 840 trở lên (nên cả `large` và `extraLarge`), dùng logical pixel thật — cửa sổ laptop thấp hơn 812 không còn làm mọi khoảng cách dọc nhỏ đi |
| `splitScreenMode` | `true` | Chặn dưới chiều cao dùng để scale ở 700, để một ô chia đôi màn hình thấp vẫn dùng được |
| `textScaleMax` | 2.0 | Trần cho cỡ chữ của hệ điều hành mà người dùng đặt ([bên dưới](#cỡ-chữ-của-hệ-điều-hành-được-tôn-trọng-tới-2x)); một `const` assert từ chối giá trị dưới 2.0 |
| `phoneMaxShortestSide` | 600 | Cạnh ngắn nhất mà dưới đó một màn hình được tính là điện thoại, cho chính sách hướng `phones_portrait` |

Theme scale chữ bằng `context.sp`, nên nó đi theo chính sách này như mọi thứ khác. Cho một lớp phóng to là opt-in trong profile của app — `DisplayProfile(scale: {WindowClass.medium: ScalePolicy.bounded(max: 1.2)})` trong `lib/app/app_profile.dart`. Bảng tham số đầy đủ, mỗi cửa sổ nhận được gì, và các widget thích ứng dùng chỗ dư nằm ở [`11_design_system.md`](../guides/11_design_system.md) §6–§7.

`ResponsiveInit` phát metrics xuống qua `ResponsiveScope`, một `InheritedWidget`, nên widget nào đọc metrics là tự đăng ký theo dõi chúng — không có cờ rebuild nào để tinh chỉnh. Việc scale vẫn phải đi qua `BuildContext` — không có extension trên `num`, nên `16.h` đơn giản là không biên dịch được. Xem [luật 12](../reference/01_rules.md#12-responsive-ui), và lưu ý luật R7 của `arch_check` chặn mọi dạng bare còn sót ở mọi PR.

> [!NOTE]
> Trước đây ở đây có một `fontSizeResolver` tính tỉ lệ chiều rộng từ `View.of(context).display` — màn hình vật lý, không phải cửa sổ. Khi toàn màn hình thì hai cái khớp nhau; khi split-screen hay đổi kích thước cửa sổ, chữ scale theo cả màn hình trong khi mọi kích thước khác theo cửa sổ. `ResponsiveInit` đo cửa sổ qua `MediaQuery`, nên mặc định đã thay được resolver. Cũng đừng đưa resolver trở lại để chặn cỡ chữ: kết quả của resolver không bao giờ bị text scale bounds kẹp, mà mức chặn đó giờ nằm chính ở đó.

---

## 3. Lắp ráp DI — và vì sao thứ tự quan trọng

Thứ tự được khai trong [`apps/mobile/app_manifest.yaml`](../../../apps/mobile/app_manifest.yaml) ở mục `di_groups`, rồi `composer sync` sinh nó vào [`apps/mobile/lib/di/injection.dart`](../../../apps/mobile/lib/di/injection.dart):

```dart
const _externalModulesBefore = [..._coreModules];
const _externalModulesAfter = [
    ..._notificationsModules,
    ..._shellModules,
    ..._uiModules,
    ..._domainModules,
    ..._dataModules,
    ..._featureModules,
    ..._otherModules,
];
```

Thứ tự resolve trong file sinh ra `injection.config.dart`:

| # | Đăng ký | Ghi chú |
|:-:|:--|:--|
| 1 | `_coreModules` | `core_common`, `core_network` (đăng ký `DioFailureClassifier` vào `ErrorHandler` tại đây), `core_storage`, `core_database`, `core_di` |
| – | `lib/` của chính app | `FirebaseModule` — `FirebaseOptions` theo flavor ([`apps/mobile/lib/firebase/firebase_module.dart`](../../../apps/mobile/lib/firebase/firebase_module.dart)) |
| 2 | `_notificationsModules` | `core_notifications` — `PushNotificationService` (eager) inject chính các `FirebaseOptions` đó, nên phải đứng sau |
| 3 | `_shellModules` | `platform_shell_adapters` — `ILanguageStorage`, `IThemeStorage`, `AppBootStorage`, `NetworkConfig`, `SslPinningConfig`; rồi `platform_app_shell` — `AppRouter`, `DeeplinkProvider` |
| 4 | `_uiModules` | `core_base_ui` |
| 5 | `_domainModules` → `_dataModules` → `_featureModules` → `_otherModules` | `domain_core`, rồi package domain của từng module; `data_core`, rồi package data của từng module; package feature của từng module; provider / bloc state management |

Package app chỉ đăng ký thứ định danh nó: Firebase options, vốn gắn với một bundle ID nên không thể nằm trong `platform/`. Mọi thứ khác đều đến qua một nhóm — và khai báo của app đến trước tất cả: `runShellApp` đã đăng ký profile cùng các phần của nó (§2), nên một class trong bất kỳ nhóm nào cũng có thể nhận một phần làm tham số constructor. Injectable chạy phần đăng ký *của chính package* nằm giữa hai phase, và chỗ của app nằm ở đó. Có ba vị trí là cố ý và không được "dọn dẹp": `shell` trước `ui`, database sau các migration của nó, và `notifications` nằm ngoài `core` — mỗi cái có một mục con bên dưới.

File được sinh ra kết thúc bằng điểm vào mà mọi app dùng chung — một phần của vùng `modules`, nên app thứ ba không thể viết sai:

```dart
Future<void> configureDependencies({String? environment}) async {
  getIt.enableRegisteringMultipleInstancesOfOneType();
  final env = environment ?? AppConfig.appFlavor.toValue();
  await getIt.init(environment: env);
}
```

`enableRegisteringMultipleInstancesOfOneType()` là thứ cho phép `getAll<T>()` gom mọi `IFeatureRouteModule`. Nó có một tác dụng phụ cần biết: GetIt khi đó giữ đăng ký **đầu tiên** của một type, nên đăng ký của app thắng một type đăng ký ở nhóm `after` và thua một type ở nhóm `before`. Thay một type do shell sở hữu bằng thứ tự đăng ký là không được hỗ trợ; profile và hook mới là các điểm gắn ([`13_app_composition.md`](../guides/13_app_composition.md)).

### Mỗi package một module

Mỗi package sở hữu một DI module tại `lib/di/module.dart`:

```dart
import 'package:injectable/injectable.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}
```

`build_runner` biến nó thành `lib/di/module.module.dart`, phơi ra ví dụ `CoreStoragePackageModule`. Mỗi app lắp tất cả lại trong `apps/<id>/lib/di/injection.dart` của nó.

Bạn chỉ cần gắn annotation lên class, nó tự vào module của package đó — không bao giờ phải sửa file generated.

### Vì sao `shell` đứng trước `ui`

Đây là luật ngầm quan trọng nhất trong phần DI, và manifest có ghi rõ trong một comment.

`core_base_ui` đăng ký `ThemeProvider` và `LanguageProvider`, hai provider này inject `IThemeStorage` và `ILanguageStorage`. Hai interface đó được hiện thực trong `platform_shell_adapters` (`theme_storage_impl.dart`, `language_storage_impl.dart`), không phải trong package core nào mà các provider có thể phụ thuộc trực tiếp. Vì vậy `shell` phải khởi tạo trước — và bên trong nhóm, `platform_shell_adapters` đứng trước `platform_app_shell` (`packages: [platform_shell_adapters, platform_app_shell]`), để không gì shell đăng ký có thể phụ thuộc một adapter chưa có mặt. Đảo hai nhóm là app hỏng lúc khởi động với lỗi "IThemeStorage is not registered".

Đây cũng đúng là vị trí mà các đăng ký này chiếm trước khi shell thành package. Trước đây chúng là đăng ký cục bộ của app, thứ mà injectable chạy *giữa* `…Before` và `…After`; giờ `shell` chạy sớm trong `…After` — đầu tiên ở `apps/admin`, ngay sau `notifications` ở `apps/mobile`. Thứ tự app khởi động không đổi — chỉ chỗ đặt code là đổi.

### Database mở sau khi các migration của nó đã đăng ký

Package mở database phải chạy sau mọi thứ đóng góp migration cho nó. Mở database là `@preResolve`, và chính việc mở là thứ chạy các bước `IDatabaseMigration` đã thu thập — nên mọi bước phải được đăng ký trước khi mở. Bên trong package sở hữu, `@Order(1)` trên hàm mở giải quyết việc đó (`modules/cache/data/lib/di/module.dart`): injectable đăng ký các mục của một package theo `@Order` tăng dần, nên các bước của chính package (order mặc định 0) được đăng ký trước. Nhưng `@Order` không vươn sang module khác. `data_cache` (module mẫu `cache`) mở `CacheDatabase` của nó khi nhóm `data` khởi tạo, nên một migration do package thuộc nhóm *sau* đóng góp — ví dụ một feature — đơn giản là chưa có mặt, và bị bỏ qua mà không báo lỗi. Database của riêng bạn cũng cần `@Order(1)` y như vậy trên hàm mở. Bản thân `core_database` không đăng ký gì (nó chỉ là cơ chế), nên nó nằm trong `core` được.

### Vì sao `notifications` không nằm trong `core`

`PushNotificationService` là `@singleton` eager inject `FirebaseOptions`, mà `FirebaseOptions` lại do chính app đăng ký, giữa hai phase — chúng gắn với một bundle ID, nên không package platform nào được sở hữu. Đặt ở `before` thì service sẽ resolve chúng trước khi chúng tồn tại và ném lỗi lúc khởi động. App nào không gửi push notification thì bỏ nhóm này, và cũng không cần `lib/firebase/`.

### Cái bẫy thứ tự với eager singleton

> [!CAUTION]
> Một `@Singleton` eager được dựng **ngay lúc đăng ký**. Nếu nó phụ thuộc một kiểu do module chạy *sau* đăng ký, khởi động sẽ ném `… is not registered`.
>
> `flutter analyze` không thể phát hiện lỗi này (RULE-13) — đây là lỗi thứ tự lúc chạy, và smoke test DI bên dưới là thứ bắt được nó. Để chẩn đoán, đọc các file sinh ra: `apps/mobile/lib/di/injection.config.dart` cho thứ tự module, còn `lib/di/module.module.dart` của từng package cho đăng ký theo type — mọi `gh<Dep>()` mà một singleton eager gọi phải được đăng ký *phía trên* nó, hoặc bởi một module khởi tạo sớm hơn.

Hoặc để test đọc giúp: `test/di_smoke_test.dart` của mỗi app chạy `configureDependencies()` được sinh ra cho từng flavor, với plugin được thay bằng test double (storage trong bộ nhớ, thư mục tạm cho `path_provider`, test API Firebase core của FlutterFire và channel messaging / local-notification giả trong `apps/mobile`), rồi dựng mọi lazy singleton và gọi `checkAppContract` cho nó: mọi contract bắt buộc, mọi contract tuỳ chọn được khai là `provided` hay `absent` trong manifest, có màn hình, `order` của tab không trùng và `AppRouter.router` lắp ráp được. Gate 3 của CI chạy nó như test của mọi package. Đảo `shell` và `ui` là test hỏng đúng với lỗi boot bên dưới.

Ví dụ thật: `ThemeProvider` của `core_base_ui` inject `IThemeStorage`, do nhóm `shell` đăng ký (qua `platform_shell_adapters`). Smoke test còn đòi `AppBootStorage`, `NetworkConfig` và `SslPinningConfig`, và đòi `DioFailureClassifier` của `core_network` đã tự đăng ký vào `ErrorHandler` trong nhóm `core`. Đó là lý do `shell` được xếp trước `ui` trong `di_groups` của mọi app — đảo lại là app hỏng lúc boot. (`NetworkConfigImpl` từng là ví dụ ở đây, vì inject `AuthLocalDataSource` từ một module chạy sau. Giờ nó resolve `ISessionGateway` ngay lúc gọi, và không còn dependency constructor nào xuyên module.)

Một ca thật theo chiều an toàn. `ThemeStorageImpl` là một `@Singleton(as: IThemeStorage)` eager trong nhóm `shell`. Dependency duy nhất trong constructor của nó là `StorageManager`, do `core_storage` đăng ký ở nhóm 1 — đúng chiều. Nếu nó inject thêm, chẳng hạn, `AuthLocalDataSource` từ `data_auth` (nhóm 6), app sẽ hỏng lúc boot ở mọi lần mở. Cách sửa chỉ là một từ — đổi thành `@LazySingleton` — hoặc tốt hơn, đừng phụ thuộc vào module nào cả.

Đó chính là điều `NetworkConfigImpl` làm. Nó từng inject `AuthLocalDataSource` và `RefreshTokenUseCase`, và phải lazy đúng vì lý do này. Giờ nó chỉ nhận `ILanguageStorage` từ chính nhóm của mình và đọc phiên đăng nhập qua `ISessionGateway` ngay lúc gọi:

```dart
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  NetworkConfigImpl(this._languageStorage);

  /// Null in a build that composes no auth module.
  ISessionGateway? get _session => getItOrNull<ISessionGateway>();
  // ...
}
```

### `AppRouter` là eager, nhưng router của nó thì không

`AppRouter` *đúng là* `@singleton` (eager), nhưng vẫn an toàn: `router` là trường `late final`.

```dart
late final GoRouter router = GoRouter( … );
```

`GoRouter` — cùng các lời gọi `getAllOrEmpty<IFeatureRouteModule>()` bên trong nó — không được tính toán cho tới khi có ai đó đọc `.router` lần đầu. Lúc đó mọi feature module đã đăng ký xong. Nếu `router` là trường thường, router sẽ được lắp trong bước 2 và gom được **không** route feature nào.

---

## 4. Adapter của shell

Shell hiện thực những hợp đồng mà package core khai báo nhưng tự nó không thể thoả mãn. Các hiện thực nằm trong package riêng, `platform_shell_adapters` (`platform/shell/adapters/`), được đăng ký đầu tiên trong nhóm DI `shell`. Mỗi adapter sở hữu `StorageValue` riêng và giữ key trong `platform/shell/adapters/lib/src/utils/`. `NetworkConfigImpl` hiển thị `RetryDialog` của `core_ui_kit` khi timeout — lý do duy nhất package này phụ thuộc nhóm ui. Ba adapter đọc profile của app qua một tham số constructor tuỳ chọn: `NetworkConfigImpl` đọc `SslPinningPolicy` và `LocaleProfile`, `LanguageStorageImpl` đọc `LocaleProfile` (ngôn ngữ lần chạy đầu mở ra), `ThemeStorageImpl` đọc `ThemeProfile` (chế độ mà khi chưa lưu gì thì rơi về).

| File | Hiện thực | Sở hữu | Cách đăng ký |
|:--|:--|:--|:--|
| `theme_storage_impl.dart` | `IThemeStorage` | `themeMode` (pref) | `@Singleton(as: IThemeStorage)` + `@PostConstruct(preResolve: true)` |
| `language_storage_impl.dart` | `ILanguageStorage` | `locale` (pref) | như trên |
| `app_boot_storage.dart` | — | `viewed_onboard` (pref) | `@singleton` + `@PostConstruct(preResolve: true)` |
| `network_config_impl.dart` | `NetworkConfig` | — | `@LazySingleton(as: NetworkConfig)` |
| `network_binding_module.dart` | bind `SslPinningConfig` | — | `@module` |

### Vì sao `SslPinningConfig` cần binding riêng

`NetworkConfig implements SslPinningConfig`, nhưng **GetIt phân giải theo đúng kiểu đã đăng ký và không đi ngược chuỗi supertype**. Chỉ đăng ký `as: NetworkConfig` khiến `getItOrNull<SslPinningConfig>()` trả `null`, nên `AppInitializer` bỏ qua pinning hoàn toàn — âm thầm, trên mọi flavor.

Vì vậy kiểu thứ hai cần một binding riêng qua module, đúng mẫu dual-registration mà `feature_auth` dùng cho `ISessionStatusStream`:

```dart
@module
abstract class NetworkBindingModule {
  @lazySingleton
  SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
}
```

Tham số khai kiểu `NetworkConfig` nên phép upcast được trình biên dịch kiểm tra — không cần ép kiểu `as`.

Thứ binding này trao ra là quyết định của chính app: `NetworkConfigImpl.sslPinningHashes` là `SslPinningPolicy.hashesFor(flavor)`, tức các pin (hoặc danh sách rỗng của một flavor `disabled`) mà manifest khai dưới `flavors.<f>.ssl_pinning` — không bao giờ là một hằng số trong package này.

---

## 5. Lắp ráp router

[`app_router.dart`](../../../platform/shell/app_shell/lib/src/navigation/app_router.dart) dựng GoRouter **hoàn toàn từ các đóng góp qua DI**.

```dart
List<RouteBase> get _featureRoutes => [
  for (final module in getAllOrEmpty<IFeatureRouteModule>()) ...module.routes,
];

List<INavDestinationModule> get _destinations =>
    getAllOrEmpty<INavDestinationModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
```

Cấu trúc tạo ra:

```
GoRouter(navigatorKey: NavigatorKeys.rootKey)
└── ShellRoute(navigatorKey: appKey)          → NavigatorWrapperWidget
    ├── ..._featureRoutes                      ← IFeatureRouteModule
    └── StatefulShellRoute.indexedStack        ← INavDestinationModule (sắp theo order)
        └── builder → IDashboardRouteModule
```

Mọi điểm gom đều lùi về phương án dự phòng khi không có đóng góp nào:

| Thiếu | Dự phòng |
|:--|:--|
| `IFeatureRouteModule` | danh sách rỗng — không có route stack; app vẫn dựng được |
| `INavDestinationModule` | một nhánh giữ chỗ tại `/_empty_dashboard` vẽ `SizedBox.shrink()`, giữ `StatefulShellRoute` hợp lệ |
| `IDashboardRouteModule` | chính `navigationShell` — các tab không có chrome. (Trước đây là `SizedBox.shrink()`: app có tab mà không có dashboard sẽ mở ra màn hình trắng) |
| `IAppEntryLocation` | `AppRouter.fallbackLocation`: `RouterProfile.fallbackPath` khi app đặt một cái, nếu không thì path của tab dashboard đầu tiên (`order` nhỏ nhất), nếu không có thì placeholder `/_empty_dashboard` (không phải `/`). Không có entry location nghĩa là không có onboarding để hiện, nên boot đi tiếp tới bước kiểm tra đăng nhập |
| `ISignInLocation` | Không redirect tới màn đăng nhập, lúc boot hay khi đăng xuất — đúng khi không có module sở hữu phiên |
| `IPostSignInLocation` | Sau khi đăng nhập, app đi tới `fallbackLocation` thay vì đứng yên ở màn hình login |

`initialLocation` là `AppRouter.entryLocation`: `IAppEntryLocation` đã đăng ký **chỉ ở lần chạy đầu tiên**, `fallbackLocation` ở mọi lần sau. "Lần chạy đầu tiên" là cờ riêng của shell, `AppBootStorage.viewedOnboard`, được `NavigatorWrapperWidget` gán ở lần boot đầu tiên có entry location (§6); `AppRouter.resolveEntryLocation` là phần quyết định thuần. Vì vậy người dùng quay lại mở app ở tab đầu tiên trong lúc phiên đang khôi phục, không phải ở onboarding — và nếu đã đăng xuất thì redirect khởi động đưa họ tới màn đăng nhập. `RouterProfile.entry` đổi quy tắc đó theo từng app: `firstLaunch` (mặc định, như trên), `always` (entry location ở mọi lần khởi động nguội; redirect khởi động vẫn đưa người dùng quay lại đi tiếp) hoặc `never` (một `IAppEntryLocation` đã đăng ký bị bỏ qua).

Nhờ vậy, xoá một feature package không thể làm sập shell.

> [!CAUTION]
> **Tuyệt đối không hardcode route của feature vào `app_router.dart`.** Thêm `$myFeatureRoute` vào đó là buộc app shell dính chặt vào feature của bạn, phá vỡ cam kết "gỡ feature ra app vẫn chạy". Hãy đăng ký `IFeatureRouteModule` hoặc `INavDestinationModule` trong DI module của chính feature đó. Xem [`../guides/04_routing.md`](../guides/04_routing.md).

`refreshListenable: getItOrNull<ISessionRefreshListenable>()` (được `feature_auth` bind vào `AuthProvider` của nó) khiến GoRouter phân giải lại vị trí hiện tại — chạy mọi `redirect` gắn trên nó — khi trạng thái đăng nhập đổi. Không route mẫu nào khai báo redirect, nên tự nó không tạo ra thay đổi nào thấy được; nó là điểm móc cho một guard. App nào muốn **một guard áp dụng toàn app** thì truyền `ShellHooks.redirect`, mà `AppRouter` trao cho `GoRouter(redirect:)`; guard riêng của module vẫn nằm trong `GoRouteData.redirect` của nó. Việc *điều hướng* khi đăng nhập / đăng xuất do `NavigatorWrapperWidget` làm, bằng cách lắng nghe `ISessionState.sessionChanges` (§6). `errorPageBuilder` vẽ `UndefinedRouteWidget` — một widget có tên, không bao giờ dùng closure ẩn danh.

`observers: [routeObserver, ...]` gắn `AppRouter.routeObserver` — và sau nó là những gì `ShellHooks.navigatorObservers` trả về — vào navigator gốc, và go_router chuyển tiếp các observer gốc tới mọi navigator của `ShellRoute` và `StatefulShellBranch` (`notifyRootObserver`, mặc định bật) — nên chính observer mà `AppInitializer.init` trao cho `RouteAwareWidget` thấy mọi lần push và pop, kể cả trong tab. `platform/shell/app_shell/test/app_router_test.dart` kiểm tra cả hai cấp.

### Entry location và fallback location

Mọi lần tra cứu trong `app_router.dart` đều chịu được việc thiếu đóng góp — đây chính là thứ khiến feature gỡ được:

```dart
String get fallbackLocation {
  final tabs = _destinations;
  if (tabs.isNotEmpty) return tabs.first.path;
  return _emptyDestinationPath;
}

String get entryLocation {
  final entry = getItOrNull<IAppEntryLocation>();
  return resolveEntryLocation(
    entryPath: entry?.path,
    // The shell's own first-launch flag, set by NavigatorWrapperWidget.
    entrySeen:
        entry != null &&
        (getItOrNull<AppBootStorage>()?.viewedOnboard.value ?? false),
    fallback: fallbackLocation,
  );
}
```

```dart
builder: (context, state, navigationShell) {
  return getItOrNull<IDashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      navigationShell;
},
```

Có hai vị trí, và chúng khác nhau có chủ đích (app có thể đặt tên cho fallback bằng `RouterProfile.fallbackPath`). `entryLocation` là nơi khởi động nguội đáp xuống — onboarding khi được ghép, nhưng **chỉ ở lần chạy đầu tiên**: khi `NavigatorWrapperWidget` đã ghi nhận là đã xem (cờ `AppBootStorage.viewedOnboard` của shell), mọi lần khởi động nguội sau đó đáp xuống `fallbackLocation`, nên người dùng quay lại không phải thấy onboarding trong lúc phiên đang khôi phục. `fallbackLocation` là "trang chủ": `back()` khi không còn gì để pop, nút "về trang chủ" của `UndefinedRouteWidget`, và sau khi đăng nhập nếu không có `IPostSignInLocation`. Nó luôn là một route đã đăng ký, không bao giờ là onboarding — người vừa đăng nhập không được đưa ngược về onboarding.

Path không khớp sẽ rơi vào `errorPageBuilder` → `UndefinedRouteWidget` (một widget class thật, không bao giờ dùng widget vô danh inline).

### Vì sao `NavigatorKeys` nằm ở `core_di`

Một `ShellRoute` và các route con của nó phải tham chiếu **cùng một** instance `GlobalKey`. Shell do app shell lắp ráp; route con lại khai bên trong feature package. Đặt key ở một trong hai phía đều phạm luật — shell (`platform_app_shell`) là core nên không được phụ thuộc feature (R1), còn feature thì không được phụ thuộc shell. `core_di`, thứ mà cả hai phía đều đã phụ thuộc, là nơi trung lập.

DI Hub không khai key nào mang tên feature. `nested(id)` trả về đúng cùng một instance cho cùng một id, nên shell route và route con khớp nhau mà không cần khai báo tập trung — và bề mặt công khai của `core_di` không phình thêm từ vựng sản phẩm. Cách xin một key: [`../guides/04_routing.md` § 7](../guides/04_routing.md#7-cho-module-một-back-stack-riêng).

---

## 6. `NavigatorWrapperWidget` — điều hướng đầu tiên và các chuyển đổi auth

Nằm bên trong app `ShellRoute` và bọc mọi route trong app. Nó tách điều hướng thành hai trách nhiệm riêng biệt.

**Redirect lúc khởi động** chỉ chạy một lần, trong `initState`, hoãn tới `endOfFrame`:

```dart
WidgetsBinding.instance.endOfFrame.whenComplete(() async {
  await _session?.ensureInitialized(); // ISessionState, via getItOrNull
  if (!mounted) return;
  // entry location? → ISignInLocation? → IPostSignInLocation (else fallbackLocation)
  _bootCompleted = true;
});
```

Chờ `endOfFrame` bảo đảm khung hình đầu tiên đã lên màn hình trước mọi redirect, còn `ensureInitialized()` chờ việc khôi phục phiên hoàn tất để quyết định được đưa ra dựa trên trạng thái thật. Không ghép module nào sở hữu phiên đăng nhập thì `_session` là null và app được coi như chưa đăng nhập. Mỗi trường hợp đi tới đâu do thêm hai hợp đồng `core_di` quyết định, cả hai resolve bằng `getItOrNull`: `ISignInLocation` (do `feature_auth` đóng góp: đường dẫn login) cho người dùng chưa đăng nhập — không có ai đăng ký thì không redirect — và `IPostSignInLocation` (do `feature_home` đóng góp: tab home) cho người đã đăng nhập — không có ai đăng ký thì về `AppRouter.fallbackLocation`. Widget tự gọi `context.go(path)`; nó không gọi tên module hay luồng sản phẩm nào.

**Các chuyển đổi về sau** đến qua hai stream subscription mở trong `initState` — `ISessionState.sessionChanges` và `.sessionFailures` — và được chặn theo hai cách khác nhau. `_onSessionChanged` (có điều hướng) bị bỏ qua cho tới khi `_bootCompleted && _session.hasRestoredSession`, để chính lần phát của bước khôi phục phiên không tranh giành lần điều hướng đầu tiên với redirect khởi động. `_onSessionFailure` (chỉ hiện toast) chỉ kiểm tra `_bootCompleted` — nó không điều hướng, nên không có gì để tranh giành. Bản thân `build` chỉ là `Overlay.wrap(child: widget.child)`.

**Deep link** được khởi động trong `_goToPostSignIn`, nên không bao giờ được route đè lên onboarding hay màn đăng nhập. Có module sở hữu phiên đăng nhập thì mọi đường đều được phủ — rời onboarding dẫn tới đăng nhập, và đăng nhập dẫn tới `_goToPostSignIn`. Không có module auth thì không bao giờ có lần đăng nhập nào, nên khi boot dừng ở entry location, widget sẽ khởi động deep link vào lần đầu router rời khỏi đó (`navigator_wrapper_widget_test.dart`).

> [!NOTE]
> `_goToOnboarding()` gán `viewedOnboard.value = true` trong khối `finally`, nên cờ được ghi ở lần boot đầu tiên có entry location, kể cả khi người dùng đã đăng nhập sẵn và onboarding chưa từng hiện. Cờ này nghĩa là "lần chạy đầu tiên đã qua", và `AppRouter.entryLocation` đọc nó đúng theo nghĩa đó: lần khởi động nguội kế tiếp bắt đầu ở `fallbackLocation`.

---

## 7. `AppMaterialWrapper` và `RootApp`

`AppMaterialWrapper` tồn tại để `MaterialApp` của splash và `MaterialApp` có router dùng chung một cấu hình. Hai constructor: mặc định (`MaterialApp` thường, dùng cho splash) và `.router` (dùng bởi `RootApp`).

Cây provider mà nó cài đặt:

```
MultiProvider(ThemeProvider, LanguageProvider)
└── Consumer2<ThemeProvider, LanguageProvider>
    └── AnnotatedRegion<SystemUiOverlayStyle>
        └── ChangeNotifierProvider(DeeplinkProvider)
            └── every IAppTreeWrapper (e.g. feature_auth's AuthProvider)
                └── MaterialApp[.router]
```

Chính `Consumer2` ở lớp ngoài là thứ khiến thay đổi theme và ngôn ngữ lan ra toàn app.

Trong cây không có `TooltipVisibility(visible: false)`. Trước đây có, để tooltip không bật lên khi nhấn giữ — nhưng nó cũng gỡ mọi tooltip khỏi cây semantics, mà screen reader đọc `tooltip` của một nút chỉ có icon làm nhãn của nút: nút ẩn/hiện mật khẩu bị đọc thành "button". Giờ theme làm việc đó thay: `ThemeProvider` đặt `tooltipTheme: TooltipThemeData(triggerMode: TooltipTriggerMode.manual)`, chặn popup khi nhấn giữ/chạm trên màn hình cảm ứng mà vẫn giữ nhãn (di chuột vẫn hiện bong bóng — trigger mode không áp dụng cho chuột). Xoá dòng đó nếu muốn lấy lại tooltip nhấn giữ mặc định của Material. `platform/shell/app_shell/test/accessibility_test.dart` kiểm tra nhãn vẫn còn.

Các delegate localization được gom từ DI bằng `getAllOrEmpty` — app không có feature nào đăng ký delegate vẫn resolve được bộ delegate toàn cục — nên feature không bao giờ phải sửa file này:

```dart
final delegates = [
  ...getAllOrEmpty<IFeatureLocalization>().map((e) => e.delegate),
  ...AppLocalizations.localizationsDelegates,
  ...GlobalMaterialLocalizations.delegates,
];
```

Các ngôn ngữ app cung cấp không phải hằng số ở đây: `supportedLocales` và việc chọn locale đến từ `LanguageSet` mà `LocaleProfile` của app định nghĩa (`LanguageProvider.languageSet`), còn delegate Material là của chính `material_ui`, nên một app chỉ có tiếng Việt vẫn có chuỗi Material tiếng Việt và không có cảnh báo.

`RootApp` cấp bốn đối tượng router từ `getIt<AppRouter>().router` và bổ sung `builder` toàn cục: các overlay host, `AppDialogController` và một `GestureDetector` bỏ focus bàn phím khi chạm ra ngoài. `AppMaterialWrapper` bọc mọi thứ một `builder` trả về — cho cả splash lẫn router — trong `MediaQuery.withClampedTextScaling(maxScaleFactor: display.textScaleMax)`, nên trang, toast và dialog dùng chung một trần text scale.

### Bản dịch của feature tới `MaterialApp` thế nào

Mỗi feature tự sở hữu bản dịch của mình. App shell không hề biết tên chúng.

| Ở đâu | Chứa gì |
|---|---|
| `modules/<f>/feature/assets/language/*.arb` | File dịch của feature |
| `modules/<f>/feature/l10n.yaml` | Cấu hình codegen cho feature đó |
| `modules/<f>/feature/lib/src/gen/language/` | Delegate + class được sinh ra |
| `modules/<f>/feature/lib/src/localization/<f>_localization_impl.dart` | Phần implement `IFeatureLocalization` |
| `core_base_ui` | Chuỗi global / fallback dùng chung |

> [!CAUTION]
> Một feature **tuyệt đối không** được sửa `platform/shell/app_shell/lib/src/root_app.dart` hay `app_material_wrapper.dart` để đăng ký delegate của nó. Việc đăng ký đi qua DI:

```dart
// platform/shell/app_shell/lib/src/app_material_wrapper.dart
// `getAllOrEmpty`, not `getIt.getAll`: the latter throws when no feature
// registers `IFeatureLocalization`. Every feature package is removable, so
// an app built without any of them must still resolve its delegates —
// falling back to the global `core_base_ui` ones.
final delegates = [
  ...getAllOrEmpty<IFeatureLocalization>().map((e) => e.delegate),
  ...AppLocalizations.localizationsDelegates,
  // material_ui's own delegates, not the SDK's — see AppMaterialWrapper.
  ...GlobalMaterialLocalizations.delegates,
];
```

Chính `getAllOrEmpty` là thứ khiến feature có thể gỡ bỏ được: xoá package đi thì danh sách chỉ đơn giản là ngắn lại.

Hợp đồng, trong `core_di`:

```dart
// platform/foundation/contracts/lib/src/i_feature_localization.dart
/// Interface for feature localization delegates.
/// Enables safe registration and retrieval via getAllOrEmpty<IFeatureLocalization>() in the app shell.
abstract class IFeatureLocalization {
  LocalizationsDelegate get delegate;
}
```

Cách thêm một chuỗi hay một ngôn ngữ: [`../guides/09_localization_theming.md`](../guides/09_localization_theming.md).

### Cỡ chữ của hệ điều hành được tôn trọng, tối đa 2x

`builder` của `RootApp` trước đây kết thúc bằng `MediaQuery.withNoTextScaling`, ghim mọi chữ ở 100% bất kể người dùng đặt gì — một lỗi accessibility (WCAG 2.2 SC 1.4.4 yêu cầu chữ phóng được tới 200%), không phải một lựa chọn bố cục. Giờ nó kẹp (clamp) thay vì tắt: cài đặt của người dùng đi qua nguyên vẹn tới `DisplayProfile.textScaleMax` (mặc định 2.0 — app có thể cho phép nhiều hơn, còn một `const` assert trong [`display_profile.dart`](../../../platform/foundation/kernel/lib/src/profile/display_profile.dart) từ chối giá trị thấp hơn, RULE-38), kể cả scaler phi tuyến (Android 14+), và đầu dưới không bị kẹp.

Điều này **không** scale chữ hai lần với `core_responsive`. Hai hệ số độc lập và được áp ở hai chỗ khác nhau:

| Hệ số | Ai áp | Trả lời câu hỏi |
|:--|:--|:--|
| `context.sp(x)` (thang chữ của theme, `AppTextStyles`) | `core_responsive`, vào `TextStyle.fontSize` | "cỡ thiết kế này to bao nhiêu trong cửa sổ này?" — theo chiều rộng cửa sổ, kẹp bởi `textScaleBounds`. Nó không bao giờ đọc `MediaQuery.textScaler` |
| `MediaQuery.textScaler` | `Text` / `RichText` của Flutter, lúc layout | "người dùng muốn chữ to hơn bao nhiêu?" |

Một style body 16 đơn vị là 16 × (hệ số cửa sổ) logical pixel, rồi × tỉ lệ của người dùng khi vẽ — mỗi cái đúng một lần. Thứ **không** lớn theo text scale là bố cục đặt kích thước bằng `context.h` / `context.w`: một hộp cao cố định chứa chữ có thể tràn ở 2x. Hãy để khung chứa chữ tự co theo nội dung (padding, `minHeight`), đừng đặt chiều cao cố định. `modules/auth/feature/test/login_page_text_scale_test.dart` và `modules/dashboard/feature/test/dashboard_text_scale_test.dart` dựng màn hình đăng nhập trên ba cỡ điện thoại và phần chrome của dashboard từ điện thoại tới desktop ở 2x, và fail khi có bất kỳ overflow nào — hãy chép chúng cho màn hình mới.

---

## 8. Đi tiếp từ đâu

| Việc cần làm | Hướng dẫn |
|:--|:--|
| Đăng ký route từ một feature | [`../guides/04_routing.md`](../guides/04_routing.md) |
| Thêm một đăng ký DI cho đúng | [`../guides/05_di.md`](../guides/05_di.md) |
| Thêm một giá trị lưu trữ | [`../guides/06_storage.md`](../guides/06_storage.md) |
| Cấu hình mạng / pinning | [`../guides/08_networking.md`](../guides/08_networking.md) |
| Hiểu các tầng bên dưới | [`01_overview.md`](01_overview.md) |
