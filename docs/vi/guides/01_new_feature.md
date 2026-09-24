# Hướng dẫn: Tạo một feature mới

File này trả lời câu hỏi **"làm sao thêm một mảng màn hình mới vào app?"** — trọn vẹn từ thư mục
rỗng đến route mà app gọi tới được. Ví dụ xuyên suốt: dựng feature `profile`.

Đọc xong bạn sẽ có: package đã sinh, route đăng ký qua DI (không đụng `app_router.dart`),
controller khởi tạo đúng ở tầng route, bản dịch riêng, và navigator để feature khác gọi mà không
phải import bạn.

---

## 1. Sinh package

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

Năm tham số vị trí được đọc bởi
[`tools/module_generator/src/input_actions.dart`](../../../tools/module_generator/src/input_actions.dart):

| Vị trí | Giá trị | Ý nghĩa |
| :-- | :-- | :-- |
| 1 | `1` | Loại module — `1` Feature, `2` Domain, `3` Data, `4` Core, `5` Custom |
| 2 | `profile` | Tên module (snake_case). Package thành `feature_profile` tại `modules/profile/feature` |
| 3 | `""` | Tiền tố package tuỳ chỉnh — chỉ dùng khi loại là `5` (`<tiền_tố>_<tên>` tại `platform/<nhóm>/<tên>`). Truyền `""` cho loại 1–4 |
| 4 | `1` | State management — `1` Provider, `2` BLoC, `3` không dùng |
| 5 | `1` | Kiểu route — `1` `IFeatureRouteModule`, `2` `INavDestinationModule`, `3` không sinh |

Chạy không kèm tham số trên terminal thì tool sẽ hỏi tương tác từng bước; không có terminal thì
thiếu tham số sẽ thoát với mã 64 thay vì tự đoán. `--help` in ra cách dùng.

Tuỳ chọn `--apps <id,id>` đặt sau các tham số vị trí chỉ compose module vào những app đó —
`app.id` lấy từ `apps/*/app_manifest.yaml`, ví dụ `--apps mobile`. Không có nó thì module vào mọi
app. Id lạ sẽ thoát mã 64 trước khi ghi bất cứ thứ gì.

> [!NOTE]
> Nếu đã có package tên `feature_profile`, tool **từ chối** và thoát với mã 64 (mã 1 nếu thư mục
> `modules/profile/feature` tồn tại mà không chứa package đó) — nó không bao giờ
> ghi đè hay xoá một package có sẵn. Hãy tự xoá hoặc đổi tên trước.

### Chọn tham số 5 — quyết định hình dạng routing của bạn

| Chọn | Khi nào | Bạn nhận được |
| :-- | :-- | :-- |
| `1` `IFeatureRouteModule` | Một chồng màn hình push lên trên app (auth, onboarding, màn chi tiết) | Stub `*FeatureRouteModule` |
| `2` `INavDestinationModule` | Một **đích điều hướng chính** — bottom bar trên điện thoại, `NavigationRail` từ cửa sổ medium trở lên — cần back stack riêng bền vững | Stub `*NavDestination` |
| `3` không | Bạn sẽ tự nối routing sau, hoặc feature không có route | Không sinh stub |

> [!WARNING]
> Chỉ dùng `2` cho tab bottom-nav thật. Màn hình push (login, chi tiết) phải nằm trong
> `IFeatureRouteModule`. Đăng ký tab giả sẽ phá thứ tự index của dashboard — xem
> [`04_routing.md`](04_routing.md).

---

## 2. Tool làm gì, và bạn còn phải làm gì

**Tự động** (xem [`tools/module_generator/generate.dart`](../../../tools/module_generator/generate.dart)):

1. Tạo cây thư mục và `pubspec.yaml`
2. Ghi `lib/di/module.dart` với `@InjectableInit.microPackage()`
3. Thêm vào mục `modules:` của **mọi** `apps/<id>/app_manifest.yaml` — cả `admin` lẫn `mobile` — trừ khi `--apps` chỉ định một tập con, rồi tự chạy `dart tools/composer/composer.dart sync`, lệnh này sinh lại danh sách `workspace:` ở `pubspec.yaml` gốc cùng path dependency và `injection.dart` của từng app. Bạn không phải chạy tay gì cả — nhưng xem ghi chú bên dưới nếu module không thuộc về mọi app
4. Chạy `dependency_sync.dart`, `flutter pub get`, `flutter gen-l10n`, barrel generator,
   `build_runner build --workspace`, rồi `dart fix --apply`
5. Ghi sẵn các test pass ngay khi sinh ra: `test/profile_page_test.dart` (page dưới
   `ResponsiveInit` và localization của nó, controller được cung cấp đúng như route cung cấp) và
   `test/profile_provider_test.dart` — `test/<name>_bloc_test.dart` với BLoC, không có test
   controller với SM `3`. Chạy bằng `cd modules/profile/feature && flutter test`; CI Gate 3 cũng
   chạy chúng

> [!IMPORTANT]
> **Không có `--apps` thì mọi app đều compose module mới — kể cả `apps/admin`.** `apps/admin` cố ý chỉ là một tập con (auth + settings), nên với module chỉ dành cho `mobile`, hãy nói rõ ngay khi sinh:
>
> ```bash
> dart tools/module_generator/generate.dart 1 profile "" 1 1 --apps mobile
> ```
>
> Lỡ sinh vào mọi app rồi? Gỡ nó ra khỏi `admin` bằng tay:
>
> 1. Xoá dòng `- { id: <name>, layers: [...] }` của nó dưới `modules:` trong `apps/admin/app_manifest.yaml` (hoặc chỉ bỏ khỏi `layers:` những layer app đó không cần).
> 2. `dart tools/composer/composer.dart sync` — viết lại path dependency trong `apps/admin/pubspec.yaml` và `apps/admin/lib/di/injection.dart`; danh sách `workspace:` ở root vẫn giữ package chừng nào còn app khác compose nó.
> 3. `flutter pub get && dart run build_runner build --workspace` — sinh lại `injection.config.dart` của admin.
>
> Commit manifest cùng với những gì `sync` sinh lại: CI Gate 0 (`composer verify`) fail khi chúng lệch nhau.

**Thủ công — tool in ra ở cuối:**

1. Hoàn thiện `TypedGoRoute` / navigator trong `lib/src/routing/`
2. Điền nội dung cho stub route module (`routes`, và với tab thì thêm `order`, `path`, `destination`)
3. Nếu bạn thêm một hợp đồng navigator vào `core_di` (§7), chạy barrel generator cho `platform/foundation/contracts/lib` trước
4. Chạy lại `build_runner`, rồi **restart hoàn toàn** app — DI mới không được hot reload nhận

> [!NOTE]
> FVM được tự phát hiện (`useFvm` in `tools/shared/toolchain.dart`): tool chỉ thêm tiền tố `fvm ` vào lệnh khi có đủ
> cả hai — một file cấu hình (`.fvmrc` hoặc `.fvm/fvm_config.json`) và `fvm --version` chạy được.
> Nếu không, nó gọi thẳng `dart` / `flutter` toàn cục. Xem
> [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md).

---

## 3. Cấu trúc thư mục

Generator sinh ra cây thư mục dưới đây (cùng các file sinh tự động `gen/`, `*.g.dart` và `module.module.dart`). `widgets/` được tạo **rỗng**, mà git không theo dõi thư mục rỗng — nó biến mất khỏi commit hay bản clone mới cho tới khi widget con đầu tiên được đặt vào.

```
modules/profile/feature/
├── assets/language/          en.arb, vi.arb  — bản dịch riêng của feature
├── l10n.yaml                 cấu hình gen-l10n (tên class, thư mục output)
├── lib/
│   ├── di/
│   │   ├── module.dart       @InjectableInit.microPackage()
│   │   └── localization.dart implementation của IFeatureLocalization
│   ├── feature_profile.dart  barrel công khai
│   └── src/
│       ├── pages/            widget *Page / *Screen
│       ├── widgets/          widget con *Widget / *Card (được tạo rỗng)
│       ├── provider/         controller (Provider) — là `bloc/` nếu bạn chọn BLoC
│       ├── routing/          route module + navigator impl
│       ├── extensions/       extension l10n
│       ├── gen/language/     localisation sinh tự động (không sửa tay)
│       └── utils/            hằng số thuộc sở hữu của package này
└── pubspec.yaml
```

> [!NOTE]
> Thư mục controller là **số ít** — `src/provider/` (như `feature_auth`) hoặc `src/bloc/` (như
> `feature_home`). Đặt tên số nhiều `providers/` / `blocs/` là vi phạm quy ước; xem
> [`../reference/02_naming.md`](../reference/02_naming.md).

Hằng số path đã có sẵn — generator ghi chúng vào `lib/src/utils/<name>_path.dart`, và mọi thứ khác đều tham chiếu tới đó. **Hãy sửa file đã được sinh** để đổi hoặc thêm path; đừng tạo file thứ hai:

```dart
// modules/profile/feature/lib/src/utils/profile_path.dart — như generator sinh ra
class ProfilePath {
  ProfilePath._();

  static const String PROFILE = '/profile';
}
```

Cùng hình dạng với
[`modules/home/feature/lib/src/utils/home_path.dart`](../../../modules/home/feature/lib/src/utils/home_path.dart).

---

## 4. Viết route module

### Phương án A — tab bottom-nav (`INavDestinationModule`)

Hai file. Trước hết là bản thân các route — code thật từ
[`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

```dart
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../bloc/home_profile_bloc.dart';
import '../pages/pages.dart';
import '../utils/home_path.dart';

part 'home_route_module.g.dart';

/// SAMPLE — a tab's route is an ordinary typed route; the shell turns each
/// destination's routes into a `StatefulShellBranch`.
@TypedGoRoute<HomeRoute>(path: HomePath.HOME)
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

Rồi tới phần đóng góp qua DI — code thật từ
[`home_nav_destination.dart`](../../../modules/home/feature/lib/src/routing/home_nav_destination.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';
import '../utils/home_path.dart';
import 'home_route_module.dart';

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

`order` quyết định vị trí tab và **bắt buộc phải duy nhất** giữa mọi tab đã đăng ký — `AppRouter`
sắp xếp theo nó để dựng danh sách `StatefulShellBranch`.

### Phương án B — chồng màn hình push (`IFeatureRouteModule`)

Nhỏ hơn nhiều. Code thật từ
[`modules/auth/feature/lib/src/routing/auth_feature_route_module.dart`](../../../modules/auth/feature/lib/src/routing/auth_feature_route_module.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import 'auth_route_module.dart';

@LazySingleton(as: IFeatureRouteModule)
class AuthFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$authShellRoute];
}
```

Không có `order` — nhóm route này khớp theo path chứ không theo chỉ số.

> [!CAUTION]
> Tuyệt đối không sửa `platform/shell/app_shell/lib/presentation/navigation/app_router.dart` để thêm route của bạn. Nó
> gom các đóng góp qua `getAllOrEmpty<IFeatureRouteModule>()` và
> `getAllOrEmpty<INavDestinationModule>()`. Hardcode ở đó là phá khả năng gỡ feature.

---

## 5. Khởi tạo controller ở tầng route

Controller được tạo trong `build` của route, không bao giờ tạo bên trong page.

```dart
// BLoC — trích từ home_route_module.dart ở trên
return BlocProvider(
  // Auth is optional: an app composed without `feature_auth` registers
  // no ISessionStatusStream, and Home then shows the signed-out state.
  create: (_) => getIt<HomeProfileBloc>(
    param1: getItOrNull<ISessionStatusStream>(),
  ),
  child: const HomePage(),
);
```

```dart
// Provider — cùng hình dạng
return ChangeNotifierProvider(
  create: (_) => getIt<ProfileProvider>(),
  child: const ProfilePage(),
);
```

> [!CAUTION]
> **Tuyệt đối không bọc controller lần nữa bên trong Page.** `BlocProvider` /
> `ChangeNotifierProvider` đã nằm ở route rồi. Bọc lần hai tạo ra *instance thứ hai*: page đọc
> state mà không ai ghi vào, còn instance thứ nhất bị rò rỉ. Đây là lỗi phổ biến nhất với pattern
> này.

Controller gắn màn hình dùng `@injectable` (factory, huỷ theo route). Chỉ controller toàn app —
`AuthProvider`, `ThemeProvider`, `LanguageProvider` — mới dùng `@lazySingleton`. Đăng ký controller
màn hình thành singleton sẽ rò rỉ nó suốt vòng đời tiến trình. Chi tiết ở [`05_di.md`](05_di.md).

---

## 6. Đa ngôn ngữ

Bản dịch của feature nằm trong chính feature. Không thêm gì vào app shell.

**Generator đã ghi sẵn cả bốn phần dưới đây** — `l10n.yaml`, hai file ARB, extension
`context.l10n<Name>` và phần đăng ký `IFeatureLocalization` — và chạy `gen-l10n` một lần. Việc của bạn
là **sửa các file đã được sinh**, chủ yếu là ARB; đừng tạo lại chúng. Chúng được trình bày ở đây để
bạn biết mỗi file làm gì.

`modules/profile/feature/l10n.yaml` — như generator sinh ra, cùng hình dạng với
[`modules/home/feature/l10n.yaml`](../../../modules/home/feature/l10n.yaml):

```yaml
arb-dir: assets/language
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: FeatureProfileLocalizations
preferred-supported-locales: [en, vi]
untranslated-messages-file: untranslated-messages.txt
output-dir: lib/src/gen/language
```

`assets/language/en.arb` (và `vi.arb` tương ứng) — được sinh với một key duy nhất, `title`, mà page
được sinh (và, với một tab, nhãn destination được sinh) đọc qua `context.l10nProfile.title`. Thêm
key của bạn bên cạnh, theo `lowerCamelCase`, và dịch giá trị trong `vi.arb` — generator ghi cùng một
từ tiếng Anh vào cả hai file:

```json
{
  "@@locale": "en",
  "title": "Profile"
}
```

Extension — bản được sinh theo đúng code thật này từ
[`l10n_home_extension.dart`](../../../modules/home/feature/lib/src/extensions/l10n_home_extension.dart):

```dart
import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

Phần đăng ký delegate qua DI — được sinh thành `lib/di/localization.dart`, giống code thật này từ
[`modules/home/feature/lib/di/localization.dart`](../../../modules/home/feature/lib/di/localization.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_home.dart';

@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
```

[`app_material_wrapper.dart`](../../../platform/shell/app_shell/lib/presentation/app_material_wrapper.dart) của app shell gom mọi `IFeatureLocalization` đã đăng ký bằng `getAllOrEmpty`, nên **không sửa `root_app.dart`** (hay wrapper đó).

Sinh lại sau mỗi lần đổi `.arb`:

```bash
cd modules/profile/feature && flutter gen-l10n
```

> [!WARNING]
> Mọi chữ hiển thị cho người dùng đều phải được dịch. Hardcode chuỗi trong UI là bị cấm — xem
> [`09_localization_theming.md`](09_localization_theming.md).

---

## 7. Navigator — để feature khác gọi tới bạn

Feature khác không được import `feature_profile`. Khai hợp đồng trong **package API** của module bạn, `modules/<name>/api` (ở đây là `profile_api` — chỉ phụ thuộc foundation và Flutter, `arch_check` R3; cách tạo: [`12_module_isolation.md` § 7](12_module_isolation.md)). Bên gọi phụ thuộc `profile_api`, không bao giờ phụ thuộc `feature_profile`; `core_di` không chứa navigator của module nào:

```dart
// modules/profile/api/lib/src/navigators/profile_navigator.dart
import 'package:flutter/widgets.dart';

abstract class ProfileNavigator {
  void toProfile(BuildContext context);
}
```

Đúng hình dạng của
[`home_navigator.dart`](../../../modules/home/api/lib/src/navigators/home_navigator.dart) trong `home_api`.

Cài đặt nó ngay trong `routing/` của bạn — code thật từ
[`home_navigator_impl.dart`](../../../modules/home/feature/lib/src/routing/home_navigator_impl.dart):

```dart
import 'package:home_api/home_api.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'home_route_module.dart';

@Singleton(as: HomeNavigator)
class HomeNavigatorImpl implements HomeNavigator {
  @override
  void toHome(BuildContext context) => const HomeRoute().go(context);
}
```

Bên gọi ở package khác dùng `getItOrNull<ProfileNavigator>()?.toProfile(context)` (arch_check R8) — không hardcode path, không
`context.go('/profile')`. Luôn truyền `BuildContext` từ widget gọi, đừng lấy từ `NavigatorKeys`.

---

## 8. Hoàn tất và kiểm chứng

```bash
# 1. Export ProfileNavigator mới từ barrel của core_di (§7 đã thêm một file vào platform/foundation/contracts/lib)
dart tools/barrel_generator/generate.dart platform/foundation/contracts/lib
# 2. Sinh lại DI / route — injectable phải thấy ProfileNavigator qua `package:core_di/core_di.dart`
dart run build_runner build --workspace
# 3. Export lại các file mới của feature (và các file được sinh) từ barrel của nó
dart tools/barrel_generator/generate.dart modules/profile/feature/lib
flutter analyze
```

> [!IMPORTANT]
> Bỏ bước 1 thì `flutter analyze` báo `Undefined name 'ProfileNavigator'` ở navigator impl và ở
> phần đăng ký được sinh của nó: barrel của `core_di` là file được sinh, nên một file thêm vào
> `platform/foundation/contracts/lib/src/` sẽ vô hình với package khác cho tới khi chạy barrel generator cho
> `platform/foundation/contracts/lib`. Điều này đúng với mọi package bạn thêm file vào — chạy lại barrel generator cho
> `lib/` của nó.

Sau đó **restart hoàn toàn** app (không phải hot reload) để đồ thị DI mới được dựng lại.

### Checklist

- [ ] `pubspec.yaml` của package có `resolution: workspace`
- [ ] Mọi dependency thực dùng đều được khai — kiểm bằng `dart tools/unused_checker/check_unused_packages.dart`
- [ ] Hằng số nằm trong `src/utils/`, không rải rác
- [ ] Route đăng ký qua `IFeatureRouteModule` / `INavDestinationModule` — `app_router.dart` không bị đụng
- [ ] Controller tạo ở tầng route, page **không** bọc lại
- [ ] Controller màn hình là `@injectable`, không phải singleton
- [ ] Đã đăng ký `IFeatureLocalization` — `root_app.dart` không bị đụng
- [ ] Không hardcode chuỗi hiển thị
- [ ] Mọi kích thước đi qua context — `context.w()` / `context.h()` / `context.sp()` / `context.r()`
- [ ] Navigator interface ở `core_di`, implementation nằm cục bộ
- [ ] Không import feature khác (không ngoại lệ — widget dùng chung lấy từ `core_ui_kit`)

---

## 9. Gỡ một feature

App phải chạy được khi xoá bất kỳ feature nào. Gỡ theo đúng thứ tự:

1. Dòng của nó trong mục `modules:` ở mọi `apps/<id>/app_manifest.yaml` có ghép nó
2. `dart tools/composer/composer.dart sync` — sinh lại `injection.dart`, path dependency của app và danh sách `workspace:` ở root
3. Thư mục `modules/<tên>/feature/`
4. `flutter pub get && dart run build_runner build --workspace`

**Hãy để tool làm.** `remove_sample.dart` thực hiện các bước trên, và quan trọng hơn là nó
nói cho bạn biết điều mà danh sách thủ công kia không nói:

```bash
dart tools/sample_cleanup/remove_sample.dart --list   # cái nào sample, cái nào framework
dart tools/sample_cleanup/remove_sample.dart auth     # dry-run, không ghi gì
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

> [!CAUTION]
> **Các bước trên không phải lúc nào cũng đủ.** App shell thì suy biến an toàn — nó phân giải mọi
> thứ qua hợp đồng `core_di` kèm fallback `getAllOrEmpty` / `getItOrNull` — nhưng *các sample khác*
> có thể đang phụ thuộc cứng vào cái bạn định xoá. Một contract do feature gỡ được sở hữu phải đến
> tay nơi tiêu thụ theo đúng cách đó — không bao giờ qua tham số constructor bắt buộc, thứ DI không
> thể thoả mãn khi chủ sở hữu đã bị gỡ. Hiện nay gỡ `auth` không làm vỡ sample nào; ba nơi tiêu thụ
> xuống cấp an toàn:
>
> | Nơi tiêu thụ | Kiểu phụ thuộc | Hậu quả |
> |---|---|---|
> | `feature_home` (`home_route_module.dart:25`) | `getItOrNull<ISessionStatusStream>()` truyền vào dưới dạng **factory param** | Home hiển thị trạng thái chưa đăng nhập |
> | `feature_settings` (`settings_page.dart:47`) | `getItOrNull<IAuthActionHandler>()` (từ `auth_api`, được `remove_sample` giữ lại khi còn bị import) | Dòng logout đơn giản bị ẩn đi |
> | `feature_onboarding` (`OnboardingPage`) | `getItOrNull<AuthNavigator>()` (từ `auth_api`, cũng được giữ lại) | Nút bấm chuyển sang Home (`HomeNavigator`); không có cả hai thì nút không làm gì |
>
> Dry-run in ra mọi liên kết nó biết — `breaks` và `safe_couplings` trong
> `tools/sample_manifest.yaml` — cộng các package API được giữ lại vì package khác vẫn import
> chúng. Hãy đọc nó trước khi xoá bất cứ thứ gì.

> [!NOTE]
> Việc `injection.dart` gọi tên các package feature là **tham chiếu cứng có chủ đích duy nhất** của
> composition root — nơi lắp ráp thì buộc phải biết nó lắp cái gì. Đó cũng là chỗ duy nhất: không
> file nào khác trong app import module (`arch_check` R10 giữ điều đó), và shell dùng chung ở `platform/shell/app_shell/` là
> package `platform/`, nên R1 cấm nó import module ngay từ đầu. Shell có import `core_ui_kit` ở vài
> nơi, và điều đó hoàn toàn ổn — đó là package core, không phải feature có thể gỡ.

---

## Liên quan

- [`04_routing.md`](04_routing.md) — hợp đồng routing chi tiết
- [`03_state_management.md`](03_state_management.md) — Provider và BLoC
- [`05_di.md`](05_di.md) — phạm vi đăng ký và thứ tự nạp module
- [`10_cross_feature.md`](10_cross_feature.md) — giao tiếp với feature khác
- [`../architecture/05_features.md`](../architecture/05_features.md) — luật của tầng feature
