# 08. Định Tuyến & Điều Hướng Phân Rã Toàn Diện (Decentralized Scoped Routing)

Hệ thống định tuyến của **Codebase Provider Monorepo** sử dụng thư viện `go_router` kết hợp với trình sinh mã an toàn kiểu dữ liệu **`go_router_builder`**. Để giải quyết triệt để vấn đề xung đột mã nguồn (Merge Conflicts) và đảm bảo tính **Tự Trị Đóng Gói (Encapsulation)** của từng Feature Package, dự án áp dụng mô hình **Định tuyến Phân rã Định danh (Decentralized Scoped Navigators)**.

---

## 🏛️ 1. Triết Lý Thiết Kế Tránh Xung Đột (Zero-Conflict Routing)

Trong mô hình Monorepo lớn:
- Nếu dùng chung một file interface định tuyến (như `AppNavigator`) tại `core_common`, mọi thay đổi từ bất kỳ nhóm tính năng nào đều phải sửa đổi file này ➔ Gây **Merge Conflicts** nghiêm trọng khi gom code.
- Đồng thời, `core_common` không nên phụ thuộc vào các Feature con vì sẽ gây ra **Lỗi Tham Chiếu Vòng (Circular Dependency)**.

### 🛠️ Giải pháp Đỉnh cao: Decoupled Navigation Contracts qua `core_di`
Chúng ta phân rã hợp đồng định tuyến và quy tụ về "Hub" `core_di`:
1. **Quy tụ Interface tại `core_di` (DI Hub)**: Thay vì mỗi Feature tự định nghĩa, tất cả các **Interface Navigator** (ví dụ: `AuthNavigator`) và các Routing Module chia sẻ giao diện đều được khai báo tập trung tại `packages/core/di`.
2. **Feature giao tiếp thông qua `core_di`**: Các Feature khi muốn điều hướng hoặc gọi Widget của nhau chỉ việc `import 'package:core_di/core_di.dart';` và `getIt<T>()` mà không cần import chéo lẫn nhau. Điều này chấm dứt triệt để lỗi Circular Dependency.
3. Triển khai phân tán tại gói Feature cục bộ: Thay vì triển khai tập trung ở App Shell, mỗi gói Feature tự viết mã triển khai thực tế (Implementation) cho Interface Navigator của chính mình trong thư mục routing/ (ví dụ: auth_navigator_impl.dart trong feature_auth).

---

## 🚥 2. Sơ Đồ Kiến Trúc Điều Hướng Phân Tán (Decentralized Architecture Grid)

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                        TẦNG FEATURE (PACKAGES)                             │
│  feature_auth / onboarding     feature_home / settings      feature_dashboard│
│  IFeatureRouteModule           IDashboardTabModule          DashboardRouteModule│
│  (+ AuthNavigator, …)          (order, path, routes, nav)   (chrome / shell UI)│
└───────────────┬──────────────────────────┬───────────────────────┬───────────┘
                │                          │                       │
                └──────────────────────────┼───────────────────────┘
                                           │ package:core_di
                                           ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  core_di: Navigators + IFeatureRouteModule + IDashboardTabModule +         │
│           IAppEntryLocation + DashboardRouteModule + NavigatorKeys         │
└────────────────────────────────────────────────────────────────────────────┘
                                           ▲
                                           │ getAllOrEmpty / getItOrNull
┌────────────────────────────────────────────────────────────────────────────┐
│  app AppRouter — lắp route động (không hardcode list $fooRoute)            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Bảng hợp đồng (cheat-sheet)

| Hợp đồng | Mục đích | Có `order`? | Ai triển khai |
| :--- | :--- | :--- | :--- |
| `IFeatureRouteModule` | Route stack/shell anh em dưới `ShellRoute` | **Không** (match theo path) | auth, onboarding, … |
| `IDashboardTabModule` | Một tab bottom-nav + một `StatefulShellBranch` | **Có** (khớp index nav) | home, settings, … |
| `IAppEntryLocation` | `GoRouter.initialLocation` lúc cold-start | n/a | thường là onboarding |
| `DashboardRouteModule` | Chỉ **chrome** dashboard (scaffold / host bottom bar) | n/a | chỉ `feature_dashboard` |
| `IFeatureLocalization` | Delegate ARB của feature | n/a | mọi feature có chuỗi |

---

## 🧭 2.1. `feature_dashboard` — vì sao tồn tại và cách tránh dùng sai

### Vì sao cần Dashboard

`feature_dashboard` **không** phải chỗ nhét code page Home/Settings/Chat/Profile. Nó chỉ sở hữu **chrome shell** sau khi đã đăng nhập:

1. **`DashboardRouteModule`** — gắn `StatefulNavigationShell` vào `Scaffold` (`DashboardPage`).
2. **Host bottom navigation** — đọc `getAllOrEmpty<IDashboardTabModule>()`, sort theo `order`, dựng `BottomNavigationBar`. **Nội dung tab** vẫn thuộc feature sở hữu.
3. **Package tùy chọn** — `AppRouter` dùng `getItOrNull<DashboardRouteModule>()`; bỏ dashboard thì fallback `SizedBox.shrink()`, app vẫn chạy.

Nhờ đó **layout shell** tách khỏi **feature sản phẩm từng tab**, thêm/bớt tab không sửa `app_router.dart` và không import chéo feature.

### Dashboard BẮT BUỘC làm

- `@Singleton(as: DashboardRouteModule)`.
- Trong `DashboardPage`, item nav **chỉ** từ `IDashboardTabModule` (cùng sort với branch của `AppRouter`).
- Label tab lấy từ l10n của từng feature (`tabLabel`), không hardcode Home/Settings trong dashboard.

### Dashboard TUYỆT ĐỐI không được

| Anti-pattern | Vì sao sai |
| :--- | :--- |
| Import `feature_home` / `feature_settings` rồi nhúng page | Phá cô lập feature; rủi ro circular; bỏ qua DI tabs |
| Sở hữu `HomePage` / `SettingsPage` / BLoC nghiệp vụ của tab | Dashboard là chrome, không phải “túi chứa” |
| Hardcode list `BottomNavigationBarItem` bỏ qua DI | Gỡ package tab → crash hoặc tab chết |
| Tự đăng ký `IDashboardTabModule` cho tab “ảo” | Tab thuộc feature sở hữu màn hình đó |
| Dùng Dashboard cho login, onboarding, màn chỉ push | Những màn đó dùng `IFeatureRouteModule` + Navigator |
| Nhét nhiều tab không liên quan vào một feature “vì Dashboard cần” | Một feature = một bounded UI; Dashboard chỉ host |

### Khi nào `IDashboardTabModule` vs `IFeatureRouteModule`

Dùng **`IDashboardTabModule`** chỉ khi **đủ** các điều kiện:

- Là **điểm đến chính** trong shell đã auth (tab bottom-nav / rail).
- Cần branch ổn định trong `StatefulShellRoute` (giữ state khi đổi tab).
- `order` duy nhất và khớp các tab khác.

Dùng **`IFeatureRouteModule`** khi:

- Màn hình đi bằng **push / go** (login, register, detail, wizard, onboarding).
- **Không** phải đích bottom-nav.
- Thứ tự sibling không quan trọng (GoRouter match theo path).

**Sai:** gắn `IDashboardTabModule` cho “Quên mật khẩu” / “Sửa hồ sơ” chỉ để khỏi viết Navigator.  
**Đúng:** `IFeatureRouteModule` (nếu top-level dưới shell) hoặc route lồng trong cây của tab + `XxxNavigator`.

### Gỡ một tab hoặc cả dashboard

1. Gỡ feature khỏi root `workspace`, `app/pubspec.yaml`, và `ExternalModule(...)` trong `injection.dart`.
2. **Không** sửa mảng route trong `app_router.dart`.
3. **Hot restart** (đổi DI không áp dụng bằng hot reload).
4. Còn &lt; 2 tab → `DashboardPage` ẩn bottom bar; 0 tab → `AppRouter` gắn branch placeholder trống.

---

## 💻 3. Hướng Dẫn Thực Hành Chi Tiết

Dưới đây là quy chuẩn triển khai điều hướng phân rã theo Feature:

### Bước 1: Khai báo Interface cục bộ bên trong `core_di`
Tạo tệp `packages/core/di/lib/src/navigators/auth_navigator.dart`:
```dart
import 'package:flutter/widgets.dart';

abstract class AuthNavigator {
  void toLogin(BuildContext context);
  void toRegister(BuildContext context);
  void toForgotPassword(BuildContext context);
}
```
*Lưu ý: Interface Navigator chỉ chứa các phương thức điều hướng tới các tuyến đường do chính Feature đó quản lý. Ví dụ: `toHome()` không thuộc Auth nên được đưa vào `HomeNavigator`.*

Và đừng quên xuất bản (export) trong file barrel chính của package (`packages/core/di/lib/core_di.dart`):
```dart
export 'src/navigators/auth_navigator.dart';
```

### Bước 2: Điều hướng qua shell listener (ưu tiên cho AuthProvider toàn cục)
`AuthProvider` toàn cục **không** nhận `BuildContext` ở `login` / `logout`. Cập nhật state/stream trong provider; điều hướng từ `ProviderStateListener` trong `NavigatorWrapperWidget`:

```dart
import 'package:core_di/core_di.dart';

class AuthProvider extends BaseProvider<UserEntity> {
  // ...
  Future<void> login(String email, String password) async {
    await executeOperation(
      OperationConfig(
        operation: () => _loginUseCase(...),
        // Không điều hướng tại đây — shell ProviderStateListener xử lý login ↔ home.
      ),
    );
  }

  Future<void> logout() async {
    await executeOperation(
      OperationConfig(
        operation: () => _logoutUseCase(const NoParams()),
        showLoading: false,
        onSuccess: (_) async {
          // Xóa user còn giữ lại (Result<void> một mình sẽ giữ data cũ).
          updateState(
            state: const ViewState.success(),
            data: null,
            retainOldData: false,
          );
        },
      ),
    );
  }
}
```

Với navigator gắn màn hình (không phải global), vẫn có thể truyền `BuildContext` và gọi `getIt<HomeNavigator>().toHome(context)` trong `onSuccess` khi phù hợp.

### Bước 3: Triển khai thực tế tại gói Feature cục bộ
Tạo tệp triển khai bên trong thư mục `routing/` của gói Feature tương ứng, ví dụ: `packages/features/auth/lib/src/routing/auth_navigator_impl.dart`:
```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'auth_route_module.dart';

@Singleton(as: AuthNavigator)
class AuthNavigatorImpl implements AuthNavigator {
  @override
  void toLogin(BuildContext context) => const LoginRoute().go(context);

  @override
  void toRegister(BuildContext context) => const RegisterRoute().go(context);

  @override
  void toForgotPassword(BuildContext context) => const ForgotPasswordRoute().go(context);
}
```

Đăng ký xuất bản tệp tin triển khai tại barrel file định tuyến của feature (`packages/features/auth/lib/src/routing/routing.dart`). Việc này giúp GetIt tự động nhận diện thông qua micro-package DI và nạp vào Host App lúc khởi động.

---

## 🏛️ 4. Khai báo & Phân cấp các Navigator Keys (Global Keys)

Để hỗ trợ đắc lực cho các cấu trúc định tuyến lồng nhau (`Nested Shells`, `Tab Bar navigation`), tránh xung đột và tham chiếu chéo giữa các packages con, monorepo khai báo tập trung các `GlobalKey<NavigatorState>` tại [routing_interfaces.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/di/lib/src/routing/routing_interfaces.dart):

```dart
class NavigatorKeys {
  NavigatorKeys._();
  static final appKey = GlobalKey<NavigatorState>();
  static final rootKey = GlobalKey<NavigatorState>();
  static final authKey = GlobalKey<NavigatorState>();
  static final homeKey = GlobalKey<NavigatorState>();
}
```

### Quy tắc Phân cấp & Phạm vi hoạt động (Hierarchy & Scopes):
1. **`rootKey`**: 
   - Navigator gốc của toàn bộ ứng dụng (`GoRouter(navigatorKey: NavigatorKeys.rootKey)`).
   - Dùng để hiển thị các màn hình đè lên toàn bộ giao diện (như Dialogs toàn cục, BottomSheet, hoặc màn hình lỗi `UndefineRouteWidget`).
2. **`appKey`**:
   - Dùng cho Shell chính của ứng dụng (`ShellRoute(navigatorKey: NavigatorKeys.appKey)`).
   - Bọc các thành phần dùng chung qua `NavigatorWrapperWidget` (redirect auth lúc boot, side-effect auth toàn cục, và deep link qua `DeeplinkProvider`).
3. **`authKey`**:
   - Navigator lồng cục bộ của `feature_auth` (`AuthShellRoute(navigatorKey: NavigatorKeys.authKey)`).
   - Đảm bảo các tuyến con như `LoginRoute`, `RegisterRoute` được đẩy trong khung hiển thị auth: `static final $parentNavigatorKey = NavigatorKeys.authKey;`.
4. **`homeKey`**:
   - Navigator lồng cục bộ cho các trang thuộc tab chính (`feature_home`).

---

## 🚦 5. Quản lý AppRouter thông qua Dependency Injection (GetIt)

Lớp `AppRouter` được cấu hình như một `@singleton` của GetIt để hỗ trợ mock tests và tuân thủ chặt chẽ đồ thị phụ thuộc (DI Graph):

```dart
@singleton
class AppRouter {
  final routeObserver = RouteObserver<ModalRoute>();

  BuildContext get currentContext {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context?.mounted ?? false) {
      return router.routerDelegate.navigatorKey.currentContext!;
    }
    throw FlutterError('AppRouter [currentContext] cannot be null');
  }

  String get currentRouterName {
    final route = router.routerDelegate.currentConfiguration.last.route;
    return route.name ?? route.path;
  }

  late final GoRouter router = GoRouter(
    debugLogDiagnostics: kDebugMode,
    navigatorKey: NavigatorKeys.rootKey,
    refreshListenable: getItOrNull<AuthProvider>(),
    errorPageBuilder: (context, state) {
      return NoTransitionPage(child: UndefineRouteWidget(state: state));
    },
    // IAppEntryLocation → else tab đầu → else '/'
    initialLocation: fallbackLocation,
    routes: [
      ShellRoute(
        navigatorKey: NavigatorKeys.appKey,
        parentNavigatorKey: NavigatorKeys.rootKey,
        builder: (context, state, child) =>
            NavigatorWrapperWidget(child: child),
        routes: [
          // ...getAllOrEmpty<IFeatureRouteModule>().expand((m) => m.routes)
          StatefulShellRoute(
            parentNavigatorKey: NavigatorKeys.appKey,
            branches: dashboardBranches,
            navigatorContainerBuilder: (context, navigationShell, children) {
              return getItOrNull<DashboardRouteModule>()
                      ?.navigatorContainerBuilder(
                        context,
                        navigationShell,
                        children,
                      ) ??
                  const SizedBox.shrink();
            },
            builder: (context, state, navigationShell) {
              return getItOrNull<DashboardRouteModule>()?.builder(
                    context,
                    state,
                    navigationShell,
                  ) ??
                  const SizedBox.shrink();
            },
          ),
        ],
      ),
    ],
  );
}
```

### 💡 Lưu ý đặc biệt về Trang Splash (Splash Page):
- `SplashPage` hoàn toàn được quản lý thủ công bởi lớp `MainScope` (`AppMaterialWrapper(home: splashScreen)` không sử dụng router) phục vụ hiển thị tạm thời khi khởi tạo cấu hình lúc startup. 
- Vì không sử dụng router, **`SplashPage` không được khai báo tuyến đường (Route path) trong GoRouter**. Thuộc tính `initialLocation` của GoRouter lấy từ `getItOrNull<IAppEntryLocation>()?.path` (mẫu onboarding), rồi `IDashboardTabModule.path` đầu tiên, cuối cùng `/`.

### 🧩 `NavigatorWrapperWidget` (App Shell)
- Nằm tại `app/lib/presentation/widgets/navigator_wrapper_widget.dart` (không viết inline trong `AppRouter`).
- Trách nhiệm:
  1. Sau frame đầu tiên (`WidgetsBinding.instance.endOfFrame.whenComplete`), `await AuthProvider.ensureInitialized()` (chờ `initialize()` — gồm session restore — hoàn tất) rồi thực hiện redirect auth / deep-link **lần đầu**. Boot sở hữu navigation đầu tiên.
  2. Bọc shell child bằng `ProviderStateListener<AuthProvider, UserEntity>` để toast lỗi auth toàn cục và điều hướng login ↔ home **sau boot**. Dùng `listenWhen` để bỏ qua success của session-restore, tránh double-redirect.
- **`UndefineRouteWidget`** nằm tại `app/lib/presentation/widgets/undefine_route_widget.dart` và chỉ dùng làm child của `errorPageBuilder` trong GoRouter.

---

## 🚥 6. Khởi Tạo Scoped UI Controller Tại Route Level (Route-Level Instantiation)

Để đảm bảo tính độc lập tuyệt đối giữa các module và quản lý vòng đời bộ nhớ tối ưu (Auto-dispose các state managers cục bộ khi rời màn hình), monorepo áp dụng quy tắc: **Mọi Feature Controller cục bộ (ViewModel, Bloc, Cubit) bắt buộc phải được khởi tạo trực tiếp tại tầng định tuyến trong phương thức `build` của lớp Route tương ứng.**

### ❌ Trường hợp KHÔNG ĐÚNG (Anti-pattern):
1. Đăng ký `@lazySingleton` hoặc `@singleton` cho Feature Controller (như `OnboardingProvider` hoặc `LoginBloc`). Điều này làm lãng phí RAM của hệ thống vì trạng thái của nó sẽ bị GetIt giữ lại vĩnh viễn ngay cả khi người dùng đã chuyển sang màn hình khác.
2. Khởi tạo Widget Provider (ChangeNotifierProvider, BlocProvider) ở tầng App Shell, làm rò rỉ chi tiết triển khai nội bộ của Feature ra Host App.

### ✅ Trường hợp ĐÚNG (Standard Pattern):
Khai báo Controller với annotation `@injectable` (để GetIt tự động mapping các class phụ thuộc nhưng sinh ra **instance mới** mỗi lần lấy). Sau đó, cung cấp Controller này ngay trong chính lớp `GoRouteDataCustom` của Feature ở file `route_module.dart`:

**Ví dụ với Provider:**
```dart
@TypedGoRoute<OnboardingRoute>(path: OnboardingPath.ONBOARDING)
class OnboardingRoute extends GoRouteDataCustom with $OnboardingRoute {
  const OnboardingRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return ChangeNotifierProvider(
      // Dùng getIt để tự động resolve UseCases/Services, rút gọn code đáng kể.
      // Vì là @injectable, nó tạo ra instance mới tinh cho riêng Route này.
      create: (context) => getIt<OnboardingProvider>(),
      child: const OnboardingPage(),
    );
  }
}
```

**Ví dụ với BLoC:**
```dart
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      create: (context) => getIt<LoginCubit>(),
      child: const LoginPage(),
    );
  }
}
```

### 💡 Lợi ích:
1. **Tự động giải phóng (Auto-dispose)**: Khi người dùng chuyển tiếp sang màn hình khác, khung quản lý (Provider / Bloc) sẽ tự động gọi hàm `dispose()` hoặc `close()` để giải phóng Controller khỏi RAM.
2. **Khép kín Tính năng (Encapsulation)**: Gói Host App (`app`) hoàn toàn không cần quan tâm Feature đó sử dụng công cụ quản lý trạng thái nào. Mọi thiết lập logic nằm trọn vẹn và an toàn bên trong Feature Package.

---

## 💎 7. Lợi ích Tuyệt đối của Mô hình Phân rã Toàn diện
1. **Triệt tiêu hoàn toàn Merge Conflicts**: Lập trình viên làm việc trên `feature_auth` chỉ chỉnh sửa `AuthNavigator` cục bộ và `auth_navigator_impl.dart` bên trong `feature_auth/routing/`. Họ không bao giờ đụng vào tệp tin của các feature khác.
2. **Khớp 100% nguyên lý ISP (Interface Segregation)**: Các module không cần nhìn thấy các phương thức định tuyến của nhau. Chúng chỉ cần khai báo và sử dụng đúng các phương thức chúng thực sự cần.
3. **Độc lập và Cô lập (Encapsulation)**: Không có bất kỳ phụ thuộc ngược nào từ core về feature, loại bỏ hoàn toàn circular dependency. Dễ dàng viết Unit Test độc lập bằng cách mock Navigator cục bộ của từng module.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
