<!-- translated-from: docs/en/architecture/05_features.md@b65f8b3 -->
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
| `domain_*` | Use case, entity, repository interface |
| `core_di` | Hợp đồng Navigator / action handler / routing / stream |
| `core_common` | Hằng số, `ErrorHandler`, helper, các hàm `getIt` — và bản re-export `AppFailure` từ `domain_core` |
| `core_base_ui` | Design token, theme, `ThemeProvider` / `LanguageProvider` |
| `core_responsive` | Extension scale trên `BuildContext` (`context.w/h/r/sp`) — bắt buộc với mọi file có đặt kích thước widget; `context.adaptive`, `AdaptiveLayout` và các widget thích ứng khác cho màn hình có layout đổi theo cửa sổ |
| `provider_state_management` **hoặc** `bloc_state_management` | Tuỳ hướng state feature chọn |
| `core_ui_kit` | Widget dùng lại (là package **core**, không phải feature) |

### Bị cấm

> [!CAUTION]
> - **Không bao giờ import `data_*`.** Feature nói chuyện với interface của Domain; app shell mới là nơi bind implementation.
> - **Không bao giờ import feature package khác.** Không có ngoại lệ — widget dùng chung lấy từ `core_ui_kit`, vốn nằm ở core. Nhu cầu liên feature phải đi qua hợp đồng ở `core_di` — xem [giao tiếp giữa các feature](../guides/10_cross_feature.md).
> - **Không bao giờ sửa `platform/shell/app_shell/lib/presentation/navigation/app_router.dart`** để thêm route của bạn, và không sửa `root_app.dart` để thêm localization delegate. Cả hai đều được lắp ráp từ đóng góp qua DI.

Pubspec đã cưỡng chế phần lớn điều này: phụ thuộc workspace duy nhất của `feature_dashboard` là `core_di`, `core_responsive` và `platform_kernel`, nên nó *về mặt vật lý không thể* import một feature khác.

---

## 2. Bố cục package

```
modules/<name>/feature/
├── assets/
│   └── language/            # en.arb, vi.arb
├── lib/
│   ├── feature_<name>.dart  # barrel công khai
│   ├── di/
│   │   ├── module.dart      # @InjectableInit.microPackage()
│   │   ├── localization.dart# hiện thực IFeatureLocalization
│   │   └── di.dart
│   └── src/
│       ├── pages/           # *_page.dart — màn hình đầy đủ
│       ├── widgets/         # *_widget.dart, *_card.dart — widget con
│       ├── provider/  HOẶC  bloc/
│       ├── routing/         # route module, NavigatorImpl
│       ├── utils/           # <name>_path.dart + hằng số của package
│       ├── handlers/        # tuỳ chọn — hiện thực I*ActionHandler
│       ├── services/        # tuỳ chọn — hiện thực agnostic stream
│       ├── extensions/      # extension l10n
│       ├── gen/             # l10n sinh tự động — không sửa tay
│       └── src.dart
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
| `feature_dashboard` | Khung chrome điều hướng (bottom bar / rail) | không | `DashboardRouteModule` |
| `feature_home` | Tab Home | **BLoC** | `INavDestinationModule` (order 0), `IPostSignInLocation` (`core_di`); `HomeNavigator` (`home_api` của chính nó) |
| `feature_settings` | Tab Settings | không (dùng provider toàn cục) | `INavDestinationModule` (order 1) |
| `feature_splash` | Màn hình splash | không | `IAppSplashScreen` — **không phải route**; do `MainScope` hiển thị |

Mọi feature có chuỗi hiển thị đều đăng ký thêm `IFeatureLocalization` của mình — trừ `feature_dashboard`, vốn không có chuỗi nào. `ISessionGateway` do `data_auth` đăng ký, không phải feature. `feature_onboarding` import `auth_api` và `home_api`, `feature_settings` import `auth_api` — những cạnh liên module duy nhất, mỗi cạnh trỏ tới một package API, không bao giờ tới feature khác.

`feature_auth` và `feature_home` được xây trên **hai** hướng state khác nhau một cách có chủ đích, để template minh hoạ cả hai. Xem [state management](../guides/03_state_management.md) — và hãy đọc phần so sánh trung thực ở đó trước khi chọn, vì hai nhánh **không** được trang bị ngang nhau.

> [!NOTE]
> `feature_splash` không có thư mục `routing/`. Màn hình splash được `MainScope` hiển thị trước khi `GoRouter` tồn tại, nên nó hoàn toàn không phải một route. Xem [app shell](06_app_shell.md).

---

## 4. `feature_dashboard` chỉ là chrome

Dashboard sở hữu `Scaffold` và chrome điều hướng — `BottomNavigationBar` trên cửa sổ `compact`, `NavigationRail` từ `medium` trở lên, dạng mở rộng từ `large` trở lên — không gì khác. Nó dựng chúng từ những tab được đăng ký trong DI:

```dart
// modules/dashboard/feature/lib/src/pages/dashboard_page.dart
@override
Widget build(BuildContext context) {
  final index = navigationShell.currentIndex;
  final tabs = getAllOrEmpty<INavDestinationModule>().toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  if (tabs.length < 2) return Scaffold(body: navigationShell);

  final selected = index.clamp(0, tabs.length - 1);
  void onSelect(int tabIndex) => _onTap(tabIndex, tabs[tabIndex].onRestore);
  // This is where a neutral [NavDestination] becomes one app's widget —
  // the same modules feed both forms below, unchanged.
  final destinations = [for (final tab in tabs) tab.destination(context)];

  // A phone keeps the bottom bar (the shell locks phone-sized displays to
  // portrait). From a medium window up — a tablet in either orientation,
  // an unfolded foldable, a desktop window — the tabs move to a side
  // rail, which costs width the window has to spare instead of height it
  // has not.
  final sizeClass = context.windowSizeClass;
  if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selected,
        onTap: onSelect,
        items: [for (final d in destinations) _itemOf(d)],
      ),
    );
  }

  final extended = sizeClass.isAtLeast(WindowSizeClass.large);
  // The rail sits at the start edge: the left in LTR, the right in RTL
  // (a `Row` follows the text direction). It pads for the insets on its
  // outer side only; the side facing the content is the content's to pad.
  final isRtl = Directionality.of(context) == TextDirection.rtl;
  return Scaffold(
    body: Row(
      children: [
        SafeArea(
          left: !isRtl,
          right: isRtl,
          child: NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: onSelect,
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [for (final d in destinations) _railItemOf(d)],
          ),
        ),
        Expanded(child: navigationShell),
      ],
    ),
  );
}
```

Trong các package của workspace, `feature_dashboard` chỉ phụ thuộc `core_di`, `core_responsive` và `platform_kernel` — nó **về mặt vật lý không thể** import feature khác. Vì nó đọc `getAllOrEmpty`, xoá `feature_home` sẽ mất tab Home mà app vẫn khởi động được. Khi có ít hơn hai tab thì không có bar hay rail nào cả.

Chrome được chọn theo **lớp kích thước cửa sổ**, không theo thiết bị — tablet ở cả hai hướng, iPad đang Split View và cửa sổ desktop đều nhận đúng chrome mà cửa sổ của nó đủ chỗ. (Màn hình cỡ điện thoại bị `AppInitializer` khoá dọc lúc khởi động, nên luôn hiện bottom bar; bỏ khoá đó thì điện thoại xoay ngang sẽ nhận rail theo đúng quy tắc này.) Đây là mẫu tham chiếu của template cho layout thích ứng; các widget và quy tắc nằm ở [design system §7](../guides/11_design_system.md#7-bố-cục-cho-tablet-máy-gập-và-chia-đôi-màn-hình).

### Dashboard KHÔNG được phép

- Import `feature_home` / `feature_settings`, hoặc nhúng page của chúng
- Sở hữu `HomePage` / `SettingsPage`, hay bất kỳ BLoC nghiệp vụ nào của tab
- Hardcode danh sách destination thay vì đọc từ DI
- Tự đăng ký `INavDestinationModule` để tạo tab "giả"

### Đóng góp một tab

Feature đăng ký một implementation là có ngay branch và nav item:

```dart
// modules/home/feature/lib/src/routing/home_nav_destination.dart
@LazySingleton(as: INavDestinationModule)
class HomeNavDestination extends INavDestinationModule {
  @override
  int get order => 0;                       // khóa sắp xếp tăng dần, duy nhất mỗi tab

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

`INavDestinationModule` còn cung cấp `onRestore()` dạng virtual — được gọi khi người dùng bấm vào chính tab đang mở (thao tác quen thuộc "cuộn lên đầu / pop về gốc"). Override nếu tab của bạn cần phản ứng.

Chỉ dùng `INavDestinationModule` cho **điểm đến chính của bottom-nav** cần `StatefulShellBranch` riêng. Màn hình push chồng lên một tab chỉ là route thường bên trong branch đó.

---

## 5. Widget dùng chung nằm ở core, không phải ở đây

Thư viện widget dùng lại là **`core_ui_kit`** tại `platform/ui/ui_kit` — một package core, không phải feature. Nó nằm ngoài `modules/*/feature/` để mọi thứ trong thư mục đó đều là mảng sản phẩm thực sự gỡ được. Cấu trúc, chiều phụ thuộc và quy tắc UI-agnostic của nó được mô tả ở [tầng core](02_core.md).

Điều quan trọng ở phía feature là nghĩa vụ của **bên gọi**:

```dart
// widget nhận số thô; feature là nơi scale
CustomButton(width: context.w(120), height: context.h(44))
```

Widget trong `core_ui_kit` không bao giờ scale lại một giá trị được truyền vào — nó dùng nguyên giá trị nhận được, và chỉ scale các hằng số mặc định của chính nó qua `core_responsive`. Scale thêm một tham số bên trong widget sẽ làm nó bị scale hai lần, nên việc scale giá trị bạn truyền vào luôn được làm ở đây, ngay tại chỗ gọi — và luôn qua `BuildContext`, vì `core_responsive` **không có extension trên `num`**: `120.w` không biên dịch được.

## 6. Vòng đời UI controller

| Phạm vi | Annotation | Dùng cho |
|:---|:---|:---|
| **Theo màn hình** | `@injectable` (factory) | ViewModel / BLoC gắn với một màn hình |
| **Toàn app** | `@lazySingleton` | `AuthProvider`, `ThemeProvider`, `LanguageProvider`, `AppProvider`, `DeeplinkProvider` |

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

Controller toàn cục thì không cần bọc gì cả. `AuthProvider` là `@lazySingleton`, nên `LoginRoute` dựng thẳng `const LoginPage()` và page đọc nó bằng `Consumer<AuthProvider>`:

```dart
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.nested('auth');

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const LoginPage();
  }
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

| Thành phần | Hậu tố file | Hậu tố class | Ví dụ |
|:---|:---|:---|:---|
| Màn hình | `_page.dart` / `_screen.dart` | `Page` / `Screen` | `LoginPage` |
| Widget con | `_widget.dart` / `_card.dart` | `Widget` / `Card` | `AuthHeaderWidget` |
| Controller Provider | `_provider.dart` | `Provider` | `AuthProvider` |
| Controller BLoC | `_bloc.dart` | `Bloc` | `HomeProfileBloc` |
| Cubit | `_cubit.dart` | `Cubit` | chỉ khi event không mang lại gì |
| Navigator impl | `_navigator_impl.dart` | `NavigatorImpl` | `AuthNavigatorImpl` |
| Action handler impl | `_action_handler_impl.dart` | `ActionHandlerImpl` | `AuthActionHandlerImpl` |
| Dialog | `_dialog.dart` | `Dialog` | `ConfirmationDialog` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` | `HomeSettingsBottomSheet` |

Dialog và bottom sheet **luôn luôn** là class widget riêng — không bao giờ là closure viết thẳng trong `showDialog(builder: …)`.

Mọi văn bản hiển thị cho người dùng đều phải dịch; hardcode chuỗi là bị cấm. Xem [localization và theming](../guides/09_localization_theming.md).

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

Checklist:

- [ ] Có `resolution: workspace` trong pubspec; không có `data_*` và không có feature khác trong dependencies
- [ ] Route đăng ký qua `IFeatureRouteModule` hoặc `INavDestinationModule` — không đụng `app_router.dart`
- [ ] Localization đăng ký qua `IFeatureLocalization` — không đụng `root_app.dart`
- [ ] Controller theo màn hình là `@injectable`, tạo ở route, không bọc lại trong page
- [ ] Hằng số đường dẫn nằm ở `src/utils/<name>_path.dart`
- [ ] Điều hướng liên feature đi qua Navigator interface ở `core_di`, `BuildContext` truyền từ bên gọi
- [ ] Mọi kích thước đều scale qua `BuildContext` — `context.w()` / `context.h()` / `context.sp()` / `context.r()`
- [ ] Layout đổi theo cửa sổ thì chọn theo lớp kích thước cửa sổ (`context.adaptive`, `AdaptiveLayout`) — không bao giờ theo thiết bị hay nền tảng
- [ ] Asset riêng của feature nằm trong feature package, không nhét vào `core_base_ui`

---

## 9. Giao tiếp giữa các feature — vì sao có hình dạng này

Các feature không bao giờ import lẫn nhau. Phần hướng dẫn — chọn mô hình nào trong sáu mô hình và nối dây ra sao — nằm ở [`../guides/10_cross_feature.md`](../guides/10_cross_feature.md). Mục này giải thích vì sao nó có hình dạng như vậy.

Bảng đăng ký: RULE-04, RULE-08, RULE-12, RULE-25, RULE-54.

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

### Vì sao là `SessionPrincipal` chứ không phải `UserEntity`

Hợp đồng ở `core_di` không được gọi
tên một kiểu thuộc package `domain_*` (RULE-08): import đó khiến mọi bên tiêu thụ
phụ thuộc `domain_auth` ngay lúc biên dịch, và `getItOrNull` không gỡ được điều đó. Vì vậy `core_di`
sở hữu một value type nhỏ,
[`SessionPrincipal`](../../../platform/foundation/contracts/lib/src/session/session_principal.dart), và feature
auth thu hẹp entity của mình về kiểu đó tại ranh giới (`AuthStatusStreamImpl.toPrincipal`). Hợp đồng cố ý nhỏ
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
