<!-- translated-from: docs/en/guides/04_routing.md@b65f8b3 -->
# Routing & Điều hướng

## Mục tiêu

Bạn thêm một màn hình từ bên trong feature package, không đụng tới app shell. Màn hình được dựng thành route type-safe bằng `go_router_builder`, đăng ký qua DI, và feature khác điều hướng tới nó qua một interface thay vì path hardcode. Nếu cần, bạn cho nó mở được từ deep link.

## Điều kiện cần

- Một feature package — [`01_new_feature.md`](01_new_feature.md).
- **Router được lắp ráp thế nào** từ các đóng góp qua DI, cây shell nó dựng ra, và nó suy giảm mềm ra sao khi thiếu module: [`../architecture/06_app_shell.md` § 5](../architecture/06_app_shell.md#5-lắp-ráp-router). Tóm tắt: `app_router.dart` chỉ lắp ráp và không bao giờ gọi tên route của feature nào (RULE-20).
- Dashboard được và không được sở hữu gì: [`../architecture/05_features.md` § 4](../architecture/05_features.md#4-feature_dashboard-chỉ-là-chrome).

---

## 1. Chọn contract routing

Tất cả contract nằm ở `platform/foundation/contracts/lib/src/routing/`.

| Contract | Dùng cho | Có thứ tự? | Ai implement |
|---|---|---|---|
| `IFeatureRouteModule` | Route top-level / dạng stack dưới app shell | Không — GoRouter khớp theo path | auth, onboarding, … |
| `INavDestinationModule` | Một tab bottom-nav + `StatefulShellBranch` của nó | **Có** — `order` tăng dần | home, settings, … |
| `IAppEntryLocation` | Điểm bắt đầu ở lần chạy đầu tiên (`initialLocation` cho tới khi đã hiện một lần) | n/a | thường là onboarding |
| `ISignInLocation` | Nơi shell đưa người dùng chưa đăng nhập tới (boot, đăng xuất, mất phiên) | n/a | module sở hữu phiên — `feature_auth` |
| `IPostSignInLocation` | Nơi shell đưa người dùng đã đăng nhập tới (boot, đăng nhập); không có thì `fallbackLocation` | n/a | module trang đích — `feature_home` |
| `DashboardRouteModule` | Chrome của dashboard (scaffold + host bottom bar / rail) | n/a | **chỉ** `feature_dashboard` |

Chỉ dùng `INavDestinationModule` cho **đích đến bottom-nav thật sự** cần back stack riêng bền vững. Màn hình chỉ push lên stack thì thuộc về `IFeatureRouteModule` (RULE-24).

## 2. Thêm hằng số path

Hằng số path nằm ở thư mục `src/utils/` của feature, không nằm trong `routing/` (RULE-09). `modules/auth/feature/lib/src/utils/auth_path.dart`:

```dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
}
```

## 3. Khai báo route type-safe

Route được khai bằng annotation và sinh ra `*_route_module.g.dart`. `modules/auth/feature/lib/src/routing/auth_route_module.dart`:

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

Thêm route anh em bằng các mục `TypedGoRoute` khác trong `routes:`. Chúng dùng chung Navigator lồng của shell, nên dùng chung một back stack. `$authShellRoute` được sinh ra chính là thứ feature trả về từ `IFeatureRouteModule.routes` (bước 5).

## 4. Tạo controller trong route

`build()` của route là nơi controller màn hình được tạo và gắn vào cây widget (RULE-21).

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
> Bản thân page **không được** bọc provider lần thứ hai. Xem [`03_state_management.md`](03_state_management.md) § 9.

Màn hình dùng controller **toàn cục** (ví dụ `LoginPage` với `AuthProvider` là `@lazySingleton`) thì build thẳng page, không bọc gì.

## 5. Đăng ký contract route

Đăng ký trong DI module của chính feature, gắn `@LazySingleton(as: ...)`. Không bao giờ thêm route vào `app_router.dart` (RULE-20).

### Route dạng stack — `IFeatureRouteModule`

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

Hãy dùng path duy nhất và tránh catch-all chồng lấn: thứ tự giữa các module không được đảm bảo.

### Tab chính — `INavDestinationModule`

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

`order` là khoá sắp xếp tăng dần, không phải index, và phải duy nhất giữa các tab. `destination` trả về một `NavDestination` trung lập, nên cùng một đóng góp hiển thị được thành mục của bottom bar hay của rail. `feature_dashboard` dựng chrome đó từ mọi tab đã đăng ký, và bỏ hẳn chrome khi có ít hơn hai tab ([`../architecture/05_features.md` § 4](../architecture/05_features.md#4-feature_dashboard-chỉ-là-chrome)). Vì sao chrome đổi theo lớp kích thước cửa sổ: [`11_design_system.md` § 7](11_design_system.md#7-bố-cục-cho-tablet-máy-gập-và-chia-đôi-màn-hình).

## 6. Cho feature khác điều hướng tới màn hình của bạn

Feature A không bao giờ import feature B (RULE-04). Điều hướng vượt ranh giới qua một interface trong **package API của module B** — `modules/<id>/api`, tên `<id>_api`. Feature A phụ thuộc package đó thay cho feature B (`arch_check` R3). `core_di` không chứa navigator của module nào (RULE-22).

**1. Khai báo** — `modules/auth/api/lib/src/navigators/auth_navigator.dart` (package `auth_api`):

```dart
abstract class AuthNavigator {
  void toLogin(BuildContext context);
}
```

Mỗi route mà feature sở hữu là một method — và chỉ những route nó sở hữu.

Một file **mới** trong package API vô hình với mọi nơi dùng cho tới khi barrel export nó. `package:auth_api/auth_api.dart` re-export `src/navigators/navigators.dart`, là file được sinh ra. Hãy sinh lại nó; đừng tự thêm dòng `export`, vì generator xoá các dòng viết tay (RULE-75). Module chưa có package API thì tạo nó trước: [`12_module_isolation.md` § 4](12_module_isolation.md#4-tạo-package-api-cho-module).

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

Các luật áp dụng ở chỗ gọi:

- **RULE-22** · Không bao giờ hardcode chuỗi path hay gọi `GoRouter.of(context).go('/auth/login')` để sang feature khác.
- **RULE-23** · Truyền `BuildContext` thẳng từ widget gọi. Đừng dùng `NavigatorKeys.*.currentContext` hay `appRouter.currentContext`: chúng bỏ qua vòng đời widget và gây lỗi "dùng sau khi dispose".
- **RULE-12** · Dùng `getItOrNull` ở mọi chỗ gọi cần sống sót khi feature đích bị gỡ.
- **RULE-22** · App shell không dùng navigator của module nào. Người dùng chưa đăng nhập được đưa tới `ISignInLocation.path`, người đã đăng nhập tới `IPostSignInLocation.path`. Module sở hữu phiên và module trang đích đóng góp hai contract đó (`AuthSignInLocation`, `HomePostSignInLocation`), còn `NavigatorWrapperWidget` tự gọi `context.go(path)`.

## 7. Cho module một back stack riêng

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

Chỉ xin key bằng `NavigatorKeys.nested('<id>')` **khi** một module thực sự cần navigator lồng riêng — back stack riêng. Shell route và các route con phải dùng cùng một id, như `AuthShellRoute` và `LoginRoute` ở bước 3. Destination bên trong `StatefulShellRoute` đã có branch navigator từ GoRouter nên không cần. Vì sao các key nằm ở `core_di`: [`../architecture/06_app_shell.md` § 5](../architecture/06_app_shell.md#vì-sao-navigatorkeys-nằm-ở-core_di).

## 8. Sinh route và export file

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<name>/feature/lib
```

Chạy `build_runner` sau **mọi** thay đổi annotation route. Rồi chạy barrel generator cho mọi package bạn đã thêm file — kể cả `modules/<id>/api/lib` khi bạn thêm navigator (bước 6).

## 9. Thiết lập deep link

Có hai dạng link đi vào app, và cả hai đều về cùng một location của router:

| Link | Location của router |
|:---|:---|
| `https://<WEB_DOMAIN>/settings?tab=2` (Android App Link / iOS universal link) | `/settings?tab=2` |
| `<scheme>://settings?tab=2` (custom scheme — segment đầu tiên nằm ở vị trí host) | `/settings?tab=2` |

Nền tảng đưa URI cho `app_links`. `DeeplinkProvider` (`platform/shell/app_shell/lib/presentation/providers/deeplink_provider.dart`) đổi nó thành location bằng `locationOf` rồi điều hướng. Nó chỉ làm vậy sau khi `canRoute` đã kiểm tra phiên đăng nhập, và chỉ khi `NavigatorWrapperWidget` đã khởi động nó — không bao giờ đè lên onboarding hay login. Path không module nào đăng ký sẽ rơi vào `UndefineRouteWidget`, như mọi location lạ khác.

### Giữ deep linking có sẵn của Flutter ở trạng thái tắt

Từ Flutter 3.27, engine mặc định cũng tự xử lý deep link. Nó đẩy thẳng URI vào `GoRouter`, bỏ qua `DeeplinkProvider` cùng bước kiểm tra phiên: người dùng chưa đăng nhập có thể mở màn hình cần đăng nhập, và mỗi link bị điều hướng hai lần. Vì vậy cả hai nền tảng đều tắt nó:

- Android — trong `<activity>` ở `apps/mobile/android/app/src/main/AndroidManifest.xml`: `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />`
- iOS — `apps/mobile/ios/Runner/Info.plist`: `FlutterDeepLinkingEnabled` = `false`

Đừng xoá cái nào khi `DeeplinkProvider` vẫn là lối vào duy nhất của router.

### Đặt giá trị theo từng flavor

| Flavor | Custom scheme | Application id Android | Bundle id iOS |
|:---|:---|:---|:---|
| `dev` | `codebase-dev` | `com.example.codebase.dev` | `com.example.codebase.dev` |
| `staging` | `codebase-stg` | `com.example.codebase.stg` | `com.example.codebase.staging` |
| `prod` | `codebase` | `com.example.codebase` | `com.example.codebase` |

Mỗi flavor một scheme, để dev, staging và prod cài song song không tranh nhau một link. Scheme được khai ở hai nơi, và hai nơi phải khớp nhau:

- `resValue("string", "DEEP_LINK_SCHEME", …)` trong từng mục `productFlavors` của `apps/mobile/android/app/build.gradle.kts`;
- build setting `DEEP_LINK_SCHEME` của từng configuration Runner trong `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (Xcode: *Runner → Build Settings → User-Defined*).

Đổi tên app thì đổi cả sáu chỗ cùng lúc.

`WEB_DOMAIN` lấy từ file env của flavor (`apps/mobile/env.dev`, …). Các file env đã commit để trống giá trị này.

### Cấu hình Android

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

`@string/WEB_DOMAIN` là một `resValue` mà `build.gradle.kts` giải mã từ dart-define. Khi file env để trống `WEB_DOMAIN`, nó thành `example.invalid`, một tên miền dành riêng không bao giờ phân giải được. Host rỗng sẽ khiến filter nhận mọi link https.

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

Fingerprint là của khoá dùng để ký APK **được cài**:

- với khoá bạn tự ký: `keytool -list -v -keystore <release.jks> -alias <alias>`;
- với bản build qua Play dùng Play App Signing: SHA-256 của *App signing key certificate* trong Play Console → *Test and release → App integrity* — không phải của upload key.

Kiểm tra trên thiết bị:

```bash
adb shell pm get-app-links com.example.codebase            # "verified" cho từng domain
adb shell pm verify-app-links --re-verify com.example.codebase
adb shell am start -a android.intent.action.VIEW -d "codebase-dev://settings?tab=2"
adb shell am start -a android.intent.action.VIEW -d "https://<WEB_DOMAIN>/settings?tab=2"
```

### Cấu hình iOS

**Custom scheme.** `Info.plist` đăng ký nó dưới `CFBundleURLTypes`, với `CFBundleURLSchemes` = `$(DEEP_LINK_SCHEME)` và `CFBundleURLName` = `$(PRODUCT_BUNDLE_IDENTIFIER)`. Không cần gì thêm: `xcrun simctl openurl booted "codebase-dev://settings?tab=2"` mở bản dev.

**Universal link** vẫn tắt cho tới khi bạn sở hữu domain, vì entitlement này làm provisioning fail với App ID chưa có capability. Để bật:

1. Bật **Associated Domains** cho từng App ID trên Apple Developer portal (hoặc *Signing & Capabilities → + Capability* trong Xcode) rồi tạo lại provisioning profile.
2. Bỏ comment khối `com.apple.developer.associated-domains` trong `apps/mobile/ios/Runner/Runner.entitlements`.
   - Giá trị của nó, `applinks:$(WEB_DOMAIN)$(APP_LINK_MODE)`, được mở rộng từ `Flutter/Environment.xcconfig`. Build pre-action của mỗi scheme flavor ghi file đó ra từ dart-define, nên hãy build qua scheme flavor (`--flavor`).
   - Để `APP_LINK_MODE` trống ở production; `?mode=developer` bỏ qua cache CDN của Apple trên thiết bị đã bật *Associated Domains Development*.
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

`ABCDE12345` là Team ID của bạn; thêm một mục `appIDs` cho mỗi bundle id dùng domain đó. Apple tải file qua CDN của họ lúc app được cài, nên thay đổi có thể mất một lúc mới tới thiết bị. `?mode=developer` sinh ra để xử lý chuyện đó.

---

## Kiểm tra

```bash
dart run build_runner build --workspace   # file route *.g.dart và phần đăng ký DI
flutter analyze                           # No issues found!
dart tools/arch_check/check.dart          # ✅ All architecture rules hold … (R3, R8, R10)
cd apps/mobile && flutter test test/di_smoke_test.dart   # mọi route module đều resolve được
```

`platform/shell/app_shell/test/app_router_test.dart` cho thấy cách test routing với một `AppRouter` thật. Với deep link, dùng các lệnh `adb` và `xcrun` ở bước 9.

Checklist review:

- [ ] Không đụng `app_router.dart`
- [ ] Hằng số path nằm ở `src/utils/`, không phải `routing/`
- [ ] Controller tạo trong `build()` của route, page không bọc lại
- [ ] `INavDestinationModule.order` xếp tab vào đúng vị trí mong muốn (khóa sắp xếp tăng dần, không phải index) và là duy nhất
- [ ] Điều hướng xuyên feature đi qua Navigator interface trong `<id>_api` của module đích
- [ ] `BuildContext` truyền từ UI, không lấy từ `NavigatorKeys`
- [ ] Đã chạy lại `build_runner` sau khi sửa annotation route
- [ ] Deep link vẫn chỉ tới router qua `DeeplinkProvider` — `flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled` giữ nguyên `false` (bước 9)

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `Undefined name '$myRoute'` hoặc thiếu `*.g.dart` | Chưa chạy `build_runner` từ khi đổi annotation | `dart run build_runner build --workspace` (bước 8) |
| Không vào được màn hình mới; GoRouter hiện `UndefineRouteWidget` | Contract route chưa được đăng ký, hoặc app chỉ được hot reload | Kiểm tra annotation `@LazySingleton(as: IFeatureRouteModule)`, chạy lại `build_runner`, rồi **khởi động lại hẳn** app |
| `Undefined name 'MyNavigator'` ở nơi dùng | Barrel của package API chưa export file mới | Chạy barrel generator cho `modules/<id>/api/lib` (bước 6) |
| Tab sai thứ tự, hoặc tab này thay tab kia | Hai `INavDestinationModule` trùng `order` | Cho mỗi tab một `order` riêng (bước 5) |
| Không có bottom bar hay rail | Có ít hơn hai tab được đăng ký | Đúng thiết kế: dashboard bỏ chrome khi dưới hai tab |
| Deep link mở màn hình khi chưa đăng nhập, hoặc điều hướng hai lần | Deep linking có sẵn của Flutter bị bật lại | Đặt lại `flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled` = `false` (bước 9) |
| `pm get-app-links` không báo `verified` | `assetlinks.json` thiếu, bị redirect, hoặc sai fingerprint | Phục vụ file như bước 9, với khoá ký của APK được cài |
| Provisioning fail sau khi bật universal link | App ID chưa có capability Associated Domains | Bật capability rồi tạo lại profile (bước 9) |

## Liên quan

- Luật: RULE-04 (không import feature → feature), RULE-12 (tra cứu tuỳ chọn), RULE-20 (không sửa `app_router.dart`), RULE-21 (controller ở route), RULE-22 (navigator trong `<id>_api`), RULE-23 (`BuildContext` từ nơi gọi), RULE-24 (tab so với màn hình push) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/06_app_shell.md` § 5](../architecture/06_app_shell.md#5-lắp-ráp-router) — lắp ráp router, entry và fallback location, suy giảm mềm
- [`03_state_management.md`](03_state_management.md) — vòng đời controller
- [`05_di.md`](05_di.md) — contract được đăng ký và gom lại thế nào
- [`10_cross_feature.md`](10_cross_feature.md) — các mô hình giao tiếp xuyên feature khác
