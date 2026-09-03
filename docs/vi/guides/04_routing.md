# Routing & Điều hướng

**File này trả lời:** làm sao thêm một màn hình, và làm sao điều hướng sang màn hình thuộc feature khác?

**Đọc xong bạn làm được:** đăng ký route từ bên trong feature package mà không đụng app shell, dựng route type-safe bằng `go_router_builder`, và điều hướng xuyên feature qua interface thay vì hardcode path.

---

## 1. Ý tưởng cốt lõi: routing là phi tập trung

`app/lib/presentation/navigation/app_router.dart` **chỉ lắp ráp**. Nó không bao giờ gọi tên route của feature nào — nó gom những gì feature đã đăng ký qua DI:

```dart
List<IDashboardTabModule> get _dashboardTabs {
  return getAllOrEmpty<IDashboardTabModule>().toList()
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
        └── mỗi IDashboardTabModule một StatefulShellBranch (sắp theo order)
```

---

## 2. Bốn contract routing

Tất cả nằm ở `packages/core/di/lib/src/routing/`.

| Contract | Dùng cho | Có thứ tự? | Ai implement |
|---|---|---|---|
| `IFeatureRouteModule` | Route top-level / dạng stack dưới app shell | Không — GoRouter khớp theo path | auth, onboarding, … |
| `IDashboardTabModule` | Một tab bottom-nav + `StatefulShellBranch` của nó | **Có** — `order` phải khớp index nav | home, settings, … |
| `IAppEntryLocation` | Vị trí lúc khởi động nguội (`initialLocation`) | n/a | thường là onboarding |
| `DashboardRouteModule` | Chrome của dashboard (scaffold + host bottom bar) | n/a | **chỉ** `feature_dashboard` |

### 2.1 `IFeatureRouteModule`

```dart
abstract class IFeatureRouteModule {
  List<RouteBase> get routes;
}
```

Đăng ký trong chính feature sở hữu — `packages/features/onboarding/lib/src/routing/onboarding_feature_route_module.dart`:

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

### 2.2 `IDashboardTabModule`

```dart
abstract class IDashboardTabModule {
  int get order;                    // 0 = tab đầu tiên
  String get path;                  // path chuẩn, dùng cho fallback
  List<RouteBase> get routes;       // mount trong một StatefulShellBranch
  void onRestore();                 // bấm lại vào tab đang active
  BottomNavigationBarItem navigationBarItem(BuildContext context);
}
```

`packages/features/home/lib/src/routing/home_dashboard_tab_module.dart`:

```dart
@LazySingleton(as: IDashboardTabModule)
class HomeDashboardTabModule extends IDashboardTabModule {
  @override
  int get order => 0;

  @override
  String get path => HomePath.HOME;

  @override
  List<RouteBase> get routes => [$homeShellRoute];

  @override
  BottomNavigationBarItem navigationBarItem(BuildContext context) {
    return BottomNavigationBarItem(
      icon: const Icon(Icons.home),
      label: context.l10nHome.tabLabel,
    );
  }
}
```

> [!NOTE]
> Chỉ dùng `IDashboardTabModule` cho **đích đến bottom-nav thật sự** cần back stack riêng bền vững. Màn hình chỉ push lên stack thì thuộc về `IFeatureRouteModule`.

### 2.3 Dashboard chỉ là chrome

`feature_dashboard` chỉ phụ thuộc `core_di` và `core_common` — nó **về mặt vật lý không thể** import feature khác. Page của nó dựng bottom bar từ DI (`packages/features/dashboard/lib/src/pages/dashboard_page.dart`):

```dart
final tabs = getAllOrEmpty<IDashboardTabModule>().toList()
  ..sort((a, b) => a.order.compareTo(b.order));
return Scaffold(
  body: navigationShell,
  bottomNavigationBar: tabs.length < 2 ? null : BottomNavigationBar(...),
);
```

Dashboard **không được**:
- import `feature_home` / `feature_settings` hay nhúng page của chúng
- sở hữu page của tab hoặc BLoC nghiệp vụ của tab
- hardcode danh sách `BottomNavigationBarItem` thay vì đọc DI
- tự đăng ký `IDashboardTabModule` để tạo tab "giả"

Chú ý `tabs.length < 2` ẩn hẳn thanh bar khi có ít hơn hai tab — một phần của cơ chế suy giảm mềm ở §6.

---

## 3. Route type-safe với `go_router_builder`

Route được khai bằng annotation và sinh ra `*_route_module.g.dart`. **Phải chạy `dart run build_runner build -d --workspace` sau mỗi thay đổi.**

Hằng số path nằm ở thư mục `src/utils/` của feature, không nằm trong `routing/` — mọi package đều giữ constants của mình dưới `utils/`:

`packages/features/auth/lib/src/utils/auth_path.dart`:

```dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
  static const String REGISTER = '/auth/register';
  static const String FORGOT_PASSWORD = '/auth/forgot-password';
}
```

`packages/features/auth/lib/src/routing/auth_route_module.dart`:

```dart
@TypedShellRoute<AuthShellRoute>(
  routes: [
    TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN),
    TypedGoRoute<RegisterRoute>(path: AuthPath.REGISTER),
    TypedGoRoute<ForgotPasswordRoute>(path: AuthPath.FORGOT_PASSWORD),
  ],
)
class AuthShellRoute extends ShellRouteData {
  const AuthShellRoute();

  static final $navigatorKey = NavigatorKeys.authKey;
  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return navigator;
  }
}

class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;
  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const LoginPage();
  }
}
```

`$authShellRoute` được sinh ra chính là thứ feature trả về từ `IFeatureRouteModule.routes`.

---

## 4. Khởi tạo controller ở route

`build()` của route là nơi controller màn hình được tạo và gắn vào cây widget.

**BLoC** — `packages/features/home/lib/src/routing/home_route_module.dart`:

```dart
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      create: (_) => getIt<HomeProfileBloc>(),
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
    create: (context) => getIt<OnboardingProvider>(),
    child: const OnboardingPage(),
  );
}
```

> [!CAUTION]
> Bản thân page **không được** bọc provider lần thứ hai. Xem [`03_state_management.md`](03_state_management.md) §4.

Route của màn hình dùng controller **toàn cục** (ví dụ `LoginPage` với `AuthProvider` là `@lazySingleton`) thì build thẳng page, không bọc gì.

---

## 5. Điều hướng xuyên feature

Feature A không bao giờ được import Feature B. Điều hướng vượt ranh giới thông qua interface đặt ở `core_di`.

**1. Khai báo** — `packages/core/di/lib/src/navigators/auth_navigator.dart`:

```dart
abstract class AuthNavigator {
  void toLogin(BuildContext context);
  void toRegister(BuildContext context);
  void toForgotPassword(BuildContext context);
}
```

**2. Implement trong feature sở hữu** — `packages/features/auth/lib/src/routing/auth_navigator_impl.dart`:

```dart
@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) {
    const LoginRoute().go(context);
  }

  @override
  void toRegister(BuildContext context) => const RegisterRoute().go(context);

  @override
  void toForgotPassword(BuildContext context) =>
      const ForgotPasswordRoute().go(context);
}
```

**3. Gọi từ bất kỳ đâu:**

```dart
getIt<AuthNavigator>().toLogin(context);
// hoặc, khi feature đó có thể bị gỡ:
getItOrNull<AuthNavigator>()?.toLogin(context);
```

### Quy tắc

- Một Navigator interface **chỉ** phơi ra route mà chính feature đó sở hữu.
- **Không bao giờ** hardcode chuỗi path hay gọi `GoRouter.of(context).go('/auth/login')` để sang feature khác.
- **`BuildContext` phải được truyền trực tiếp từ widget gọi.** Đừng lấy từ `NavigatorKeys.*.currentContext` hay `appRouter.currentContext` — cách đó bỏ qua vòng đời widget và sinh lỗi "dùng sau khi dispose".
- Dùng `getItOrNull` ở những chỗ gọi cần sống sót khi feature đích bị gỡ.

---

## 6. `NavigatorKeys` — vì sao đặt ở DI Hub

`packages/core/di/lib/src/routing/navigator_keys.dart`:

```dart
class NavigatorKeys {
  NavigatorKeys._();

  static final appKey = GlobalKey<NavigatorState>();
  static final rootKey = GlobalKey<NavigatorState>();
  static final authKey = GlobalKey<NavigatorState>();
}
```

Một `ShellRoute` và các route con của nó phải tham chiếu **cùng một** instance `GlobalKey`. Shell do app shell lắp ráp; route con lại khai bên trong feature package. Đặt key ở một trong hai phía sẽ tạo vòng phụ thuộc — app shell vốn đã phụ thuộc mọi feature, nên feature không thể phụ thuộc ngược lại app shell để lấy key. `core_di`, thứ mà cả hai phía đều đã phụ thuộc, là nơi trung lập.

`authKey` mang tên một feature, bình thường sẽ là mùi phân tầng sai. Nó được chấp nhận vì đây là **hạ tầng routing, không phải business logic**: key chỉ là token định danh trao cho GoRouter, và `core_di` không hề import `feature_auth`.

Chỉ thêm key mới **khi** một feature thực sự cần navigator lồng riêng (back stack riêng). Tab trong dashboard đã có branch navigator từ `StatefulShellRoute` của GoRouter nên không cần.

---

## 7. Suy giảm mềm khi thiếu module

Mọi lần tra cứu trong `app_router.dart` đều chịu được việc thiếu đóng góp — đây chính là thứ khiến feature gỡ được:

```dart
String get _fallbackLocation {
  final entry = getItOrNull<IAppEntryLocation>()?.path;
  if (entry != null) return entry;
  final tabs = _dashboardTabs;
  if (tabs.isNotEmpty) return tabs.first.path;
  return '/';
}
```

```dart
builder: (context, state, navigationShell) {
  return getItOrNull<DashboardRouteModule>()?.builder(
        context,
        state,
        navigationShell,
      ) ??
      const SizedBox.shrink();
},
```

| Thiếu gì | Kết quả |
|---|---|
| Toàn bộ `IFeatureRouteModule` | Không có route stack; app vẫn dựng được |
| Toàn bộ `IDashboardTabModule` | Một branch giữ chỗ `/_empty_dashboard` giữ `StatefulShellRoute` hợp lệ |
| `DashboardRouteModule` | Dashboard render `SizedBox.shrink()` |
| `IAppEntryLocation` | Rơi về path của tab đầu tiên, rồi tới `/` |

Path không khớp sẽ rơi vào `errorPageBuilder` → `UndefineRouteWidget` (một widget class thật, không bao giờ dùng widget vô danh inline).

---

## 8. Thêm một màn hình — từ đầu đến cuối

1. **Hằng số path** → `lib/src/utils/<feature>_path.dart`.
2. **Class route** → `lib/src/routing/<feature>_route_module.dart` với `@TypedGoRoute` / `@TypedShellRoute`; tạo controller trong `build()`.
3. **Đăng ký contract** → `IFeatureRouteModule` cho route stack, hoặc `IDashboardTabModule` cho tab, gắn `@LazySingleton(as: ...)`.
4. **Cần vào từ feature khác?** Thêm method vào Navigator interface của feature đó ở `core_di` và implement trong `*_navigator_impl.dart`.
5. **Sinh code** → `dart run build_runner build -d --workspace`.
6. **Barrel** → `dart tools/barrel_generator/generate.dart packages/features/<name>/lib`.

## Checklist

- [ ] Không đụng `app_router.dart`
- [ ] Hằng số path nằm ở `src/utils/`, không phải `routing/`
- [ ] Controller tạo trong `build()` của route, page không bọc lại
- [ ] `IDashboardTabModule.order` khớp đúng vị trí tab mong muốn
- [ ] Điều hướng xuyên feature đi qua Navigator interface ở `core_di`
- [ ] `BuildContext` truyền từ UI, không lấy từ `NavigatorKeys`
- [ ] Đã chạy lại `build_runner` sau khi sửa annotation route

## Liên quan

- [`03_state_management.md`](03_state_management.md) — vòng đời controller
- [`05_di.md`](05_di.md) — contract được đăng ký và gom lại thế nào
- [`10_cross_feature.md`](10_cross_feature.md) — các mô hình giao tiếp xuyên feature khác
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — lắp ráp router
