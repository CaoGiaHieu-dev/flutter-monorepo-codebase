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
| `core_common` | Hằng số, `AppFailure`, helper, các hàm `getIt` |
| `core_base_ui` | Design token, theme, `ThemeProvider` / `LanguageProvider` |
| `provider_state_management` **hoặc** `bloc_state_management` | Tuỳ hướng state feature chọn |
| `core_ui_kit` | Widget dùng lại (là package **core**, không phải feature) |

### Bị cấm

> [!CAUTION]
> - **Không bao giờ import `data_*`.** Feature nói chuyện với interface của Domain; app shell mới là nơi bind implementation.
> - **Không bao giờ import feature package khác.** Không có ngoại lệ — widget dùng chung lấy từ `core_ui_kit`, vốn nằm ở core. Nhu cầu liên feature phải đi qua hợp đồng ở `core_di` — xem [giao tiếp giữa các feature](../guides/10_cross_feature.md).
> - **Không bao giờ sửa `app/lib/presentation/navigation/app_router.dart`** để thêm route của bạn, và không sửa `root_app.dart` để thêm localization delegate. Cả hai đều được lắp ráp từ đóng góp qua DI.

Pubspec đã cưỡng chế phần lớn điều này: `feature_dashboard` chỉ khai `core_di` và `core_common`, nên nó *về mặt vật lý không thể* import một feature khác.

---

## 2. Bố cục package

```
packages/features/<name>/
├── assets/
│   └── language/            # <name>_en.arb, <name>_vi.arb
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
// packages/features/auth/lib/src/utils/auth_path.dart
class AuthPath {
  AuthPath._();
  static const String LOGIN = '/auth/login';
  static const String REGISTER = '/auth/register';
  static const String FORGOT_PASSWORD = '/auth/forgot-password';
}
```

---

## 3. Các feature package trong template

| Package | Mối quan tâm | State management | Đăng ký |
|:---|:---|:---|:---|
| `feature_onboarding` | Giới thiệu lần đầu chạy | không | `IFeatureRouteModule`, `IAppEntryLocation` |
| `feature_auth` | Đăng nhập / đăng ký / quên mật khẩu | **Provider** | `IFeatureRouteModule`, `AuthNavigator`, `IAuthStatusStream`, `IAuthActionHandler` |
| `feature_dashboard` | Khung chrome bottom-nav | không | `DashboardRouteModule` |
| `feature_home` | Tab Home | **BLoC** | `IDashboardTabModule` (order 0), `HomeNavigator` |
| `feature_settings` | Tab Settings | không (dùng provider toàn cục) | `IDashboardTabModule` (order 1), `SettingsNavigator` |
| `feature_splash` | Màn hình splash | không | chỉ `IFeatureLocalization` — **không phải route** |

`feature_auth` và `feature_home` được xây trên **hai** hướng state khác nhau một cách có chủ đích, để template minh hoạ cả hai. Xem [state management](../guides/03_state_management.md) — và hãy đọc phần so sánh trung thực ở đó trước khi chọn, vì hai nhánh **không** được trang bị ngang nhau.

> [!NOTE]
> `feature_splash` không có thư mục `routing/`. Màn hình splash được `MainScope` hiển thị trước khi `GoRouter` tồn tại, nên nó hoàn toàn không phải một route. Xem [app shell](06_app_shell.md).

---

## 4. `feature_dashboard` chỉ là chrome

Dashboard sở hữu `Scaffold` và `BottomNavigationBar` — không gì khác. Nó dựng cả hai từ những tab được đăng ký trong DI:

```dart
// packages/features/dashboard/lib/src/pages/dashboard_page.dart
@override
Widget build(BuildContext context) {
  final index = navigationShell.currentIndex;
  final tabs = getAllOrEmpty<IDashboardTabModule>().toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return Scaffold(
    body: navigationShell,
    bottomNavigationBar: tabs.length < 2
        ? null
        : BottomNavigationBar(
            currentIndex: index.clamp(0, tabs.length - 1),
            onTap: (tabIndex) => _onTap(context, tabIndex, tabs[tabIndex].onRestore),
            items: [for (final tab in tabs) tab.navigationBarItem(context)],
          ),
  );
}
```

Vì nó đọc `getAllOrEmpty`, xoá `feature_home` sẽ mất tab Home mà app vẫn khởi động được. Khi có ít hơn hai tab, thanh nav bị ẩn hoàn toàn.

### Dashboard KHÔNG được phép

- Import `feature_home` / `feature_settings`, hoặc nhúng page của chúng
- Sở hữu `HomePage` / `SettingsPage`, hay bất kỳ BLoC nghiệp vụ nào của tab
- Hardcode danh sách `BottomNavigationBarItem` thay vì đọc từ DI
- Tự đăng ký `IDashboardTabModule` để tạo tab "giả"

### Đóng góp một tab

Feature đăng ký một implementation là có ngay branch và nav item:

```dart
// packages/features/home/lib/src/routing/home_dashboard_tab_module.dart
@LazySingleton(as: IDashboardTabModule)
class HomeDashboardTabModule extends IDashboardTabModule {
  @override
  int get order => 0;                       // phải khớp vị trí tab mong muốn

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

`IDashboardTabModule` còn cung cấp `onRestore()` dạng virtual — được gọi khi người dùng bấm vào chính tab đang mở (thao tác quen thuộc "cuộn lên đầu / pop về gốc"). Override nếu tab của bạn cần phản ứng.

Chỉ dùng `IDashboardTabModule` cho **điểm đến chính của bottom-nav** cần `StatefulShellBranch` riêng. Màn hình push chồng lên một tab chỉ là route thường bên trong branch đó.

---

## 5. Widget dùng chung nằm ở core, không phải ở đây

Thư viện widget dùng lại là **`core_ui_kit`** tại `packages/core/ui_kit` — một package core, không phải feature. Nó đã được chuyển ra khỏi `packages/features/` để mọi thứ còn lại ở đây đều là mảng sản phẩm thực sự gỡ được. Cấu trúc, chiều phụ thuộc và quy tắc UI-agnostic của nó được mô tả ở [tầng core](02_core.md).

Điều quan trọng ở phía feature là nghĩa vụ của **bên gọi**:

```dart
// widget nhận số thô; feature là nơi scale
CustomButton(width: 120.w, height: 44.h)
```

Widget trong `core_ui_kit` không bao giờ tự áp `flutter_screenutil_plus` bên trong. Nếu bạn truyền vào giá trị đã scale thì nó sẽ bị scale hai lần, nên việc scale luôn được làm ở đây, ngay tại chỗ gọi.

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
// packages/features/home/lib/src/routing/home_route_module.dart
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

> [!CAUTION]
> **Không bọc lần thứ hai bên trong page.** Nếu route đã cung cấp controller, thêm một `BlocProvider` / `ChangeNotifierProvider` nữa trong `HomePage.build` sẽ tạo ra một instance *khác*. Page hiển thị một object trong khi event lại đi tới object kia — giao diện trông như đứng yên, và cả hai instance đều không được dispose đúng cách.

Controller toàn cục thì không cần bọc gì cả. `AuthProvider` là `@lazySingleton`, nên `LoginRoute` dựng thẳng `const LoginPage()` và page đọc nó bằng `Consumer<AuthProvider>`:

```dart
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;

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

Bản BLoC được đổi tên từ `ViewState` thành `BlocViewState<T>` chính là để một file import cả hai barrel không bị trùng tên:

```dart
@injectable
class HomeProfileBloc
    extends BaseBloc<HomeProfileEvent, BlocViewState<UserEntity?>> {
  HomeProfileBloc(this._authStatusStream)
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
# type=1 (feature), tên, thư mục, SM: 1=Provider 2=BLoC 3=không, route: 1=stack 2=tab 3=không
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

Generator tạo package, thêm vào workspace, và đăng ký DI module của nó trong `app/lib/di/injection.dart`. Sau đó:

```bash
dart tools/barrel_generator/generate.dart packages/features/profile/lib
dart run build_runner build -d --workspace
```

Checklist:

- [ ] Có `resolution: workspace` trong pubspec; không có `data_*` và không có feature khác trong dependencies
- [ ] Route đăng ký qua `IFeatureRouteModule` hoặc `IDashboardTabModule` — không đụng `app_router.dart`
- [ ] Localization đăng ký qua `IFeatureLocalization` — không đụng `root_app.dart`
- [ ] Controller theo màn hình là `@injectable`, tạo ở route, không bọc lại trong page
- [ ] Hằng số đường dẫn nằm ở `src/utils/<name>_path.dart`
- [ ] Điều hướng liên feature đi qua Navigator interface ở `core_di`, `BuildContext` truyền từ bên gọi
- [ ] Mọi kích thước đều scale bằng `.w` / `.h` / `.sp` / `.r`
- [ ] Asset riêng của feature nằm trong feature package, không nhét vào `core_base_ui`

---

## Liên quan

- [App shell](06_app_shell.md) — cách các package này được lắp thành một app
- [Hướng dẫn: tạo feature](../guides/01_new_feature.md)
- [Hướng dẫn: state management](../guides/03_state_management.md) · [routing](../guides/04_routing.md) · [giao tiếp liên feature](../guides/10_cross_feature.md)
- [Quy tắc](../reference/01_rules.md) · [Đặt tên](../reference/02_naming.md)
