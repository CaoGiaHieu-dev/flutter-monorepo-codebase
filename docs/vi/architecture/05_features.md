<!-- translated-from: docs/en/architecture/05_features.md@0930d8e -->
# Tầng Feature

**File này trả lời:** một package sở hữu màn hình được tổ chức thế nào, nó được phép phụ thuộc vào đâu, và các feature giữ độc lập với nhau ra sao mà vẫn ghép lại thành một app.

**Đọc xong bạn làm được:** đặt đúng thư mục cho mọi file mới trong feature package, chọn đúng giữa `@injectable` và `@lazySingleton` cho controller, và nhận ra những vi phạm ranh giới mà tầng này được thiết kế để ngăn chặn.

---

## 1. Một feature = một mối quan tâm UI duy nhất

Một feature package sở hữu **một** bề mặt sản phẩm. Home và Settings là hai package tách biệt dù cả hai đều là tab của dashboard, vì chúng phục vụ mối quan tâm khác nhau và thay đổi vì lý do khác nhau.

Phép thử thực tế: *nếu cắt màn hình này khỏi sản phẩm, package có biến mất theo không?* Nếu không, đó là hai feature.

### Được phép phụ thuộc

| Được phụ thuộc | Vì sao |
|:---|:---|
| `domain_<own>`, `domain_core` | Use case, entity và repository interface của chính module mình — không bao giờ domain của module khác |
| `<id>_api` | Hợp đồng navigator và action handler mà một module cung cấp cho feature — của chính nó và của module khác (`auth_api`, `home_api`) |
| `core_di` | Hợp đồng trung lập với sản phẩm: routing, session, location, localization, stream |
| `core_common` | Hằng số, `ErrorHandler`, helper, các hàm `getIt` — và bản re-export `AppFailure` từ `domain_core` |
| `core_base_ui` | Design token, theme, `ThemeProvider` / `LanguageProvider` |
| `core_responsive` | `context.w/h/sp/r` — bắt buộc với mọi file có đặt kích thước widget (RULE-30); `context.adaptive`, `AdaptiveLayout` và các widget thích ứng khác cho màn hình có layout đổi theo cửa sổ |
| `provider_state_management` **hoặc** `bloc_state_management` | Tuỳ hướng state feature chọn |
| `core_ui_kit` | Widget dùng lại (là package **core**, không phải feature) |

### Bị cấm

> [!CAUTION]
> - **Không bao giờ import `data_*`.** Feature nói chuyện với interface của Domain; app shell mới là nơi bind implementation.
> - **Không bao giờ import feature package khác.** Không có ngoại lệ — widget dùng chung lấy từ `core_ui_kit`, vốn nằm ở core. Nhu cầu liên feature phải đi qua `<id>_api` của module sở hữu hoặc một hợp đồng trung lập ở `core_di` — xem [giao tiếp giữa các feature](../guides/10_cross_feature.md) (RULE-04).
> - **Không bao giờ sửa `platform/shell/app_shell/lib/src/navigation/app_router.dart`** để thêm route của bạn, và không sửa `app_material_wrapper.dart` để thêm localization delegate. Cả hai đều được lắp ráp từ đóng góp qua DI (RULE-20, RULE-34).

Pubspec đã cưỡng chế phần lớn điều này: phụ thuộc workspace duy nhất của `feature_dashboard` là `core_di` và `core_responsive`, nên nó *về mặt vật lý không thể* import một feature khác. `arch_check` R3 giữ phần còn lại.

---

## 2. Bố cục package

```
modules/<name>/feature/
├── assets/
│   └── language/            # en.arb, vi.arb
├── l10n.yaml                # cấu hình gen-l10n
├── lib/
│   ├── feature_<name>.dart  # barrel duy nhất của package, được sinh ra
│   ├── di/
│   │   └── module.dart      # @InjectableInit.microPackage()
│   └── src/
│       ├── pages/           # *_page.dart — màn hình đầy đủ
│       ├── widgets/         # *_widget.dart, *_card.dart — widget con
│       ├── provider/  HOẶC  bloc/
│       ├── routing/         # route module, nav destination, NavigatorImpl, location
│       ├── localization/    # <name>_localization_impl.dart — IFeatureLocalization
│       ├── utils/           # <name>_path.dart + hằng số của package
│       ├── extensions/      # extension l10n
│       ├── handlers/        # tuỳ chọn — hiện thực I*ActionHandler
│       ├── session/         # tuỳ chọn — ISessionStatusStream của bên sở hữu phiên
│       ├── app/             # tuỳ chọn — IAppTreeWrapper / IAppSplashScreen
│       └── gen/language/    # sinh bởi gen-l10n, bị git-ignore — không sửa tay
└── pubspec.yaml
```

> [!IMPORTANT]
> **Hằng số đường dẫn route nằm ở `src/utils/`, không phải `src/routing/`.**
>
> Mọi package giữ hằng số của mình trong thư mục `utils/` riêng, mà đường dẫn route chính là hằng số. `feature_auth` có `src/utils/auth_path.dart`; `feature_home` có `src/utils/home_path.dart`. Các *route module* vẫn ở `src/routing/` và import đường dẫn từ `../utils/`.

```dart
// modules/auth/feature/lib/src/utils/auth_path.dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
}
```

---

## 3. Các feature package trong template

| Package | Mối quan tâm | State management | Đăng ký |
|:---|:---|:---|:---|
| `feature_onboarding` | Giới thiệu lần đầu chạy | không | `IFeatureRouteModule`, `IAppEntryLocation` |
| `feature_auth` | Đăng nhập (một màn hình) | **Provider** | `IFeatureRouteModule`, `ISignInLocation`, `ISessionStatusStream`, `ISessionState`, `ISessionRefreshListenable`, `IAppTreeWrapper` (`core_di`); `AuthNavigator`, `IAuthActionHandler` (`auth_api` của chính nó) |
| `feature_dashboard` | Khung chrome điều hướng (bottom bar / rail) | không | `IDashboardRouteModule` |
| `feature_home` | Tab Home | **BLoC** | `INavDestinationModule` (order 0), `IPostSignInLocation` (`core_di`); `HomeNavigator` (`home_api` của chính nó) |
| `feature_settings` | Tab Settings | không (dùng provider toàn cục) | `INavDestinationModule` (order 1) |
| `feature_splash` | Màn hình splash | không | `IAppSplashScreen` — **không phải route**; do `MainScope` hiển thị |

Mọi feature có chuỗi hiển thị đều đăng ký thêm `IFeatureLocalization` của mình — trừ `feature_dashboard` và `feature_splash`, vốn không có chuỗi nào. `ISessionGateway` do `data_auth` đăng ký, không phải feature. `feature_onboarding` import `auth_api` và `home_api`, `feature_settings` import `auth_api` — những cạnh liên module duy nhất, mỗi cạnh trỏ tới một package API, không bao giờ tới feature khác.

`feature_auth` và `feature_home` được xây trên **hai** hướng state khác nhau một cách có chủ đích, để template minh hoạ cả hai. Xem [state management](../guides/03_state_management.md) — và hãy đọc phần so sánh trung thực ở đó trước khi chọn, vì hai nhánh **không** được trang bị ngang nhau.

> [!NOTE]
> `feature_splash` không có thư mục `routing/`. Màn hình splash được `MainScope` hiển thị trước khi `GoRouter` tồn tại, nên nó hoàn toàn không phải một route. Xem [app shell](06_app_shell.md).

---

## 4. `feature_dashboard` chỉ là chrome

Dashboard sở hữu `Scaffold` và chrome điều hướng — `BottomNavigationBar` trên cửa sổ `compact`, `NavigationRail` từ `medium` trở lên, dạng mở rộng từ `large` trở lên — không gì khác. Nó dựng chúng từ danh sách `destinations` mà router của shell trao cho `IDashboardRouteModule.builder`:

```dart
// modules/dashboard/feature/lib/src/routing/dashboard_route_module_impl.dart
@Singleton(as: IDashboardRouteModule)
class DashboardRouteModuleImpl implements IDashboardRouteModule {
  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
    List<INavDestinationModule> destinations,
  ) {
    return DashboardPage(
      navigationShell: navigationShell,
      destinations: destinations,
    );
  }
}
```

```dart
// modules/dashboard/feature/lib/src/pages/dashboard_page.dart
@override
Widget build(BuildContext context) {
  // A bar or rail needs at least two destinations.
  if (destinations.length < 2) return Scaffold(body: navigationShell);

  final items = [for (final tab in destinations) tab.destination(context)];
  final selected = navigationShell.currentIndex;
  final sizeClass = context.windowSizeClass;

  if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selected,
        onTap: _onSelect,
        // `shifting` (Flutter's default from the fourth tab) hides the
        // labels of unselected tabs.
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        items: [
          for (final d in items)
            BottomNavigationBarItem(
              icon: Icon(d.icon),
              activeIcon: Icon(d.selectedIcon ?? d.icon),
              label: d.label,
            ),
        ],
      ),
    );
  }

  // The rail costs width a wide window has to spare, not height it has not.
  final extended = sizeClass.isAtLeast(WindowSizeClass.large);
  return Scaffold(
    body: SafeArea(
      top: false,
      bottom: false,
      child: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: _onSelect,
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [
              for (final d in items)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon ?? d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          Expanded(child: navigationShell),
        ],
      ),
    ),
  );
}
```

Trong các package của workspace, `feature_dashboard` chỉ phụ thuộc `core_di` và `core_responsive` — nó **về mặt vật lý không thể** import feature khác. Vì các tab đến từ DI, xoá `feature_home` sẽ mất tab Home mà app vẫn khởi động được. Khi có ít hơn hai tab thì không có bar hay rail nào cả; app nào ghép hai tab trở lên thì phải ghép cả dashboard, nếu không chỉ truy cập được tab đầu (`checkAppContract` `C12`, RULE-24).

Chrome được chọn theo **lớp kích thước cửa sổ**, không theo thiết bị — tablet ở cả hai hướng, iPad đang Split View và cửa sổ desktop đều nhận đúng chrome mà cửa sổ của nó đủ chỗ. (Với chính sách hướng mặc định `phones_portrait`, màn hình cỡ điện thoại bị `AppInitializer` khoá dọc lúc khởi động, nên luôn hiện bottom bar; với chính sách `free` thì điện thoại xoay ngang sẽ nhận rail theo đúng quy tắc này.) Đây là mẫu tham chiếu của template cho layout thích ứng; các widget và quy tắc nằm ở [design system §7](../guides/11_design_system.md#7-bố-cục-cho-tablet-máy-gập-và-chia-đôi-màn-hình).

### Dashboard KHÔNG được phép

- Import `feature_home` / `feature_settings`, hoặc nhúng page của chúng
- Sở hữu `HomePage` / `SettingsPage`, hay bất kỳ BLoC nghiệp vụ nào của tab
- Hardcode danh sách destination thay vì vẽ `destinations` mà builder nhận được — router của shell gom `INavDestinationModule` một lần, sắp theo `order`, nên chrome và các nhánh không thể lệch nhau
- Tự đăng ký `INavDestinationModule` để tạo tab "giả"

### Đóng góp một tab

Feature đăng ký một implementation là có ngay branch và nav item:

```dart
// modules/home/feature/lib/src/routing/home_nav_destination.dart
/// SAMPLE: a module contributing one primary navigation destination. It
/// describes the destination ([NavDestination]) instead of building a widget,
/// so the dashboard can render it as a bottom bar or a rail.
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

`order` là khóa sắp xếp tăng dần và phải duy nhất mỗi tab. Bấm vào chính tab đang mở sẽ đưa branch đó về trang đầu của nó (`navigationShell.goBranch(index, initialLocation: …)` trong dashboard).

Chỉ dùng `INavDestinationModule` cho **điểm đến chính của bottom-nav** cần `StatefulShellBranch` riêng. Màn hình push chồng lên một tab chỉ là route thường bên trong branch đó.

---

## 5. Widget dùng chung nằm ở core, không phải ở đây

Thư viện widget dùng lại là **`core_ui_kit`** tại `platform/ui/ui_kit` — một package core, không phải feature. Nó nằm ngoài `modules/*/feature/` để mọi thứ trong thư mục đó đều là mảng sản phẩm thực sự gỡ được. Cấu trúc, chiều phụ thuộc và quy tắc UI-agnostic của nó được mô tả ở [tầng core](02_core.md).

Điều quan trọng ở phía feature là nghĩa vụ của **bên gọi**:

```dart
// widget nhận kích thước đã scale; bên gọi là nơi scale
CustomButton.rectangle(minWidth: context.w(120), height: context.h(44), child: …)
```

Widget trong `core_ui_kit` không bao giờ scale lại một giá trị được truyền vào — nó dùng nguyên giá trị nhận được, và chỉ scale các hằng số mặc định của chính nó qua `core_responsive`. Scale thêm một tham số bên trong widget sẽ làm nó bị scale hai lần, nên việc scale giá trị bạn truyền vào luôn được làm ở đây, ngay tại chỗ gọi (RULE-30, RULE-31). Không có extension trên `num` — `120.w` không biên dịch được, chỉ `context.w(120)` mới được.

## 6. Vòng đời UI controller

| Phạm vi | Annotation | Dùng cho |
|:---|:---|:---|
| **Theo màn hình** | `@injectable` (factory) | ViewModel / BLoC gắn với một màn hình |
| **Toàn app** | `@lazySingleton` | `AuthProvider`, `ThemeProvider`, `LanguageProvider`, `DeeplinkProvider` |

> [!CAUTION]
> **Tuyệt đối không đăng ký controller theo màn hình dưới dạng singleton.** GetIt sẽ giữ instance vĩnh viễn, khiến state rò rỉ giữa các lần vào màn hình và object không bao giờ được dispose.

### Khởi tạo ở tầng Route

Controller được tạo trong `build` của route, không phải bên trong page:

```dart
// modules/home/feature/lib/src/routing/home_route_module.dart
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

> [!CAUTION]
> **Không bọc lần thứ hai bên trong page.** Nếu route đã cung cấp controller, thêm một `BlocProvider` / `ChangeNotifierProvider` nữa trong `HomePage.build` sẽ tạo ra một instance *khác*. Page hiển thị một object trong khi event lại đi tới object kia — giao diện trông như đứng yên, và cả hai instance đều không được dispose đúng cách.

Controller toàn cục thì không cần bọc gì cả. `AuthProvider` là `@lazySingleton`, nên `LoginRoute` dựng thẳng `const LoginPage()` và page đọc nó bằng `context.read<AuthProvider>()` và một `Selector`:

```dart
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
```

### Dùng `ViewState` nào?

Cả hai package state đều export một union trạng thái, và chúng **không thể thay thế cho nhau**:

| | `provider_state_management` | `bloc_state_management` |
|:---|:---|:---|
| Kiểu | `ViewState` (nằm trong `ViewStateModel<T>`) | `BlocViewState<T>` |
| Generic | không | có |
| Số variant | 5 (có `loadingMore`) | 4 |
| Nhánh error | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — bắt buộc |

Kiểu của nhánh BLoC được đặt tên là `BlocViewState<T>` chứ không phải `ViewState`, để một file import cả hai barrel không gặp hai kiểu khác nhau dưới cùng một cái tên:

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<SessionPrincipal?>> {
  HomeProfileBloc(@factoryParam this._sessionStatusStream)
    : super(const BlocViewState.initial()) { … }
```

---

## 7. Quy tắc đặt tên

Hậu tố file và class cho page, widget, controller, navigator, handler, localization và route, mỗi loại kèm ví dụ thật trong cây thư mục: [đặt tên](../reference/02_naming.md).

Dialog và bottom sheet **luôn luôn** là class widget riêng — không bao giờ là closure viết thẳng trong `showDialog(builder: …)` (RULE-36). Mọi văn bản hiển thị cho người dùng đều được dịch qua ARB của feature và `IFeatureLocalization`, còn key ARB là `lowerCamelCase` (RULE-34, RULE-35). Xem [localization và theming](../guides/09_localization_theming.md).

---

## 8. Tạo một feature

```bash
# type=1 (feature), tên, prefix (chỉ cho type 5 — truyền ""), SM: 1=Provider 2=BLoC 3=không, route: 1=stack 2=tab 3=không
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

Generator tạo package, thêm vào mọi `app_manifest.yaml` rồi chạy `composer sync` — bước này sinh lại danh sách `workspace:` ở root cùng `pubspec.yaml` và `injection.dart` của từng app. Sau khi bạn tự thêm file:

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/profile/feature/lib
```

Checklist (mỗi dòng dẫn tới dòng registry phát biểu nó):

- [ ] Có `resolution: workspace` trong pubspec; không có `data_*`, không có feature khác và không có domain của module khác trong dependencies (RULE-04)
- [ ] Route đăng ký qua `IFeatureRouteModule` hoặc `INavDestinationModule` — không đụng `app_router.dart` (RULE-20)
- [ ] Localization đăng ký qua `IFeatureLocalization` — không đụng `app_material_wrapper.dart`; key ARB là `lowerCamelCase` (RULE-34, RULE-35)
- [ ] Controller theo màn hình là `@injectable`, tạo ở route, không bọc lại trong page (RULE-10, RULE-21)
- [ ] Hằng số đường dẫn nằm ở `src/utils/<name>_path.dart` (RULE-09)
- [ ] Điều hướng sang module khác đi qua navigator của module đó trong `<id>_api` của nó, resolve bằng `getItOrNull`, `BuildContext` truyền từ bên gọi (RULE-22, RULE-23)
- [ ] Mọi kích thước đều scale qua `context.w/h/sp/r` (RULE-30)
- [ ] Layout đổi theo cửa sổ thì chọn theo lớp kích thước cửa sổ (`context.adaptive`, `AdaptiveLayout`) — không bao giờ theo thiết bị hay nền tảng (RULE-32)
- [ ] Dialog và bottom sheet là class widget riêng (RULE-36)
- [ ] Asset riêng của feature nằm trong feature package, không nhét vào `core_base_ui` (RULE-37)

---

## 9. Giao tiếp giữa các feature — vì sao có hình dạng này

Các feature không bao giờ import lẫn nhau. Phần hướng dẫn — chọn mô hình nào trong sáu mô hình và nối dây ra sao — nằm ở [`../guides/10_cross_feature.md`](../guides/10_cross_feature.md). Mục này giải thích vì sao nó có hình dạng như vậy.

Bảng đăng ký: RULE-04, RULE-08, RULE-12, RULE-22, RULE-25, RULE-54.

```
feature_a  ──✗──>  feature_b        cấm tuyệt đối
feature_a  ──✓──>  b_api            hợp đồng module B dành cho feature khác nằm ở đây
feature_b  ──✓──>  b_api            B implement và đăng ký theo chúng
ai cũng    ──✓──>  core_di          hợp đồng trung lập với sản phẩm (session, location, routing)
```

Một hợp đồng nằm ở một trong hai chỗ trung lập. **Package API của module B** (`modules/<b>/api`,
`b_api`) chứa những gì tồn tại để *feature khác chạm tới B* — navigator, action handler, một
widget builder (`auth_api`, `home_api` trong các sample); nó chỉ phụ thuộc foundation và
Flutter, và feature của B implement nó. **`core_di`**, DI Hub, chỉ chứa thứ trung lập với sản
phẩm — thứ mà chính platform cần, đặt tên theo nhu cầu đó (phiên đăng nhập, vị trí đăng nhập /
sau đăng nhập, routing), không bao giờ theo module cung cấp nó. Dù ở đâu, cả hai phía đều phụ
thuộc hợp đồng, không phía nào phụ thuộc phía kia. Chính điều đó làm cho feature có thể gỡ ra
được; `arch_check` R3 giữ các luật của package API.

### Điều hướng liên module đi qua navigator của đích

Một feature đưa người dùng vào màn hình của module khác thì gọi navigator của module đó (RULE-22): hợp đồng nằm trong `<id>_api` của đích, phần hiện thực nằm trong feature của đích, còn bên gọi resolve nó một cách tuỳ chọn và truyền `BuildContext` của chính mình (RULE-23):

```dart
// modules/onboarding/feature/lib/src/pages/onboarding_page.dart
onPressed: () {
  final auth = getItOrNull<AuthNavigator>();
  if (auth != null) {
    auth.toLogin(context);
  } else {
    getItOrNull<HomeNavigator>()?.toHome(context);
  }
},
```

App shell không gọi tên module nào: nó đưa người dùng chưa đăng nhập tới `ISignInLocation` và người đã đăng nhập tới `IPostSignInLocation` ([app shell § 6](06_app_shell.md)). Phần hướng dẫn là [routing § 6](../guides/04_routing.md#6-cho-feature-khác-điều-hướng-tới-màn-hình-của-bạn).

### Vì sao là `SessionPrincipal` chứ không phải `UserEntity`

Hợp đồng ở `core_di` không được gọi
tên một kiểu thuộc package `domain_*` (RULE-08): import đó khiến mọi bên tiêu thụ
phụ thuộc `domain_auth` ngay lúc biên dịch, và `getItOrNull` không gỡ được điều đó. Vì vậy `core_di`
sở hữu một value type nhỏ,
[`SessionPrincipal`](../../../platform/foundation/contracts/lib/src/session/session_principal.dart), và feature
auth thu hẹp entity của mình về kiểu đó tại ranh giới (`AuthStatusStreamImpl.updateAuthStatus`). Hợp đồng cố ý nhỏ
hơn entity — bên tiêu thụ chỉ hỏi *ai đang đăng nhập* sẽ không bao giờ thấy phần còn lại.

### Vì sao có `currentUser` bên cạnh stream

`sessionStatusStream` là stream *broadcast*: nó không
phát lại giá trị cuối cho listener mới. Một bên đăng ký sau khi đã đăng nhập sẽ "mù" cho tới lần
thay đổi kế tiếp, nên nó đọc `currentUser` để lấy state tại thời điểm đăng ký.

### Vì sao stream được đăng ký hai lần

Class cụ thể được đăng ký để `feature_auth` inject thẳng
`AuthStatusStreamImpl` và gọi method ghi `updateAuthStatus` — không cần tra `getIt`, không cần ép
kiểu `as`. Phần bind `@module` sau đó lộ *cùng một instance* dưới dạng interface chỉ-đọc cho mọi
bên khác. Bên sở hữu ghi, bên tiêu thụ đọc.

### Vì sao theme và locale bỏ qua Domain

Một use case sẽ phải nhận và trả `ThemeMode`, vốn là kiểu của
`package:flutter/material.dart`. Tầng domain là Dart thuần và **không thể import Flutter**, nên đưa
theme đi qua nó là bất khả thi về mặt cấu trúc — đây là ràng buộc cứng, không phải đường tắt.

Implementation nằm ở app shell (`platform/shell/adapters/lib/src/theme_storage_impl.dart`) vì đó là nơi provider của
`core_base_ui` và cơ chế của `core_storage` gặp nhau mà không tạo thành vòng phụ thuộc.

### Anti-pattern

| Đừng | Vì sao | Thay bằng |
| :-- | :-- | :-- |
| `import 'package:feature_b/...'` từ feature A | Trói cứng hai feature; không feature nào gỡ được | Hợp đồng trong `b_api` (hoặc hợp đồng trung lập ở `core_di`) |
| Hợp đồng riêng của một module (`AuthNavigator`) đặt trong `core_di` | Platform khi đó gọi tên một module sản phẩm, và giữ một hợp đồng chết khi module bị gỡ | `<id>_api` của module sở hữu |
| Lộ `Bloc` hay `ChangeNotifier` ra ngoài feature | Ép feature kia phải theo thư viện state của bạn | Mô hình 3 — neutral stream |
| `getIt<KiểuDoFeatureSởHữu>()` | Ném lỗi khi feature đó bị gỡ | `getItOrNull<T>()` + fallback |
| Dùng Action Handler để điều hướng | Sai công cụ; mất type-safe route | Navigator interface |
| Đặt logic nghiệp vụ dùng chung vào `core_ui_kit` | Đó là package UI | Một UseCase ở domain |
| Hợp đồng `core_di` gọi tên entity của `domain_*` | Mọi bên tiêu thụ phải phụ thuộc package domain đó; trái RULE-08 | Value type do hợp đồng sở hữu (`SessionPrincipal`) |

---

## Liên quan

- [App shell](06_app_shell.md) — cách các package này được lắp thành một app
- [Hướng dẫn: tạo feature](../guides/01_new_feature.md)
- [Hướng dẫn: state management](../guides/03_state_management.md) · [routing](../guides/04_routing.md) · [giao tiếp liên feature](../guides/10_cross_feature.md)
- [Quy tắc](../reference/01_rules.md) · [Đặt tên](../reference/02_naming.md)
