# Tầng Core

Tài liệu này trả lời câu hỏi **"trong `packages/core/*` có gì, và khi nào thì dùng package nào?"**. Đọc xong bạn sẽ chọn đúng core package cho từng việc — và nhận ra khi nào thứ bạn định thêm vào thực ra *không* thuộc về core.

Core là **hạ tầng**. Nó cung cấp cơ chế; nó không mã hoá nghiệp vụ, và không biết feature nào tồn tại.

---

## 0. Ba luật chi phối mọi package core

**Core không được phụ thuộc feature hay data.** Có bốn ngoại lệ đã duyệt, liệt kê ở [phần tổng quan](01_overview.md#các-ngoại-lệ-đã-được-duyệt). `tools/arch_check/check.dart` cưỡng chế danh sách này ở mọi PR.

**Core cấp cơ chế, không cấp chính sách.** `core_storage` cho bạn `StorageValue<T>`; nó không quyết định rằng tồn tại một key tên `token`. `core_database` cho bạn kết nối và hợp đồng migration; nó không biết ý nghĩa nghiệp vụ của bảng. Hễ một package core bắt đầu gọi tên một khái niệm domain cụ thể, cái tên đó thuộc về chỗ khác.

**Mọi package giữ constants trong thư mục `utils/` của chính nó.** Một ngoại lệ đã duyệt: design token trong `core_base_ui/src/styles/` giữ nguyên vị trí — xem [`core_base_ui`](#3-core_base_ui--design-system) bên dưới.

---

## 1. `core_common` — nguyên thuỷ dùng chung

Đáy của ngăn xếp. Không phụ thuộc package cục bộ nào; mọi thứ khác đều có thể phụ thuộc nó.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Config | `src/config/` | `AppConfig` (flavor, design size, base URL, locale mặc định), `AppInitializer` (HttpOverrides, log, hướng màn hình, system UI), `SslPinningConfig` |
| Lỗi | `src/error/` | `AppFailure` (union Freezed), `ErrorHandler.handleError()`, các kiểu exception |
| Extension | `src/extensions/` | `bool`, `DateTime`, `Dio`, `Enum`, `List`, `num`, `String` |
| Mixin | `src/mixins/` | `LifecycleMixin`, `NetworkMixin`, `LoadMoreControllerBinding` |
| Trợ giúp routing | `src/routing/` | `GoRouteDataCustom`, `RouteAwareWidget`, page transition |
| Utils **và constants** | `src/utils/` | `ApiStatusConstants`, `EnvConstants`, `AppUtils`, `Debounce`, `MessageQueue`, `DownloadImage`, `formatters/`, `helpers/` (`TypeHelper`, `ValidationHelper`, `JsonConverters`, `AppInfoHelper`), `dialog/` |
| Firebase | `src/firebase/` | `FirebaseModule` cấp `FirebaseOptions` theo từng flavor |

### Những gì đã bị gỡ khỏi đây, và vì sao

`core_common` từng có thư mục `constants/` đã trở thành **god object** — một chỗ duy nhất, mọi package import được, liệt kê hằng số thuộc về từng domain riêng lẻ. Bốn file đã bị gỡ:

| Đã gỡ | Số phận | Lý do |
|:--|:--|:--|
| `StorageKeyConstants` | xoá | Liệt kê chung `TOKEN`, `AUTH_USER`, `LOCALE`, `THEME_MODE`, `VIEWED_ONBOARD`. Mọi package đọc được key storage của mọi feature khác. Key nay nằm cùng chủ sở hữu — xem [hướng dẫn storage](../guides/06_storage.md). |
| `ApiConstants` | chuyển → `AuthApiConstants` | Chứa `/user/login`, `/user/register`, `/user/refresh-token`… — endpoint chỉ thuộc auth. Nay ở [`packages/data/auth/lib/src/utils/auth_api_constants.dart`](../../../packages/data/auth/lib/src/utils/auth_api_constants.dart). |
| `AnalyticsConstants`, `SocketConstants`, `FirebaseRemoteConfigConstants` | xoá | Không nơi nào tham chiếu, và các hệ thống tương ứng không tồn tại. Riêng `SocketConstants` còn chứa event dành cho chat (`TYPING`, `USER_JOINED`) ngay trong một package core. |

Hai file constants còn lại đều thật sự toàn cục: `ApiStatusConstants` (mã trạng thái HTTP) và `EnvConstants` (giá trị `String.fromEnvironment`). Thư mục `utilities/` cũ đã được gộp vào `utils/` để package chỉ có đúng một nơi cho việc này.

> [!CAUTION]
> Trước khi thêm một hằng số vào `core_common`, hãy tự hỏi: *có nhiều hơn một domain không liên quan cùng đọc nó không?* Nếu không, nó thuộc về `utils/` của package sở hữu.

---

## 2. `core_di` — DI Hub

Chỉ chứa hợp đồng. Không hiện thực, không nghiệp vụ. Đây là vùng trung lập để hai package không được import nhau vẫn gặp được nhau.

| Nhóm hợp đồng | Đường dẫn | Mục đích |
|:--|:--|:--|
| Navigator | `src/navigators/` | `AuthNavigator`, `HomeNavigator`, `OnboardingNavigator`, `SettingsNavigator` — khai ở đây, hiện thực trong feature sở hữu |
| Routing | `src/routing/` | `IFeatureRouteModule`, `IDashboardTabModule`, `IAppEntryLocation`, `DashboardRouteModule`, `NavigatorKeys` |
| Action handler | `src/actions/` | `IAuthActionHandler` — hành động UI xuyên feature (vd đăng xuất) |
| Agnostic stream | `src/agnostic_streams/` | `IAuthStatusStream` — chia sẻ state giữa feature Provider và feature BLoC |
| Hợp đồng storage | `src/theme/`, `src/language/` | `IThemeStorage`, `ILanguageStorage` — hiện thực trong app shell |
| Localization | `src/feature_localization.dart` | `IFeatureLocalization` — mỗi feature tự đóng góp delegate |

**`NavigatorKeys`** nằm ở [`src/routing/navigator_keys.dart`](../../../packages/core/di/lib/src/routing/navigator_keys.dart) (đã tách khỏi `routing_interfaces.dart`, file này giờ chỉ còn interface). Nó phơi ra `rootKey`, `appKey` và `authKey`.

`authKey` mang tên một feature cụ thể — bình thường đây là dấu hiệu sai phân tầng. Nó được chấp nhận vì class này là *hạ tầng routing*: một `ShellRoute` và các route con phải dùng **cùng một** instance `GlobalKey`, nhưng shell do app shell dựng còn route con khai bên trong `feature_auth`. Đặt key ở bên nào cũng tạo chu trình, nên Hub — nơi cả hai đều đã phụ thuộc — giữ nó. Hub không bao giờ import `feature_auth`.

> [!NOTE]
> `core_di` phụ thuộc `go_router`. Đây không phải rò rỉ: `IFeatureRouteModule` trả về `List<RouteBase>`, `IDashboardTabModule` trả về `BottomNavigationBarItem`. Đây *chính là* hợp đồng routing nên buộc phải nói ngôn ngữ của GoRouter. Trừu tượng thêm một lớp nữa chỉ tạo adapter vô ích.

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

Các magic value *không phải* token thì đã được gom vào `src/utils/base_ui_constants.dart`. Ranh giới phân biệt: nếu một designer nhìn vào mà nhận ra, đó là token và ở lại `styles/`.

### `ThemeProvider` phản ứng khi OS đổi theme

`ThemeProvider` là `@lazySingleton` có mixin `WidgetsBindingObserver`. Ở chế độ `ThemeMode.system`, độ sáng của OS có thể đổi khi app đang chạy, nên nó override `didChangePlatformBrightness()` và rebuild — nhưng chỉ khi chế độ thực sự *là* `system`, để lựa chọn light/dark cứng không gây rebuild thừa.

`WidgetsBindingObserver` được chọn thay vì gán `platformDispatcher.onPlatformBrightnessChanged`: trường đó là một **slot đơn**, ai gán sau sẽ âm thầm thắng. Với một singleton toàn cục phải cạnh tranh cùng framework và plugin, đó là rủi ro thật.

Observer được gỡ trong `dispose()`, và hàm này gắn `@disposeMethod` để GetIt gọi khi reset container — thiếu nó thì mỗi lần `resetDependencies()` trong test sẽ để lại một observer cũ còn đăng ký.

---

## 4. `core_ui_kit` — widget dùng lại

Thư viện widget dùng chung mà mọi feature đều có thể dùng. Nó là **core, không phải feature**: nằm tại `packages/core/ui_kit` để `packages/features/` chỉ còn chứa các mảng sản phẩm thực sự gỡ được.

Cấu trúc phẳng (không có `src/`): `buttons/`, `inputs/`, `dialogs/`, `feedback/`, `layout/`, `media/`, `navigation/`, `utils/`.

Nó phụ thuộc `core_common`, `core_base_ui` và `provider_state_management` — không bao giờ phụ thuộc một feature hay `data_*`.

> [!NOTE]
> Phụ thuộc chỉ chạy **một chiều**: `core_ui_kit -> provider_state_management`. Trước đây nó chạy cả hai chiều, tạo thành vòng lặp ngay bên trong vòng core; giờ `provider_state_management` tự có `DefaultLoadingWidget` / `DefaultEmptyWidget` thay vì mượn widget có thương hiệu.

### Quy tắc UI-agnostic

Widget dùng lại nhận số **thô, chưa scale** và không được tự áp `flutter_screenutil_plus` bên trong. Scale là việc của bên gọi:

```dart
// bên gọi scale
CustomButton(width: 120.w, height: 44.h)

// widget tự scale tham số của mình -- sai
double get _width => width.w;
```

Áp `.w` bên trong nghĩa là bên gọi nào đã scale sẽ bị scale hai lần, còn bên gọi muốn một giá trị pixel nguyên bản thì không cách nào lấy được.

> [!WARNING]
> **Một bug thật mà luật này ngăn được.** `AppBarCustom` trước đây có:
>
> ```dart
> @override
> double? get leadingWidth => 64.w;
> ```
>
> Hai lỗi cùng lúc: nó tự scale bên trong, và — vì là getter override — nó **âm thầm vứt bỏ giá trị `leadingWidth` mà bên gọi truyền vào constructor**. Tham số trông như được hỗ trợ nhưng không làm gì cả. Nó đã được gỡ bỏ.

### Hằng số

Giá trị mặc định của các widget này nằm ở `packages/core/ui_kit/lib/utils/shared_ui_constants.dart`:

```dart
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(milliseconds: 200);
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const Duration MEDIA_ERROR_TOAST_DURATION = Duration(seconds: 2);
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
```

Đây là giá trị mặc định, không phải chính sách — bên gọi cần giá trị khác thì truyền qua constructor.

---

## 5. `core_network` — HTTP client

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
> **SSL pinning chỉ tốt bằng danh sách hash của nó.** `sslPinningHashes` hiện trả `const []`, tức pinning đang tắt. `AppInitializer` ghi log mức `ERROR` trên các flavor khác dev khi danh sách rỗng hoặc config chưa đăng ký, nên lỗ hổng này hiện rõ chứ không im lặng — nhưng nó vẫn là lỗ hổng cho tới khi bạn điền hash vào. Xem [hướng dẫn networking](../guides/08_networking.md).

Chi tiết đầy đủ về chuỗi interceptor, các lớp chống đệ quy khi refresh token và việc che header nằm ở [`../guides/08_networking.md`](../guides/08_networking.md).

---

## 6. `core_storage` — lưu trữ key–value có mã hoá

Chỉ cấp **cơ chế**. Không định nghĩa key, không định nghĩa preset nào.

| Thành phần export | Mục đích |
|:--|:--|
| `StorageInterface` | Hợp đồng cho backend |
| `StorageManager` | `@singleton`; phân giải backend theo `StorageType`, khởi tạo song song mọi backend qua `@PostConstruct(preResolve: true)` |
| `StorageValue<T>` | Bọc phản ứng quanh một key — `ChangeNotifier` + `Stream` broadcast, cache trong RAM, tự ghi xuống đĩa khi set |
| `StorageType` | `pref` (SharedPreferences) · `secure` (có phần cứng hỗ trợ) |
| `ObfuscatedString` / `ObfuscatedBytes` | Che dữ liệu trong RAM |
| `PrefStorageImpl` / `SecureStorageImpl` | Nội bộ, phân giải qua `@Named('Pref')` / `@Named('Secure')` |

### Che RAM là bảo vệ thật, không phải nhãn dán

Ngoài mã hoá dữ liệu lúc nghỉ (AES-256-CBC với IV ngẫu nhiên mỗi lần ghi), `StorageValue` còn giữ giá trị **trong bộ nhớ** ở dạng XOR mask ngẫu nhiên, chỉ lộ ra đúng khoảnh khắc cần đọc. Master key cũng được xử lý y hệt. Điều này nâng rào chắn trước tấn công đọc memory dump — một lớp mà phần lớn template bỏ qua hoàn toàn.

`SecureStorageImpl` còn tự phục hồi: nếu mục trong Keychain/KeyStore không đọc được nữa, nó xoá và sinh lại master key thay vì để app kẹt vĩnh viễn không khởi động được.

### Quyền sở hữu

Mỗi package tiêu thụ tự khai `StorageValue` của mình qua `StorageManager` được inject, key đặt trong `utils/` của package đó. Các chủ sở hữu hiện tại:

| Chủ sở hữu | Package | Key | Backend |
|:--|:--|:--|:--|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | secure |
| `LanguageRepositoryImpl` | `data_language` | `locale` | pref |
| `ThemeStorageImpl` | `app` | `themeMode` | pref |
| `LanguageStorageImpl` | `app` | `locale` | pref |
| `AppBootStorage` | `app` | `viewed_onboard` | pref |

Xem [`../guides/06_storage.md`](../guides/06_storage.md) để có các bước cụ thể.

---

## 7. `core_database` — lưu trữ quan hệ (Drift + SQLite)

Chạy trên isolate nền qua `NativeDatabase.createInBackground`. **Không phụ thuộc package nào khác** trong workspace.

| Nhóm | Đường dẫn | Nội dung |
|:--|:--|:--|
| Database | `src/database/` | `AppDatabase`, bảng `CacheEntries`, `CacheEntriesDao` |
| Kết nối | `src/connection/` | `DatabaseConnectionFactory` — phân giải file, executor nền, cách ly file hỏng |
| **Truy cập** | `src/access/` | `IDatabaseHandle`, `DatabaseHandle` |
| **Migration** | `src/migration/` | `IDatabaseMigration`, `DatabaseMigrationRunner` |
| Constants | `src/utils/database_constants.dart` | `DEFAULT_FILE_NAME`, `DEFAULT_READ_POOL`, `BUSY_TIMEOUT_MS` |

### Hai hợp đồng giữ các package không chạm bảng của nhau

**`IDatabaseMigration`** — package nào đổi schema thì hiện thực hợp đồng này ngay cạnh bảng của mình và đăng ký trong DI module của chính nó, y như cách feature đóng góp route. `version` là phiên bản schema mà bước đó *tạo ra*; các bước được phát lại theo thứ tự nên thiết bị bỏ lỡ vài bản phát hành vẫn về đúng schema. Trùng version bị từ chối ngay lúc khởi động thay vì âm thầm chạy một cái.

**`IDatabaseHandle`** — package xin đúng accessor mình cần thay vì nhận `AppDatabase` kèm toàn bộ DAO:

```dart
ProfileLocalDataSource(IDatabaseHandle handle)
  : _dao = handle.accessor(ProfileDao.new);
```

> [!NOTE]
> Đây là **cô lập ở mức bề mặt API, không phải cô lập cưỡng chế**. Drift phân giải mọi bảng lúc biên dịch qua `@DriftDatabase` và dùng chung một kết nối, nên callback factory vẫn nhận được database. Giá trị nằm ở chỗ: vượt qua ranh giới trở thành hành động cố ý và nhìn thấy được khi review, chứ không phải một tham số constructor bình thường. Định nghĩa bảng vẫn tập trung; package sở hữu *đường truy cập* của mình.

Phần gia cố kết nối (`foreign_keys = ON`, chế độ WAL, busy timeout) và chiến lược cách ly file hỏng nằm ở [`../guides/07_database.md`](../guides/07_database.md).

---

## 8. `core_notifications` — thông báo đẩy và cục bộ

`PushNotificationService` bọc Firebase Messaging và `flutter_local_notifications`. Channel ID và loại payload nằm ở `src/utils/notification_constants.dart` — chuyển về từ `core_common`, vì một channel ID của chat không có lý do gì để mọi package trong app đọc được.

---

## 9. State management — hai nhánh, **chưa ngang bằng nhau**

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

### `BlocViewState` được đổi tên vì một lý do

Kiểu state của BLoC là `BlocViewState<T>`, **không phải** `ViewState`. Cả hai package đều export từ barrel công khai, và nhánh Provider vốn đã export một `ViewState` khác về ngữ nghĩa. Trùng tên nghĩa là file nào import cả hai barrel sẽ dính lỗi biên dịch do đụng tên — một cái bẫy tiềm ẩn nay đã được gỡ.

`OperationGlobalConfig` phơi getter chỉ-đọc; `setup()` **gộp** thay vì ghi đè, nên gọi hai lần không còn âm thầm xoá bộ hook đầu tiên, và có `reset()` cho test.

Cách dùng thực tế cho cả hai nhánh: [`../guides/03_state_management.md`](../guides/03_state_management.md).

---

## 10. Bản đồ phụ thuộc

Chỉ liệt kê phụ thuộc cục bộ (trong workspace) — bỏ qua package từ pub.dev.

| Package | Phụ thuộc |
|:--|:--|
| `core_database` | *(không có)* |
| `core_common` | `domain_core` *(ngoại lệ đã duyệt — `ErrorHandler` sinh ra `AppFailure`)* |
| `core_di` | `domain_auth` *(ngoại lệ đã duyệt)* |
| `core_network` | `core_common` |
| `core_storage` | `core_common` |
| `core_notifications` | `core_common` |
| `core_base_ui` | `core_common`, `core_di` |
| `bloc_state_management` | `domain_core` *(ngoại lệ đã duyệt — `AppFailure` cho `BlocViewState.error`)* |
| `provider_state_management` | `core_common`, `domain_core` *(ngoại lệ đã duyệt)* |
| `core_ui_kit` | `core_common`, `core_base_ui`, `provider_state_management` |

Không mũi tên nào trong bảng này trỏ tới `packages/features/*` hay `packages/data/*` — đó là bất biến cần giữ.
