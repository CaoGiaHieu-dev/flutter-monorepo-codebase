<!-- translated-from: docs/en/guides/01_new_feature.md@a5b62df -->
# Hướng dẫn: Tạo một feature mới

## Mục tiêu

Bạn thêm một mảng màn hình mới vào app, trọn vẹn từ một thư mục trống tới một route mà app mở được. Ví dụ xuyên suốt là feature `profile`. Cuối cùng bạn có:

- một package được sinh ra, đã ghép vào những app bạn chọn;
- một route nối qua DI, không bao giờ qua `app_router.dart`;
- một controller được khởi tạo ở tầng route;
- bản dịch riêng của feature;
- một navigator mà feature khác gọi được mà không cần import bạn.

## Điều kiện cần

- Môi trường đã cài đặt xong — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).
- Mới đến với repo? Hãy làm [`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md) trước. Nó đi hết con đường của hướng dẫn này một lần, với mọi lệnh đã được chạy kiểm chứng.
- Một feature package được tổ chức ra sao và được phụ thuộc vào đâu — [`../architecture/05_features.md`](../architecture/05_features.md).

---

## 1. Sinh package

```bash
dart tools/module_generator/generate.dart 1 profile "" 1 1
```

Năm tham số vị trí được đọc bởi [`tools/module_generator/src/input_actions.dart`](../../../tools/module_generator/src/input_actions.dart):

| Vị trí | Giá trị | Ý nghĩa |
| :-- | :-- | :-- |
| 1 | `1` | Loại module — `1` Feature, `2` Domain, `3` Data, `4` Core, `5` Custom, `6` API (`modules/<tên>/api`, package `<tên>_api`; bước 7) |
| 2 | `profile` | Tên module (snake_case). Package thành `feature_profile` tại `modules/profile/feature` |
| 3 | `""` | Tiền tố package tuỳ chỉnh — chỉ dùng khi loại là `5` (`<tiền_tố>_<tên>` tại `platform/<nhóm>/<tên>`). Truyền `""` cho mọi loại khác |
| 4 | `1` | State management — `1` Provider, `2` BLoC, `3` không dùng |
| 5 | `1` | Kiểu route — `1` `IFeatureRouteModule`, `2` `INavDestinationModule`, `3` không sinh |

Chạy không kèm tham số trên terminal thì tool sẽ hỏi tương tác từng bước. Không có terminal thì thiếu một tham số là thoát với mã 64, chứ không đoán. `--help` in ra cách dùng. Loại 4 và 5 nhận thêm `--group <nhóm>` (mặc định `infra`) để chọn thư mục nhóm dưới `platform/`; feature thì không.

Tuỳ chọn `--apps <id,id>` đặt sau các tham số vị trí chỉ ghép module vào những app đó. Các id là `app.id` trong `apps/*/app_manifest.yaml`, ví dụ `--apps mobile`. Không có nó thì module vào mọi app. Một id lạ khiến tool thoát với mã 64 trước khi ghi bất cứ thứ gì.

> [!NOTE]
> Nếu đã có package tên `feature_profile`, tool **từ chối** và thoát với mã 64. Nó thoát với mã 1 nếu thư mục `modules/profile/feature` tồn tại mà không chứa package đó. Nó không bao giờ ghi đè hay xoá một package có sẵn: hãy tự xoá hoặc đổi tên trước.

### Chọn tham số 5 — nó quyết định hình dạng routing của bạn

| Chọn | Khi nào | Bạn nhận được |
| :-- | :-- | :-- |
| `1` `IFeatureRouteModule` | Một chồng màn hình push lên trên app (auth, onboarding, màn chi tiết) | Stub `*FeatureRouteModule` |
| `2` `INavDestinationModule` | Một **đích điều hướng chính** — bottom bar trên điện thoại, `NavigationRail` từ cửa sổ medium trở lên — cần back stack riêng bền vững | Stub `*NavDestination` |
| `3` không | Bạn sẽ tự nối routing sau, hoặc feature không có route | Không sinh stub |

> [!WARNING]
> Chỉ dùng `2` cho tab bottom-nav thật (RULE-24). Màn hình push (login, chi tiết) thuộc về `IFeatureRouteModule`. Đăng ký tab giả sẽ phá thứ tự index của dashboard — xem [`04_routing.md`](04_routing.md).

## 2. Kiểm tra những gì generator đã làm

**Tự động** (xem [`tools/module_generator/generate.dart`](../../../tools/module_generator/generate.dart)):

1. Tạo cây thư mục, `pubspec.yaml`, `lib/di/module.dart` (`@InjectableInit.microPackage()`), phần khung l10n (§6), page, controller và các template route.
2. Thêm module vào mục `modules:` của **mọi** `apps/<id>/app_manifest.yaml` — cả `admin` lẫn `mobile` — trừ khi `--apps` chỉ định một tập con.
3. Tự chạy `dart tools/composer/composer.dart sync`. Lệnh này sinh lại danh sách `workspace:` ở `pubspec.yaml` gốc và, với từng app, path dependency, `injection.dart` cùng vùng `report` của `README.md`.
   - Bạn không phải chạy tay gì cả — nhưng xem ghi chú bên dưới nếu module không thuộc về mọi app.
   - Nếu module đăng ký một contract mà shell có trong catalog (splash, tab, session, reporter), mỗi app ghép nó phải khai contract đó là `provided` trong `capabilities:`: generator in lời nhắc, và `composer verify` nêu tên key cùng dòng cần dán ([`13_app_composition.md`](13_app_composition.md) § 6). `remove_sample` tự lật các contract chỉ có một nơi cung cấp về `absent` giúp bạn.
4. Chạy `dependency_sync.dart`, `flutter pub get`, `flutter gen-l10n`, barrel generator, `build_runner build --workspace`, barrel generator lần nữa (nó export cả những gì codegen vừa ghi), rồi `dart fix --apply`.
5. Ghi sẵn các test pass ngay khi sinh ra: `test/profile_page_test.dart` và `test/profile_provider_test.dart` (`test/<name>_bloc_test.dart` với BLoC, không có test controller với SM `3`). Test page dựng page dưới `ResponsiveInit` và localization của nó, với controller được cung cấp đúng như route cung cấp, trên cửa sổ cỡ điện thoại và cỡ tablet. CI Gate 3 chạy các test này.

Nếu một bước thất bại, generator khôi phục mọi file dùng chung nó đã sửa, xoá package dựng dở và sinh lại các file sinh tự động không được git theo dõi, rồi thoát với mã 1.

> [!IMPORTANT]
> **Không có `--apps` thì mọi app đều ghép module mới — kể cả `apps/admin`.** `apps/admin` cố ý chỉ là một tập con (auth + settings). Với module chỉ dành cho `mobile`, hãy nói rõ ngay khi sinh:
>
> ```bash
> dart tools/module_generator/generate.dart 1 profile "" 1 1 --apps mobile
> ```
>
> Lỡ sinh vào mọi app rồi? Gỡ nó ra khỏi `admin` bằng tay:
>
> 1. Xoá dòng `- { id: <name>, layers: [...] }` của nó dưới `modules:` trong `apps/admin/app_manifest.yaml` (hoặc chỉ bỏ khỏi `layers:` những layer app đó không cần).
> 2. `dart tools/composer/composer.dart sync` — viết lại path dependency trong `apps/admin/pubspec.yaml` và `apps/admin/lib/di/injection.dart`; danh sách `workspace:` ở root vẫn giữ package chừng nào còn app khác ghép nó.
> 3. `flutter pub get && dart run build_runner build --workspace` — sinh lại `injection.config.dart` của admin.
>
> Commit manifest cùng với những gì `sync` sinh lại: CI Gate 0 (`composer verify`) fail khi chúng lệch nhau (RULE-16).

**Thủ công — tool in danh sách này ở cuối:**

1. Hoàn thiện `TypedGoRoute` / navigator trong `lib/src/routing/`.
2. Điền nội dung cho stub route module (`routes`, và với tab thì thêm `order`, `path`, `destination`).
3. Module khác tới module này qua một navigator trong package API của module. Nếu `profile_api` chưa tồn tại, `dart tools/module_generator/generate.dart 6 profile` tạo nó và cài đặt nó trong feature này; nếu đã có, generator đã ghi sẵn `lib/src/routing/profile_navigator_impl.dart` (bước 7).
4. Dịch `assets/language/vi.arb` — nó bắt đầu là bản sao của chữ tiếng Anh.
5. Chạy lại `build_runner`, rồi **khởi động lại hẳn** app — hot reload không nhận đăng ký DI mới.

> [!NOTE]
> FVM được tự phát hiện (`useFvm` trong `tools/shared/toolchain.dart`, RULE-73). Tool chỉ thêm tiền tố `fvm ` vào lệnh khi có đủ cả hai: một file cấu hình (`.fvmrc` hoặc `.fvm/fvm_config.json`) và `fvm --version` chạy được. Nếu không, nó gọi thẳng `dart` / `flutter` toàn cục. Xem [`../getting-started/03_daily_workflow.md`](../getting-started/03_daily_workflow.md).

## 3. Làm quen với package

Generator sinh ra cây thư mục dưới đây cho một feature Provider với route kiểu stack, cùng các file sinh tự động `module.module.dart`, `*.g.dart` và `gen/`. Generator không tạo thư mục `widgets/`: bước barrel xoá các thư mục rỗng, nên hãy tạo `lib/src/widgets/` cùng với widget con đầu tiên của bạn.

```
modules/profile/feature/
├── assets/language/              en.arb, vi.arb  — bản dịch riêng của feature
├── l10n.yaml                     cấu hình gen-l10n (tên class, thư mục output)
├── lib/
│   ├── di/module.dart            @InjectableInit.microPackage()
│   ├── feature_profile.dart      barrel của package (được sinh, export mọi file bên dưới)
│   └── src/
│       ├── extensions/           l10n_profile_extension.dart — context.l10nProfile
│       ├── gen/language/         output của gen-l10n (không sửa tay)
│       ├── localization/         profile_localization_impl.dart — IFeatureLocalization
│       ├── pages/                profile_page.dart — widget *Page / *Screen
│       ├── provider/             profile_provider.dart — là `bloc/` (bloc, event, state) nếu bạn chọn BLoC
│       ├── routing/              profile_route_module.dart (route có kiểu), rồi
│       │                         profile_feature_route_module.dart hoặc profile_nav_destination.dart
│       ├── utils/                profile_path.dart — hằng số thuộc sở hữu của package này
│       └── widgets/              widget con *Widget / *Card (tạo khi cần)
├── pubspec.yaml
└── test/                         profile_page_test.dart, profile_provider_test.dart
```

> [!NOTE]
> Thư mục controller là **số ít** — `src/provider/` (như `feature_auth`) hoặc `src/bloc/` (như `feature_home`). Đặt tên số nhiều `providers/` / `blocs/` là vi phạm quy ước; xem [`../reference/02_naming.md`](../reference/02_naming.md).

Hằng số path đã có sẵn: generator ghi chúng vào `lib/src/utils/<name>_path.dart`, và mọi thứ khác đều tham chiếu tới đó (RULE-09). **Hãy sửa file đã được sinh** để đổi hoặc thêm path; đừng tạo file thứ hai:

```dart
// modules/profile/feature/lib/src/utils/profile_path.dart — như generator sinh ra
class ProfilePath {
  ProfilePath._();

  static const String PROFILE = '/profile';
}
```

Cùng hình dạng với [`modules/home/feature/lib/src/utils/home_path.dart`](../../../modules/home/feature/lib/src/utils/home_path.dart).

## 4. Viết route module

### Phương án A — tab bottom-nav (`INavDestinationModule`)

Hai file. Trước hết là bản thân các route — code thật từ [`modules/home/feature/lib/src/routing/home_route_module.dart`](../../../modules/home/feature/lib/src/routing/home_route_module.dart):

```dart
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../bloc/home_profile_bloc.dart';
import '../pages/home_page.dart';
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

Rồi tới phần đóng góp qua DI — code thật từ [`home_nav_destination.dart`](../../../modules/home/feature/lib/src/routing/home_nav_destination.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/l10n_home_extension.dart';
import '../utils/home_path.dart';
import 'home_route_module.dart';

/// SAMPLE — a module contributing one primary navigation destination.
///
/// It describes the destination ([NavDestination]) rather than building a
/// widget, so the same module works in an app that renders a bottom bar, a
/// rail or a sidebar.
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

`order` quyết định vị trí tab và **bắt buộc phải duy nhất** giữa mọi tab đã đăng ký. `AppRouter` sắp xếp theo nó để dựng danh sách `StatefulShellBranch`. Stub được sinh chọn giá trị lớn hơn `order` cao nhất hiện có 10 đơn vị, nên các tab được sinh không bao giờ trùng nhau.

### Phương án B — chồng màn hình push (`IFeatureRouteModule`)

Nhỏ hơn nhiều. Code thật từ [`modules/auth/feature/lib/src/routing/auth_feature_route_module.dart`](../../../modules/auth/feature/lib/src/routing/auth_feature_route_module.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import 'auth_route_module.dart';

@LazySingleton(as: IFeatureRouteModule)
class AuthFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$loginRoute];
}
```

Không có `order`: nhóm route này khớp theo path chứ không theo chỉ số.

> [!CAUTION]
> Tuyệt đối không sửa `platform/shell/app_shell/lib/src/navigation/app_router.dart` để thêm route của bạn (RULE-20). Nó gom các đóng góp qua `getAllOrEmpty<IFeatureRouteModule>()` và `getAllOrEmpty<INavDestinationModule>()`. Hardcode ở đó là phá khả năng gỡ feature.

## 5. Tạo controller ở tầng route

Controller được tạo trong `build` của route, không bao giờ tạo bên trong page (RULE-21).

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

Controller gắn màn hình dùng `@injectable`: một factory, huỷ theo route. Chỉ controller toàn app — `AuthProvider`, `ThemeProvider`, `LanguageProvider`, `DeeplinkProvider` — mới dùng `@lazySingleton`. Đăng ký controller màn hình thành singleton sẽ làm nó rò rỉ suốt vòng đời process (RULE-10). Chi tiết ở [`05_di.md`](05_di.md).

## 6. Sửa bản dịch

Bản dịch của feature nằm trong chính feature. Không thêm gì vào app shell (RULE-34).

**Generator đã ghi sẵn cả bốn phần dưới đây**: `l10n.yaml`, hai file ARB, extension `context.l10n<Name>` và phần đăng ký `IFeatureLocalization`. Nó cũng chạy `gen-l10n` một lần. Việc của bạn là **sửa các file đã được sinh**, chủ yếu là file ARB; đừng tạo lại chúng. Chúng được trình bày ở đây để bạn biết mỗi file làm gì.

`modules/profile/feature/l10n.yaml` — như generator sinh ra, cùng hình dạng với [`modules/home/feature/l10n.yaml`](../../../modules/home/feature/l10n.yaml):

```yaml
arb-dir: assets/language
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: FeatureProfileLocalizations
preferred-supported-locales: [en, vi]
untranslated-messages-file: untranslated-messages.txt
output-dir: lib/src/gen/language
```

`assets/language/en.arb` (và `vi.arb` tương ứng) được sinh với một key duy nhất, `title`. Page được sinh — và, với một tab, nhãn destination được sinh — đọc nó qua `context.l10nProfile.title`. Thêm các key của bạn cạnh nó, theo kiểu `lowerCamelCase` (RULE-35). Nhớ dịch cả giá trị trong `vi.arb`: generator ghi từ tiếng Anh vào cả hai file.

```json
{
  "@@locale": "en",
  "title": "Profile"
}
```

Extension — bản được sinh theo đúng code thật này từ [`l10n_home_extension.dart`](../../../modules/home/feature/lib/src/extensions/l10n_home_extension.dart):

```dart
import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

Phần đăng ký delegate qua DI — được sinh thành `lib/src/localization/profile_localization_impl.dart`, giống code thật này từ [`modules/home/feature/lib/src/localization/home_localization_impl.dart`](../../../modules/home/feature/lib/src/localization/home_localization_impl.dart):

```dart
import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../extensions/l10n_home_extension.dart';

/// Hands this feature's translations to the app shell, which collects every
/// `IFeatureLocalization` into `MaterialApp.localizationsDelegates`.
@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
```

[`app_material_wrapper.dart`](../../../platform/shell/app_shell/lib/src/app_material_wrapper.dart) của app shell gom mọi `IFeatureLocalization` đã đăng ký bằng `getAllOrEmpty`. Vì vậy **không sửa `root_app.dart`** (hay wrapper đó). Với chữ của một thao tác thất bại, `AppFailure.message` là chẩn đoán tiếng Anh và không bao giờ được hiển thị (RULE-34): hãy bắt đầu từ `context.l10n.failureMessage(failure.code)`, thứ `core_base_ui` diễn đạt theo mã của failure, và chỉ thêm key ARB riêng khi màn hình nói được điều cụ thể hơn ([`03_state_management.md`](03_state_management.md) § 8).

Sinh lại sau mỗi lần đổi `.arb`:

```bash
cd modules/profile/feature && flutter gen-l10n
```

> [!WARNING]
> Mọi chữ hiển thị cho người dùng đều phải được dịch. Hardcode chuỗi trong UI là bị cấm — xem
> [`09_localization_theming.md`](09_localization_theming.md).

## 7. Phơi navigator cho feature khác

Feature khác không được import `feature_profile` (RULE-04). Hợp đồng nằm trong **package API** của module bạn, `modules/<name>/api` — ở đây là `profile_api`, chỉ được phụ thuộc foundation và Flutter (`arch_check` R3). Bên gọi phụ thuộc `profile_api`, không bao giờ phụ thuộc `feature_profile`; `core_di` không chứa navigator của module nào (RULE-22). Loại `6` của generator ghi nó ra:

```bash
dart tools/module_generator/generate.dart 6 profile                 # thêm --apps mobile cho khớp với feature
```

Nó tạo package `profile_api` — một `pubspec.yaml` mà Flutter là dependency duy nhất, `lib/src/navigators/profile_navigator.dart` và barrel `lib/profile_api.dart` — và ghi layer `api` vào các manifest. Khi `feature_profile` đã tồn tại cùng route được sinh của nó, cũng lần chạy đó thêm `profile_api` vào `dependencies:` của feature và ghi phần cài đặt, `lib/src/routing/profile_navigator_impl.dart`; sinh theo thứ tự ngược lại thì `generate.dart 1 profile` tự nối với `profile_api` có sẵn theo cách tương tự. Package API không có DI module và không cần mục `di_groups`. Cách bố trí một package API và những gì `arch_check` ép nó tuân theo: [`12_module_isolation.md` § 4](12_module_isolation.md#4-tạo-package-api-cho-module).

Hợp đồng được sinh, cùng hình dạng với [`home_navigator.dart`](../../../modules/home/api/lib/src/navigators/home_navigator.dart) trong `home_api`:

```dart
// modules/profile/api/lib/src/navigators/profile_navigator.dart
import 'package:flutter/widgets.dart';

abstract class ProfileNavigator {
  void toProfile(BuildContext context);
}
```

và phần cài đặt nằm ngay trong `routing/` của bạn:

```dart
// modules/profile/feature/lib/src/routing/profile_navigator_impl.dart
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:profile_api/profile_api.dart';

import 'profile_route_module.dart';

@LazySingleton(as: ProfileNavigator)
class ProfileNavigatorImpl implements ProfileNavigator {
  @override
  void toProfile(BuildContext context) => const ProfileRoute().go(context);
}
```

Thêm một method cho mỗi route module sở hữu, ở cả hai file, và giữ chúng khớp nhau. Bên gọi ở package khác khai `profile_api` trong `dependencies:` và dùng `getItOrNull<ProfileNavigator>()?.toProfile(context)` (RULE-12, `arch_check` R8). Không hardcode path, không `context.go('/profile')`. Luôn truyền `BuildContext` từ widget gọi, đừng lấy từ `NavigatorKeys` (RULE-23).

## 8. Sinh lại code và khởi động lại app

Generator đã chạy `build_runner` và barrel generator. Hãy chạy lại sau khi bạn thêm, đổi tên hoặc xoá một file, hay đổi một annotation:

```bash
# 1. Export lại các file bạn đã thêm — ở mọi package bạn đụng tới, kể cả package API
dart tools/barrel_generator/generate.dart modules/profile/api/lib
dart tools/barrel_generator/generate.dart modules/profile/feature/lib
# 2. Sinh lại DI / route — injectable phải thấy ProfileNavigator qua `package:profile_api/profile_api.dart`
dart run build_runner build --workspace
flutter analyze
```

> [!IMPORTANT]
> Thêm file của một method vào `modules/profile/api/lib/src/` mà bỏ bước 1 thì `flutter analyze` báo `Undefined name` ở mọi nơi tiêu thụ. Mỗi package có một barrel được sinh, và một file dưới `lib/src/` vô hình với package khác cho tới khi chạy barrel generator cho `lib/` của package đó. Điều này đúng với mọi package bạn thêm file vào (RULE-75).

Sau đó **khởi động lại hẳn** app (không phải hot reload) để đồ thị DI mới được dựng.

## 9. Gỡ một feature

App phải chạy được khi xoá bất kỳ feature nào (RULE-05). Gỡ theo đúng thứ tự:

1. Dòng của nó trong mục `modules:` ở mọi `apps/<id>/app_manifest.yaml` có ghép nó
2. `dart tools/composer/composer.dart sync` — sinh lại `injection.dart`, path dependency của app và danh sách `workspace:` ở root
3. Các thư mục package của module — `modules/<tên>/<layer>/` cho từng tầng nó có (`api`, `domain`, `data`, `feature`), rồi `modules/<tên>/`. `composer verify` báo lỗi với package còn trên đĩa mà không app nào ghép. Module chỉ là một feature thì chỉ có `modules/<tên>/feature/`
4. `flutter pub get && dart run build_runner build --workspace`

**Với module mẫu, hãy để tool làm.** `remove_sample.dart` thực hiện các bước trên. Quan trọng hơn, nó cho bạn biết điều mà danh sách thủ công ở trên không thể:

```bash
dart tools/sample_cleanup/remove_sample.dart --list   # cái nào sample, cái nào framework
dart tools/sample_cleanup/remove_sample.dart auth     # dry-run, không ghi gì
dart tools/sample_cleanup/remove_sample.dart auth --apply
```

Phần *Dọn dẹp* của tutorial đi con đường thủ công một lần, cho một module không phải mẫu ([`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md#dọn-dẹp-gỡ-module)).

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
> | `feature_home` (`HomeRoute.build`) | `getItOrNull<ISessionStatusStream>()` truyền vào dưới dạng **factory param** | Home hiển thị trạng thái chưa đăng nhập |
> | `feature_settings` (`SettingsPage`) | `getItOrNull<IAuthActionHandler>()` (từ `auth_api`, được `remove_sample` giữ lại khi còn bị import) | Dòng logout đơn giản bị ẩn đi |
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
> nơi, và điều đó hoàn toàn ổn — đó là package platform, không phải feature có thể gỡ.

---

## Kiểm tra

```bash
flutter analyze                                           # No issues found!
dart tools/arch_check/check.dart                          # ✅ All architecture rules hold across N packages.
dart tools/composer/composer.dart verify                  # ✅ Generated artifacts are up to date.
cd modules/profile/feature && flutter test && cd -        # All tests passed!
cd apps/mobile && flutter test test/di_smoke_test.dart    # All tests passed! — mọi lazy singleton và factory đều build được
dart tools/unused_checker/check_unused_packages.dart      # ✅ Success! No unused packages found …
```

Kết thúc bằng một lần build APK debug sau mọi thay đổi DI hay dependency (RULE-77): `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev`.

Checklist review:

- [ ] `pubspec.yaml` của package có `resolution: workspace`
- [ ] Mọi dependency thực dùng đều được khai — kiểm bằng `dart tools/unused_checker/check_unused_packages.dart`
- [ ] Hằng số nằm trong `src/utils/`, không rải rác
- [ ] Route đăng ký qua `IFeatureRouteModule` / `INavDestinationModule` — `app_router.dart` không bị đụng
- [ ] Controller tạo ở tầng route, page **không** bọc lại
- [ ] Controller màn hình là `@injectable`, không phải singleton
- [ ] Đã đăng ký `IFeatureLocalization` — `root_app.dart` không bị đụng
- [ ] Không hardcode chuỗi hiển thị
- [ ] Mọi kích thước đi qua context — `context.w()` / `context.h()` / `context.sp()` / `context.r()`
- [ ] Navigator interface nằm trong `<id>_api` của module, implementation nằm trong `routing/` của feature
- [ ] Không import feature khác (không ngoại lệ — widget dùng chung lấy từ `core_ui_kit`)

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| Generator thoát với mã 64 | Thiếu tham số khi không có terminal, tên không hợp lệ, id lạ trong `--apps`, hoặc `feature_<name>` đã tồn tại | Truyền đủ năm tham số; chọn tên khác hoặc gỡ package cũ (bước 1) |
| Module mới xuất hiện trong `apps/admin` | Sinh mà không có `--apps` | Gỡ nó khỏi `apps/admin/app_manifest.yaml`, rồi `composer sync` (bước 2) |
| `composer verify` fail trên CI | Manifest đổi mà chưa chạy `composer sync`, hoặc vùng managed bị sửa tay | Chạy `dart tools/composer/composer.dart sync` và commit những gì nó ghi |
| `Undefined name 'ProfileNavigator'` | Barrel của package API chưa export file mới | Chạy barrel generator cho `modules/profile/api/lib` (bước 8) |
| State màn hình không bao giờ cập nhật | Page tự bọc thêm một provider thứ hai | Bỏ lớp bọc khỏi page (bước 5) |
| Route hay đăng ký mới không có hiệu lực | Hot reload không dựng lại đồ thị DI | Chạy `build_runner`, rồi khởi động lại hẳn (bước 8) |
| `context.l10nProfile.<key>` không tồn tại | Chưa chạy `gen-l10n` sau khi sửa ARB | `cd modules/profile/feature && flutter gen-l10n` (bước 6) |

## Liên quan

- Luật: RULE-04, RULE-05, RULE-09, RULE-10, RULE-16, RULE-20, RULE-21, RULE-22, RULE-23, RULE-24, RULE-34, RULE-35 — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../getting-started/04_first_feature_tutorial.md`](../getting-started/04_first_feature_tutorial.md) — đi hết con đường này một lần, đã kiểm chứng
- [`04_routing.md`](04_routing.md) — hợp đồng routing chi tiết
- [`03_state_management.md`](03_state_management.md) — Provider và BLoC
- [`05_di.md`](05_di.md) — phạm vi đăng ký và thứ tự nạp module
- [`10_cross_feature.md`](10_cross_feature.md) — giao tiếp với feature khác
- [`../architecture/05_features.md`](../architecture/05_features.md) — luật của tầng feature
