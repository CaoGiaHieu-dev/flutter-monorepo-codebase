# Tầng Core

Tài liệu này trả lời câu hỏi **"trong `platform/*` có gì, và khi nào thì dùng package nào?"**. Đọc xong bạn sẽ chọn đúng core package cho từng việc — và nhận ra khi nào thứ bạn định thêm vào thực ra *không* thuộc về core.

Core là **hạ tầng**. Nó cung cấp cơ chế; nó không mã hoá nghiệp vụ, và không biết feature nào tồn tại.

---

## 0. Ba luật chi phối mọi package core

**Core không được phụ thuộc feature hay data.** Có ba ngoại lệ đã duyệt, liệt kê ở [phần tổng quan](01_overview.md#các-ngoại-lệ-đã-được-duyệt). `tools/arch_check/check.dart` cưỡng chế danh sách này ở mọi PR.

**Core cấp cơ chế, không cấp chính sách.** `core_storage` cho bạn `StorageValue<T>`; nó không quyết định rằng tồn tại một key tên `token`. `core_database` cho bạn kết nối và hợp đồng migration; nó không biết ý nghĩa nghiệp vụ của bảng. Hễ một package core bắt đầu gọi tên một khái niệm domain cụ thể, cái tên đó thuộc về chỗ khác.

**Mọi package giữ constants trong thư mục `utils/` của chính nó.** Một ngoại lệ đã duyệt: design token trong `core_base_ui/src/styles/` giữ nguyên vị trí — xem [`core_base_ui`](#3-core_base_ui--design-system) bên dưới.

---

## 1. `platform_kernel` và `core_common` — nguyên thuỷ dùng chung

Đáy của ngăn xếp hạ tầng là hai package, tách theo đúng một câu hỏi: *có cần Flutter không?*

**`platform_kernel`** là Dart thuần — không có `flutter` trong dependency, `arch_check` R9 cưỡng chế điều đó. Phụ thuộc workspace duy nhất của nó là `domain_core`, để lấy `AppFailure` mà `ErrorHandler` sinh ra. Hãy phụ thuộc thẳng vào nó, trừ khi bạn cần thứ gì gắn với Flutter.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Service locator | `src/di/` | `getIt`, `getItOrNull`, `getAll`, `getAllOrEmpty` |
| Config | `src/config/` | `SslPinningConfig` |
| Enum | `src/enums/` | enum dùng toàn app (`Flavor`, …) |
| Lỗi | `src/error/` | `ErrorHandler.handleError()`, các kiểu exception, và một bản re-export của `AppFailure` (khai trong `domain_core`, nằm cạnh `Result<T>`) |
| Extension | `src/extensions/` | `bool`, `DateTime`, `Enum`, `List`, `num`, `String` |
| Utils **và constants** | `src/utils/` | `EnvConstants`, `MessageQueue`, `helpers/` (`TypeHelper`, `ValidationHelper`, `JsonConverters`) |

**`core_common`** là nửa gắn với Flutter. Nó khai hai phụ thuộc workspace — `platform_kernel`, được nó re-export toàn bộ nên một import `package:core_common/core_common.dart` vẫn resolve được mọi thứ ở trên, và `core_responsive`, dùng bởi các widget chuyển trang trong `src/routing/page_transitions/`.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Config | `src/config/` | `AppConfig` (flavor, design size, base URL, locale mặc định), `AppInitializer` (HttpOverrides, log, hướng màn hình — chỉ khoá dọc trên màn hình cỡ điện thoại, system UI) |
| Mixin | `src/mixins/` | `LifecycleMixin`, `NetworkMixin`, `LoadMoreControllerBinding` |
| Trợ giúp routing | `src/routing/` | `GoRouteDataCustom`, `RouteAwareWidget`, page transition |
| Utils | `src/utils/` | `AppUtils`, `Debounce`, `formatters/`, `helpers/` (`AppInfoHelper`), `dialog/` |

### Những gì *không* thuộc về đây, và vì sao

`core_common` không có thư mục `constants/`. Một thư mục constants dùng chung đặt ở package đáy sẽ thành **god object** — một chỗ duy nhất, mọi package import được, liệt kê những giá trị vốn thuộc về từng domain riêng lẻ:

| Loại hằng số | Nơi nó thuộc về | Vì sao không phải ở đây |
|:--|:--|:--|
| Key storage (`TOKEN`, `AUTH_USER`, `LOCALE`, `THEME_MODE`, `VIEWED_ONBOARD`) | cùng chỗ với class sở hữu giá trị đó — xem [hướng dẫn storage](../guides/06_storage.md) | Liệt kê chung một chỗ thì mọi package đọc và ghi đè được key storage của mọi feature khác. |
| Endpoint REST (`/user/login`, `/user/refresh-token`) | package data sở hữu chúng — [`modules/auth/data/lib/src/utils/auth_api_constants.dart`](../../../modules/auth/data/lib/src/utils/auth_api_constants.dart) | Chúng chỉ thuộc về auth. Không thứ gì khác có lý do gọi tên chúng. |
| Hằng số của một hệ thống con (tên event analytics, event socket như `TYPING` / `USER_JOINED`, key remote-config) | package hiện thực hệ thống con đó, nếu có | Event dành riêng cho chat mà nằm trong một package core là rò rỉ ranh giới, còn hằng số cho một hệ thống repo không hề có thì chỉ là gánh nặng chết. |

Đúng một file constants nằm ở đáy ngăn xếp, vì nó thật sự toàn cục: `EnvConstants` (giá trị `String.fromEnvironment`), trong `src/utils/` của `platform_kernel`.

> [!CAUTION]
> Trước khi thêm một hằng số vào `core_common`, hãy tự hỏi: *có nhiều hơn một domain không liên quan cùng đọc nó không?* Nếu không, nó thuộc về `utils/` của package sở hữu.

**Firebase options cũng không nằm ở đây.** Chúng gắn với một bundle ID, nên thuộc về một app: mỗi app dùng Firebase sở hữu `lib/firebase/firebase_module.dart` đăng ký `FirebaseOptions` theo từng flavor (của app mẫu là [`apps/mobile/lib/firebase/firebase_module.dart`](../../../apps/mobile/lib/firebase/firebase_module.dart)). Khi module đó còn nằm trong `core_common`, một app thứ hai sẽ thừa hưởng luôn định danh Firebase của app mobile.

---

## 2. `core_di` — DI Hub

Chỉ chứa hợp đồng. Không hiện thực, không nghiệp vụ. Đây là vùng trung lập để hai package không được import nhau vẫn gặp được nhau.

| Nhóm hợp đồng | Đường dẫn | Mục đích |
|:--|:--|:--|
| Navigator | `src/navigators/` | `AuthNavigator`, `HomeNavigator` — khai ở đây, hiện thực trong feature sở hữu |
| Routing | `src/routing/` | `IFeatureRouteModule`, `INavDestinationModule`, `IAppEntryLocation`, `DashboardRouteModule`, `NavigatorKeys` |
| Action handler | `src/actions/` | `IAuthActionHandler` — hành động UI xuyên feature (vd đăng xuất) |
| Agnostic stream | `src/agnostic_streams/` | `IAuthStatusStream` — chia sẻ state giữa feature Provider và feature BLoC |
| Hợp đồng storage | `src/theme/`, `src/language/` | `IThemeStorage`, `ILanguageStorage` — hiện thực trong app shell |
| Localization | `src/feature_localization.dart` | `IFeatureLocalization` — mỗi feature tự đóng góp delegate |

**`NavigatorKeys`** có file riêng, [`src/routing/navigator_keys.dart`](../../../platform/di/lib/src/routing/navigator_keys.dart), tách khỏi các interface routing nằm trong `routing_interfaces.dart`. Nó phơi ra `rootKey`, `appKey`, và `nested(id)` cho module cần back stack riêng.

Một `ShellRoute` và các route con phải dùng **cùng một** instance `GlobalKey`, nhưng shell do app shell dựng còn route con khai bên trong feature. Đặt key ở bên nào cũng tạo chu trình, nên Hub — nơi cả hai đều đã phụ thuộc — giữ nó.

Key được *yêu cầu theo id* chứ không khai sẵn: `NavigatorKeys.nested('auth')` luôn trả về cùng một instance. Nhờ vậy DI Hub không gọi tên feature nào, và module cần back stack riêng không phải thêm gì vào đây.

> [!NOTE]
> `core_di` phụ thuộc `go_router`. Đây không phải rò rỉ: `IFeatureRouteModule` trả về `List<RouteBase>`, `INavDestinationModule` cũng trả về `List<RouteBase>`. Đây *chính là* hợp đồng routing nên buộc phải nói ngôn ngữ của GoRouter — nhưng `INavDestinationModule` mô tả điểm đến bằng `NavDestination` của chính Hub, không phải `BottomNavigationBarItem`, nên hợp đồng không cam kết vào thanh bottom bar. Trừu tượng thêm một lớp nữa chỉ tạo adapter vô ích.

**Không thuộc về đây:** bất cứ thứ gì có phần hiện thực. Nếu bạn viết `class …Impl` trong `core_di`, nó đang nằm sai package.

---

## 3. `core_base_ui` — design system

Design token, theme, typography, asset toàn cục và bộ localization nền.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Design token | `src/styles/` | `AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows` |
| Theme | `src/theme/` | `ThemeProvider`, `ThemeSystemExtension`, `ThemeSystemInterface` |
| Ngôn ngữ | `src/language/` | `LanguageProvider` |
| Extension | `src/extensions/` | `context.colors`, extension cho key/locale |
| Sinh tự động | `src/gen/` | `Assets`, `AppLocalizations` (chuỗi toàn cục) |
| Constants | `src/utils/base_ui_constants.dart` | Giá trị không phải token: thời lượng snackbar, kích thước dropdown, cỡ chữ app bar |

### Zero Flutter widget — đã kiểm chứng

Package này **không** chứa `StatelessWidget`, `StatefulWidget`, `State<…>` hay `InheritedWidget` nào. Điều này được kiểm tra, không phải mặc định tin. Widget dùng lại thuộc về [`core_ui_kit`](#4-core_ui_kit--widget-dùng-lại); `core_base_ui` chỉ cấp giá trị cho những widget đó tiêu thụ.

### Vì sao design token ở lại `styles/` thay vì `utils/`

Đây là ngoại lệ đã duyệt của luật "constants nằm trong `utils/`":

- Chúng là **API công khai**, được nhiều feature package import trực tiếp.
- `styles/` mang ý nghĩa rõ ràng — "đây là design system". `utils/` đọc lên là "linh tinh", đúng tín hiệu sai cho những token mà cả app phải tuân theo.

Các magic value *không phải* token thì nằm ở `src/utils/base_ui_constants.dart`. Ranh giới phân biệt: nếu một designer nhìn vào mà nhận ra, đó là token và ở lại `styles/`.

### `ThemeProvider` phản ứng khi OS đổi theme

`ThemeProvider` là `@lazySingleton` có mixin `WidgetsBindingObserver`. Ở chế độ `ThemeMode.system`, độ sáng của OS có thể đổi khi app đang chạy, nên nó override `didChangePlatformBrightness()` và rebuild — nhưng chỉ khi chế độ thực sự *là* `system`, để lựa chọn light/dark cứng không gây rebuild thừa.

`WidgetsBindingObserver` được chọn thay vì gán `platformDispatcher.onPlatformBrightnessChanged`: trường đó là một **slot đơn**, ai gán sau sẽ âm thầm thắng. Với một singleton toàn cục phải cạnh tranh cùng framework và plugin, đó là rủi ro thật.

Observer được gỡ trong `dispose()`, và hàm này gắn `@disposeMethod` để GetIt gọi khi reset container — thiếu nó thì mỗi lần `resetDependencies()` trong test sẽ để lại một observer cũ còn đăng ký.

---

## 4. `core_ui_kit` — widget dùng lại

Thư viện widget dùng chung mà mọi feature đều có thể dùng. Nó là **core, không phải feature**: nằm tại `platform/ui_kit` để `modules/*/feature/` chỉ còn chứa các mảng sản phẩm thực sự gỡ được.

Cấu trúc phẳng (không có `src/`): `buttons/`, `inputs/`, `dialogs/`, `feedback/`, `layout/`, `media/`, `navigation/`, `utils/`.

Nó phụ thuộc `core_common`, `core_base_ui`, `core_responsive` và `provider_state_management` — không bao giờ phụ thuộc một feature hay `data_*`.

> [!NOTE]
> Phụ thuộc chạy **một chiều**: `core_ui_kit -> provider_state_management`. Cạnh ngược lại sẽ khép một chu trình ngay bên trong vòng core, nên `provider_state_management` tự mang `DefaultLoadingWidget` / `DefaultEmptyWidget` của riêng nó thay vì mượn widget có thương hiệu từ đây.

### Quy tắc UI-agnostic

Widget dùng lại dùng tham số **đúng như nhận được** và không được tự scale chúng qua `core_responsive`. Scale là việc của bên gọi, nên khi giá trị đến nơi thì nó đã ở đơn vị pixel thiết bị — để ý `context.w(120)` ở phía gọi bên dưới. Widget vẫn scale hằng số **của chính nó**, nếu không thì nó chẳng responsive gì cả:

```dart
// bên gọi scale
CustomButton(width: context.w(120), height: context.h(44))

// widget tự scale tham số của mình -- sai
double _width(BuildContext context) => context.w(width);
```

Scale bên trong nghĩa là bên gọi nào đã scale sẽ bị scale hai lần, còn bên gọi muốn một giá trị pixel nguyên bản thì không cách nào lấy được.

> [!WARNING]
> **Luật này cấm điều gì.** Một `AppBar` trong `core_ui_kit` mang theo:
>
> ```dart
> @override
> double? get leadingWidth => context.w(64);
> ```
>
> Hai lỗi cùng lúc: nó tự scale bên trong, và — vì là getter override — nó **âm thầm vứt bỏ giá trị `leadingWidth` mà bên gọi truyền vào constructor**. Tham số trông như được hỗ trợ nhưng không làm gì cả.

### Hằng số

Giá trị mặc định của các widget này nằm ở `platform/ui_kit/lib/utils/shared_ui_constants.dart`:

```dart
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(milliseconds: 200);
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
```

Đây là giá trị mặc định, không phải chính sách — bên gọi cần giá trị khác thì truyền qua constructor.

---

## 5. `core_responsive` — scale theo khung thiết kế và layout thích ứng, gắn với `BuildContext`

Cơ chế scale mà mọi widget trong app đều đi qua, cùng các lớp kích thước cửa sổ và widget thích ứng dùng để chọn layout. Nó nằm tại `platform/responsive` và **không phụ thuộc gì ngoài `flutter`** — không package nào trong workspace, không package bên thứ ba nào, và cũng không import `material`.

| Thành phần export | Đường dẫn | Mục đích |
|:--|:--|:--|
| `ResponsiveInit` | `src/responsive_init.dart` | `StatelessWidget`, gắn **một lần** phía trên `MaterialApp`. Tham số: `child` (bắt buộc), `designSize` (mặc định 360×690), `scaleBounds` và `textScaleBounds` (cùng mặc định `ScaleBounds.downOnly()`), `profiles`, `breakpoints` (mặc định `ResponsiveBreakpoints.material3()`), `splitScreenMode`, `minTextAdapt`, `fontSizeResolver`. Assert rằng `designSize` và `designSize` của mọi profile đều dương và hữu hạn |
| `ResponsiveScope` | `src/responsive_scope.dart` | `InheritedWidget` mang `ResponsiveMetrics`; `maybeOf(context)` trả nullable, `of(context)` assert khi thiếu |
| `ResponsiveMetrics` | `src/responsive_metrics.dart` | Value object bất biến với các phép `width`, `height`, `radius`, `diagonal`, `diameter`, `sp`, `spMin`; cho thấy giá trị đã resolve `activeProfile` / `effectiveDesignSize` / `effectiveScaleBounds` / `effectiveTextScaleBounds` / `effectiveMinTextAdapt`, cùng `windowSizeClass`, `windowHeightClass`, `orientation`, và hàm static `isValidDesignSize(size)` |
| `FontSizeResolver` | `src/responsive_metrics.dart` | `typedef double Function(num fontSize, ResponsiveMetrics metrics)` — kết quả không bị bound nào kẹp |
| `ScaleBounds` | `src/scaling/scale_bounds.dart` | Khoảng mà một hệ số scale được phép nhận: `downOnly()` (mặc định — thu nhỏ, không bao giờ phóng to), `fixed()`, `unbounded()`, hoặc `ScaleBounds(min:, max:)`; `clamp` coi hệ số NaN là 1 |
| `ResponsiveProfile` | `src/scaling/responsive_profile.dart` | Ghi đè `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` cho một `WindowSizeClass` (`null` là kế thừa); `resolve` chọn đúng lớp, không có thì lớp nhỏ hơn gần nhất |
| `WindowSizeClass` / `WindowHeightClass` / `ResponsiveBreakpoints` | `src/adaptive/window_size_class.dart` | Lớp chiều rộng của cửa sổ (`compact` < 600 ≤ `medium` < 840 ≤ `expanded` < 1200 ≤ `large` < 1600 ≤ `extraLarge`), lớp chiều cao, và nơi chúng bắt đầu |
| `ResponsiveContext` | `src/context_extension.dart` | Extension trên `BuildContext` — **lối duy nhất** để scale ([bảng bên dưới](#extension-trên-buildcontext)); cộng `responsive`, `windowSizeClass`, `windowHeightClass` |
| `AdaptiveContext` | `src/adaptive/adaptive_context_extension.dart` | Extension trên `BuildContext` — `adaptive(compact:, medium:, …)`, `isCompactWindow`, `isExpandedOrWider`, `separatingDisplayFeature`, `foldPosture` |
| `AdaptiveBuilder` / `AdaptiveLayout` | `src/adaptive/adaptive_builder.dart` | Một builder, hoặc mỗi lớp cửa sổ một builder |
| `AdaptiveSplitView` | `src/adaptive/adaptive_split_view.dart` | Master–detail: hai ô tại nếp gập, bản lề hoặc từ `splitAt`, một ô trong các trường hợp còn lại; `divider` tuỳ chọn được layout rộng đúng `dividerExtent` (mặc định 1). `primary` bị giới hạn để divider và `secondary` luôn vừa, và một `primaryWidth` không chừa gì cho `secondary` sẽ lùi về một ô. `AdaptiveSplitView.isSplit(context)` cho danh sách biết đang ở trường hợp nào |
| `AdaptiveContent` | `src/adaptive/adaptive_content.dart` | Chặn nội dung ở chiều rộng dễ đọc (640, không scale) |
| `FoldPosture` | `src/adaptive/fold_posture.dart` | `flat` / `book` / `tabletop` |
| Constants | `src/utils/` | `ResponsiveConstants`: `SPLIT_SCREEN_MIN_HEIGHT` (700), `DEFAULT_DESIGN_WIDTH` (360), `DEFAULT_DESIGN_HEIGHT` (690), `DESIGN_SCALE_FACTOR` (1), các giá trị `BREAKPOINT_*`; `AdaptiveConstants`: `SPLIT_PRIMARY_FRACTION` (0.4), `SPLIT_DIVIDER_EXTENT` (1), `CONTENT_MAX_WIDTH` (640) — nằm trong `src/utils/`, như hằng số của mọi package khác |

Mọi hệ số đều bị kẹp, và mặc định chỉ theo chiều xuống: cửa sổ nhỏ hơn khung thì thiết kế thu nhỏ, cửa sổ lớn hơn thì vẽ 1:1 và để chỗ dư cho layout. Phóng to là opt-in, có chặn, theo từng lớp cửa sổ.

Đầu vào suy biến không bao giờ làm layout sụp. Cửa sổ rỗng — Android báo 0×0 ở frame đầu tiên — scale theo 1 chứ không phải 0; hệ số NaN được kẹp thành 1; một khung thiết kế không dùng được (một cạnh bằng 0 hoặc vô hạn) assert ở debug và scale theo 1 ở release.

### Vì sao metrics đi qua `InheritedWidget`

`core_responsive` phát metrics qua `InheritedWidget`, nên mỗi lần đọc đều **đăng ký dependency** và việc rebuild đúng widget do chính Flutter lo. Cách làm thay thế — treo giá trị scale trên một singleton toàn cục — vẫn cho ra đúng con số nhưng không đăng ký gì cả, nên widget đọc nó không bao giờ biết metrics đã đổi (xoay máy, chia đôi màn hình, resize).

`ResponsiveInit` là `StatelessWidget` có chủ đích: nó đọc `MediaQuery.sizeOf(context)` — một dependency **chỉ theo size** — nên rebuild khi resize và bỏ qua thay đổi brightness / textScale / padding. Không cần `WidgetsBindingObserver`, không `setState`.

`ResponsiveScope.of(context)` **assert** với thông điệp *"No ResponsiveInit found above this context."* thay vì lùi về giá trị không scale. Fail to tiếng là cố ý: một fallback im lặng "không scale" sẽ đẩy layout sai ra mọi thiết bị. Các thành viên về layout — `context.windowSizeClass` và mọi thứ adaptive — là ngoại lệ: chọn layout là câu hỏi về cửa sổ, nên thiếu `ResponsiveInit` chúng phân lớp cửa sổ theo mặc định Material 3.

### Extension trên `BuildContext`

| Lời gọi | Trục |
|:--|:--|
| `context.responsive` | trả về `ResponsiveMetrics` |
| `context.w(n)` | chiều rộng — cũng dùng cho thứ phải giữ vuông |
| `context.h(n)` | chiều cao |
| `context.r(n)` | trục nhỏ hơn — bo góc, viền, nét |
| `context.sp(n)` | cỡ chữ (hoặc `fontSizeResolver`, khi có) |
| `context.spMin(n)` | `sp` chặn trên bằng giá trị thiết kế — chữ co được, không phình ra; bằng `sp` dưới bound mặc định |
| `context.dg(n)` | cả hai trục |
| `context.dm(n)` | trục lớn hơn |
| `context.edgeInsets({all, horizontal, vertical, left, top, right, bottom})` | `horizontal` theo `w`, `vertical` theo `h`, `all` theo `w` |
| `context.borderRadius({all, topLeft, topRight, bottomLeft, bottomRight})` | `r` |
| `context.verticalSpace(n)` / `context.horizontalSpace(n)` | một `SizedBox`, theo `h` / `w` |
| `context.windowSizeClass` / `context.windowHeightClass` | lớp cửa sổ — dùng được cả khi không có `ResponsiveInit` |

> [!CAUTION]
> **Cố ý không có extension trên `num`.** `16.w` **không biên dịch được**. Một con số không mang theo context, nên extension kiểu đó chỉ có thể đọc một singleton toàn cục — và widget đọc biến toàn cục thì không bao giờ biết metrics đã đổi. Bắt buộc phải có `BuildContext` chính là cách biến "làm đúng" thành lựa chọn duy nhất viết được. Package không có instance toàn cục, không có hàm `init()` mệnh lệnh, không có trợ giúp `setWidth()` và không có cờ điều khiển rebuild — một khi metrics đã nằm trong `InheritedWidget` thì nhắm đúng widget để rebuild là việc của Flutter.

Luật **R7** của `dart tools/arch_check/check.dart` chặn dạng bare — mẫu `[\d)]\.(spMin|sp|dg|dm|w|h|r)\b(?!\s*\()` — trong mọi file có import `core_responsive`, và là Gate 1 của `pr_quality_check.yml`.

> [!NOTE]
> Test widget nào có scale **phải** bọc widget cần test trong `ResponsiveInit`, nếu không `ResponsiveScope.of` sẽ assert. Test của bản thân package nằm tại `platform/responsive/test/`.

Phần lắp ráp ở gốc cây (`_ResponsiveWrapper` trong `platform/app_shell/lib/main_scope.dart`) mô tả tại [app shell](06_app_shell.md#_responsivewrapper); cách chọn trục, đổi khung thiết kế, chính sách scale và các widget thích ứng nằm ở [`../guides/11_design_system.md`](../guides/11_design_system.md) (§4–§7).

---

## 6. `core_network` — HTTP client

Dựng trên Dio, cấu hình qua hợp đồng `NetworkConfig` nên package không đụng trực tiếp tới storage hay UI.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Client | `src/api_client.dart` | `ApiClient.createClient()` — factory Dio, lắp chuỗi interceptor |
| Hợp đồng | `src/network_config.dart` | `NetworkConfig` — `getToken`, `getLocale`, `onRetryCallback`, `onRefreshToken`, `onRefreshFailed`, `sslPinningHashes` |
| Interceptor | `src/interceptors/` | `AuthInterceptor`, `RefreshTokenInterceptor`, `RetryInterceptor`, `LoggingInterceptor` |
| Handler | `src/handlers/` | `RefreshTokenHandler`, `RetryHandler` |
| Constants | `src/utils/network_constants.dart` | Timeout, tên header, tiền tố `Bearer`, extra key, log tag |

`NetworkConfig` được hiện thực **ở app shell**, không phải ở đây — đó chính là điều giữ cho `core_network` không dính bất kỳ phụ thuộc storage nào. Hai callback refresh mặc định `null`, nên client không có endpoint refresh sẽ đơn giản trả `401` nguyên vẹn cho nơi gọi.

> [!CAUTION]
> **SSL pinning chỉ tốt bằng danh sách hash của nó.** `sslPinningHashes` hiện trả `const []`, tức pinning đang tắt. `AppInitializer` ghi log mức `ERROR` mỗi khi danh sách rỗng hoặc config chưa đăng ký trên bất kỳ bản build nào không bỏ qua kiểm tra certificate — tức mọi bản trừ bản debug đã khai báo tường minh `--flavor dev`, kể cả bản thiếu hoặc sai flavor (được coi như `prod` về TLS), nên lỗ hổng này hiện rõ chứ không im lặng — nhưng nó vẫn là lỗ hổng cho tới khi bạn điền hash vào. Xem [hướng dẫn networking](../guides/08_networking.md).

Chi tiết đầy đủ về chuỗi interceptor, các lớp chống đệ quy khi refresh token và việc che header nằm ở [`../guides/08_networking.md`](../guides/08_networking.md).

---

## 7. `core_storage` — lưu trữ key–value có mã hoá

Chỉ cấp **cơ chế**. Không định nghĩa key, không định nghĩa preset nào.

| Thành phần export | Mục đích |
|:--|:--|
| `StorageInterface` | Hợp đồng cho backend |
| `StorageManager` | `@singleton`; phân giải backend theo `StorageType`, khởi tạo backend secure trước rồi tới các backend khác qua `@PostConstruct(preResolve: true)` — secure đi trước vì lần mở đầu tiên nó xoá sạch namespace keystore, nơi cũng chứa master key của backend pref |
| `StorageValue<T>` | Bọc phản ứng quanh một key — `ChangeNotifier` + `Stream` broadcast, cache trong RAM, tự ghi xuống đĩa khi set |
| `StorageType` | `pref` (SharedPreferences) · `secure` (có phần cứng hỗ trợ) |
| `ObfuscatedString` / `ObfuscatedBytes` | Che dữ liệu trong RAM |
| `PrefStorageImpl` / `SecureStorageImpl` | Nội bộ, phân giải qua `@Named('Pref')` / `@Named('Secure')` |

### Che RAM là bảo vệ thật, không phải nhãn dán

Ngoài mã hoá dữ liệu lúc nghỉ (AES-256-CBC với IV ngẫu nhiên mỗi lần ghi), `StorageValue` còn giữ giá trị **trong bộ nhớ** ở dạng XOR mask ngẫu nhiên, chỉ lộ ra đúng khoảnh khắc cần đọc. Master key cũng được xử lý y hệt. Điều này nâng rào chắn trước tấn công đọc memory dump — một lớp mà phần lớn template bỏ qua hoàn toàn.

`SecureStorageImpl` không bao giờ xoá sạch kho khi gặp lỗi platform: việc đọc master key thất bại (Keychain bị khoá trước lần mở khoá đầu tiên, KeyStore đang bận) được thử lại rồi ném lại lỗi mà không xoá gì; chỉ master key có nhưng không dùng được mới bị thay, và chỉ giá trị không giải mã được mới bị xoá. `PrefStorageImpl` áp cùng quy tắc cho master key của riêng nó: chỉ lùi về key trong SharedPreferences khi key đó mở được các preference đã lưu hoặc chưa có preference nào để mất, còn không thì ném lại lỗi và giữ nguyên mọi preference. Xem [hướng dẫn storage](../guides/06_storage.md).

### Quyền sở hữu

Mỗi package tiêu thụ tự khai `StorageValue` của mình qua `StorageManager` được inject, key đặt trong `utils/` của package đó. Các chủ sở hữu hiện tại:

| Chủ sở hữu | Package | Key | Backend |
|:--|:--|:--|:--|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | secure |
| `ThemeStorageImpl` | `platform_app_shell` | `themeMode` | pref |
| `LanguageStorageImpl` | `platform_app_shell` | `locale` | pref |
| `AppBootStorage` | `platform_app_shell` | `viewed_onboard` | pref |

Xem [`../guides/06_storage.md`](../guides/06_storage.md) để có các bước cụ thể.

---

## 8. `core_database` — lưu trữ quan hệ (Drift + SQLite)

Chạy trên isolate nền qua `NativeDatabase.createInBackground`. **Không phụ thuộc package nào khác** trong workspace.

Package này **chỉ cấp cơ chế**: nó không sở hữu database, bảng hay DAO nào, và DI module của nó không đăng ký gì cả. Package nào cần lưu dữ liệu quan hệ thì tự khai **database của chính mình** ngay cạnh bảng, DAO và data source của nó, rồi mở database đó bằng các mảnh ghép dưới đây. `CacheDatabase` của module mẫu `cache` (`modules/cache/data/lib/src/database/`) là bản đấu nối tham chiếu.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Mở database | `src/opening/` | `DriftDatabaseOpener` — mở bất kỳ `GeneratedDatabase` nào trên isolate nền, kiểm tra tính toàn vẹn, cách ly file hỏng |
| Kết nối | `src/connection/` | `DatabaseConnectionFactory` — phân giải file, executor nền |
| **Truy cập** | `src/access/` | `IDatabaseHandle`, `DatabaseHandle` |
| **Migration** | `src/migration/` | `IDatabaseMigration`, `DatabaseMigrationRunner`, `driftMigrationStrategy` |
| Constants | `src/utils/database_constants.dart` | `DEFAULT_READ_POOL`, `BUSY_TIMEOUT_MS`, `CORRUPT_FILE_SUFFIX`, các marker lỗi hỏng file / lỗi môi trường |

Drift phân giải `@DriftDatabase(tables:)` lúc biên dịch và bắt buộc DAO phải là `part of` thư viện database của nó, nên một database khai ở đây sẽ phải gọi tên bảng của bất kỳ package nào sở hữu chúng. Giữ database thuộc về từng package mua được một tính chất: xoá package là xoá luôn database của nó, và không package nào khác với tới được các dòng dữ liệu đó. Cái giá phải trả là SQL không join xuyên ranh giới package — vượt qua một bounded context là việc của tầng repository, không phải của một câu truy vấn.

### Hai hợp đồng giữ các package không chạm bảng của nhau

**`IDatabaseMigration`** — package nào đổi schema thì hiện thực hợp đồng này ngay cạnh bảng của mình và đăng ký trong DI module của chính nó, y như cách feature đóng góp route. `version` là phiên bản schema mà bước đó *tạo ra*; các bước được phát lại theo thứ tự nên thiết bị bỏ lỡ vài bản phát hành vẫn về đúng schema. Trùng version bị từ chối ngay lúc khởi động thay vì âm thầm chạy một cái.

**`IDatabaseHandle`** — data source xin đúng accessor mình cần thay vì nhận một object database kèm toàn bộ DAO trên đó:

```dart
ProfileLocalDataSource(IDatabaseHandle<ProfileDatabase> handle)
  : _dao = handle.accessor(ProfileDao.new);
```

> [!NOTE]
> Trong phạm vi **một** database, đây là **cô lập ở mức bề mặt API, không phải cô lập cưỡng chế**: callback factory vẫn nhận được object database, nên một bên gọi cố tình vẫn với tới được mọi DAO trên đó. Giá trị nằm ở chỗ vượt qua ranh giới trở thành hành động cố ý và nhìn thấy được khi review, chứ không phải một tham số constructor bình thường. Cô lập *giữa các package* mới là rào chắn thật, và nó do đồ thị package cưỡng chế — package nào không khai `data_cache` thì thậm chí không gọi được tên `CacheDatabase`.

Phần gia cố kết nối (`foreign_keys = ON`, chế độ WAL, busy timeout) và chiến lược cách ly file hỏng nằm ở [`../guides/07_database.md`](../guides/07_database.md).

---

## 9. `core_notifications` — thông báo đẩy và cục bộ

`PushNotificationService` bọc Firebase Messaging và `flutter_local_notifications`. Channel ID và loại payload nằm ở `src/utils/notification_constants.dart`, tức ngay trong package tiêu thụ chúng — một channel ID thông báo không có lý do gì để mọi package trong app đọc được.

Service này là `@singleton` eager inject `FirebaseOptions`, mà mỗi app tự đăng ký từ `lib/firebase/firebase_module.dart` của mình. Vì thế manifest của app đặt `core_notifications` trong nhóm `notifications` với `phase: after` thay vì trong `core`: `before` chạy trước phần đăng ký của chính app. App không dùng push notification thì bỏ nhóm này đi.

---

## 10. State management — hai nhánh, **chưa ngang bằng nhau**

Template hỗ trợ Provider và BLoC. Cần biết trước khi chọn: hai nhánh không được đầu tư như nhau.

| | `provider_state_management` | `bloc_state_management` |
|:--|:--|:--|
| Lớp nền | `BaseProvider<T>` — hiện thực đầy đủ | `BaseBloc` / `BaseCubit` — *chỉ là điểm mở rộng, không thêm gì* |
| Trợ giúp bất đồng bộ | `executeOperation(OperationConfig(...))` tự lo loading/success/failure | **không có** |
| Kiểu state | `ViewStateModel<T>` + `ViewState` (5 nhánh, có `loadingMore`, data nằm ở model) | `BlocViewState<T>` (4 nhánh, tự mang payload) |
| Dạng lỗi | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — bắt buộc |
| Thành phần thêm | `StateManager`, `OperationExecutor`, `OperationGlobalConfig`, `LoadMoreMixin`, `ProviderStateListener`, `BaseViewWidget` | — |

> [!WARNING]
> Ở nhánh BLoC, bạn phải tự bóc `Result<T>`, tự map `AppFailure`, và tự emit loading/kết thúc **bằng tay trong từng handler**. Nhánh Provider gói toàn bộ việc đó trong `executeOperation`. File `base_bloc.dart` ghi rõ điều này và có ví dụ mẫu cách làm thủ công.

### `BlocViewState<T>`

Kiểu state của BLoC là `BlocViewState<T>`, **không phải** `ViewState`. Cả hai package đều export từ barrel công khai, và nhánh Provider export một `ViewState` khác hẳn về ngữ nghĩa. Chính cái tên riêng biệt này cho phép một file import cả hai barrel mà không đụng tên lúc biên dịch.

`OperationGlobalConfig` phơi getter chỉ-đọc; `setup()` **gộp** thay vì ghi đè, nên gọi hai lần vẫn giữ được cả hai bộ hook, và có `reset()` cho test.

Cách dùng thực tế cho cả hai nhánh: [`../guides/03_state_management.md`](../guides/03_state_management.md).

---

## 11. Bản đồ phụ thuộc

Chỉ liệt kê phụ thuộc cục bộ (trong workspace) — bỏ qua package từ pub.dev.

| Package | Phụ thuộc |
|:--|:--|
| `domain_core` | *(không có)* |
| `core_database` | *(không có)* |
| `core_di` | *(không có)* |
| `core_responsive` | *(không có)* |
| `platform_kernel` | `domain_core` *(ngoại lệ đã duyệt — `ErrorHandler` sinh ra `AppFailure`)* |
| `core_common` | `platform_kernel`, `core_responsive` |
| `core_network` | `platform_kernel` |
| `core_notifications` | `platform_kernel` |
| `core_storage` | `core_common` |
| `data_core` | `platform_kernel`, `domain_core` |
| `core_base_ui` | `core_common`, `core_di`, `core_responsive` |
| `bloc_state_management` | `domain_core` *(ngoại lệ đã duyệt — `AppFailure` cho `BlocViewState.error`)* |
| `provider_state_management` | `core_common`, `domain_core` *(ngoại lệ đã duyệt)* |
| `core_ui_kit` | `core_common`, `core_base_ui`, `core_responsive`, `provider_state_management` |
| `platform_app_shell` | `core_base_ui`, `core_common`, `core_di`, `core_network`, `core_responsive`, `core_storage`, `core_ui_kit`, `provider_state_management` |

Không mũi tên nào trong bảng này trỏ tới `modules/*/feature` hay `modules/*/data` — đó là bất biến cần giữ.
