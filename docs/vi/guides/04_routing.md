# Routing & Điều hướng

**File này trả lời:** làm sao thêm một màn hình, và làm sao điều hướng sang màn hình thuộc feature khác?

**Đọc xong bạn làm được:** đăng ký route từ bên trong feature package mà không đụng app shell, dựng route type-safe bằng `go_router_builder`, và điều hướng xuyên feature qua interface thay vì hardcode path.

---

## 1. Ý tưởng cốt lõi: routing là phi tập trung

`platform/shell/app_shell/lib/presentation/navigation/app_router.dart` **chỉ lắp ráp**. Nó không bao giờ gọi tên route của feature nào — nó gom những gì feature đã đăng ký qua DI:

```dart
List<INavDestinationModule> get _destinations {
  return getAllOrEmpty<INavDestinationModule>().toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

List<RouteBase> get _featureRoutes {
  return [
    for (final module in getAllOrEmpty<IFeatureRouteModule>())
      ...module.routes,
  ];
}
```

> [!CAUTION]
> **Tuyệt đối không sửa `app_router.dart` để thêm route.** Thêm `$myFeatureRoute` vào đó là buộc app shell dính chặt vào feature của bạn, phá vỡ cam kết "gỡ feature ra app vẫn chạy". Hãy đăng ký contract trong DI module của chính feature.

Cây shell mà nó dựng lên:

```
GoRouter (navigatorKey: NavigatorKeys.rootKey)
└── ShellRoute (navigatorKey: appKey)  →  NavigatorWrapperWidget
    ├── ...route từ IFeatureRouteModule        ← auth, onboarding, …
    └── StatefulShellRoute.indexedStack        →  DashboardRouteModule.builder
        └── mỗi INavDestinationModule một StatefulShellBranch (sắp theo order)
```

---

## 2. Bốn contract routing

Tất cả nằm ở `platform/foundation/contracts/lib/src/routing/`.

| Contract | Dùng cho | Có thứ tự? | Ai implement |
|---|---|---|---|
| `IFeatureRouteModule` | Route top-level / dạng stack dưới app shell | Không — GoRouter khớp theo path | auth, onboarding, … |
| `INavDestinationModule` | Một tab bottom-nav + `StatefulShellBranch` của nó | **Có** — `order` tăng dần | home, settings, … |
| `IAppEntryLocation` | Điểm bắt đầu ở lần chạy đầu tiên (`initialLocation` cho tới khi đã hiện một lần) | n/a | thường là onboarding |
| `ISignInLocation` | Nơi shell đưa người dùng chưa đăng nhập tới (boot, đăng xuất, mất phiên) | n/a | module sở hữu phiên — `feature_auth` |
| `IPostSignInLocation` | Nơi shell đưa người dùng đã đăng nhập tới (boot, đăng nhập); không có thì `fallbackLocation` | n/a | module trang đích — `feature_home` |
| `DashboardRouteModule` | Chrome của dashboard (scaffold + host bottom bar / rail) | n/a | **chỉ** `feature_dashboard` |

### 2.1 `IFeatureRouteModule`

```dart
abstract class IFeatureRouteModule {
  List<RouteBase> get routes;
}
```

Đăng ký trong chính feature sở hữu — `modules/onboarding/feature/lib/src/routing/onboarding_feature_route_module.dart`:

```dart
@LazySingleton(as: IFeatureRouteModule)
class OnboardingFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$onboardingRoute];
}

@LazySingleton(as: IAppEntryLocation)
class OnboardingAppEntryLocation implements IAppEntryLocation {
  @override
  String get path => OnboardingPath.ONBOARDING;
}
```

Hãy dùng path duy nhất và tránh catch-all chồng lấn — thứ tự giữa các module không được đảm bảo.

### 2.2 `INavDestinationModule`

```dart
abstract class INavDestinationModule {
  int get order;                    // 0 = tab đầu tiên
  String get path;                  // path chuẩn, dùng cho fallback
  List<RouteBase> get routes;       // mount trong một StatefulShellBranch
  // Bấm lại vào tab đang active. Là method cụ thể, không abstract: thân mặc
  // định chỉ ghi log — override nó để "cuộn lên đầu / pop về gốc".
  void onRestore() {
    DynamicLogger.log('onRestore $runtimeType', level: LogLevel.INFO);
  }
  NavDestination destination(BuildContext context);
}
```

`modules/home/feature/lib/src/routing/home_nav_destination.dart`:

```dart
@LazySingleton(as: INavDestinationModule)
class HomeNavDestination extends INavDestinationModule {
  @override
  int get order => 0;

  @override
  String get path => HomePath.HOME;

  @override
  List<RouteBase> get routes => [$homeRoute];

  @override
  NavDestination destination(BuildContext context) => NavDestination(
    label: context.l10nHome.tabLabel,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  );
}
```

> [!NOTE]
> Chỉ dùng `INavDestinationModule` cho **đích đến bottom-nav thật sự** cần back stack riêng bền vững. Màn hình chỉ push lên stack thì thuộc về `IFeatureRouteModule`.

### 2.3 Dashboard chỉ là chrome

Trong các package của workspace, `feature_dashboard` chỉ phụ thuộc `core_di`, `core_responsive` và `platform_kernel` — nó **về mặt vật lý không thể** import feature khác. Page của nó dựng điều hướng từ DI (`modules/dashboard/feature/lib/src/pages/dashboard_page.dart`): bottom bar trên cửa sổ `compact`, `NavigationRail` từ `medium` trở lên.

```dart
final tabs = getAllOrEmpty<INavDestinationModule>().toList()
  ..sort((a, b) => a.order.compareTo(b.order));
if (tabs.length < 2) return Scaffold(body: navigationShell);
// …
final sizeClass = context.windowSizeClass;
if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
  return Scaffold(
    body: navigationShell,
    bottomNavigationBar: BottomNavigationBar(
      // …
    ),
  );
}
// … otherwise a NavigationRail beside the navigationShell
```

Dashboard **không được**:
- import `feature_home` / `feature_settings` hay nhúng page của chúng
- sở hữu page của tab hoặc BLoC nghiệp vụ của tab
- hardcode danh sách destination thay vì đọc DI
- tự đăng ký `INavDestinationModule` để tạo tab "giả"

Chú ý `tabs.length < 2` bỏ hẳn bar (hoặc rail) khi có ít hơn hai tab — một phần của cơ chế suy giảm mềm ở §7. `destination` của một tab là một `NavDestination` trung lập, nên cùng một đóng góp hiển thị được thành mục của bar hay của rail; vì sao chrome đổi theo lớp kích thước cửa sổ thì xem [`11_design_system.md`](11_design_system.md#7-layout-thích-ứng-tablet-máy-gập-chia-đôi-màn-hình) §7.

---

## 3. Route type-safe với `go_router_builder`

Route được khai bằng annotation và sinh ra `*_route_module.g.dart`. **Phải chạy `dart run build_runner build --workspace` sau mỗi thay đổi.**

Hằng số path nằm ở thư mục `src/utils/` của feature, không nằm trong `routing/` — mọi package đều giữ constants của mình dưới `utils/`:

`modules/auth/feature/lib/src/utils/auth_path.dart`:

```dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
}
```

`modules/auth/feature/lib/src/routing/auth_route_module.dart`:

```dart
@TypedShellRoute<AuthShellRoute>(
  routes: [TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)],
)
class AuthShellRoute extends ShellRouteData {
  const AuthShellRoute();

  static final $navigatorKey = NavigatorKeys.nested('auth');
  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return navigator;
  }
}

class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.nested('auth');
  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
```

Thêm route anh em bằng các mục `TypedGoRoute` khác trong `routes:` — chúng dùng chung Navigator lồng của shell, nên dùng chung một back stack. `$authShellRoute` được sinh ra chính là thứ feature trả về từ `IFeatureRouteModule.routes`.

---

## 4. Khởi tạo controller ở route

`build()` của route là nơi controller màn hình được tạo và gắn vào cây widget.

**BLoC** — `modules/home/feature/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no ISessionStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<ISessionStatusStream>(),
      ),
      child: const HomePage(),
    );
  }
}
```

**Provider** — cùng hình dạng:

```dart
@override
Widget build(BuildContext context, GoRouterState state) {
  return ChangeNotifierProvider(
    create: (context) => getIt<ProfileProvider>(),
    child: const ProfilePage(),
  );
}
```

> [!CAUTION]
> Bản thân page **không được** bọc provider lần thứ hai. Xem [`03_state_management.md`](03_state_management.md) §4.

Route của màn hình dùng controller **toàn cục** (ví dụ `LoginPage` với `AuthProvider` là `@lazySingleton`) thì build thẳng page, không bọc gì.

---

## 5. Điều hướng xuyên feature

Feature A không bao giờ được import Feature B. Điều hướng vượt ranh giới thông qua interface đặt trong **package API của module B** — `modules/<id>/api`, tên `<id>_api` — mà feature A phụ thuộc thay cho feature B (`arch_check` R3). `core_di` không chứa navigator của module nào.

**1. Khai báo** — `modules/auth/api/lib/src/navigators/auth_navigator.dart` (package `auth_api`):

```dart
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
```

Mỗi route mà feature sở hữu là một method — và chỉ những route nó sở hữu.

Một file **mới** trong package API sẽ vô hình với mọi nơi dùng cho tới khi barrel export nó — `package:auth_api/auth_api.dart` re-export `src/navigators/navigators.dart`, là file được sinh ra. Hãy sinh lại nó (đừng tự thêm dòng `export`; generator xoá các dòng viết tay). Module chưa có package API thì tạo nó trước: `docs/vi/guides/12_module_isolation.md` § 7.

```bash
dart tools/barrel_generator/generate.dart modules/auth/api/lib
```

**2. Implement trong feature sở hữu** — `modules/auth/feature/lib/src/routing/auth_navigator_impl.dart`:

```dart
@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) => const LoginRoute().go(context);
}
```

**3. Gọi từ bất kỳ feature nào có `auth_api` trong `dependencies:`:**

```dart
// Từ mọi package khác package sở hữu — package sở hữu có thể bị gỡ:
getItOrNull<AuthNavigator>()?.toLogin(context);

// Chỉ bên trong chính feature_auth, nơi nó không thể vắng mặt:
getIt<AuthNavigator>().toLogin(context);
```

### Quy tắc

- **RULE-22** · Một Navigator interface **chỉ** phơi ra route mà chính feature đó sở hữu.
- **RULE-22** · **Không bao giờ** hardcode chuỗi path hay gọi `GoRouter.of(context).go('/auth/login')` để sang feature khác.
- **RULE-23** · **`BuildContext` phải được truyền trực tiếp từ widget gọi.** Đừng lấy từ `NavigatorKeys.*.currentContext` hay `appRouter.currentContext` — cách đó bỏ qua vòng đời widget và sinh lỗi "dùng sau khi dispose".
- **RULE-12** · Dùng `getItOrNull` ở những chỗ gọi cần sống sót khi feature đích bị gỡ.
- **RULE-22** · **App shell không dùng navigator của module nào.** Người dùng chưa đăng nhập được đưa tới `ISignInLocation.path`, người đã đăng nhập tới `IPostSignInLocation.path` — hợp đồng `core_di` trung lập với sản phẩm, do module sở hữu phiên đăng nhập và module trang đích đóng góp (`AuthSignInLocation`, `HomePostSignInLocation`); `NavigatorWrapperWidget` tự gọi `context.go(path)`.

---

## 6. `NavigatorKeys` — vì sao đặt ở DI Hub

`platform/foundation/contracts/lib/src/routing/navigator_keys.dart`:

```dart
class NavigatorKeys {
  NavigatorKeys._();

  static final appKey = GlobalKey<NavigatorState>(debugLabel: 'app');
  static final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  static final _nested = <String, GlobalKey<NavigatorState>>{};

  /// The nested navigator key registered under [id], created on first use.
  static GlobalKey<NavigatorState> nested(String id) => _nested.putIfAbsent(
    id,
    () => GlobalKey<NavigatorState>(debugLabel: 'nested:$id'),
  );
}
```

Một `ShellRoute` và các route con của nó phải tham chiếu **cùng một** instance `GlobalKey`. Shell do app shell lắp ráp; route con lại khai bên trong feature package. Đặt key ở một trong hai phía đều phạm luật — shell (`platform_app_shell`) là core nên không được phụ thuộc feature (R1), còn feature thì không được phụ thuộc shell. `core_di`, thứ mà cả hai phía đều đã phụ thuộc, là nơi trung lập.

DI Hub không khai key nào mang tên feature. `nested(id)` trả về đúng cùng một instance cho cùng một id, nên shell route và route con khớp nhau mà không cần khai báo tập trung — và bề mặt công khai của `core_di` không phình thêm từ vựng sản phẩm.

Chỉ xin key **khi** một module thực sự cần navigator lồng riêng (back stack riêng). Destination bên trong `StatefulShellRoute` đã có branch navigator từ GoRouter nên không cần.

---

## 7. Suy giảm mềm khi thiếu module

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
  return getItOrNull<DashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      navigationShell;
},
```

| Thiếu gì | Kết quả |
|---|---|
| Toàn bộ `IFeatureRouteModule` | Không có route stack; app vẫn dựng được |
| Toàn bộ `INavDestinationModule` | Một branch giữ chỗ `/_empty_dashboard` giữ `StatefulShellRoute` hợp lệ |
| `DashboardRouteModule` | Các tab vẫn hiển thị, chỉ là không có chrome — `navigationShell` hiển thị nhánh hiện tại. (Trước đây là `SizedBox.shrink()`: app có tab mà không có dashboard sẽ mở ra màn hình trắng) |
| `IAppEntryLocation` | Boot bắt đầu ở `fallbackLocation` — tab đầu tiên, hoặc branch giữ chỗ. Không có entry location nghĩa là không có onboarding để hiện, nên boot đi tiếp tới bước kiểm tra đăng nhập |
| `ISignInLocation` | Không redirect tới màn đăng nhập, lúc boot hay khi đăng xuất — đúng khi không có module sở hữu phiên |
| `IPostSignInLocation` | Sau khi đăng nhập, app đi tới `fallbackLocation` thay vì đứng yên ở màn hình login |

Có hai vị trí, và chúng khác nhau có chủ đích. `entryLocation` là nơi khởi động nguội đáp xuống — onboarding khi được ghép, nhưng **chỉ ở lần chạy đầu tiên**: khi `NavigatorWrapperWidget` đã ghi nhận là đã xem (cờ `AppBootStorage.viewedOnboard` của shell), mọi lần khởi động nguội sau đó đáp xuống `fallbackLocation`, nên người dùng quay lại không phải thấy onboarding trong lúc phiên đang khôi phục. `fallbackLocation` là "trang chủ": `back()` khi không còn gì để pop, nút "về trang chủ" của `UndefineRouteWidget`, và sau khi đăng nhập nếu không có `IPostSignInLocation`. Nó luôn là một route đã đăng ký, không bao giờ là onboarding — người vừa đăng nhập không được đưa ngược về onboarding.

Path không khớp sẽ rơi vào `errorPageBuilder` → `UndefineRouteWidget` (một widget class thật, không bao giờ dùng widget vô danh inline).

---

## 8. Thêm một màn hình — từ đầu đến cuối

1. **Hằng số path** → `lib/src/utils/<feature>_path.dart`.
2. **Class route** → `lib/src/routing/<feature>_route_module.dart` với `@TypedGoRoute` / `@TypedShellRoute`; tạo controller trong `build()`.
3. **Đăng ký contract** → `IFeatureRouteModule` cho route stack, hoặc `INavDestinationModule` cho tab, gắn `@LazySingleton(as: ...)`.
4. **Cần vào từ feature khác?** Thêm method vào Navigator interface của module đó trong package API của nó (`modules/<id>/api`) và implement trong `*_navigator_impl.dart`. Module chưa có Navigator thì cần một file **mới** trong `modules/<id>/api/lib/src/navigators/` — rồi chạy `dart tools/barrel_generator/generate.dart modules/<id>/api/lib` để barrel của package API export nó (§5).
5. **Sinh code** → `dart run build_runner build --workspace`.
6. **Barrel** → `dart tools/barrel_generator/generate.dart modules/<name>/feature/lib`.

---

## 9. Deep link: thiết lập nền tảng

Có hai dạng link đi vào app, và cả hai đều về cùng một location của router:

| Link | Location của router |
|:---|:---|
| `https://<WEB_DOMAIN>/settings?tab=2` (Android App Link / iOS universal link) | `/settings?tab=2` |
| `<scheme>://settings?tab=2` (custom scheme — segment đầu tiên nằm ở vị trí host) | `/settings?tab=2` |

Nền tảng đưa URI cho `app_links`, và `DeeplinkProvider` (`platform/shell/app_shell/lib/presentation/providers/deeplink_provider.dart`) đổi nó thành location bằng `locationOf` rồi điều hướng — nhưng chỉ sau khi `canRoute` đã kiểm tra phiên đăng nhập, và chỉ khi `NavigatorWrapperWidget` đã khởi động nó (không bao giờ đè lên onboarding hay login). Path không module nào đăng ký sẽ rơi vào `UndefineRouteWidget`, như mọi location lạ khác.

### Vì sao tắt deep linking có sẵn của Flutter

Từ Flutter 3.27, engine mặc định cũng tự xử lý deep link: nó đẩy thẳng URI vào `GoRouter`, bỏ qua `DeeplinkProvider` cùng bước kiểm tra phiên — người dùng chưa đăng nhập có thể mở màn hình cần đăng nhập, và mỗi link bị điều hướng hai lần. Vì vậy cả hai nền tảng đều tắt nó:

- Android — trong `<activity>` ở `apps/mobile/android/app/src/main/AndroidManifest.xml`: `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />`
- iOS — `apps/mobile/ios/Runner/Info.plist`: `FlutterDeepLinkingEnabled` = `false`

Đừng xoá cái nào khi `DeeplinkProvider` vẫn là lối vào duy nhất của router.

### Giá trị theo từng flavor

| Flavor | Custom scheme | Application id Android | Bundle id iOS |
|:---|:---|:---|:---|
| `dev` | `codebase-dev` | `com.example.codebase.dev` | `com.example.codebase.dev` |
| `staging` | `codebase-stg` | `com.example.codebase.stg` | `com.example.codebase.staging` |
| `prod` | `codebase` | `com.example.codebase` | `com.example.codebase` |

Mỗi flavor một scheme, để dev, staging và prod cài song song không tranh nhau một link. Scheme được khai hai lần và hai nơi phải khớp nhau: `resValue("string", "DEEP_LINK_SCHEME", …)` trong từng mục `productFlavors` của `apps/mobile/android/app/build.gradle.kts`, và build setting `DEEP_LINK_SCHEME` của từng configuration Runner trong `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (Xcode: *Runner → Build Settings → User-Defined*). Đổi tên app thì đổi cả sáu chỗ cùng lúc.

`WEB_DOMAIN` lấy từ file env của flavor (`apps/mobile/env.dev`, …). Các file env đã commit để trống giá trị này.

### Android

`AndroidManifest.xml` khai hai intent-filter `VIEW` trên `MainActivity`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" />
    <data android:host="@string/WEB_DOMAIN" />
</intent-filter>
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="@string/DEEP_LINK_SCHEME" />
</intent-filter>
```

`@string/WEB_DOMAIN` là một `resValue` mà `build.gradle.kts` giải mã từ dart-define. Khi file env để trống `WEB_DOMAIN`, nó thành `example.invalid` — tên miền dành riêng, không bao giờ phân giải được — vì host rỗng sẽ khiến filter nhận mọi link https.

**Xác minh App Links.** `autoVerify` khiến Android tải `https://<WEB_DOMAIN>/.well-known/assetlinks.json` lúc cài đặt. Phục vụ file qua https, không redirect, kiểu `application/json`, liệt kê mọi flavor dùng domain đó:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.codebase",
      "sha256_cert_fingerprints": ["AA:BB:…"]
    }
  }
]
```

Fingerprint là của khoá dùng để ký APK **được cài**: `keytool -list -v -keystore <release.jks> -alias <alias>` với khoá bạn tự ký; với bản build qua Play dùng Play App Signing, chép SHA-256 của *App signing key certificate* trong Play Console → *Test and release → App integrity* — không phải của upload key. Kiểm tra trên thiết bị:

```bash
adb shell pm get-app-links com.example.codebase            # "verified" cho từng domain
adb shell pm verify-app-links --re-verify com.example.codebase
adb shell am start -a android.intent.action.VIEW -d "codebase-dev://settings?tab=2"
adb shell am start -a android.intent.action.VIEW -d "https://<WEB_DOMAIN>/settings?tab=2"
```

### iOS

**Custom scheme.** `Info.plist` đăng ký nó dưới `CFBundleURLTypes`, với `CFBundleURLSchemes` = `$(DEEP_LINK_SCHEME)` và `CFBundleURLName` = `$(PRODUCT_BUNDLE_IDENTIFIER)`. Không cần gì thêm: `xcrun simctl openurl booted "codebase-dev://settings?tab=2"` mở bản dev.

**Universal link** vẫn tắt cho tới khi bạn sở hữu domain, vì entitlement này làm provisioning fail với App ID chưa có capability. Để bật:

1. Bật **Associated Domains** cho từng App ID trên Apple Developer portal (hoặc *Signing & Capabilities → + Capability* trong Xcode) rồi tạo lại provisioning profile.
2. Bỏ comment khối `com.apple.developer.associated-domains` trong `apps/mobile/ios/Runner/Runner.entitlements`. Giá trị của nó, `applinks:$(WEB_DOMAIN)$(APP_LINK_MODE)`, được mở rộng từ `Flutter/Environment.xcconfig`, file mà build pre-action của mỗi scheme flavor ghi ra từ dart-define — nên hãy build qua scheme flavor (`--flavor`). Để `APP_LINK_MODE` trống ở production; `?mode=developer` bỏ qua cache CDN của Apple trên thiết bị đã bật *Associated Domains Development*.
3. Phục vụ `https://<WEB_DOMAIN>/.well-known/apple-app-site-association` — không đuôi file, `application/json`, không redirect:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.example.codebase"],
        "components": [{ "/": "/*" }]
      }
    ]
  }
}
```

`ABCDE12345` là Team ID của bạn; thêm một mục `appIDs` cho mỗi bundle id dùng domain đó. Apple tải file qua CDN của họ lúc app được cài, nên thay đổi có thể mất một lúc mới tới thiết bị — `?mode=developer` sinh ra để xử lý chuyện đó.

## Checklist

- [ ] Không đụng `app_router.dart`
- [ ] Hằng số path nằm ở `src/utils/`, không phải `routing/`
- [ ] Controller tạo trong `build()` của route, page không bọc lại
- [ ] `INavDestinationModule.order` xếp tab vào đúng vị trí mong muốn (khóa sắp xếp tăng dần, không phải index) và là duy nhất
- [ ] Điều hướng xuyên feature đi qua Navigator interface trong `<id>_api` của module đích
- [ ] `BuildContext` truyền từ UI, không lấy từ `NavigatorKeys`
- [ ] Đã chạy lại `build_runner` sau khi sửa annotation route
- [ ] Deep link vẫn chỉ tới router qua `DeeplinkProvider` — `flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled` giữ nguyên `false` (§9)

## Liên quan

- [`03_state_management.md`](03_state_management.md) — vòng đời controller
- [`05_di.md`](05_di.md) — contract được đăng ký và gom lại thế nào
- [`10_cross_feature.md`](10_cross_feature.md) — các mô hình giao tiếp xuyên feature khác
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — lắp ráp router
