<!-- translated-from: docs/en/architecture/02_core.md@e5b7f09 -->
# Tầng Core

Tài liệu này trả lời câu hỏi **"trong `platform/*` có gì, và khi nào thì dùng package nào?"**. Đọc xong bạn sẽ chọn đúng core package cho từng việc — và nhận ra khi nào thứ bạn định thêm vào thực ra *không* thuộc về core.

Core là **hạ tầng**. Nó cung cấp cơ chế; nó không mã hoá nghiệp vụ, và không biết feature nào tồn tại.

---

## 0. Ba luật chi phối mọi package core

Ba luật áp dụng cho mọi thứ trong trang này — RULE-01, RULE-44 / RULE-46 (cơ chế, không phải chính sách) và RULE-09 trong [bảng đăng ký](../reference/01_rules.md#bảng-đăng-ký-luật).

**Core không được phụ thuộc feature hay data** (RULE-01). Bốn cạnh `→ domain_core` đã duyệt được liệt kê ở [phần tổng quan](01_overview.md#các-ngoại-lệ-đã-được-duyệt); `tools/arch_check/check.dart` cưỡng chế danh sách này ở mọi PR.

**Core cấp cơ chế, không cấp chính sách.** `core_storage` cho bạn `StorageValue<T>`; nó không quyết định rằng tồn tại một key tên `token`. `core_database` cho bạn kết nối và hợp đồng migration; nó không biết ý nghĩa nghiệp vụ của bảng. Hễ một package core bắt đầu gọi tên một khái niệm domain cụ thể, cái tên đó thuộc về chỗ khác.

**Mọi package giữ constants trong thư mục `utils/` của chính nó.** Một ngoại lệ đã duyệt: design token trong `core_base_ui/src/styles/` giữ nguyên vị trí — xem [`core_base_ui`](#3-core_base_ui--design-system) bên dưới.

### Package nằm ở đâu — sáu nhóm

`platform/` được chia thành sáu thư mục nhóm theo vai trò. Chỉ có thư mục cho biết package thuộc nhóm nào — **tên** package không mang nhóm (`core_di` nằm ở `platform/foundation/contracts`), nên import, `app_manifest.yaml` và tên phụ thuộc trong từng `pubspec.yaml` hoàn toàn không nhắc tới nhóm.

| Nhóm | Thư mục | Package (thư mục) | Thứ thuộc về đây | Được phụ thuộc vào |
|:--|:--|:--|:--|:--|
| **foundation** | `platform/foundation/` | `platform_kernel` (`kernel/`), `core_di` (`contracts/`), `core_common` (`common/`) | Nền mà mọi package khác dựng lên: service locator, xử lý lỗi và các kiểu app-profile (Dart thuần); các hợp đồng DI giữa module; helper boot, vòng đời và routing gắn với Flutter. Không gọi tên kiểu Dio (HTTP client) nào | foundation, `domain_core` |
| **layers** | `platform/layers/` | `domain_core` (`domain/`), `data_core` (`data/`) | Hợp đồng nền của tầng domain và data — `Result<T>`, `AppFailure`, `BaseEntity`, `BaseRepository` — mà `modules/*/domain` và `modules/*/data` mở rộng | `domain_core`: không gì. `data_core`: foundation, `domain_core` |
| **infra** | `platform/infra/` | `core_network`, `core_storage`, `core_database`, `core_notifications` (`network/`, `storage/`, `database/`, `notifications/`) | Cơ chế với ra ngoài tiến trình — HTTP, lưu trữ key–value, SQLite, push. Chỉ cơ chế: không key, bảng hay endpoint của module sản phẩm nào. Nhóm mặc định của `generate.dart 4` / `5` | foundation, layers — không bao giờ một package infra khác |
| **ui** | `platform/ui/` | `core_responsive` (`responsive/`), `core_base_ui` (`design_system/`), `core_ui_kit` (`ui_kit/`) | Scale và layout thích ứng, design token, theme và chuỗi dùng chung, thư viện widget dùng chung | foundation, ui — không bao giờ state, infra hay shell |
| **state** | `platform/state/` | `provider_state_management` (`provider/`), `bloc_state_management` (`bloc/`) | Lớp nền quản lý state, và các widget gắn với nó (`LoadMoreListView`); mỗi feature chọn một | foundation, layers, ui |
| **shell** | `platform/shell/` | `platform_shell_adapters` (`adapters/`), `platform_app_shell` (`app_shell/`) | Các adapter hạ tầng mà mọi app đăng ký (`NetworkConfigImpl`, storage adapter, `AppBootStorage`); app shell mà mọi app compose: boot, kiểm tra composition, lắp ráp router, material wrapper, deep link | mọi nhóm platform (`app_shell → adapters`, không bao giờ ngược lại) |

Chiều phụ thuộc, mỗi mũi tên trỏ về phía bị phụ thuộc: `domain_core ← foundation ← data_core ← infra`, `foundation ← ui ← state`, `layers ← state`, `shell ← toàn bộ platform/`. `platform_kernel → domain_core` là một trong bốn cạnh đã duyệt: `ErrorHandler` sinh ra `AppFailure`. Không gì dưới `platform/` phụ thuộc `modules/` (`arch_check` R1). `arch_check` **R11** bắt buộc chiều giữa các nhóm: nó đọc nhóm của package từ thư mục (`platform/<group>/<package>`; package nằm ngoài thư mục nhóm hợp lệ tự nó là vi phạm) và đối chiếu mọi mục `dependencies:` là package platform với bảng trên — bảng nhóm được phép nằm ở [bảng đăng ký](../reference/01_rules.md#chiều-giữa-các-nhóm-platform-r11) (RULE-02). Dev dependency không bị kiểm; test của `platform_app_shell` dùng `core_storage` cho fake. Một cạnh trỏ vào `domain_core` / `data_core` vẫn cần danh sách đã duyệt của R1.

Mọi cạnh package đều tuân theo chiều này, không có ngoại lệ: `BottomTransitionPage` (scale qua `core_responsive`) nằm ở `core_ui_kit`; các widget gắn với `LoadMoreMixin` (`LoadMoreListView`) nằm ở `provider_state_management`, nên kit không khai package quản lý state nào; và kernel không gọi tên kiểu Dio nào — `core_network` đóng góp `DioFailureClassifier` qua `ErrorHandler.registerClassifier` (§ 1, § 6).

Package cơ chế mới đặt vào `infra` — `dart tools/module_generator/generate.dart 4 <name>` đặt nó ở đó; truyền `--group <group>` cho nhóm khác.

---

## 1. `platform_kernel` và `core_common` — nguyên thuỷ dùng chung

Đáy của ngăn xếp hạ tầng là hai package, tách theo đúng một câu hỏi: *có cần Flutter không?*

**`platform_kernel`** là Dart thuần — không có `flutter` trong dependency, `arch_check` R9 cưỡng chế điều đó, và cũng không transport: nó không gọi tên kiểu nào của `dio`. Phụ thuộc workspace duy nhất của nó là `domain_core`, để lấy `AppFailure` mà `ErrorHandler` sinh ra. Hãy phụ thuộc thẳng vào nó, trừ khi bạn cần thứ gì gắn với Flutter. Mọi thứ nằm trong `lib/src/`:

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Service locator | `service_locator.dart` | `getIt`, `getItOrNull`, `getAll`, `getAllOrEmpty`, và typedef `ServiceLocator` cho code phải gọi tên locator mà không khai `get_it` |
| Flavor | `flavor.dart` | `Flavor` (`dev`, `staging`, `prod`; `toValue()` là cách viết của `--flavor` / môi trường DI) |
| Lỗi | `error/` | `ErrorHandler.handleError()` (không bao giờ throw), các kiểu `AppException`, và một bản re-export các kiểu failure khai trong `domain_core` cạnh `Result<T>`. `ErrorClassifier` + `ErrorHandler.registerClassifier` cho phép package sở hữu một kiểu exception tự ánh xạ nó — `core_network` đăng ký `DioFailureClassifier` (§ 6). `ErrorHandler.onUnclassifiedError` là một callback thường cho những exception nó không phân loại được — app shell trỏ nó tới `IErrorReporter` tuỳ chọn ([`06_app_shell.md`](06_app_shell.md#lỗi-và-crash-reporting)) |
| App profile | `profile/` | Các kiểu một app dùng để tự mô tả với shell — `AppProfile`, `AppFacts`, `AppPlatform`, `PlatformFacts`, `SslPinningPolicy`, và các section tinh chỉnh có kiểu (`DisplayProfile`, `RouterProfile`, `LocaleProfile`, `ThemeProfile`, `NetworkProfile`); `registerAppProfile` đưa chúng vào locator. Ý nghĩa từng trường: [`06_app_shell.md`](06_app_shell.md#hồ-sơ-app), [`13_app_composition`](../guides/13_app_composition.md) |
| Helper | `helpers/` | `TypeHelper`, `ValidationHelper` |
| Extension cho String | `string_extension.dart` | `StringExtension` (`capitalize`, `isValidEmail`, `truncate`, …) và `StringPriceExtension` — không có định dạng `DateTime` hay `num`: ngày, giờ và tiền tệ phụ thuộc locale, nên hãy định dạng bằng `DateFormat` / `NumberFormat` của `intl` với locale hiện tại |
| Hằng số | `utils/` | `EnvConstants` (`BASE_URL`, `APP_NAME`), `ErrorCodes`, `ProfileConstants` (các define `ALLOW_UNDECLARED_PLATFORM` và `APP_FLAVOR`) |

**`core_common`** là nửa gắn với Flutter. Nó khai hai phụ thuộc workspace — `platform_kernel`, được nó re-export toàn bộ (`src/kernel.dart`) nên một import `package:core_common/core_common.dart` vẫn resolve được mọi thứ ở trên; và `core_di`, cho `IAnalytics` tuỳ chọn mà `RouteAwareWidget` báo lượt xem màn hình tới. Nó không phụ thuộc gì trong nhóm `ui`.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Config | `src/config/` | `AppConfig` (xác định flavor, quy tắc bỏ qua TLS, locale mặc định), `AppInitializer` (logger, `HttpOverrides`, chính sách hướng màn hình, `RouteAwareWidget.observer`), `resolveAppPlatform()` (chỗ duy nhất ánh xạ thiết bị đang chạy sang một `AppPlatform`) |
| Mixin | `src/mixins/` | `LifecycleMixin`, `NetworkMixin`, `DisposeGuard` |
| Trợ giúp routing | `src/go_route_data_custom.dart` | `GoRouteDataCustom`, `RouteAwareWidget` |
| Helper | `src/helpers/` | `AppUtils`, `EasyDebounce`, `AppInfoHelper` (thông tin package) |
| Input formatter | `src/input_formatters.dart` | `NumberCurrencyFormatter`, `PhoneNumberFormatter` |

### Những gì *không* thuộc về đây, và vì sao

`core_common` không có thư mục `constants/`. Một thư mục constants dùng chung đặt ở package đáy sẽ thành **god object** — một chỗ duy nhất, mọi package import được, liệt kê những giá trị vốn thuộc về từng domain riêng lẻ:

| Loại hằng số | Nơi nó thuộc về | Vì sao không phải ở đây |
|:--|:--|:--|
| Key storage (`TOKEN`, `AUTH_USER`, `LOCALE`, `THEME_MODE`, `VIEWED_ONBOARD`) | cùng chỗ với class sở hữu giá trị đó — xem [hướng dẫn storage](../guides/06_storage.md) | Liệt kê chung một chỗ thì mọi package đọc và ghi đè được key storage của mọi feature khác. |
| Endpoint REST (`/user/login`, `/user/refresh-token`) | package data sở hữu chúng — [`modules/auth/data/lib/src/utils/auth_api_constants.dart`](../../../modules/auth/data/lib/src/utils/auth_api_constants.dart) | Chúng chỉ thuộc về auth. Không thứ gì khác có lý do gọi tên chúng. |
| Hằng số của một hệ thống con (tên event analytics, event socket như `TYPING` / `USER_JOINED`, key remote-config) | package hiện thực hệ thống con đó, nếu có | Event dành riêng cho chat mà nằm trong một package core là rò rỉ ranh giới, còn hằng số cho một hệ thống repo không hề có thì chỉ là gánh nặng chết. |

Ba file constants nằm ở đáy ngăn xếp, vì chúng thật sự toàn cục — tất cả trong `src/utils/` của `platform_kernel`: `EnvConstants` (giá trị `String.fromEnvironment`), `ProfileConstants` (các define build-time mà boot đọc) và `ErrorCodes` ([`error_codes.dart`](../../../platform/foundation/kernel/lib/src/utils/error_codes.dart) — mọi mã lỗi phi-HTTP mà platform gán, chia theo dải: `1xxx` mạng (`NETWORK_ERROR`, `NO_INTERNET`, `CONNECTION_TIMEOUT`, `REQUEST_CANCELLED`, …), `2xxx` storage, `3xxx` validation, `4xxx` parsing, `5xxx` cache, `6xxx` dịch vụ ngoài, `7xxx` response envelope (`RESPONSE_REJECTED`, `EMPTY_RESPONSE`) và `UNKNOWN` 9999 — tất cả nằm ngoài dải HTTP nên một 5xx luôn là 5xx thật).

> [!CAUTION]
> Trước khi thêm một hằng số vào `core_common`, hãy tự hỏi: *có nhiều hơn một domain không liên quan cùng đọc nó không?* Nếu không, nó thuộc về `utils/` của package sở hữu.

**Firebase options cũng không nằm ở đây.** Chúng gắn với một bundle ID, nên thuộc về một app: mỗi app dùng Firebase sở hữu `lib/firebase/firebase_module.dart` đăng ký `FirebaseOptions` theo từng flavor (của app mẫu là [`apps/mobile/lib/firebase/firebase_module.dart`](../../../apps/mobile/lib/firebase/firebase_module.dart)).

---

## 2. `core_di` — DI Hub

Chỉ chứa hợp đồng. Không hiện thực, không nghiệp vụ. Đây là vùng trung lập nơi platform gặp các module — và mọi hợp đồng ở đây đều **trung lập với sản phẩm**: đặt tên theo thứ platform cần (một phiên đăng nhập, một vị trí), không bao giờ theo module tình cờ cung cấp nó.

| Nhóm hợp đồng | Đường dẫn (dưới `lib/src/`) | Mục đích |
|:--|:--|:--|
| Routing | `routing/` | `IFeatureRouteModule`, `INavDestinationModule` (cùng `NavDestination` của nó), `IAppEntryLocation`, `ISignInLocation` / `IPostSignInLocation` (nơi shell đưa người dùng đã đăng xuất / đã đăng nhập tới), `IDashboardRouteModule`, `NavigatorKeys` — mỗi hợp đồng một file |
| Session | `session/` | `SessionPrincipal`, `SessionFailure`, `ISessionState` (phía shell), `ISessionStatusStream` (phía feature: chia sẻ state giữa feature Provider và feature BLoC), `ISessionRefreshListenable`, `ISessionGateway` (transport) — do module nào sở hữu đăng nhập hiện thực |
| App | `app/` | `IAppSplashScreen` (splash bằng Dart), `IAppTreeWrapper` (bọc cây widget, có thứ tự) |
| Hợp đồng storage | `i_theme_storage.dart`, `i_language_storage.dart` | `IThemeStorage`, `ILanguageStorage` — hiện thực trong package adapter của app shell (`platform_shell_adapters`) |
| Localization | `i_feature_localization.dart` | `IFeatureLocalization` — mỗi feature tự đóng góp delegate |
| Observability | `observability/` | `IErrorReporter`, `IAnalytics` — tuỳ chọn, do app implement (Crashlytics, Sentry, Firebase Analytics, …); xem [`06_app_shell.md`](06_app_shell.md#lỗi-và-crash-reporting) |

App cung cấp những hợp đồng nào, và shell làm gì khi thiếu từng cái, là khai báo `capabilities:` của app (RULE-81) — [`06_app_shell.md`](06_app_shell.md#shell-resolve-những-gì-từ-một-app) liệt kê chúng.

**`NavigatorKeys`** có file riêng, [`src/routing/navigator_keys.dart`](../../../platform/foundation/contracts/lib/src/routing/navigator_keys.dart), tách khỏi các interface routing. Nó phơi ra `rootKey`, `appKey`, và `nested(id)` cho module cần back stack riêng.

Một `ShellRoute` và các route con phải dùng **cùng một** instance `GlobalKey`, nhưng shell do app shell dựng còn route con khai bên trong feature. Đặt key ở bên nào cũng tạo chu trình, nên Hub — nơi cả hai đều đã phụ thuộc — giữ nó.

Key được *yêu cầu theo id* chứ không khai sẵn: `NavigatorKeys.nested('auth')` luôn trả về cùng một instance. Nhờ vậy DI Hub không gọi tên feature nào, và module cần back stack riêng không phải thêm gì vào đây.

> [!NOTE]
> `core_di` phụ thuộc `go_router`. Đây không phải rò rỉ: `IFeatureRouteModule` và `INavDestinationModule` đều trả về `List<RouteBase>`. Đây *chính là* hợp đồng routing nên buộc phải nói ngôn ngữ của GoRouter — nhưng `INavDestinationModule` mô tả điểm đến bằng `NavDestination` của chính Hub, không phải `BottomNavigationBarItem`, nên hợp đồng không cam kết vào thanh bottom bar. Trừu tượng thêm một lớp nữa chỉ tạo adapter vô ích.

**Không thuộc về đây:** bất cứ thứ gì có phần hiện thực. Nếu bạn viết `class …Impl` trong `core_di`, nó đang nằm sai package. Cũng không phải hợp đồng tồn tại để một feature chạm tới *một module khác* — `AuthNavigator`, `IAuthActionHandler`, `HomeNavigator`: chúng nằm trong package API của module sở hữu (`modules/auth/api` → `auth_api`, `modules/home/api` → `home_api`), vốn chỉ được phụ thuộc foundation và Flutter (`arch_check` R3).

---

## 3. `core_base_ui` — design system

Design token, theme, typography, asset toàn cục và bộ localization nền. Phụ thuộc `core_responsive`, `core_di`, `core_common` và `platform_kernel`.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Design token | `src/styles/` | `AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows` |
| Theme | `src/theme/` | `ThemeProvider` (dựng `ThemeData` từ palette), `ThemeSystemExtension` (palette — các token màu gồm `shadow` và `scrim`; hai palette `light` / `dark`; `toColorScheme`; `withOverrides` cho `ThemeProfile` của app) |
| Ngôn ngữ | `src/language/` | `LanguageProvider`, `LanguageSet` (các ngôn ngữ app cung cấp, lấy từ `LocaleProfile` của nó), `AppLanguages` (`supported`, `fallback`, `resolve`, `nameOf` — nơi thêm tên hiển thị của một ngôn ngữ) |
| Extension | `src/extensions/` | `context.colors` / `context.colorScheme` / `context.l10n`, `GlobalKey.showDropDown`, `Locale.languageName`, `AppLocalizations.failureMessage(code)` (câu đã dịch của một failure, chọn theo code — không bao giờ theo `AppFailure.message`, RULE-34) |
| Licenses | `src/licenses/` | `registerBaseUiLicenses()` — giấy phép của typeface |
| Sinh tự động | `src/gen/` | `Assets` (logo SVG), `FontFamily`, `AppLocalizations` (chuỗi toàn cục) |
| Constants | `src/utils/base_ui_constants.dart` | Giá trị không phải token: kích thước dropdown, cỡ chữ tiêu đề app bar, elevation khi cuộn dưới app bar, alpha chỉ báo navigation rail |

Typeface và các chuỗi toàn cục nằm trong package này (`assets/fonts/`, `assets/language/`). Ảnh launcher icon và native splash là đầu vào của build, không phải asset lúc chạy: chúng nằm ở `assets/branding/` của repo, được `icons_launcher-<flavor>.yaml` và `flutter_native_splash-<flavor>.yaml` ở root đọc. Palette mà một app ghi đè được khai trong `ThemeProfile` của nó (`PaletteToken` → màu), không phải bằng cách sửa package này — [`11_design_system.md`](../guides/11_design_system.md).

### Zero Flutter widget — đã kiểm chứng

Package này **không** chứa `StatelessWidget`, `StatefulWidget`, `State<…>` hay `InheritedWidget` nào trong `lib/`. Điều này được kiểm tra, không phải mặc định tin. Widget dùng lại thuộc về [`core_ui_kit`](#4-core_ui_kit--widget-dùng-lại); `core_base_ui` chỉ cấp giá trị cho những widget đó tiêu thụ.

### Vì sao design token ở lại `styles/` thay vì `utils/`

Đây là ngoại lệ đã duyệt của luật "constants nằm trong `utils/`" (RULE-09):

- Chúng là **API công khai**, được nhiều feature package import trực tiếp.
- `styles/` mang ý nghĩa rõ ràng — "đây là design system". `utils/` đọc lên là "linh tinh", đúng tín hiệu sai cho những token mà cả app phải tuân theo.

Các magic value *không phải* token thì nằm ở `src/utils/base_ui_constants.dart`. Ranh giới phân biệt: nếu một designer nhìn vào mà nhận ra, đó là token và ở lại `styles/`.

### Màu do review giữ

`arch_check` R20 từ chối một số thô trong các constructor layout và paint mà nó liệt kê (kể cả `fontSize:`) nằm ngoài `styles/` và `utils/`. Một màu hardcode thì không bị kiểm: luật lexical `Colors.<name>` không phân biệt được literal đúng với vi phạm, và RULE-71 cấm comment suppression mà một danh sách ngoại lệ sẽ cần. Vì vậy RULE-33 do review giữ — đọc `context.colors.*`, không bao giờ dùng literal. Hai giá trị trông như ngoại lệ thật ra là token: `scrim` (lớp phủ modal và loading, đen có alpha ở cả hai palette, vì một scrim đảo theo theme sẽ *làm sáng* màn hình ở chế độ tối) và `shadow` (thứ `AppShadows` dùng).

### `ThemeProvider` phản ứng khi OS đổi theme

`ThemeProvider` là `@lazySingleton` có mixin `WidgetsBindingObserver`. Ở chế độ `ThemeMode.system`, độ sáng của OS có thể đổi khi app đang chạy, nên nó override `didChangePlatformBrightness()` và rebuild — nhưng chỉ khi chế độ thực sự *là* `system`, để lựa chọn light/dark cứng không gây rebuild thừa.

`WidgetsBindingObserver` được chọn thay vì gán `platformDispatcher.onPlatformBrightnessChanged`: trường đó là một **slot đơn**, ai gán sau sẽ âm thầm thắng. Với một singleton toàn cục phải cạnh tranh cùng framework và plugin, đó là rủi ro thật.

Observer được gỡ trong `dispose()`, và hàm này gắn `@disposeMethod` để GetIt gọi khi reset container — thiếu nó thì mỗi lần `resetDependencies()` trong test sẽ để lại một observer cũ còn đăng ký.

```dart
// platform/ui/design_system/lib/src/theme/theme_provider.dart
@override
void didChangePlatformBrightness() {
  super.didChangePlatformBrightness();
  if (_themeMode != ThemeMode.system) return;

  // Refresh the status/navigation bar styling for the new brightness…
  setSystemTheme();
  // …and rebuild consumers, because `currentTheme` now resolves differently.
  notifyListeners();
}

@disposeMethod
@override
void dispose() {
  if (_isObservingPlatform) {
    WidgetsBinding.instance.removeObserver(this);
    _isObservingPlatform = false;
  }
  super.dispose();
}
```

Giá trị đã lưu được đọc qua `IThemeStorage` — xem [`../guides/06_storage.md`](../guides/06_storage.md#9-chia-sẻ-giá-trị-qua-ranh-giới-package).

---

## 4. `core_ui_kit` — widget dùng lại

Thư viện widget dùng chung mà mọi feature đều có thể dùng. Nó là **core, không phải feature**: nằm tại `platform/ui/ui_kit` để `modules/*/feature/` chỉ còn chứa các mảng sản phẩm thực sự gỡ được.

Mọi thứ nằm dưới `lib/src/`, sau barrel duy nhất của package (`lib/core_ui_kit.dart`):

| Thư mục | Nội dung |
|:--|:--|
| `buttons/` | `CustomButton.rectangle` |
| `inputs/` | `CustomInputField` |
| `feedback/` | `LoadingWidget`, `EmptyWidget` |
| `media/` | `CustomCacheNetworkImage` |
| `layout/` | `TextScaleDown` |
| `navigation/` | `BottomTransitionPage` — một `Page` hiển thị route go_router dưới dạng modal bottom sheet |
| `dialogs/` | **`AppOverlay`**, hệ thống overlay duy nhất: dialog xếp hàng (`showDialog<T>` / `dismissDialog` / `clearDialogs`), toast và loading indicator, hiển thị không cần `BuildContext`; `OverlayDialogWidget` / `OverlayDialogState.closeDialog` làm nền cho dialog tự đóng (`RetryDialog` là một); `AppOverlayInitializer`, do app shell mount |
| `utils/` | `SharedUiConstants` |

Nó phụ thuộc `core_base_ui` và `core_responsive` — không bao giờ phụ thuộc một package quản lý state, infra, một feature hay `data_*`.

> [!NOTE]
> Phụ thuộc chạy **một chiều**: `state -> ui`. `provider_state_management` được phụ thuộc nhóm ui (`LoadMoreListView` của nó lấy padding của spinner từ token `AppSpacing` trong `core_base_ui`); `core_ui_kit` không phụ thuộc package quản lý state nào. Vì vậy widget gắn với `LoadMoreMixin` hay `ViewState` nằm ở `provider_state_management`, không ở đây. `provider_state_management` cũng tự mang `DefaultLoadingWidget` / `DefaultEmptyWidget` thay vì mượn widget có thương hiệu từ đây.

### Quy tắc UI-agnostic

RULE-31: widget dùng lại dùng tham số **đúng như nhận được** và không được tự scale chúng qua `core_responsive`. Scale là việc của bên gọi, nên khi giá trị đến nơi thì nó đã ở đơn vị pixel thiết bị — để ý `context.w(120)` ở phía gọi bên dưới. Widget vẫn scale hằng số **của chính nó**, nếu không thì nó chẳng responsive gì cả:

```dart
// bên gọi scale
CustomButton.rectangle(minWidth: context.w(120), height: context.h(44))

// widget tự scale tham số của mình -- sai
double _width(BuildContext context) => context.w(width);
```

Scale bên trong nghĩa là bên gọi nào đã scale sẽ bị scale hai lần, còn bên gọi muốn một giá trị pixel nguyên bản thì không cách nào lấy được.

> [!WARNING]
> **Luật này cấm điều gì.** Một widget app bar mang theo:
>
> ```dart
> @override
> double? get leadingWidth => context.w(64);
> ```
>
> Hai lỗi cùng lúc: nó tự scale bên trong, và — vì là getter override — nó **âm thầm vứt bỏ giá trị `leadingWidth` mà bên gọi truyền vào constructor**. Tham số trông như được hỗ trợ nhưng không làm gì cả.

### Hằng số

Giá trị mặc định của các widget này nằm ở `platform/ui/ui_kit/lib/src/utils/shared_ui_constants.dart`:

```dart
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(
    milliseconds: 200,
  );
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const double BUTTON_HEIGHT = 48;
  // … kích thước và alpha mặc định của các widget còn lại
}
```

Đây là giá trị mặc định, không phải chính sách — bên gọi cần giá trị khác thì truyền qua constructor. Kích thước tính bằng design pixel; widget tự scale giá trị mặc định của mình.

---

## 5. `core_responsive` — scale theo khung thiết kế và layout thích ứng, gắn với `BuildContext`

Cơ chế scale mà mọi widget trong app đều đi qua, cùng các lớp kích thước cửa sổ và widget thích ứng dùng để chọn layout. Nó nằm tại `platform/ui/responsive` và **không phụ thuộc gì ngoài `flutter`** — không package nào trong workspace, không package bên thứ ba nào, và cũng không import `material`.

| Thành phần export | Đường dẫn | Mục đích |
|:--|:--|:--|
| `ResponsiveInit` | `src/responsive_init.dart` | `StatelessWidget`, gắn **một lần** phía trên `MaterialApp`. Tham số: `child` (bắt buộc), `designSize` (mặc định 375×812), `scaleBounds` và `textScaleBounds` (cùng mặc định `ScaleBounds.downOnly()`), `profiles`, `breakpoints` (mặc định `ResponsiveBreakpoints.material3()`), `splitScreenMode`, `minTextAdapt`, `fontSizeResolver`. Assert rằng `designSize` và `designSize` của mọi profile đều dương và hữu hạn |
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
| Constants | `src/utils/` | `ResponsiveConstants`: `SPLIT_SCREEN_MIN_HEIGHT` (700), `DEFAULT_DESIGN_WIDTH` (375), `DEFAULT_DESIGN_HEIGHT` (812), `DESIGN_SCALE_FACTOR` (1), các giá trị `BREAKPOINT_*` và `BREAKPOINT_HEIGHT_*`; `AdaptiveConstants`: `SPLIT_PRIMARY_FRACTION` (0.4), `SPLIT_DIVIDER_EXTENT` (1), `CONTENT_MAX_WIDTH` (640) — nằm trong `src/utils/`, như hằng số của mọi package khác |

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
| `context.edgeInsets({all, horizontal, vertical, left, top, right, bottom})` | `horizontal` theo `w`, `vertical` theo `h`, `all` theo `w` — cạnh vật lý |
| `context.edgeInsetsDirectional({all, horizontal, vertical, start, top, end, bottom})` | cùng các trục; `start`/`end` đảo theo chiều văn bản |
| `context.borderRadius({all, topLeft, topRight, bottomLeft, bottomRight})` | `r` |
| `context.verticalSpace(n)` / `context.horizontalSpace(n)` | một `SizedBox`, theo `h` / `w` |
| `context.windowSizeClass` / `context.windowHeightClass` | lớp cửa sổ — dùng được cả khi không có `ResponsiveInit` |

> [!CAUTION]
> **Cố ý không có extension trên `num`.** `16.w` **không biên dịch được**. Một con số không mang theo context, nên extension kiểu đó chỉ có thể đọc một singleton toàn cục — và widget đọc biến toàn cục thì không bao giờ biết metrics đã đổi. Bắt buộc phải có `BuildContext` chính là cách biến "làm đúng" thành lựa chọn duy nhất viết được. Package không có instance toàn cục, không có hàm `init()` mệnh lệnh, không có trợ giúp `setWidth()` và không có cờ điều khiển rebuild — một khi metrics đã nằm trong `InheritedWidget` thì nhắm đúng widget để rebuild là việc của Flutter.

RULE-30: luật **R7** của `dart tools/arch_check/check.dart` chặn dạng bare — một số literal hoặc một tổng trong ngoặc theo sau bởi `.w` / `.h` / `.r` / `.sp` / `.spMin` / `.dg` / `.dm` — trong mọi file `lib/` viết tay, cùng một `extension … on num` có thể làm nó biên dịch được; **R20** chặn một số thô trong các constructor layout và paint mà nó liệt kê. Cả hai là Gate 1 của `pr_quality_check.yml`.

> [!NOTE]
> Test widget nào có scale **phải** bọc widget cần test trong `ResponsiveInit`, nếu không `ResponsiveScope.of` sẽ assert. Test của bản thân package nằm tại `platform/ui/responsive/test/`.

Phần lắp ráp ở gốc cây (`_ResponsiveWrapper` trong `platform/shell/app_shell/lib/src/main_scope.dart`) mô tả tại [app shell](06_app_shell.md#_responsivewrapper); cách chọn trục, đổi khung thiết kế, chính sách scale và các widget thích ứng nằm ở [`../guides/11_design_system.md`](../guides/11_design_system.md) (§4–§7).

---

## 6. `core_network` — HTTP client

Dựng trên Dio, cấu hình qua hợp đồng `NetworkConfig` nên package không đụng trực tiếp tới storage hay UI.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Client | `src/api_client.dart` | `ApiClient.createClient()` — factory Dio, lắp chuỗi interceptor |
| DI module | `lib/di/network_module.dart` | `NetworkModule` — đăng ký `Dio` mặc định của app, do `ApiClient` dựng (`@lazySingleton`) |
| Hợp đồng | `src/network_config.dart` | `NetworkConfig` — `getToken`, `getLocale`, `onRetryCallback`, `onRefreshToken`, `onRefreshFailed` |
| Interceptor | `src/interceptors/` | `AuthInterceptor`, `RefreshTokenInterceptor`, `RetryInterceptor`, `LoggingInterceptor` |
| Handler | `src/handlers/` | `RefreshTokenHandler`, `RetryHandler`, và `RequestOptions.forReplay()` (`request_replay.dart`) |
| Constants | `src/utils/network_constants.dart` | Tên header, tiền tố `Bearer`, cờ request `EXTRA_*`, log tag — timeout, header thêm và chính sách redirect là `NetworkProfile` của app |
| Ánh xạ lỗi | `src/error/dio_failure_classifier.dart` | `DioFailureClassifier` — `DioException` → `AppFailure` (timeout → `NetworkFailure` `CONNECTION_TIMEOUT`, `badResponse` → `AuthFailure` 401/403 hoặc `ServerFailure` mang status — `ErrorCodes.HTTP_ERROR` khi không có, cancel → `ErrorCodes.REQUEST_CANCELLED`, …) |

`DioFailureClassifier` là cách `ErrorHandler` của kernel biết về Dio mà không import nó: một `@singleton` eager có `@PostConstruct` gọi `ErrorHandler.registerClassifier`. Module của package này chạy trong nhóm DI `core`, nên classifier được đăng ký trước khi có bất kỳ Dio client nào (tất cả đều lazy) và trước khi repository nào chạy; constructor của `ApiClient` đăng ký lại lần nữa, idempotent, cho client dựng ngoài DI. Unit test nào đẩy một repository tới `DioException` mà không qua DI thì gọi `DioFailureClassifier.ensureRegistered()` trước. DI smoke test của các app khẳng định việc đăng ký này (`checkAppContract` C08).

`NetworkConfig` được hiện thực **ở package adapter của app shell** (`platform_shell_adapters`), không phải ở đây — đó chính là điều giữ cho `core_network` không dính bất kỳ phụ thuộc storage nào. Hai callback refresh mặc định `null`, nên client không có endpoint refresh sẽ đơn giản trả `401` nguyên vẹn cho nơi gọi.

> [!CAUTION]
> **SSL pinning chỉ tốt bằng quyết định mà một app đưa ra.** Các pin là quyết định trong manifest của app cho flavor (`flavors.<f>.ssl_pinning`, do `SslPinningPolicy` mang và `AppInitializer` đọc — `NetworkConfig` không dính vào), và các app mẫu khai `disabled` kèm lý do cho staging và prod — nên pinning tắt ở đó, và `AppInitializer` ghi lý do ở mức `WARNING` trong mỗi lần mở trên Android hay iOS không bỏ qua kiểm tra (mọi bản trừ bản debug đã khai báo tường minh `--flavor dev`, kể cả bản thiếu hoặc sai flavor, được coi như `prod` về TLS). Lỗ hổng hiện rõ chứ không im lặng, và nó vẫn là lỗ hổng cho tới khi một app khai pin. Xem [hướng dẫn networking](../guides/08_networking.md#10-bật-ssl-pinning).

Cách khai một service, cho request bỏ qua một bước, thêm client thứ hai hay bật pinning: [`../guides/08_networking.md`](../guides/08_networking.md). Phần dưới đây mô tả những gì diễn ra bên trong client.

### Cấu hình mặc định của `ApiClient`

`core_network` không bao giờ hard-code thông tin đăng nhập hay UI. Nó nhận mọi thứ qua `NetworkConfig` (xem bên dưới), do app shell implement, và những gì một app tinh chỉnh — timeout, header thêm, redirect — qua `NetworkProfile` của nó, được đăng ký trước khi graph dựng, nên `Dio` mặc định mà nhóm `core` tạo ra đã mang sẵn.

```dart
// platform/infra/network/lib/src/api_client.dart
@lazySingleton
class ApiClient {
  final NetworkConfig _config;
  final NetworkProfile _profile;
  final LocaleProfile _locale;

  // The profiles are optional: a client built by hand takes the template defaults.
  ApiClient(
    this._config, [
    this._profile = const NetworkProfile(),
    this._locale = const LocaleProfile(),
  ]) {
    // … throws when NetworkProfile.headers names a credential or shell-owned header (RULE-66)
    DioFailureClassifier.ensureRegistered();
  }

  /// Default base options for Dio.
  BaseOptions get _defaultOptions => BaseOptions(
    baseUrl: EnvConstants.BASE_URL,
    connectTimeout: _profile.connectTimeout, // 20 s unless the app sets it
    receiveTimeout: _profile.receiveTimeout,
    sendTimeout: _profile.sendTimeout,
    followRedirects: _profile.followRedirects,
    headers: {
      ..._profile.headers,
      HttpHeaders.contentTypeHeader: ContentType.json.value,
    },
  );
```

### Chuỗi interceptor

Dio chạy interceptor theo **đúng thứ tự được thêm vào** — cho cả `onRequest` lẫn `onError`. Thứ tự thật trong `createClient()` là:

```
1. AuthInterceptor            → gắn header Authorization + language
2. RefreshTokenInterceptor    → bắt 401, làm mới phiên, replay   (chỉ khi có cấu hình)
3. RetryInterceptor           → bắt lỗi timeout / mất kết nối
4. LoggingInterceptor         → log có cấu trúc (chỉ bản debug)
```

```dart
// platform/infra/network/lib/src/api_client.dart
dio.interceptors.add(
  AuthInterceptor(
    getToken: _config.getToken,
    getLocale: _config.getLocale,
    defaultLanguageCode: _locale.fallback,
  ),
);

// Renewing an expired session must happen before the retry pass,
// otherwise a 401 would be replayed with the same stale token.
// Only wired when the app supplies a refresh callback; without one a
// 401 surfaces to the caller unchanged.
final onRefreshToken = _config.onRefreshToken;
if (onRefreshToken != null) {
  final onRefreshFailed = _config.onRefreshFailed;
  dio.interceptors.add(
    RefreshTokenInterceptor(
      RefreshTokenHandler(
        dio: dio,
        currentToken: _config.getToken,
        onRefreshToken: onRefreshToken,
        onRefreshFailed: onRefreshFailed ?? () async {},
      ),
    ),
  );
}

dio.interceptors.addAll([
  RetryInterceptor(
    handleRetry: retryHandler.handleRetry,
    retryWhen: retryHandler.retryWhen,
  ),
  LoggingInterceptor(tag: NetworkConstants.CLIENT_LOG_TAG),
]);
```

Auth chạy trước để token được gắn trước mọi thứ; refresh đứng trước retry để một lỗi 401 được **làm mới** chứ không bị replay với đúng cái token đã chết.

#### `AuthInterceptor`

Gắn header `language` viết hoa — mã mà `NetworkConfig.getLocale` đã resolve, nếu không có thì `LocaleProfile.fallback` của app (mặc định `en`) — và bearer token khi request cần auth:

```dart
// platform/infra/network/lib/src/interceptors/auth_interceptor.dart
if (needAuthentication) {
  final token = getToken() ?? '';
  if (token.isNotEmpty) {
    options.headers.addAll({
      HttpHeaders.authorizationHeader:
          '${NetworkConstants.BEARER_PREFIX} $token',
    });
  }
}
```

> [!NOTE]
> Tên header ngôn ngữ là `'language'` (không chuẩn), **không phải** `Accept-Language`. Phía server phải khớp đúng tên này.

#### `RetryInterceptor`

Chỉ lỗi tầng vận chuyển mới được retry — **không** retry theo HTTP status code:

```dart
// platform/infra/network/lib/src/handlers/retry_handler.dart
bool retryWhen(DioExceptionType type) {
  return type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout;
}
```

Nhiều request lỗi đồng thời được gom vào một hàng đợi và chỉ hiện **một** dialog retry duy nhất qua `NetworkConfig.onRetryCallback`. Nếu không truyền callback, mọi request trong hàng đợi sẽ bị huỷ thay vì treo. "Retry" lấy mọi request ra khỏi hàng đợi (mỗi bên gọi một mục) và gửi lại qua chính `Dio` đó với `canRetry: false`: interceptor auth và refresh chạy lại (token mới, 401 được refresh), timeout thì đưa bên gọi trở lại hàng đợi cho dialog kế tiếp, còn lỗi khác tới tay bên gọi đúng là lỗi *đó* chứ không phải timeout ban đầu.

#### `LoggingInterceptor`

Cả ba hook đều nằm sau `kDebugMode`, và header chứa thông tin đăng nhập bị che **ngay cả ở bản debug**:

```dart
// platform/infra/network/lib/src/interceptors/logging_interceptor.dart
static Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
  const redactedKeys = {
    HttpHeaders.authorizationHeader,
    HttpHeaders.cookieHeader,
    HttpHeaders.setCookieHeader,
    HttpHeaders.proxyAuthorizationHeader,
  };

  return {
    for (final entry in headers.entries)
      entry.key: redactedKeys.contains(entry.key.toLowerCase())
          ? '***REDACTED***'
          : entry.value,
  };
}
```

Body cũng được che, ở mọi độ sâu: giá trị dưới `password`, `token`, `access_token` / `accessToken`, `refresh_token`, `id_token`, `secret` hoặc `client_secret` được in thành `***REDACTED***` — request login mang password trong body, còn response trả token trong body.

### App cung cấp `NetworkConfig` thế nào

```dart
// platform/infra/network/lib/src/network_config.dart
abstract class NetworkConfig {
  String? Function() get getToken;
  String? Function() get getLocale;

  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  });

  Future<String?> Function()? get onRefreshToken => null;
  Future<void> Function()? get onRefreshFailed => null;
}
```

Hai getter refresh mặc định `null`, nên trong một app không có endpoint refresh thì `401` đi thẳng tới caller, nguyên vẹn.

Phần implement giao mỗi giá trị cho đúng chủ sở hữu của nó, thay vì tự đọc storage:

```dart
// platform/shell/adapters/lib/src/network_config_impl.dart
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  NetworkConfigImpl(
    this._languageStorage, [
    LocaleProfile locale = const LocaleProfile(),
  ]) : _languages = LanguageSet(locale);

  final ILanguageStorage _languageStorage;
  final LanguageSet _languages;

  /// Null in a build that composes no session owner.
  ISessionGateway? get _session => getItOrNull<ISessionGateway>();

  /// Whether a session owner is composed — *without* resolving it:
  /// resolving the gateway while `Dio` is being built closes a dependency
  /// cycle.
  bool get _hasSession => getIt.isRegistered<ISessionGateway>();

  @override
  String? Function() get getToken =>
      () => _session?.readToken();

  /// The app's language, resolved like `LanguageProvider` resolves it, so the
  /// server always gets a language the app offers.
  @override
  String? Function() get getLocale =>
      () => _languages.resolve(_languageStorage.getLanguage()).languageCode;

  @override
  Future<String?> Function()? get onRefreshToken =>
      _hasSession ? _refreshSession : null;

  @override
  Future<void> Function()? get onRefreshFailed =>
      _hasSession ? _clearSession : null;
```

> [!IMPORTANT]
> `NetworkConfigImpl` không import module nào. Nó đọc token qua `ISessionGateway`, được resolve bằng `getItOrNull` ngay lúc gọi thay vì inject, nên nó dựng được dù build có module auth hay không, và không thứ tự DI nào làm hỏng được nó. Khi không có gateway nào được đăng ký, `onRefreshToken` trả về null — và `ApiClient` chỉ gắn `RefreshTokenInterceptor` **khi** giá trị đó khác null, nên một build không có auth sẽ không có interceptor refresh, thay vì có một cái không bao giờ thành công. `arch_check` R1 giữ điều đó: nó nằm trong `platform_shell_adapters`, và package `platform/` không được import module. Xem [`../guides/05_di.md`](../guides/05_di.md).

### Luồng refresh token

`_refreshSession` giao việc cho `ISessionGateway`, do `data_auth` hiện thực: repository refresh và lưu thông tin đăng nhập, còn gateway đọc lại token từ chủ sở hữu. Bản thân config không lưu gì cả:

```dart
// platform/shell/adapters/lib/src/network_config_impl.dart
Future<String?> _refreshSession() async => await _session?.refreshToken();

// modules/auth/data/lib/src/session/auth_session_gateway_impl.dart
@override
Future<String?> refreshToken() async {
  final result = await _repository.refreshToken();
  if (result.isSuccess) return _local.getUserToken();
  final failure = result.errorOrNull;
  if (isTransientFailure(failure)) {
    throw StateError(
      'Session renewal did not reach the server: '
      '${failure?.message}',
    );
  }
  return null;
}

// modules/auth/data/lib/src/session/transient_failure.dart
/// Whether [failure] says nothing about the session's validity — the
/// renewal never got an answer — so the session must be kept.
bool isTransientFailure(AppFailure<dynamic>? failure) {
  if (failure is NetworkFailure) return true;
  if (failure is! ServerFailure) return false;
  final code = failure.code;
  if (code == null) return false;
  return (code >= 500 && code < 600) || code == ErrorCodes.REQUEST_CANCELLED;
}
```

#### Bị từ chối hay không tới được server

Câu trả lời của gateway quyết định số phận của phiên đăng nhập:

| `refreshToken()` | Nghĩa là | `RefreshTokenHandler` |
| :-- | :-- | :-- |
| một token | đã gia hạn | gửi lại request và mọi request đang chờ nó |
| `null` | server **từ chối** (401/403, mọi 4xx, hoặc một 200 mà envelope báo lỗi — `ErrorCodes.RESPONSE_REJECTED`) | gọi `onRefreshFailed` một lần, reject tất cả |
| ném lỗi | không nhận được câu trả lời (mất mạng, HTTP 5xx thật, bị huỷ) — chỉ những trường hợp này | reject tất cả, **giữ nguyên phiên** |

`onRefreshFailed` chính là `NetworkConfigImpl._clearSession`: gateway xoá thông tin đăng nhập đã lưu, rồi `ISessionState.onSessionLost()` đưa bên sở hữu về trạng thái đăng xuất — đúng thay đổi mà `NavigatorWrapperWidget` lắng nghe để chuyển tới màn đăng nhập. Chỉ xoá storage thì người dùng vẫn ở lại màn hình, "đang đăng nhập", mà không có token.

Một `401` tới *sau* khi refresh đã xong — request được gửi bằng token cũ — không khởi động refresh mới: `RefreshTokenHandler` so header `Authorization` của request với `NetworkConfig.getToken` và, nếu khác nhau, chỉ gửi lại request. Với refresh token xoay vòng, một lần refresh thừa có thể làm mất hiệu lực chính phiên vừa được gia hạn.

#### N request 401 đồng thời → chỉ một lần refresh

`RefreshTokenHandler` xếp hàng mọi thứ sau một `Completer`. Request 401 đầu tiên thực hiện refresh; những cái còn lại chờ trên cùng future đó:

```dart
// platform/infra/network/lib/src/handlers/refresh_token_handler.dart
// If a refresh is already in progress, wait for it to complete.
if (_completer != null) {
  final String? newToken = await _completer!.future;
  if (newToken != null) {
    // The token was successfully refreshed, retry the original request.
    return _retryRequest(err, handler);
  } else {
    // The token refresh failed, reject the original request.
    return handler.reject(err);
  }
}
```

Việc `await` lần retry là **cố ý**:

```dart
// `await` keeps the refresh lock (`_completer`) held until the retry
// finishes; releasing it earlier would let a concurrent 401 start a
// second, redundant refresh.
return await _retryRequest(err, handler);
```

Body dạng `FormData` được dựng lại trước khi replay (`RequestOptions.forReplay()`), vì stream của form chỉ đọc được một lần.

#### Ba lớp chống đệ quy vô hạn

```dart
// platform/infra/network/lib/src/interceptors/refresh_token_interceptor.dart
/// Three guards keep the flow from looping:
/// 1. Requests that opted out of auth
///    ([NetworkConstants.EXTRA_NEED_AUTHENTICATION] `= false`) or out of
///    refresh ([NetworkConstants.EXTRA_CAN_REFRESH_TOKEN] `= false`) are
///    ignored, so the login and refresh calls never trigger a refresh.
/// 2. A request already replayed after a refresh is marked with
///    [NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] and is not refreshed a
///    second time.
/// 3. [RefreshTokenHandler] serialises concurrent `401`s behind a single
///    `Completer`, so N failing requests cause exactly one refresh.
```

Lớp 2 tinh tế — cờ được set **trước khi** giao việc, vì bản replay quay lại chính interceptor này:

```dart
// Mark the options *before* handing over: `RefreshTokenHandler` replays
// this same RequestOptions through `dio.fetch`, which re-enters this
// interceptor. The flag makes that second pass fall through to `super`.
err.requestOptions.extra[NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] = true;
```

> [!NOTE]
> Refresh của sample **chính là** một HTTP call qua chính client này (`AuthRemoteDataSource.refreshToken`), nên nó và `login` mang `@Extra({NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false})` (lớp 1); lời gọi refresh còn đặt thêm `EXTRA_CAN_RETRY: false`, vì nó chạy lúc boot và bên trong 401 của request khác nên phải fail nhanh thay vì chờ dialog retry. Khi không có token đã lưu, `AuthRepositoryImpl.refreshToken` trả lời luôn mà không gọi mạng. Thiếu cờ này, một `401` từ chính lời gọi refresh sẽ đi vào `RefreshTokenHandler` trong lúc lần refresh của handler vẫn đang chạy, và chờ chính nó mãi mãi. Endpoint nào của bạn mà `401` mang nghĩa khác "hết phiên" cũng cần cờ này.

### Pinning được cài lúc nào, và khi nào bị bỏ qua

Khi pinning được cài, manifest của app đã quyết định nó, theo từng flavor, và initializer áp dụng quyết định đó — nó không bao giờ im lặng bỏ qua:

```dart
// platform/foundation/common/lib/src/config/app_initializer.dart
switch (profile.facts.sslPinning.decisionFor(flavor)) {
  case PinnedSsl(:final hashes):
    HttpOverrides.global = _MyHttpSecurityPinningHttpOverrides(hashes);
  case DisabledSsl(:final reason):
    // WARNING: "SSL pinning is disabled for flavor <f>: <reason>. Traffic is NOT pinned."
  case null:
    // ERROR naming flavors.<f>.ssl_pinning — unreachable once `validate` (P04) passed
}
```

Nơi pinning áp dụng được hay không là một sự thật của platform (`AppPlatform.canPinTls`: Android và iOS). Trên **web** trình duyệt tự xác thực chứng chỉ và Dio dùng adapter của trình duyệt, nên không cài gì và một dòng `INFO` nói rõ điều đó; trên **desktop** plugin pinning không có implementation, nên một dòng `INFO` ghi "not applicable" thay vì cài một client sẽ đẩy mọi lời gọi HTTPS qua một plugin không có phần desktop. `profile`, `platform` và `flavor` là tham số bắt buộc của `initBeforeRunApp` và `init`: initializer không bao giờ đoán nó chạy ở đâu hay là flavor nào (RULE-82), và không có chế độ không-profile với nguồn pin riêng.

`_setupHttpOverrides` chạy từ `AppInitializer.initBeforeRunApp()`, được `runShellApp` gọi sau các bước kiểm tra profile và hook `beforeDependencies`, và **trước** `configureDependencies()` — nó chỉ đọc profile nên không cần đăng ký gì. Thời điểm là mấu chốt: `IOHttpClientAdapter` của Dio giữ `HttpClient` nó tạo đầu tiên suốt vòng đời của `Dio`, và mọi thứ đồ thị dựng ra đều có thể mở kết nối — một singleton eager khi DI khởi tạo, một implementation contract mà `checkAppContract` resolve ngay sau đó, một controller tạo trên splash (auth khôi phục phiên bằng một lần refresh token). Override cài muộn hơn, sau DI hay trong `initService`, sẽ không bao giờ tới được client đó. `AppInitializer.init` gọi lại `initBeforeRunApp()` cho host nào bỏ qua bước này; lần gọi thứ hai không cài gì. `platform/shell/app_shell/test/boot_order_test.dart` sẽ fail nếu thứ tự bị đảo lại.

Kiểm tra certificate chỉ bị bỏ qua (phục vụ server tự ký cục bộ) **trong bản debug đã khai báo tường minh flavor `dev`** — `AppConfig.bypassesCertificateValidation`. Mọi trường hợp khác đi qua đường pinning: `staging`, `prod`, bản profile hay release của `dev`, và bản build **thiếu hoặc sai** flavor — được coi như `prod` và ghi log mức ERROR. Đây là cố ý fail closed. `AppConfig.appFlavor` (môi trường DI) lùi về `dev` ở bản debug và về `prod` ở các bản còn lại, nhưng việc xử lý certificate đọc `AppConfig.declaredFlavor`, vốn là `null` trừ khi bản build nêu một flavor đã biết.

---

## 7. `core_storage` — lưu trữ key–value có mã hoá

Chỉ cấp **cơ chế**. Không định nghĩa key, không định nghĩa preset nào. Phụ thuộc workspace duy nhất của nó là `platform_kernel` (`TypeHelper`).

| Thành phần export | Mục đích |
|:--|:--|
| `StorageInterface` | `abstract interface class` — hợp đồng cho backend (`init`, `read`, `write`, `delete`, `isValidKey`); không crypto, không `deleteAll` |
| `StorageType` | `pref` (SharedPreferences) · `secure` (có phần cứng hỗ trợ) |
| `EncryptedStorage` | Lớp nền của cả hai backend: các hàm AES-256-CBC (`encryptData` / `decryptData`), các hàm master key, phần chặn key dành riêng và các tuỳ chọn `flutter_secure_storage` được ghim |
| `StorageManager` | `@singleton`; phân giải backend theo `StorageType`, khởi tạo backend secure trước rồi tới các backend khác qua `@PostConstruct(preResolve: true)` — secure đi trước vì lần mở đầu tiên nó xoá sạch namespace keystore, nơi cũng chứa master key của backend pref |
| `StorageValue<T>` | Bọc phản ứng quanh một key — `ChangeNotifier` + `Stream` broadcast, cache trong RAM. `save(T)` và `remove()` trả `Future<void>` hoàn tất khi dữ liệu đã nằm trên đĩa; các lần ghi được **tuần tự hoá** (giá trị set sau cùng là giá trị còn lại trên đĩa) và một lần ghi lỗi được log, không bao giờ throw; setter `value` bắt đầu cùng lần ghi đó mà không chờ. Notify sau `dispose` là no-op (`isDisposed`) |
| `StorageCodec` | Encode / decode / revive JSON của các giá trị mà `StorageValue` lưu |
| `ObfuscatedBytes` | Che dữ liệu trong RAM (`fromString`, `reveal`, `revealString`, `dispose`) |
| `PrefStorageImpl` / `SecureStorageImpl` | Nội bộ, phân giải qua `@Named('Pref')` / `@Named('Secure')` |
| `StorageConstants` | Tên key dành riêng, kích thước master key, số lần thử lại (`src/utils/`) |

`core_storage` cố ý khai báo **zero key**: nó chỉ cấp bộ máy, và mỗi package tự khai giá trị của mình.

> [!NOTE]
> Không có object preset dùng chung và không có sổ đăng ký key tập trung — không `StorageValuePresets`, không `StorageKeyConstants`. Một object gom key của mọi domain sẽ cho phép bất kỳ ai inject nó đọc và ghi dữ liệu của feature khác, nên cơ chế cố ý không cung cấp thứ đó để bạn với tay tới.

### Các lớp mã hoá, và che RAM

**Lớp 1 — AES-256-CBC phần mềm, IV ngẫu nhiên mỗi lần ghi.** Cài đặt một lần trên `EncryptedStorage` nên cả hai backend đều thừa hưởng:

```dart
// platform/infra/storage/lib/src/impl/encrypted_storage.dart
String encryptData(String data) {
  return _withKey((enc) {
    final iv = encrypter.IV.fromSecureRandom(StorageConstants.IV_BYTES);
    return '${iv.base64}:${enc.encrypt(data, iv: iv).base64}';
  });
}
```

IV ngẫu nhiên mỗi lần ghi nghĩa là ghi cùng một giá trị hai lần cho ra hai bản mã khác nhau — người quan sát không thể biết giá trị có đổi hay không. `_withKey` chỉ lộ master key trong khoảnh khắc gọi rồi xoá về 0 các buffer.

**Lớp 2 — phần cứng.** Master key 256-bit nằm trong Keychain/KeyStore dưới tên `_internal_master_key`, sinh ra ở lần chạy đầu tiên:

```dart
// platform/infra/storage/lib/src/impl/secure_storage_impl.dart
if (masterKey == null) {
  // Generate a new 32-byte (256-bit) random key for AES
  final newKey = EncryptedStorage.generateKey();
  try {
    await _storage.write(
      key: StorageConstants.SECURE_MASTER_KEY_ID,
      value: newKey,
    );
    masterKey = newKey;
  } catch (e) {
    // … đã ghi log
    rethrow;
  }
}
```

**Che RAM.** Cả master key lẫn giá trị trong cache đều không nằm trong bộ nhớ dưới dạng byte đọc được. Cả hai bị XOR với một mask ngẫu nhiên và chỉ lộ ra đúng khoảnh khắc được dùng — `StorageValue` giữ giá trị trong RAM dưới dạng `ObfuscatedBytes`, và master key cũng được xử lý y hệt:

```dart
// platform/infra/storage/lib/src/obfuscated_bytes.dart
class ObfuscatedBytes {
  ObfuscatedBytes(List<int> original)
    : _mask = _randomMask(original.length),
      _masked = Uint8List(original.length) {
    for (var i = 0; i < original.length; i++) {
      _masked[i] = original[i] ^ _mask[i];
    }
  }
```

Điều này nâng rào chắn trước tấn công đọc memory dump; nó không thay thế các lớp ở trên.

#### Khi Keychain trục trặc — thử lại, không bao giờ xoá sạch

Việc đọc master key có thể lỗi vì những lý do nhất thời: Keychain trước lần mở khoá đầu tiên sau khi khởi động lại máy (app được mở nền), KeyStore đang bận. Vì vậy `SecureStorageImpl` không bao giờ coi một lỗi platform là hỏng dữ liệu và không bao giờ xoá sạch kho — master key của `PrefStorageImpl` nằm trong cùng kho, nên xoá sạch sẽ phá luôn mọi preference. Việc thử lại là `EncryptedStorage.readKeyWithRetry`, dùng chung cho cả hai backend:

```dart
// platform/infra/storage/lib/src/impl/encrypted_storage.dart
static Future<String?> readKeyWithRetry(
  FlutterSecureStorage storage,
  String keyId, {
  required Duration retryDelay,
  required String tag,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await storage.read(key: keyId);
    } catch (e) {
      final lastAttempt = attempt >= StorageConstants.MASTER_KEY_READ_ATTEMPTS;
      // … ghi log: WARNING khi thử lại, ERROR ở lần cuối …
      if (lastAttempt) rethrow; // không xoá gì, không sinh key mới
      await Future<void>.delayed(retryDelay * attempt);
    }
  }
}
```

| Lỗi | Điều xảy ra |
| :-- | :-- |
| Lỗi platform khi đọc master key | thử lại (3 lần); nếu vẫn lỗi, `init` **ném lại lỗi** và kho giữ nguyên — sinh key mới sẽ bỏ rơi mọi giá trị đã mã hoá bằng key không đọc được |
| Master key có nhưng không dùng được (không phải key base64 256-bit) | chỉ thay key đó; các giá trị mã hoá bằng nó sẽ giải mã lỗi và bị `read()` xoá từng cái một |
| Hỏng dữ liệu trong chính storage của plugin | xử lý ở tầng native: trên Android `AndroidOptions.resetOnError` (bật mặc định) reset phần không giải mã được trước khi trả kết quả |
| Lỗi platform trong `read(key)` | trả `null` **và giữ nguyên giá trị** — lần đọc sau vẫn còn |
| Giá trị giải mã hoặc decode lỗi trong `read(key)` | chỉ xoá đúng key đó và trả `null`, để một dòng hỏng không làm chết mọi lần mở app |

#### Master key của backend pref — cùng một quy tắc

`PrefStorageImpl` mã hoá giá trị SharedPreferences bằng master key riêng, `_internal_pref_master_key`, cất trong cùng kho bảo mật. Nó không bao giờ thay một key có thể vẫn còn tốt — một key mới sẽ bỏ rơi mọi preference đã lưu (theme, ngôn ngữ, cờ onboarding), và `read()` xoá giá trị nào nó không giải mã được:

| Tình huống | `PrefStorageImpl.init` làm gì |
| :-- | :-- |
| Lỗi platform khi đọc key | thử lại (3 lần) trước khi quyết định bất cứ điều gì |
| Vẫn lỗi, chưa có preference nào được lưu | giữ một key mới trong SharedPreferences — không có gì để bỏ rơi |
| Vẫn lỗi, và key trong SharedPreferences mở được các preference đã lưu | dùng key đó (thiết bị không có kho bảo mật dùng được) |
| Vẫn lỗi, và các preference đã lưu phụ thuộc vào key không đọc được | **ném lại lỗi**, không ghi hay xoá gì — các giá trị mở lại được khi platform hồi phục |
| Đọc được lại trong khi vẫn còn key trong SharedPreferences | key nào giải mã được các giá trị đã lưu thì thắng; nếu key trong SharedPreferences thắng, nó được chuyển vào kho bảo mật và xoá khỏi SharedPreferences |
| Key không có hoặc không dùng được (không phải key base64 256-bit) | sinh key mới — trong kho bảo mật, hoặc trong SharedPreferences nếu kho bảo mật từ chối ghi; giá trị mã hoá bằng key đã mất sẽ bị `read()` xoá từng cái một |

`StorageManager.initialize` chạy backend secure trước, nên một lỗi Keychain kéo dài thường lộ ra ở đó trước khi tới lượt backend pref. Test (`platform/infra/storage/test/storage_test.dart`) chạy cả hai backend qua một bản giả `FlutterSecureStorage` chập chờn.

#### Tuỳ chọn cipher của plugin được ghim cố định

Cả hai backend mở `flutter_secure_storage` (11.x) với cùng một cặp Android tường minh — `KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding` và `StorageCipherAlgorithm.AES_GCM_NoPadding` — và `KeychainAccessibility.first_unlock` trên iOS. Trên Android, plugin ghi lại cặp nó đã dùng để ghi và, khi cặp được cấu hình khác đi, sẽ mã hoá lại toàn bộ store (`migrateOnAlgorithmChange`, mặc định bật) hoặc, nếu không được, reset nó (`resetOnError`, cũng bật). Đừng đổi hai tuỳ chọn này trừ khi bạn thật sự muốn migrate dữ liệu bảo mật của mọi người dùng.

Cặp này là thứ template đã ghi từ bản phát hành đầu tiên (10.x) và vẫn là mặc định của 11.x, nên nâng cấp 10 → 11 đọc được giá trị cũ nguyên vẹn: cùng alias KeyStore, cùng khoá đã bọc, không có bước migrate. Cái 11.x bỏ đi là các cipher trước 10 (RSA-PKCS1, AES-CBC, EncryptedSharedPreferences). App nào từng phát hành `flutter_secure_storage` 9.x trở xuống phải phát hành một bản 10.x trước — thiết bị nhảy thẳng từ 9 lên 11 sẽ mất giá trị bảo mật, gồm cả token và master key của `PrefStorageImpl`. Trên Android, `FlutterSecureStorage.checkUpgradeStatus()` (11.1+), gọi trước lần đọc đầu tiên, báo cho bạn biết điều đó có xảy ra hay không.

### Quyền sở hữu

Mỗi package tiêu thụ tự khai `StorageValue` của mình qua `StorageManager` được inject, key đặt trong `utils/` của package đó (RULE-44). Các chủ sở hữu hiện tại:

| Chủ sở hữu | Package | Key | Backend |
|:--|:--|:--|:--|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | secure |
| `ThemeStorageImpl` | `platform_shell_adapters` | `themeMode` | pref |
| `LanguageStorageImpl` | `platform_shell_adapters` | `locale` | pref |
| `AppBootStorage` | `platform_shell_adapters` | `viewed_onboard` | pref |

Các class key của app shell nằm trong `platform/shell/adapters/lib/src/utils/`. Xem [`../guides/06_storage.md`](../guides/06_storage.md) để có các bước cụ thể.

---

## 8. `core_database` — lưu trữ quan hệ (Drift + SQLite)

Chạy trên isolate nền qua `NativeDatabase.createInBackground`. **Không phụ thuộc package nào khác** trong workspace.

Package này **chỉ cấp cơ chế**: nó không sở hữu database, bảng hay DAO nào, và DI module của nó không đăng ký gì cả (RULE-46). Package nào cần lưu dữ liệu quan hệ thì tự khai **database của chính mình** ngay cạnh bảng, DAO và data source của nó, rồi mở database đó bằng các mảnh ghép dưới đây. `CacheDatabase` của module mẫu `cache` (`modules/cache/data/lib/src/database/`) là bản đấu nối tham chiếu.

Đây là ràng buộc của Drift, không phải sở thích. `@DriftDatabase(tables: [...])` được phân giải ở **compile time** — không có đăng ký bảng lúc runtime — và DAO buộc phải là **`part of`** thư viện database của nó. Package nào khai database thì buộc phải gọi tên mọi bảng trên database ấy, nên một `AppDatabase` dùng chung sẽ buộc một package phải biết bảng của tất cả package còn lại. Dời nó lên `apps/mobile/` chỉ di chuyển god object đó; cho mỗi package một database riêng mới cắt được sự phụ thuộc.

| | |
|---|---|
| **Được** | Xoá package là xoá luôn database của nó; không gì khác tham chiếu tới. |
| **Được** | Không package nào chạm được bản ghi của package khác — không có object dùng chung để mà chạm. |
| **Trả giá** | **SQL không JOIN xuyên ranh giới package.** Vượt bounded context là việc của tầng repository — ghép hai repository trong một use case — chứ không phải nhét vào một truy vấn. |

| Export | Loại | Ở đâu | Làm gì |
|---|---|---|---|
| `DriftDatabaseOpener` | `abstract final class` | `src/drift_database_opener.dart` | Mở bất kỳ `GeneratedDatabase` nào trên isolate nền, **verify** kết nối, cách ly file hỏng |
| `DatabaseConnectionFactory` | `abstract final class` | `src/database_connection_factory.dart` | Phân giải đường dẫn file trong app documents, dựng executor nền, cách ly file |
| `IDatabaseMigration<TDb>` | abstract class | `src/migration/` | Hợp đồng để một package đóng góp **một** bước schema |
| `DatabaseMigrationRunner` | class | `src/migration/` | Sắp xếp, kiểm tra và replay các bước đó |
| `driftMigrationStrategy(...)` | function | `src/migration/` | `MigrationStrategy` dùng chung: dispatch migration + các `PRAGMA` theo kết nối |
| `IDatabaseHandle<TDb>` / `DatabaseHandle<TDb>` | abstract class / class | `src/access/` | Cách một data source chạm tới database mà không cầm toàn bộ DAO |
| `DatabaseConstants` | class | `src/utils/database_constants.dart` | Kích thước read pool, busy timeout, marker lỗi hỏng/môi trường, hậu tố `.corrupt` |

Mọi thứ ở trên đều generic theo `GeneratedDatabase`: `core_database` không bao giờ gọi tên một class database cụ thể — đó chính là điểm mấu chốt.

### Hai hợp đồng giữ các package không chạm bảng của nhau

**`IDatabaseMigration`** — package nào đổi schema thì hiện thực hợp đồng này ngay cạnh bảng của mình và đăng ký trong DI module của chính nó, y như cách feature đóng góp route. `version` là phiên bản schema mà bước đó *tạo ra*; các bước được phát lại theo thứ tự nên thiết bị bỏ lỡ vài bản phát hành vẫn về đúng schema. Trùng version bị từ chối ngay lúc khởi động thay vì âm thầm chạy một cái.

**`IDatabaseHandle`** — data source xin đúng accessor mình cần thay vì nhận một object database kèm toàn bộ DAO trên đó:

```dart
ProfileLocalDataSource(IDatabaseHandle<ProfileDatabase> handle)
  : _dao = handle.accessor(ProfileDao.new);
```

> [!NOTE]
> Trong phạm vi **một** database, đây là **cô lập ở mức bề mặt API, không phải cô lập cưỡng chế**: callback factory vẫn nhận được object database, nên một bên gọi cố tình vẫn với tới được mọi DAO trên đó. Giá trị nằm ở chỗ vượt qua ranh giới trở thành hành động cố ý và nhìn thấy được khi review, chứ không phải một tham số constructor bình thường. Cô lập *giữa các package* mới là rào chắn thật, và nó do đồ thị package cưỡng chế — package nào không khai `data_cache` thì thậm chí không gọi được tên `CacheDatabase`.

Cách tạo database riêng cho một package, đóng góp migration và test nó: [`../guides/07_database.md`](../guides/07_database.md). Cơ chế bên trong được trình bày dưới đây.

### Runner migration replay thế nào

```dart
// platform/infra/database/lib/src/migration/database_migration_runner.dart
Future<void> run(Migrator m, int from, int to) async {
  if (from == to) return;

  if (to > from) {
    for (final migration in _migrations) {
      if (migration.version > from && migration.version <= to) {
        await migration.upgrade(m);
      }
    }
    return;
  }

  // A downgrade from a schema this build has no step for is refused.
  final newestKnown = _migrations.isEmpty ? null : _migrations.last.version;
  if (newestKnown == null || newestKnown < from) {
    throw UnsupportedError('Cannot downgrade the schema from version $from …');
  }

  for (final migration in _migrations.reversed) {
    if (migration.version > to && migration.version <= from) {
      await migration.downgrade(m);
    }
  }
}
```

Bốn tính chất đáng gọi tên:

1. **Dùng `if` thuần, không phải `else if`.** Thiết bị bỏ lỡ vài bản phát hành sẽ replay *mọi* bước trung gian thay vì nhảy thẳng tới hình dạng mới nhất.
2. **Upgrade chạy tăng dần, downgrade chạy giảm dần.** Thứ tự quan trọng ở cả hai chiều.
3. **Khoảng trống version là hợp lệ.** Một bản phát hành có thể không đổi schema, để trống số version đó.
4. **Downgrade cần bước tường minh.** Đi từ `from` xuống `to` sẽ ném `UnsupportedError` trừ khi có một bước đăng ký cho version `from` trở lên — runner phải biết schema mà nó đang rời bỏ. Thiếu kiểm tra này, runner không làm gì cả và drift đóng dấu `user_version` thấp hơn lên các bảng vẫn mang hình dạng mới; cài lại bản mới hơn sau đó sẽ replay các bước upgrade trên chúng (trùng cột) và lỗi ở mọi lần khởi động. Lỗi ném ra giữ nguyên file và version của nó, và `DriftDatabaseOpener` báo nó như lỗi khởi động thay vì cách ly file. Trên thực tế một bản cũ chỉ có các bước đó nếu chúng được phát hành trước thay đổi mà chúng đảo ngược — ngoài ra, cài bản cũ đè lên schema mới hơn là không được hỗ trợ.

Việc kiểm tra diễn ra một lần, lúc khởi tạo — không phải giữa chừng migration. Phát hiện lỗi wiring khi đã chạy được nửa đường sẽ để lại schema migrate dở.

> [!WARNING]
> **Drift 2.x KHÔNG có `onDowngrade`.** `MigrationStrategy` chỉ expose `onCreate`, `onUpgrade` và `beforeOpen`; chính tài liệu Drift ghi rằng "schema version upgrades and downgrades will both be run here". `IDatabaseMigration.downgrade` là thật và có test, nhưng nó đi nhờ trên đúng một entry point đó thông qua so sánh `from`/`to`. Hãy implement khi thay đổi có thể đảo ngược; **ném lỗi có mô tả rõ ràng khi không thể**, để thất bại là tường minh thay vì để lại một schema không còn khớp với code đang chạy.

### Các `PRAGMA`, và vì sao chúng được tập trung hoá

`PRAGMA` là thiết lập **theo từng kết nối và không được lưu trong file**, nên phải áp lại mỗi lần mở. Đó là lý do chúng nằm trong `beforeOpen`:

```dart
// platform/infra/database/lib/src/migration/drift_migration_strategy.dart
beforeOpen: (OpeningDetails details) async {
  // SQLite ships with foreign key enforcement OFF. Without this any
  // `references()` declared on a table is silently ignored, so broken
  // relations are only discovered as corrupt data much later.
  await database.customStatement('PRAGMA foreign_keys = ON');

  // Write-Ahead Logging lets readers run concurrently with a writer,
  // which a read pool (readPool > 0) requires, and avoids "database is locked"
  // under contention.
  await database.customStatement('PRAGMA journal_mode = WAL');

  // Wait for a held lock instead of failing instantly with SQLITE_BUSY.
  await database.customStatement('PRAGMA busy_timeout = $busyTimeoutMs');
},
```

| Pragma | Vì sao quan trọng |
|---|---|
| `foreign_keys = ON` | **SQLite mặc định TẮT cái này.** Mọi `references()` bạn khai đều bị bỏ qua âm thầm nếu thiếu nó — một cái bẫy im lặng, chỉ lộ ra rất lâu sau dưới dạng quan hệ hỏng. |
| `journal_mode = WAL` | Cho phép reader chạy đồng thời với writer. Bắt buộc khi có read pool (`readPool > 0`; mặc định là `1`); tránh lỗi "database is locked" khi tranh chấp. |
| `busy_timeout = 5000` | Chờ khoá được nhả thay vì fail ngay với `SQLITE_BUSY`. Mặc định là `0`. |

`beforeOpen` chỉ chạy trên connection **writer**. Read pool — mỗi reader là một connection riêng trên isolate riêng — không bao giờ thấy nó, nên `DatabaseConnectionFactory` còn truyền cho drift một callback `setup` đặt `busy_timeout` trên mọi connection mà drift mở (`platform/infra/database/test/database_connection_factory_test.dart` đọc lại giá trị qua một reader). `journal_mode` không cần vậy: WAL được lưu trong file. `foreign_keys` chỉ được kiểm khi ghi, mà thao tác ghi không bao giờ tới reader.

WAL sinh thêm file sidecar `-wal` và `-shm` cạnh database. SQLite tự chuyển đổi file có sẵn, an toàn và đảo ngược được. Database in-memory (trong test) bỏ qua thiết lập này và ở nguyên journal mode `memory` — chính vì vậy test WAL trong `data_cache` phải chạy trên **file thật**.

Tập trung hoá vì đúng một lý do: một package tự viết `MigrationStrategy` riêng mà quên `foreign_keys = ON` sẽ mất toàn vẹn tham chiếu mà không có lỗi nào báo.

### Phục hồi khi hỏng: cách ly, không bao giờ xoá

Việc mở database được đăng ký với `@preResolve`, nên bất cứ thứ gì ném ra ở đó đều làm hỏng `configureDependencies()` và app không khởi động được. Một file hỏng đồng nghĩa vòng lặp crash vĩnh viễn.

`DriftDatabaseOpener.open` xử lý việc này — và thiết kế nghiêng hẳn về phía *không* đụng vào dữ liệu người dùng:

```dart
// platform/infra/database/lib/src/drift_database_opener.dart
static Future<T> open<T extends GeneratedDatabase>(
  DriftDatabaseBuilder<T> build, {
  required String fileName,
  int readPool = DatabaseConstants.DEFAULT_READ_POOL,
}) async {
  try {
    return await _openVerified(build, fileName: fileName, readPool: readPool);
  } catch (error, stackTrace) {
    if (!isCorruptionError(error)) rethrow;
    // ... quarantine, then reopen empty
  }
}
```

Ba quyết định có chủ đích:

**Kết nối được verify, không phải giả định.** `createBackgroundExecutor` là lazy — nó không chạm vào file cho tới statement đầu tiên. `_openVerified` chạy một truy vấn thăm dò `SELECT 1` để database hỏng lộ ra *ngay tại đây* thay vì ở một call site vô can nào đó sau này.

**File được đổi tên, không bao giờ bị xoá.**

```dart
// platform/infra/database/lib/src/database_connection_factory.dart
/// The file is **renamed, never deleted** — if the corruption check ever
/// misfires the user's bytes are still recoverable from
/// `<fileName><CORRUPT_FILE_SUFFIX>`. Only one quarantined copy is kept;
/// an older one is replaced so repeated failures cannot fill the disk.
```

Các sidecar `-wal` / `-shm` được chuyển theo, thành `<fileName>.corrupt-wal` / `.corrupt-shm`: chúng thuộc về database đã bị cách ly và không được áp vào database mới, còn WAL chứa các transaction đã commit mà chưa checkpoint — xoá nó là mất đúng phần dữ liệu mới nhất.

**Marker môi trường phủ quyết kết luận "hỏng file".**

```dart
@visibleForTesting
static bool isCorruptionError(Object error) {
  final message = error.toString().toLowerCase();

  final looksLikeEnvironment = DatabaseConstants.ENVIRONMENT_ERROR_MARKERS
      .any(message.contains);
  if (looksLikeEnvironment) return false;

  return DatabaseConstants.CORRUPTION_ERROR_MARKERS.any(message.contains);
}
```

| Coi là hỏng file → cách ly | Coi là lỗi môi trường → ném lại, không đụng |
|---|---|
| `database disk image is malformed` | `unable to open database file` |
| `file is not a database` | `disk i/o error` |
| `file is encrypted or is not a database` | `database or disk is full` |
| `malformed database schema` | `attempt to write a readonly database` |
| | `access denied` / `permission denied` / `operation not permitted` |

Predicate khớp theo chuỗi thông báo thay vì bắt `SqliteException` có kiểu. `sqlite3` *có* là dependency được khai báo của `core_database` (connection factory import nó), nên kiểu này dùng được — nhưng nó không phải thứ tới được opener. Kết nối chạy trên một background isolate (`NativeDatabase.createInBackground`), và drift trả lỗi phát sinh ở đó về dưới dạng `DriftRemoteException`, với lỗi gốc nằm trong `remoteCause`; `on SqliteException` sẽ không bao giờ khớp. `DriftRemoteException.toString()` trả về thông báo của lỗi gốc, nên khớp theo thông báo bao được lỗi từ cả hai phía ranh giới isolate. Kiểm tra theo kiểu vẫn làm được — gỡ `remoteCause` rồi kiểm tra `SqliteException` và `extendedResultCode` của nó — nhưng vẫn cần khớp chuỗi làm dự phòng cho mọi trường hợp khác. Vì khớp chuỗi vốn mong manh, predicate được thiết kế **thiên về không phục hồi**: nếu xuất hiện marker môi trường thì database được để yên, kể cả khi marker hỏng file cũng khớp.

Mất dữ liệu người dùng tệ hơn là báo lỗi lúc khởi động.

---

## 9. `core_notifications` — thông báo đẩy và cục bộ

`PushNotificationService` bọc Firebase Messaging và `flutter_local_notifications`. Channel ID và loại payload nằm ở `src/utils/notification_constants.dart`, tức ngay trong package tiêu thụ chúng — một channel ID thông báo không có lý do gì để mọi package trong app đọc được.

Khởi động không bao giờ chờ người dùng hay mạng: `init()` (được await bên trong `configureDependencies()`) chỉ thiết lập Firebase, các channel, listener và plugin local-notifications. Việc đăng ký FCM token chạy sau đó, không await, và ghi log lỗi thay vì throw — hãy đọc token từ `tokenStream`, vì `fcmToken` có thể vẫn là `null` ngay sau khi khởi động. Xin quyền là **opt-in**: không có gì hiện hộp xin quyền lúc khởi động, app tự gọi `PushNotificationService.requestPermission()` ở chỗ nó muốn hỏi (hàm này đăng ký lại token). Một platform khai `push: false` (`platforms.<p>.push`, đọc qua `PlatformFacts`) khiến `init()` trả về trước khi đụng tới Firebase và các hàm còn lại thành no-op. Loại payload bị chặn (`addBlockedTypes` / `removeBlockedTypes`) so khớp không phân biệt hoa thường. Dòng tóm tắt và tiêu đề của inbox gộp do app cung cấp (`inboxSummaryBuilder` / `inboxTitleBuilder`, mặc định đều `null`) để chữ đến từ localization của chính app.

Service này là `@singleton` eager inject `FirebaseOptions`, mà mỗi app tự đăng ký từ `lib/firebase/firebase_module.dart` của mình. Vì thế manifest của app đặt `core_notifications` trong nhóm `notifications` với `phase: after` thay vì trong `core`: `before` chạy trước phần đăng ký của chính app. App không dùng push notification thì bỏ nhóm này đi.

---

## 10. State management — hai nhánh, **chưa ngang bằng nhau**

Template hỗ trợ Provider và BLoC. Cần biết trước khi chọn: giờ cả hai đều tự động hoá đường tải → chốt kết quả, nhưng nhánh Provider vẫn có nhiều thứ đi kèm hơn hẳn. Chọn mà không biết chúng khác nhau ở đâu là nguyên nhân bực bội phổ biến nhất.

| | `provider_state_management` | `bloc_state_management` |
|:--|:--|:--|
| Lớp nền | `BaseProvider<T>` — hiện thực đầy đủ | `BaseBloc<Event, State>` / `BaseCubit<State>` — *chỉ là điểm mở rộng, không thêm gì so với `Bloc` / `Cubit`* |
| Máy móc dùng chung | Đầy đủ: `StateManager`, `OperationExecutor`, `LoadMoreMixin`, `ensureInitialized` | `BlocResultMixin` / `CubitResultMixin` (`emitResult`) — ngoài ra không có gì |
| Trợ giúp bất đồng bộ / bóc `Result<T>` | `executeOperation(OperationConfig(...))` tự lo loading/success/failure | `emitResult` từ `BlocResultMixin<T>` / `CubitResultMixin<T>` — tương tự, **nhưng chỉ cho state `BlocViewState<T>`**; tự viết với state tuỳ biến |
| Map `AppFailure` → lỗi UI | Hook `errorStateBuilder` | Không có — `error(AppFailure)` giữ nguyên failure; map trong view, hoặc tự map vào state tuỳ biến |
| Trạng thái loading | Tự động set (bỏ qua khi đã có dữ liệu) | `emitResult` tự emit (bỏ qua khi đang hiển thị `success`) |
| Thao tác **ném exception** | Lan ra ngoài — chính `execute()` của repository mới đổi exception thành `Result.failure` | `emitResult` bắt lại: `ErrorHandler.handleError` → `error(...)`, lỗi gốc đi vào `addError` (`BlocObserver.onError`) |
| Hook toàn cục | `OperationGlobalConfig` (`onStart`/`onSuccess`/`onFailure`/`onFinish`) | Không có |
| Phân trang | `LoadMoreMixin` | Không có |
| Kiểu state | `ViewStateModel<T>` bọc `ViewState` (5 nhánh, có `loadingMore`, data nằm ở model) | `BlocViewState<T>` (tuỳ chọn; 4 nhánh, tự mang payload) hoặc state Freezed tự định nghĩa |
| Dạng lỗi | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — bắt buộc |
| Render | `BaseViewWidget`, `LoadMoreListView` | `BlocBuilder` (của `flutter_bloc`) |
| Side effect khai báo | `ProviderStateListener` / `MultiProviderStateListener` | `BlocListener` (của `flutter_bloc`) |

> [!WARNING]
> `emitResult` (`platform/state/bloc/lib/src/result_emitter.dart`) lo cho Bloc hoặc Cubit có state là `BlocViewState<T>`: loading, bóc `Result`, `none`/`cancel` hoàn tác loading của chính nó, exception đi qua `ErrorHandler`. Bloc dùng **state Freezed riêng** vẫn tự bóc `Result<T>` và tự emit loading/kết thúc trong từng handler, và nhánh BLoC không có bản tương ứng cho `OperationGlobalConfig`, `errorStateBuilder` hay `LoadMoreMixin`. `bloc_state_management` phụ thuộc `platform_kernel` để dùng `ErrorHandler` — một cạnh platform → platform, không phải một trong các ngoại lệ `→ domain_core`.

### `BlocViewState<T>`

Kiểu state của BLoC là `BlocViewState<T>`, **không phải** `ViewState`. Cả hai package đều export từ barrel công khai, và nhánh Provider export một `ViewState` khác hẳn về ngữ nghĩa. Chính cái tên riêng biệt này cho phép một file import cả hai barrel mà không đụng tên lúc biên dịch. Hai kiểu này thực sự khác nhau:

| | `ViewState` (Provider) | `BlocViewState<T>` |
|---|---|---|
| Generic | Không | Có |
| Số variant | 5 (thêm `loadingMore`) | 4 |
| Mang data | Không — data nằm ở `ViewStateModel<T>` | Có — `success(T data)` |
| Kiểu lỗi | `error({ErrorState? error})`, nullable | `error(AppFailure error)`, bắt buộc |

`BlocViewState` là **tuỳ chọn**. Màn hình có nhu cầu phức tạp hơn thì tự khai state Freezed riêng và dùng `BaseBloc<Event, CustomState>`.

`OperationGlobalConfig` phơi getter chỉ-đọc, và `setup()` gộp theo từng hook: hook nào lần gọi thứ hai bỏ qua (hoặc truyền `null`) thì giữ giá trị cũ, còn hook nào được truyền thì **thay thế** giá trị cũ — mỗi hook giữ một callback, hai lần gọi không bao giờ nối chuỗi. Vì vậy `null` không xoá được hook; `reset()` xoá tất cả, và tồn tại cho test.

Cách dùng thực tế cho cả hai nhánh: [`../guides/03_state_management.md`](../guides/03_state_management.md).

---

## 11. Build web — hiện trạng

Chưa app nào commit thư mục `web/`. `apps/admin` khai platform web với `runner: scaffold` (thư mục được tạo bằng `flutter create --platforms=web .`); `apps/mobile` không khai nó. Đo bằng `flutter build web`:

| App | Biên dịch |
|:--|:--|
| `apps/admin` (auth + settings) | có, sau khi tạo `web/` (dart2js; Wasm dry run cũng qua) |
| `apps/mobile` (mọi module mẫu) | **không** — `core_database` import `package:drift/native.dart`, kéo theo `dart:ffi` của `sqlite3` |

`flutter build web` không có tuỳ chọn `--flavor`: hãy nêu flavor bằng `--dart-define=APP_FLAVOR=<flavor>`, nếu không `AppConfig.appFlavor` là `dev` ở bản debug và `prod` ở các bản còn lại. App web cũng cần secure context (`https` hoặc `localhost`) cho kho WebCrypto của `flutter_secure_storage`.

Điều gì giúp đường boot dùng chung an toàn trên web:

- `dart:io` **biên dịch được** trên web; chỉ *gọi* phần lớn API của nó mới lỗi. Platform được đọc ở đúng một chỗ, `resolveAppPlatform()`, và các quyết định lúc boot đến từ `PlatformFacts` mà app đã khai (splash bằng Dart là chế độ `splash` của platform, không phải một nhánh theo `Platform.isIOS` — RULE-82). `GoRouteDataCustom.buildPage` bọc mọi page trong `RouteAwareWidget` trên mọi platform, nên analytics màn hình cũng chạy trên web, và trên web chỉ khác ở loại page (một `MaterialPage` thường, vì trình duyệt lo phần chuyển cảnh), `MainScope` bỏ qua `FlutterNativeSplash.remove()`, còn `core_network` chỉ dùng `dart:io` cho hằng tên header và phép kiểm tra `is SocketException` — bản thân Dio tự chuyển sang adapter của trình duyệt.
- `AppInitializer` **không** cài `HttpOverrides` trên web và ghi log một lần, mức `INFO`, rằng trình duyệt tự xác thực chứng chỉ: trình duyệt nắm TLS, nên cả pinning lẫn bypass của flavor dev đều không áp dụng được. Trong test, truyền `platform: AppPlatform.web` cho `initBeforeRunApp`.

Các lỗ hổng đã biết:

- `apps/mobile` cần database cho web trước khi biên dịch được: `WasmDatabase` của drift (asset `sqlite3.wasm` + drift worker), mở qua conditional import trong connection factory của `core_database`.
- `core_notifications` (chỉ `apps/mobile`) khởi tạo Firebase bằng options theo flavor của app, vốn không mô tả web app nào; `push` mặc định tắt trên web.

---

## 12. Bản đồ phụ thuộc

Chỉ liệt kê phụ thuộc cục bộ (trong workspace) — bỏ qua package từ pub.dev. Package nào thuộc nhóm nào, và các nhóm được phụ thuộc theo chiều nào: [§ 0](#package-nằm-ở-đâu--sáu-nhóm).

| Package | Phụ thuộc |
|:--|:--|
| `domain_core` | *(không có)* |
| `core_database` | *(không có)* |
| `core_di` | *(không có)* |
| `core_responsive` | *(không có)* |
| `platform_kernel` | `domain_core` *(ngoại lệ đã duyệt — `ErrorHandler` sinh ra `AppFailure`)* |
| `core_common` | `platform_kernel`, `core_di` |
| `core_network` | `platform_kernel` |
| `core_notifications` | `platform_kernel` |
| `core_storage` | `platform_kernel` |
| `data_core` | `platform_kernel`, `domain_core` |
| `core_base_ui` | `core_common`, `core_di`, `core_responsive`, `platform_kernel` |
| `bloc_state_management` | `platform_kernel`, `domain_core` *(ngoại lệ đã duyệt — `AppFailure` cho `BlocViewState.error`)* |
| `provider_state_management` | `core_base_ui`, `core_common`, `domain_core` *(ngoại lệ đã duyệt)* — `core_responsive` là dev dependency, cho test của nó |
| `core_ui_kit` | `core_base_ui`, `core_responsive` |
| `platform_shell_adapters` | `core_base_ui` (`LanguageSet`), `core_common`, `core_di`, `core_network`, `core_storage`, `core_ui_kit` (`RetryDialog`, `AppOverlay`) |
| `platform_app_shell` | `core_base_ui`, `core_common`, `core_di`, `core_network`, `core_responsive`, `core_ui_kit`, `provider_state_management`, `platform_shell_adapters` |

Không mũi tên nào trong bảng này trỏ tới `modules/*/feature` hay `modules/*/data` — đó là bất biến cần giữ.
