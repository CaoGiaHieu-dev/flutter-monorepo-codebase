# Luật kiến trúc

**File này trả lời:** cái gì được phép, cái gì bị cấm, và **vì sao** — cho từng tầng của monorepo.

**Đọc xong bạn có thể:** kết luận dứt điểm mọi tranh cãi "cái này có hợp lệ không?" khi review, và biết chạy lệnh nào để chứng minh.

Đây là bản **tra cứu**. Muốn hướng dẫn từng bước thì xem [`../guides/`](../guides/); muốn hiểu lý do phân tầng thì xem [`../architecture/01_overview.md`](../architecture/01_overview.md).

> [!NOTE]
> Nguồn gốc là [`.agents/AGENTS.md`](../../../.agents/AGENTS.md). Trang này phản chiếu lại và bổ sung lệnh kiểm chứng cho từng luật.

---

## 1. Hướng phụ thuộc

**Luật.** Phụ thuộc luôn hướng vào trong: `Feature → Domain ← Data`, với `core/*` là hạ tầng nằm dưới. **Không package `core/*` nào được phụ thuộc `feature_*` hay `data_*`** — cả bằng import lẫn bằng khai báo trong `pubspec.yaml`.

**Vì sao.** Core là vòng hạ tầng trong cùng. Nếu core với ngược lên trên, vòng tròn khép lại thành chu trình và không tầng nào phía trên có thể gỡ ra hay tái sử dụng độc lập được nữa.

**Domain nằm ở tâm và không phụ thuộc ai.** Trạng thái đã kiểm chứng:

| Package | Phụ thuộc workspace | Flutter SDK |
|---|---|---|
| `domain_core` | **không có** | không |
| `domain_auth` | `domain_core` | không |
| `domain_language` | `domain_core` | không |

### Ngoại lệ hướng lên được duyệt

Chỉ có đúng bốn. Thêm cái thứ năm bắt buộc phải cập nhật `AGENTS.md` và danh sách cho phép trong `tools/arch_check/check.dart` — nếu không, tool sẽ làm fail build.

| Ngoại lệ | Lý do |
|---|---|
| `core_di → domain_auth` | Hợp đồng agnostic stream phơi type entity cụ thể (`UserEntity`); dùng generic sẽ xoá mất type-safety. Xem [luật 15](#15-giao-tiếp-giữa-các-feature). |
| `provider_state_management → domain_core` | Cần `Result<T>` và `PaginatedEntity<T>` cho `executeOperation` / `PaginatedViewWidget`. |
| `core_common → domain_core` | `ErrorHandler` sinh ra `AppFailure`, mà class này giờ nằm ở `domain_core`. Core→Domain là chiều **đúng** của Clean Architecture. |
| `bloc_state_management → domain_core` | `BlocViewState.error` mang thẳng `AppFailure`, nên kiểu state cơ sở cần nó. |

> [!NOTE]
> `core_ui_kit → provider_state_management` là đúng chiều. Chiều ngược lại bị cấm — trước đây nó tạo ra một chu trình ngay bên trong vòng core, và đó chính là lý do `provider_state_management` tự trang bị `DefaultLoadingWidget` / `DefaultEmptyWidget` trong `lib/src/base_view/default_state_widgets.dart` thay vì mượn của `core_ui_kit`.

**Kiểm chứng**

```bash
# core tuyệt đối không được nhắc tên package feature hay data
grep -rn "package:feature_\|package:data_" packages/core/*/lib
grep -l "feature_\|data_" packages/core/*/pubspec.yaml

# domain tuyệt đối không chạm Flutter
grep -rn "package:flutter" packages/domain/*/lib
```

Cả bốn lệnh phải không trả về gì.

❌ **Sai** — package core mượn widget của feature:
```dart
// packages/core/provider_state_management/lib/src/base_view/base_view_widget.dart
import 'package:feature_auth/feature_auth.dart';   // core → feature
```

✅ **Đúng** — định nghĩa widget dự phòng ngay trong package core:
```dart
import 'default_state_widgets.dart';   // đi kèm package
```

---

## 2. Khai báo dependency tường minh

**Luật.** Mọi `package:` import dùng trong `lib/` phải có mục tương ứng trong `pubspec.yaml` của chính package đó. Import phục vụ production nằm ở `dependencies`, không bao giờ ở `dev_dependencies`. Gỡ bỏ mục không còn dùng.

**Vì sao.** Pub Workspaces dùng chung một `package_config.json`, nên import thiếu khai báo **vẫn compile được cục bộ**. Lỗi chỉ lộ ra khi tách package ra hoặc publish — còn mục thừa thì tạo ra ràng buộc ma, che giấu vi phạm phân tầng thật.

**Kiểm chứng**

```bash
dart tools/unused_checker/check_unused_packages.dart
```

---

## 3. Bắt buộc có thư mục `utils/`

**Luật.** Mọi package, ở mọi tầng, giữ hằng số của chính nó trong thư mục `utils/` bên trong package đó. Một hằng số có đúng **một** chủ sở hữu. Cấm tạo file constants dùng chung xuyên domain.

**Vì sao.** File constants dùng chung cho phép bất kỳ package nào đọc — và gõ nhầm — key của domain khác. Hai god-object kiểu này (`StorageKeyConstants`, `ApiConstants`) đã bị xoá vì lý do đó.

Quy ước đang áp dụng:

| Loại | Vị trí | Ví dụ thật |
|---|---|---|
| Route path | `lib/src/utils/<feature>_path.dart` | `packages/features/home/lib/src/utils/home_path.dart` |
| Storage key | `lib/src/utils/<owner>_storage_keys.dart` | `packages/data/auth/lib/src/utils/auth_storage_keys.dart` |
| API endpoint | `lib/src/utils/<owner>_api_constants.dart` | `packages/data/auth/lib/src/utils/auth_api_constants.dart` |

Class hằng số dùng private constructor và thành viên `UPPER_SNAKE_CASE`:

```dart
// packages/data/auth/lib/src/utils/auth_storage_keys.dart
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

> [!NOTE]
> **Ngoại lệ được duyệt — design token.** `AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows` ở nguyên `packages/core/base_ui/lib/src/styles/`, *không* chuyển vào `utils/`.
>
> Chúng là API công khai của design system, và `styles/` mang đúng ngữ nghĩa đó trong khi `utils/` đọc lên là "linh tinh". Di chuyển sẽ làm hỏng mọi tham chiếu trong docs mà chẳng được gì. **Đừng "sửa" chỗ này ở lần audit sau.**

`core_common` chỉ giữ giá trị thực sự dùng chung toàn cục — hiện là `ApiStatusConstants` (mã HTTP) và `EnvConstants` (nối `String.fromEnvironment`), cả hai nằm trong `lib/src/utils/`.

---

## 4. Storage do package sở hữu

**Luật.** `core_storage` chỉ cung cấp **cơ chế** và định nghĩa **zero** key. Mỗi nơi tiêu thụ tự inject `StorageManager`, tự khai `StorageValue<T>` của mình, key lấy từ class trong `utils/` của chính nó.

**Vì sao.** `StorageValuePresets` (đã xoá) là một `@Singleton` duy nhất giữ key của mọi domain — ai inject nó vào cũng đọc hoặc xoá được dữ liệu của feature khác.

Đăng ký **bắt buộc là singleton** kèm `@PostConstruct(preResolve: true)`:

```dart
// packages/data/auth/lib/src/data_sources/local/auth_local_data_source.dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );
```

> [!CAUTION]
> **Cấm** đăng ký storage owner bằng `@injectable` (factory). Mỗi lần inject sẽ dựng instance mới với cache rỗng, nên getter đồng bộ âm thầm trả `null` — không báo lỗi, chỉ đơn giản là sai dữ liệu.

Chọn backend tường minh: `StorageType.secure` cho token và PII, `StorageType.pref` cho cài đặt và cờ. Tuyệt đối không trao `StorageValue` của package này cho package khác — hãy công bố interface trên `core_di` (như `IThemeStorage` / `ILanguageStorage` đang làm).

Các owner hiện có:

| Owner | Package | Key | Backend |
|---|---|---|---|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | secure |
| `LanguageRepositoryImpl` | `data_language` | `locale` | pref |
| `ThemeStorageImpl` | app shell | `themeMode` | pref |
| `LanguageStorageImpl` | app shell | `locale` | pref |
| `AppBootStorage` | app shell | `viewed_onboard` | pref |

Hướng dẫn đầy đủ: [`../guides/06_storage.md`](../guides/06_storage.md).

---

## 5. Thứ tự đăng ký DI

**Luật.** Một `@Singleton` eager tuyệt đối không được phụ thuộc type do module khởi tạo **sau** nó trong `configureDependencies()`. Dùng `@LazySingleton` khi phụ thuộc đến từ module chạy sau.

**Vì sao.** GetIt sẽ ném `"<Type> is not registered"` ngay lúc boot. Module khởi tạo theo đúng thứ tự khai trong `app/lib/di/injection.dart`: `externalPackageModulesBefore` → đăng ký cục bộ của app → `externalPackageModulesAfter`.

Ví dụ thật: `NetworkConfigImpl` là `@LazySingleton(as: NetworkConfig)` vì nó inject `AuthLocalDataSource` từ `data_auth`, mà module này chạy sau khối app-local. Consumer duy nhất của nó (`ApiClient`) cũng lazy, nên hoãn khởi tạo là an toàn.

> [!CAUTION]
> **`flutter analyze` KHÔNG bắt được loại lỗi này.** Nó chỉ lộ ra lúc chạy thật, trên một lần boot thật.

**Kiểm chứng** — sau khi đổi bất kỳ annotation DI hay constructor nào, đọc file sinh ra và xác nhận phụ thuộc của mỗi đăng ký eager xuất hiện **trước** nó trong `init()`:

```bash
dart run build_runner build -d --workspace
grep -n "PackageModule().init\|gh.singleton<" app/lib/di/injection.config.dart
```

`@PostConstruct(preResolve: true)` trên `@lazySingleton` được await trong lúc module init rồi đăng ký lại thành lazy singleton đồng bộ thuần, nên các lệnh `gh<T>()` đồng bộ về sau đều an toàn.

---

## 6. Ranh giới feature và khả năng gỡ bỏ

**Luật.** Một feature = một mối quan tâm UI. Feature A tuyệt đối không import feature B — không có ngoại lệ; widget dùng chung lấy từ `core_ui_kit`, vốn là core. **App phải build và chạy được khi gỡ bỏ bất kỳ package feature nào.**

**Vì sao.** Một template mà không xoá được feature thì không phải template. Khả năng gỡ bỏ cũng chính là bằng chứng thực tế rằng ranh giới là có thật.

Mọi thứ app shell tiêu thụ lúc chạy đều đi qua một hợp đồng `core_di` kèm fallback:

| Cách tra cứu | Hành vi khi không có gì đăng ký |
|---|---|
| `getAllOrEmpty<T>()` | danh sách rỗng |
| `getItOrNull<T>()` | `null` |
| `getAll<T>()` | **ném lỗi** — đừng dùng cho đóng góp tuỳ chọn |

> [!WARNING]
> `getAll<T>()` và `getAllOrEmpty<T>()` khác nhau đúng ở chỗ này. Việc `getAll` ném lỗi khi type chưa đăng ký đã từng làm app crash ngay lúc dựng `MaterialApp` trong trường hợp không feature nào đóng góp `IFeatureLocalization`.

**Gỡ một feature** — bốn bước được ghi ngay trong `app/lib/di/injection.dart`:

1. mục `ExternalModule(...)` và dòng import tương ứng trong `app/lib/di/injection.dart`;
2. mục `feature_x:` trong `app/pubspec.yaml`;
3. đường dẫn của nó trong danh sách `workspace:` ở `pubspec.yaml` gốc;
4. `flutter pub get` + `dart run build_runner build -d --workspace`.

Các import trong `injection.dart` là **tham chiếu cứng có chủ đích duy nhất** của app shell tới feature — với vai trò composition root, nó buộc phải gọi tên những gì nó lắp ráp. Mọi consumer khác đều đi qua `core_di`.

**Kiểm chứng**

```bash
# sau khi gỡ một feature
flutter pub get && dart analyze app
```

---

## 7. Domain là Pure Dart

**Luật.** Không `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, hay bất kỳ thư viện UI/network nào trong `packages/domain/*`. Khái niệm UI phải được dịch sang kiểu nguyên thuỷ hoặc enum.

**Vì sao.** Domain là tầng duy nhất nên sống lâu hơn lựa chọn framework. Giờ nó được đảm bảo cả ở mức package graph: không `pubspec.yaml` domain nào khai Flutter SDK, và `domain_core` có zero phụ thuộc workspace.

Thành phần: `entities/` (Freezed, có `const Class._()`), `params/`, `repositories/` (interface), `usecases/` (`@injectable`, trả `Result<T>`), `utils/`.

---

## 8. Tầng Data

**Luật.**

- Thư mục là `data_sources/remote/` và `data_sources/local/` — **snake_case, số nhiều `data_sources`**, không bao giờ là `datasources/`.
- `RepositoryImpl` kế thừa `IBaseRepository` và bọc công việc trong `execute()` (async) hoặc `executeSync()`.
- Lỗi chuyển đổi qua `ErrorHandler.handleError(e)`. **Không bao giờ** dùng `AppFailure.fromException()`.
- **DataSource trả Model, không bao giờ trả Entity** — và không bao giờ trả class do Drift sinh.
- Không bao giờ `throw` từ Data lên UI; trả về `Result.failure(AppFailure)`.

**Vì sao có luật Model.** Trả về class row của Drift là để thư viện lưu trữ rò rỉ vào mọi nơi tiêu thụ package. `CacheEntryModel` (`packages/data/core/lib/src/models/cache_entry_model.dart`) tồn tại thuần tuý làm lớp chắn đó.

---

## 9. Freezed, BLoC và state

**Luật.**

- Subclass event của BLoC phải **private**: `const factory HomeEvent.started() = _HomeStarted;`
- Dùng `part` / `part of`: `_bloc.dart` khai `part '_event.dart';` và `part '_bloc.freezed.dart';`
- Handler nhận đủ hai tham số và phải `async`: `Future<void> _onStarted(_HomeStarted event, Emitter<...> emit) async`

> [!CAUTION]
> Closure đồng bộ gọi việc async mà không await sẽ sinh ra `emit was called after an event handler completed normally` — handler trả về ngay lập tức, rồi việc async mới emit vào một sink đã đóng.

**Tồn tại hai kiểu `ViewState` và chúng khác nhau.** Bản BLoC đã được đổi tên để tránh trùng:

| | `ViewState` (Provider) | `BlocViewState<T>` (BLoC) |
|---|---|---|
| File | `provider_state_management/lib/src/base/view_state_model.dart` | `bloc_state_management/lib/src/bloc_view_state.dart` |
| Generic | không | có |
| Số variant | 5 (có `loadingMore`) | 4 |
| Lỗi | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — bắt buộc |
| Chứa data | không (data nằm ở `ViewStateModel<T>`) | có |

> [!WARNING]
> `BaseBloc` / `BaseCubit` hiện chỉ là **điểm mở rộng rỗng**. Không có thứ gì tương đương `executeOperation` ở nhánh BLoC — bạn phải tự unwrap `Result`, tự map `AppFailure`, tự set loading trong **từng** handler. Hai nhánh chưa ngang bằng nhau.

---

## 10. Vòng đời controller

**Luật.** Controller gắn với màn hình là `@injectable` (factory). Controller toàn cục có thể là `@lazySingleton`. Controller được khởi tạo **tại route**, trong `build` của `*_route_module.dart`.

**Vì sao.** ViewModel `@singleton` bị GetIt giữ mãi mãi, nên pop màn hình là rò rỉ nó, và lần vào tiếp theo sẽ dùng lại state cũ.

> [!CAUTION]
> Nếu route đã bọc page trong `BlocProvider` / `ChangeNotifierProvider` thì widget `Page` **không được** bọc lại lần nữa. Bọc hai lần sẽ dựng hai controller; cái mà UI đọc không phải cái route tạo ra.

---

## 11. Routing

**Luật.** Tuyệt đối không sửa `app/lib/presentation/navigation/app_router.dart` để thêm route. Thay vào đó feature tự đăng ký một hợp đồng `core_di`:

| Hợp đồng | Mục đích | Có thứ tự? |
|---|---|---|
| `IFeatureRouteModule` | route dạng stack dưới `ShellRoute` của app | không (khớp theo path) |
| `IDashboardTabModule` | một tab bottom-nav + một `StatefulShellBranch` | **có** — `order` phải khớp index nav |
| `IAppEntryLocation` | `initialLocation` lúc cold-start | không áp dụng |
| `DashboardRouteModule` | chỉ phần chrome của dashboard | chỉ `feature_dashboard` |

Điều hướng xuyên feature đi qua interface Navigator khai ở `core_di`, implement trong `routing/` của feature sở hữu. Cấm hardcode path hoặc gọi `GoRouter.of(context).go(...)` sang feature khác. **`BuildContext` phải được truyền trực tiếp từ nơi gọi ở UI** — đừng với lấy `NavigatorKeys.*.currentContext`.

`feature_dashboard` **chỉ là chrome**: không được import feature tab, không sở hữu page của tab, không hardcode danh sách `BottomNavigationBarItem`, và không tự đăng ký `IDashboardTabModule`.

---

## 12. Responsive UI

**Luật.** Mọi kích thước — rộng, cao, padding, margin, cỡ chữ, bo góc — đều dùng `flutter_screenutil`: `.w`, `.h`, `.sp`, `.r`. Cấm dùng double thô trong layout.

**Widget dùng lại nhận giá trị RAW và không được tự scale bên trong.** Scale là việc của nơi gọi.

❌ **Sai** — đoạn này từng tồn tại thật, và nó âm thầm vứt bỏ giá trị của caller:
```dart
// packages/core/ui_kit/lib/navigation/app_bar_custom.dart
@override
double? get leadingWidth => 64.w;   // ghi đè super.leadingWidth vĩnh viễn
```

✅ **Đúng** — nhận tham số qua constructor, để nơi gọi tự scale.

---

## 13. Đa ngôn ngữ

**Luật.** Toàn bộ chữ hiển thị cho người dùng phải được dịch — cấm hardcode chuỗi UI. Mỗi feature sở hữu file `.arb` trong `assets/language/` của mình và đăng ký `IFeatureLocalization` qua DI. Truy cập qua extension của feature: `context.l10nAuth.someKey`.

Feature **không được** sửa `app/lib/presentation/root_app.dart` để thêm delegate; app shell tự gom bằng `getAllOrEmpty<IFeatureLocalization>()`.

Chuỗi toàn cục nằm ở `core_base_ui`. `core_ui_kit` **không được** định nghĩa `.arb` riêng — nó dùng của `core_base_ui`.

---

## 14. Dialog và bottom sheet

**Luật.** Mỗi dialog và bottom sheet là một class widget riêng trong file riêng. Cấm viết cây widget inline bên trong `showDialog()` / `showModalBottomSheet()`.

Hậu tố: `_dialog.dart` → `Dialog`, `_bottom_sheet.dart` → `BottomSheet`. Ví dụ thật: `packages/core/ui_kit/lib/dialogs/error_dialog.dart`, `retry_dialog.dart`, `warning_dialog.dart`.

---

## 15. Giao tiếp giữa các feature

**Luật.** Sáu mô hình được công nhận; chọn theo thứ bạn cần chia sẻ.

| # | Nhu cầu | Cơ chế |
|---|---|---|
| 1 | Logic nghiệp vụ | UseCase Domain dùng chung |
| 2 | Hạ tầng | core service (`core_storage`, `core_network`, …) |
| 3 | State xuyên feature | interface `Stream` / `ValueListenable` trung lập trên `core_di`, đăng ký kép |
| 4 | Tuỳ chọn UI thuần (theme, locale) | bỏ qua Domain → interface storage ở `core_di` → impl ở app shell |
| 5 | Nhúng widget của feature khác | builder interface trên `core_di` |
| 6 | Hành động UI xuyên feature | `I*ActionHandler` trong `core_di/src/actions/` |

**Đăng ký kép** (mô hình 3): feature sở hữu đăng ký class cụ thể là `@singleton`, rồi bind interface qua `@module` của DI:

```dart
@module
abstract class AuthModule {
  IAuthStatusStream bind(AuthStatusStreamImpl impl) => impl;
}
```

Nhờ vậy chủ sở hữu inject được type cụ thể qua constructor, còn mọi feature khác chỉ nhìn thấy interface.

> [!NOTE]
> GetIt phân giải theo **đúng type**, không bao giờ theo supertype. Đăng ký `Impl as InterfaceA` **không** làm cho `getIt<InterfaceB>()` chạy được, kể cả khi `InterfaceA implements InterfaceB` — phải bind riêng từng cái. Xem `app/lib/di/network_binding_module.dart`, nơi `SslPinningConfig` cần binding riêng dù `NetworkConfig implements SslPinningConfig`.

Đừng dùng Action Handler cho điều hướng thuần (dùng Navigator) hay cho logic thuần Domain (dùng UseCase).

---

## 16. Công cụ và vệ sinh code

| Luật | Chi tiết |
|---|---|
| Cấm `print()` trong `tools/` | dùng `stdout.writeln()` / `stderr.writeln()` |
| Cấm tắt lint | `// ignore_for_file: ...` bị cấm; hãy tìm cách migrate thật |
| Cấm script PowerShell | `.ps1` bị cấm (chính sách thực thi của Windows); dùng `.dart` |
| Không bao giờ sửa tay file sinh | `.g.dart`, `.freezed.dart`, `.module.dart`, `.config.dart` |
| Version lấy từ catalog | sửa `pubspec_dependencies.yaml` rồi chạy tool sync |
| Chạy lại barrel generator | sau khi thêm, đổi tên, hoặc xoá file trong `lib/` |
| Xử lý deprecation đàng hoàng | nghiên cứu đường migrate; cấm vá tạm và cấm ignore |

---

## Bảng tra luật → lệnh

| Kiểm tra | Lệnh |
|---|---|
| Dependency thừa / thiếu khai báo | `dart tools/unused_checker/check_unused_packages.dart` |
| Lệch version catalog | `dart tools/dependency_sync.dart --check` |
| Asset, file, translation thừa | `dart tools/unused_checker/check_script.dart` |
| Phân tích tĩnh | `flutter analyze` |
| Code sinh đã cập nhật chưa | `dart run build_runner build -d --workspace` |
| An toàn thứ tự DI | đọc `app/lib/di/injection.config.dart` |
| core ⇏ feature | `grep -rn "package:feature_" packages/core/*/lib` |
| Domain thuần Dart | `grep -rn "package:flutter" packages/domain/*/lib` |

---

**Tiếp theo:** [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md) · [`04_review_checklist.md`](04_review_checklist.md)
