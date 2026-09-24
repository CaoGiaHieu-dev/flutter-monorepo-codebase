# App Shell (`platform/app_shell/` + `apps/<id>/`)

Tài liệu này trả lời câu hỏi **"từ lúc chạm icon đến khi thấy màn hình đầu tiên, chuyện gì xảy ra, và ai lắp ráp mọi thứ lại?"**. Đọc xong bạn sẽ gỡ được lỗi khởi động, thêm được adapter cho shell, và hiểu vì sao thứ tự các nhóm DI trong `app_manifest.yaml` không hề tuỳ tiện.

Shell được tách làm hai, có chủ đích:

- **`apps/<id>/`** là **điểm lắp ráp (composition root)** — nơi duy nhất được phép phụ thuộc mọi tầng, và nơi duy nhất biết danh sách đầy đủ các module. Nó chỉ chứa những gì thực sự khác nhau giữa các app, ngoài ra không có gì khác.
- **`platform/app_shell/`** (`platform_app_shell`) là mọi thứ app nào cũng cần và lẽ ra phải copy: boot scope, lắp ráp router, material wrapper, các storage adapter và `NetworkConfigImpl`. Nó không import module nào — `arch_check` R1 giữ điều đó, vì đây là một package `platform/`.

Trước khi tách, thêm app thứ hai nghĩa là copy 1.369 dòng qua 24 file. Giờ một app chỉ là một manifest, một `injection.dart` được sinh ra, một `main.dart` dài một dòng, và những gì định danh chính nó — ở app mẫu là Firebase options.

---

## 1. Cái gì nằm ở đâu

```
apps/mobile/                         điểm lắp ráp
├── app_manifest.yaml                module nào, thứ tự nhóm DI ra sao
├── lib/
│   ├── main.dart                    một dòng: runShellApp(configureDependencies: …)
│   ├── di/injection.dart            do composer sinh — không bao giờ sửa tay
│   └── firebase/firebase_module.dart FirebaseOptions của app này (file options bị git-ignore)
├── android/  ios/  fastlane/        project native và lane phát hành
└── env.dev  env.stg                 giá trị theo flavor (env.prod bạn tự tạo)

platform/app_shell/lib/              dùng chung cho mọi app
├── bootstrap.dart                   runShellApp — error zone, DI, splash, init
├── main_scope.dart                  splash → init → chuyển sang root
├── di/
│   ├── module.dart                  @InjectableInit.microPackage — nhóm DI `shell`
│   ├── theme_storage_impl.dart      IThemeStorage    → StorageValue<ThemeMode>
│   ├── language_storage_impl.dart   ILanguageStorage → StorageValue<String>
│   ├── app_boot_storage.dart        cờ khởi động    → StorageValue<bool>
│   ├── network_config_impl.dart     NetworkConfig
│   ├── network_binding_module.dart  binding SslPinningConfig
│   └── utils/                       storage key do shell sở hữu
└── presentation/
    ├── root_app.dart                MaterialApp có router
    ├── app_material_wrapper.dart    cấu hình MaterialApp dùng chung
    ├── navigation/app_router.dart   lắp ráp GoRouter
    ├── providers/                   AppProvider, DeeplinkProvider
    └── widgets/                     NavigatorWrapperWidget, UndefineRouteWidget
```

### App thứ hai: `apps/admin`

[`apps/admin`](../../../apps/admin/README.md) là cùng shell này ghép một tập con khác — `auth` và `settings`, không có dashboard, splash, onboarding, home hay Firebase. Toàn bộ `lib/` của nó là `main.dart` và `di/` — `injection.dart` được sinh ra cùng barrel của nó. Mọi lookup tuỳ chọn trong package này đều thiếu đóng góp ở đó, nên các fallback mô tả bên dưới có một bản ghép thật dựa vào chúng — khi có người chạy nó; hiện CI chưa build app này.

---

## 2. Vòng đời khởi động

```mermaid
sequenceDiagram
    autonumber
    participant M as runShellApp()
    participant DI as configureDependencies()
    participant S as MainScope.run()
    participant N as FlutterNativeSplash
    participant I as AppInitializer.init()
    participant R as RootApp / AppRouter

    M->>M: runZonedGuarded(...)
    M->>M: WidgetsFlutterBinding.ensureInitialized()
    M->>DI: await configureDependencies()
    Note over DI: mọi module đăng ký xong<br/>trước khi có bất kỳ UI nào
    DI-->>M: container sẵn sàng
    M->>S: MainScope(splashScreen, root, initService).run()

    alt splashScreen == null (iOS)
        S->>N: preserve()
        S->>I: await [initService(), delay 2s]
        S->>N: remove()
        S->>R: runApp(root)
    else splashScreen != null (Android / Web)
        S->>N: remove()
        S->>S: runApp(AppMaterialWrapper(home: splash))
        S->>S: await endOfFrame
        S->>I: await [initService(), delay 2s]
        S->>R: widget.value = root  (AnimatedSwitcher fade)
    end

    R->>R: AppRouter.router dựng lười khi truy cập lần đầu
```

### Từng bước

Trình tự này nằm trong `runShellApp()` ([`platform/app_shell/lib/bootstrap.dart`](../../../platform/app_shell/lib/bootstrap.dart)); `main.dart` của app chỉ gọi nó với `configureDependencies` được sinh cho chính app đó.

1. **`runZonedGuarded`** bọc toàn bộ để lỗi bất đồng bộ không bắt được vẫn được báo cáo thay vì mất tăm. Mỗi lỗi đi qua callback `onError` (tuỳ chọn) của app — chỗ để gắn crash reporter — rồi tới `FlutterError.reportError`.
2. **`WidgetsFlutterBinding.ensureInitialized()`** — bắt buộc trước mọi lời gọi plugin.
3. **`await configureDependencies()`** chạy *trước* `MainScope`. Đến lúc widget đầu tiên build, cả container đã phân giải xong.
4. **`MainScope`** được dựng với ba thứ: hiển thị splash widget nào (nếu có), widget gốc, và `initService` — ở đây là `AppInitializer.init(routeObserver: getIt<AppRouter>().routeObserver)`.
5. **`mainScope.run()`** rẽ nhánh tuỳ theo có truyền splash widget Dart hay không.

### Hai đường splash

`runShellApp` chọn splash theo nền tảng, và lấy nó từ module nào đã đăng ký `IAppSplashScreen` — ở app mẫu là `feature_splash`:

```dart
final usesDartSplash = kIsWeb || !Platform.isIOS;
// ...
splashScreen: usesDartSplash
    ? getItOrNull<IAppSplashScreen>()?.build()
    : null,
```

| Nền tảng | `splashScreen` | Hành vi |
|:--|:--|:--|
| iOS | `null` | Splash native được **giữ lại** suốt quá trình init rồi mới gỡ. Không có splash Dart nào được vẽ. |
| Android, Web, desktop | `IAppSplashScreen.build()` | Splash native gỡ ngay lập tức; splash đã đăng ký được vẽ thay thế, rồi mờ dần sang `RootApp` qua `AnimatedSwitcher`. Không ghép module splash nào thì giá trị là `null` và đi theo đường của iOS. |

Cả hai đường đều `await Future.wait([initService(), Future.delayed(_minimumDelay)])`, với `_minimumDelay` là 2 giây. Độ trễ này là **sàn**, không phải cộng thêm — init nhanh vẫn phải chờ để splash không bị nháy.

> [!NOTE]
> `SplashPage` do `MainScope` hiển thị, **không** phải do GoRouter. Nó không có route và không bao giờ xuất hiện trong ngăn xếp điều hướng.

### `_ResponsiveWrapper`

Cả hai đường đều bọc cây widget trong **`ResponsiveInit`** (từ `core_responsive`). Nó nằm ở đúng gốc cây, nên mọi widget phía dưới đều gọi được `context.w(x)` / `context.h(x)` / `context.sp(x)` / `context.r(x)`. Cấu hình này chính là toàn bộ chính sách scale của app:

| Thiết lập | Giá trị | Tác dụng |
|:--|:--|:--|
| `designSize` | `AppConfig.design` (375×812) | Khung điện thoại mà mọi lớp cửa sổ bắt đầu từ đó |
| `scaleBounds` / `textScaleBounds` | để mặc định, `ScaleBounds.downOnly()` | Cửa sổ nhỏ hơn khung thì thiết kế thu nhỏ; cửa sổ lớn hơn — tablet, cửa sổ desktop — vẽ 1:1 và để chỗ dư cho layout |
| `profiles` | `WindowSizeClass.expanded` → `ScaleBounds.fixed()` cho layout và chữ | Từ rộng 840 trở lên (nên cả `large` và `extraLarge`), dùng logical pixel thật — cửa sổ laptop thấp hơn 812 không còn làm mọi khoảng cách dọc nhỏ đi |
| `splitScreenMode` | `true` | Chặn dưới chiều cao dùng để scale ở 700, để một ô chia đôi màn hình thấp vẫn dùng được |

Theme scale chữ bằng `context.sp`, nên nó đi theo `textScaleBounds` như mọi thứ khác. Cho một lớp phóng to là opt-in — một `ResponsiveProfile` với bound có chặn, ví dụ `ScaleBounds(max: 1.2)`. Bảng tham số đầy đủ, mỗi cửa sổ nhận được gì, và các widget thích ứng dùng chỗ dư nằm ở [`11_design_system.md`](../guides/11_design_system.md) §6–§7.

`ResponsiveInit` là `StatelessWidget`: nó đọc `MediaQuery.sizeOf(context)` — dependency **chỉ theo size** — nên tự rebuild khi màn hình đổi kích thước và bỏ qua thay đổi brightness / textScale / padding. Metrics được phát xuống qua `ResponsiveScope`, một `InheritedWidget`, nên widget nào đọc metrics là tự đăng ký theo dõi chúng — không có cờ rebuild nào để tinh chỉnh.

> [!NOTE]
> Trước đây ở đây có một `fontSizeResolver` tính tỉ lệ chiều rộng từ `View.of(context).display` — màn hình vật lý, không phải cửa sổ. Khi toàn màn hình thì hai cái khớp nhau; khi split-screen hay đổi kích thước cửa sổ, chữ scale theo cả màn hình trong khi mọi kích thước khác theo cửa sổ. `ResponsiveInit` đo cửa sổ qua `MediaQuery`, nên mặc định đã thay được resolver. Cũng đừng đưa resolver trở lại để chặn cỡ chữ: kết quả của resolver không bao giờ bị `textScaleBounds` kẹp, mà mức chặn đó giờ nằm chính ở `textScaleBounds`.

Việc scale vẫn phải đi qua `BuildContext` — `core_responsive` **không có extension trên `num`**, nên `16.h` đơn giản là không biên dịch được. Xem [luật 12](../reference/01_rules.md#12-responsive-ui), và lưu ý luật R7 của `arch_check` chặn mọi dạng bare còn sót ở mọi PR.

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
| 1 | `_coreModules` | `core_common`, `core_network`, `core_storage`, `core_database`, `core_di` |
| – | `lib/` của chính app | `FirebaseModule` — `FirebaseOptions` theo flavor ([`apps/mobile/lib/firebase/firebase_module.dart`](../../../apps/mobile/lib/firebase/firebase_module.dart)) |
| 2 | `_notificationsModules` | `core_notifications` — `PushNotificationService` (eager) inject chính các `FirebaseOptions` đó, nên phải đứng sau |
| 3 | `_shellModules` | `platform_app_shell` — `AppRouter`, `AppProvider`, `DeeplinkProvider`, `AppBootStorage`, `ILanguageStorage`, `IThemeStorage`, `NetworkConfig`, `SslPinningConfig` |
| 4 | `_uiModules` | `core_base_ui` |
| 5 | `_domainModules` → `_dataModules` → `_featureModules` → `_otherModules` | |

Package app chỉ đăng ký thứ định danh nó: Firebase options, vốn gắn với một bundle ID nên không thể nằm trong `platform/`. Mọi thứ khác đều đến qua một nhóm.

### Vì sao `shell` đứng trước `ui`

Đây là luật ngầm quan trọng nhất trong phần DI, và manifest có ghi rõ trong một comment.

`core_base_ui` đăng ký `ThemeProvider` và `LanguageProvider`, hai provider này inject `IThemeStorage` và `ILanguageStorage`. Hai interface đó được hiện thực trong `platform_app_shell` (`theme_storage_impl.dart`, `language_storage_impl.dart`), không phải trong package core nào mà các provider có thể phụ thuộc trực tiếp. Vì vậy `shell` phải khởi tạo trước. Đảo hai nhóm là app hỏng lúc khởi động với lỗi "IThemeStorage is not registered".

Đây cũng đúng là vị trí mà các đăng ký này chiếm trước khi shell thành package. Trước đây chúng là đăng ký cục bộ của app, thứ mà injectable chạy *giữa* `…Before` và `…After`; giờ `shell` chạy sớm trong `…After` — đầu tiên ở `apps/admin`, ngay sau `notifications` ở `apps/mobile`. Thứ tự app khởi động không đổi — chỉ chỗ đặt code là đổi.

### Cái bẫy thứ tự với eager singleton

> [!CAUTION]
> Một `@Singleton` eager được dựng **ngay lúc đăng ký**. Nếu nó phụ thuộc một kiểu do module chạy *sau* đăng ký, khởi động sẽ ném `… is not registered`.
>
> `flutter analyze` không thể phát hiện lỗi này — đây là lỗi thứ tự lúc chạy. Hãy kiểm chứng bằng cách đọc các file sinh ra: `apps/mobile/lib/di/injection.config.dart` cho thứ tự module, còn `lib/di/module.module.dart` của từng package cho đăng ký theo type — mọi `gh<Dep>()` mà một singleton eager gọi phải được đăng ký *phía trên* nó, hoặc bởi một module khởi tạo sớm hơn.

Ví dụ thật: `ThemeProvider` của `core_base_ui` inject `IThemeStorage`, do nhóm `shell` đăng ký. Đó là lý do `shell` được xếp trước `ui` trong `di_groups` của mọi app — đảo lại là app hỏng lúc boot. (`NetworkConfigImpl` từng là ví dụ ở đây, vì inject `AuthLocalDataSource` từ một module chạy sau. Giờ nó resolve `IAuthSessionGateway` ngay lúc gọi, và không còn dependency constructor nào xuyên module.)

### `AppRouter` là eager, nhưng router của nó thì không

`AppRouter` *đúng là* `@singleton` (eager), nhưng vẫn an toàn: `router` là trường `late final`.

```dart
late final GoRouter router = GoRouter( … );
```

`GoRouter` — cùng các lời gọi `getAllOrEmpty<IFeatureRouteModule>()` bên trong nó — không được tính toán cho tới khi có ai đó đọc `.router` lần đầu. Lúc đó mọi feature module đã đăng ký xong. Nếu `router` là trường thường, router sẽ được lắp trong bước 2 và gom được **không** route feature nào.

---

## 4. Adapter của shell

Shell hiện thực những hợp đồng mà package core khai báo nhưng tự nó không thể thoả mãn. Mỗi adapter sở hữu `StorageValue` riêng và giữ key trong `platform/app_shell/lib/di/utils/`.

| File | Hiện thực | Sở hữu | Cách đăng ký |
|:--|:--|:--|:--|
| `theme_storage_impl.dart` | `IThemeStorage` | `themeMode` (pref) | `@Singleton(as: IThemeStorage)` + `@PostConstruct(preResolve: true)` |
| `language_storage_impl.dart` | `ILanguageStorage` | `locale` (pref) | như trên |
| `app_boot_storage.dart` | — | `viewed_onboard` (pref) | `@singleton` + `@PostConstruct(preResolve: true)` |
| `network_config_impl.dart` | `NetworkConfig` | — | `@LazySingleton(as: NetworkConfig)` |
| `network_binding_module.dart` | bind `SslPinningConfig` | — | `@module` |

### Vì sao `SslPinningConfig` cần binding riêng

`NetworkConfig implements SslPinningConfig`, nhưng **GetIt phân giải theo đúng kiểu đã đăng ký và không đi ngược chuỗi supertype**. Chỉ đăng ký `as: NetworkConfig` khiến `getItOrNull<SslPinningConfig>()` trả `null`, nên `AppInitializer` bỏ qua pinning hoàn toàn — âm thầm, trên mọi flavor.

Vì vậy kiểu thứ hai cần một binding riêng qua module, đúng mẫu dual-registration mà `feature_auth` dùng cho `IAuthStatusStream`:

```dart
@module
abstract class NetworkBindingModule {
  @lazySingleton
  SslPinningConfig bindSslPinningConfig(NetworkConfig config) => config;
}
```

Tham số khai kiểu `NetworkConfig` nên phép upcast được trình biên dịch kiểm tra — không cần ép kiểu `as`.

---

## 5. Lắp ráp router

[`app_router.dart`](../../../platform/app_shell/lib/presentation/navigation/app_router.dart) dựng GoRouter **hoàn toàn từ các đóng góp qua DI**.

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
        └── builder → DashboardRouteModule
```

Mọi điểm gom đều lùi về phương án dự phòng khi không có đóng góp nào:

| Thiếu | Dự phòng |
|:--|:--|
| `IFeatureRouteModule` | danh sách rỗng |
| `INavDestinationModule` | một nhánh giữ chỗ tại `/_empty_dashboard` vẽ `SizedBox.shrink()` |
| `DashboardRouteModule` | chính `navigationShell` — các tab không có chrome |
| `IAppEntryLocation` | `AppRouter.fallbackLocation`: path của tab dashboard đầu tiên (`order` nhỏ nhất), nếu không có thì placeholder `/_empty_dashboard` (không phải `/`) |

Nhờ vậy, xoá một feature package không thể làm sập shell.

> [!CAUTION]
> **Tuyệt đối không hardcode route của feature vào `app_router.dart`.** Hãy đăng ký `IFeatureRouteModule` hoặc `INavDestinationModule` trong DI module của chính feature đó. Xem [`../guides/04_routing.md`](../guides/04_routing.md).

`refreshListenable: getItOrNull<IAuthRefreshListenable>()` (được `feature_auth` bind vào `AuthProvider` của nó) khiến GoRouter đánh giá lại redirect khi trạng thái đăng nhập đổi. `errorPageBuilder` vẽ `UndefineRouteWidget` — một widget có tên, không bao giờ dùng closure ẩn danh.

---

## 6. `NavigatorWrapperWidget` — điều hướng đầu tiên và các chuyển đổi auth

Nằm bên trong app `ShellRoute` và bọc mọi route trong app. Nó tách điều hướng thành hai trách nhiệm riêng biệt.

**Redirect lúc khởi động** chỉ chạy một lần, trong `initState`, hoãn tới `endOfFrame`:

```dart
WidgetsBinding.instance.endOfFrame.whenComplete(() async {
  await _session?.ensureInitialized(); // IAuthSessionState, via getItOrNull
  if (!mounted) return;
  // onboarding? → login? → home
  _bootCompleted = true;
});
```

Chờ `endOfFrame` bảo đảm khung hình đầu tiên đã lên màn hình trước mọi redirect, còn `ensureInitialized()` chờ việc khôi phục phiên hoàn tất để quyết định được đưa ra dựa trên trạng thái thật. Không ghép module auth nào thì `_session` là null và app được coi như chưa đăng nhập.

**Các chuyển đổi về sau** đến qua hai stream subscription mở trong `initState` — `IAuthSessionState.sessionChanges` và `.sessionFailures` — và được chặn theo hai cách khác nhau. `_onSessionChanged` (có điều hướng) bị bỏ qua cho tới khi `_bootCompleted && _session.hasRestoredSession`, để chính lần phát của bước khôi phục phiên không tranh giành lần điều hướng đầu tiên với redirect khởi động. `_onSessionFailure` (chỉ hiện toast) chỉ kiểm tra `_bootCompleted` — nó không điều hướng, nên không có gì để tranh giành. Bản thân `build` chỉ là `Overlay.wrap(child: widget.child)`.

> [!WARNING]
> `_goToOnboarding()` gán `viewedOnboard.value = true` trong khối `finally`, nên cờ vẫn được ghi ngay cả khi hàm trả về `false` vì người dùng đã đăng nhập sẵn. Trong trường hợp đó màn onboarding chưa từng được hiển thị. Hiện tại vô hại, nhưng cờ này không mang đúng ý nghĩa như tên gọi của nó.

---

## 7. `AppMaterialWrapper` và `RootApp`

`AppMaterialWrapper` tồn tại để `MaterialApp` của splash và `MaterialApp` có router dùng chung một cấu hình. Hai constructor: mặc định (`MaterialApp` thường, dùng cho splash) và `.router` (dùng bởi `RootApp`).

Cây provider mà nó cài đặt:

```
MultiProvider(ThemeProvider, LanguageProvider)
└── Consumer2<ThemeProvider, LanguageProvider>
    └── AnnotatedRegion<SystemUiOverlayStyle>
        └── TooltipVisibility(visible: false)
            └── MultiProvider(AppProvider, DeeplinkProvider)
                └── every IAppTreeWrapper (e.g. feature_auth's AuthProvider)
                    └── MaterialApp[.router]
```

Chính `Consumer2` ở lớp ngoài là thứ khiến thay đổi theme và ngôn ngữ lan ra toàn app.

Các delegate localization được gom từ DI bằng `getAllOrEmpty` — app không có feature nào đăng ký delegate vẫn resolve được bộ delegate toàn cục — nên feature không bao giờ phải sửa file này:

```dart
final delegates = [
  ...getAllOrEmpty<IFeatureLocalization>().map((e) => e.delegate),
  ...AppLocalizations.localizationsDelegates,
];
```

`RootApp` cấp bốn đối tượng router từ `getIt<AppRouter>().router` và bổ sung `builder` toàn cục: các overlay host, `AppDialogController`, một `GestureDetector` bỏ focus bàn phím khi chạm ra ngoài, và `MediaQuery.withNoTextScaling` để bố cục không bị xô lệch.

---

## 8. Đi tiếp từ đâu

| Việc cần làm | Hướng dẫn |
|:--|:--|
| Đăng ký route từ một feature | [`../guides/04_routing.md`](../guides/04_routing.md) |
| Thêm một đăng ký DI cho đúng | [`../guides/05_di.md`](../guides/05_di.md) |
| Thêm một giá trị lưu trữ | [`../guides/06_storage.md`](../guides/06_storage.md) |
| Cấu hình mạng / pinning | [`../guides/08_networking.md`](../guides/08_networking.md) |
| Hiểu các tầng bên dưới | [`01_overview.md`](01_overview.md) |
