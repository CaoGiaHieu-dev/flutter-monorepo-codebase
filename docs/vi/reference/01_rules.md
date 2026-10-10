<!-- translated-from: docs/en/reference/01_rules.md@5251b83 -->
# Luật kiến trúc

**File này trả lời:** cái gì được phép, cái gì bị cấm, **vì sao**, và thứ gì thực thi luật đó — cho từng tầng của monorepo.

**Đọc xong bạn có thể:** kết luận dứt điểm mọi tranh cãi "cái này có hợp lệ không?" khi review bằng cách trích một `RULE-NN`, và biết chạy lệnh nào để chứng minh.

Muốn hướng dẫn từng bước thì xem [`../guides/`](../guides/); muốn hiểu lý do phân tầng thì xem [`../architecture/01_overview.md`](../architecture/01_overview.md).

> [!IMPORTANT]
> **Trang này là nguồn chân lý duy nhất cho mọi luật trong repo.** Bảng đăng ký bên dưới phát biểu mỗi luật đúng một lần, với một id ổn định `RULE-NN`. Mọi tài liệu khác — `CLAUDE.md`, `.agents/AGENTS.md`, các guide, các skill trong `.claude/skills/`, checklist review, `tools/code_review/review_prompt.md` — trích id và link về đây thay vì phát biểu lại luật. Nếu một trang khác mâu thuẫn với trang này, trang này thắng và trang kia là thứ cần sửa.

---

## Bảng đăng ký luật

### Cách đọc bảng đăng ký

- **ID** — `RULE-NN`, ổn định vĩnh viễn. Mỗi dải số gom một chủ đề; khoảng trống là chỗ để mở rộng. Một id không bao giờ bị đánh số lại hay tái sử dụng. 68 luật trong chín họ: 01–09 phân tầng · 10–19 DI · 20–29 routing · 30–39 UI, l10n, a11y · 40–49 data, storage, database, network · 50–59 state · 60–69 kiểm thử, logging, lỗi · 70–79 công cụ và docs · 80–89 app và composition.
- **Thực thi bởi** — thứ chặn một vi phạm không cho merge:

  | Giá trị | Ý nghĩa |
  |---|---|
  | `arch_check Rn` | luật *n* của `dart tools/arch_check/check.dart` — CI Gate 1, chặn merge |
  | `analyzer (<lint>)` | `flutter analyze` với setting hoặc lint đó — CI Gate 2, 0 issue kể cả info |
  | `test (<file>)` | một test fail khi có vi phạm — CI Gate 3 |
  | `CI gate N` | một bước của `.github/workflows/pr_quality_check.yml`: 0 composer verify · 1 arch_check + `tools/test` · 2 analyze · 3 test theo package · 4 đồng bộ catalog · 5 docs_check · `build` job build APK debug |
  | `CI barrel gate` | bước "Barrels match the generator" của cùng workflow — sau codegen, barrel được sinh lại phải bằng barrel đã commit |
  | `CI unused-deps step` | bước cuối của job `quality`, `dart tools/unused_checker/check_unused_packages.dart`, có chặn merge |
  | `composer verify` | Gate 0 — composition sinh ra khớp với `apps/<id>/app_manifest.yaml` |
  | `docs_check` | Gate 5 — mọi đường dẫn trong docs tồn tại, `docs/en` ↔ `docs/vi` cùng hình dạng |
  | `review` | không có gì tự động — người review giữ luật, dùng [`04_review_checklist.md`](04_review_checklist.md) |

- **Kiểm chứng** — một lệnh chạy được từ gốc repo, hoặc `review`.
- **Chi tiết** — mục bên dưới (hoặc guide) giải thích luật, ngoại lệ và lịch sử của nó.

### 01–09 · Phân tầng và dependency

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-01 | Không package `platform/*` nào import hay khai báo (trong `dependencies:`, `dev_dependencies:` hay test) một package nằm dưới `modules/` — `feature_*`, `data_*`, `domain_*` của sản phẩm, `<id>_api` hay package module tuỳ biến; một cạnh trỏ vào `domain_core` / `data_core` chỉ tồn tại nếu nó là một trong bốn cạnh `→ domain_core` đã duyệt | Core là vòng trong cùng; một cạnh hướng lên khiến module không gỡ được | arch_check R1 (import, `dependencies:`, `dev_dependencies:`, import trong test) | `dart tools/arch_check/check.dart` | [§1](#1-hướng-phụ-thuộc) |
| RULE-02 | Mỗi package platform nằm ở `platform/<group>/<package>` và `dependencies:` của nó theo DAG nhóm (không infra → infra, ui không bao giờ → state) | Mỗi nhóm tự sở hữu và thay thế được | arch_check R11 | `dart tools/arch_check/check.dart` | [§1 R11](#chiều-giữa-các-nhóm-platform-r11) |
| RULE-03 | Domain là Dart thuần: một package domain (`modules/*/domain`, `domain_core`) không import và không khai package Flutter hay gắn với Flutter, package transport hay lưu trữ (`dio`, `retrofit`, `drift`, `http`), thư viện `dart:` chỉ dành cho engine, cũng như package workspace nào ngoài `domain_core` và domain của chính module đó; test của nó chạy trên `package:test` | Domain sống lâu hơn mọi lựa chọn framework | arch_check R2 (import, `dependencies:`, `dev_dependencies:`, import trong test) | `dart tools/arch_check/check.dart` | [§7](#7-domain-là-pure-dart) |
| RULE-04 | Bên trong một module chiều là `Feature → Domain ← Data`: feature không bao giờ import feature khác, package `data_*` hay domain của module khác; package data không bao giờ import feature hay data / domain / API của module khác; domain không bao giờ với tới data hay feature. Module khác chỉ được chạm qua `<id>_api` của nó (chỉ mở cho feature), package này chỉ phụ thuộc `platform/foundation/*` và package Flutter / pub | Module độc lập về sở hữu và gỡ bỏ | arch_check R3 (package feature, data và API; import, `dependencies:`, `dev_dependencies:`, test), arch_check R2 (phía domain) | `dart tools/arch_check/check.dart` | [§6](#package-api-của-module) |
| RULE-05 | Mọi module gỡ được: trong `apps/*` chỉ `lib/di/injection.dart` import package module; các package shell không import cái nào | Import kiểu vô hiệu hoá `getItOrNull` — nó fail lúc biên dịch | arch_check R10, arch_check R1 | gỡ khỏi manifest, `composer sync`, build | [§6](#6-ranh-giới-feature-và-khả-năng-gỡ-bỏ) |
| RULE-06 | Mọi import `package:` dưới `lib/` phải khai trong `dependencies:` của package đó (không chỉ `dev_dependencies`); dependency đã khai mà không ai import thì bị xoá | Một `package_config.json` dùng chung che giấu import chưa khai tới lúc tách package | arch_check R5 (chưa khai), bước unused-deps của CI (đã khai, không hề import) | `dart tools/arch_check/check.dart` · `dart tools/unused_checker/check_unused_packages.dart` | [§2](#2-khai-báo-dependency-tường-minh) |
| RULE-07 | `platform_kernel` giữ Dart thuần — không package Flutter hay gắn với Flutter, không thư viện transport hay lưu trữ (`dio`, `retrofit`, `drift`, `http`), không thư viện `dart:` chỉ dành cho engine, trong import, `dependencies:`, `dev_dependencies:` hay test | Danh sách dependency của nó là của mọi package | arch_check R9 | `dart tools/arch_check/check.dart` | [architecture/02_core §1](../architecture/02_core.md) |
| RULE-08 | `core_di` chỉ chứa contract trung lập sản phẩm: không dependency `domain_*`, contract mang value type riêng (`SessionPrincipal`), trả `Widget` thuần, và ưu tiên `sealed class` Dart 3 thay vì Freezed | Một type domain trong hub khiến mọi bên tiêu thụ phụ thuộc một module | arch_check R1 (nửa dependency), review | `dart tools/arch_check/check.dart` | [§15](#15-giao-tiếp-giữa-các-feature) |
| RULE-09 | Hằng số công khai của package nằm trong `utils/` của chính nó (route `*_path.dart`, khoá `*_storage_keys.dart`, endpoint `*_api_constants.dart`, hoặc cả hai trong một `<owner>_constants.dart`) dạng `UPPER_SNAKE_CASE`; design token ở `styles/`; không có file hằng số dùng chung xuyên domain | Mỗi hằng số có đúng một chủ | arch_check R4 (`static const` công khai nằm ngoài `utils/` / `styles/`), review (cách đặt tên, các dạng khai báo khác, file hằng số dùng chung) | `dart tools/arch_check/check.dart` | [§3](#3-hằng-số-nằm-trong-utils) |

### 10–19 · Dependency injection

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-10 | Controller của màn hình (Provider, Bloc, Cubit) là factory `@injectable`; chỉ các controller toàn app — `ThemeProvider`, `LanguageProvider`, `DeeplinkProvider`, `AuthProvider` — là `@lazySingleton` | GetIt không bao giờ giải phóng singleton — lần vào sau dùng lại state cũ | review | review | [§10](#10-vòng-đời-controller) |
| RULE-11 | Chỉ inject qua constructor — không `getIt<T>()` trong ViewModel, Bloc, Repository, UseCase hay widget; nơi được tra cứu là `build` của route module (RULE-21) và code composition của chính shell | Dependency hiện rõ và thay được bằng fake viết tay | review | review | [guides/05_di §6](../guides/05_di.md) |
| RULE-12 | Contract chỉ được implement dưới `modules/` (contract của `core_di` hay type của `<id>_api`) phải resolve bằng `getItOrNull` / `getAllOrEmpty` + fallback bên ngoài module của nó — không bao giờ `getIt` / `getAll`, và không bao giờ là tham số constructor bắt buộc của một class injectable | `getAll<T>()` ném lỗi khi không có đăng ký; gỡ module là boot sập | arch_check R8 | `dart tools/arch_check/check.dart` | [§6](#6-ranh-giới-feature-và-khả-năng-gỡ-bỏ) |
| RULE-13 | `@Singleton` eager không bao giờ phụ thuộc type do nhóm DI chạy sau đăng ký — dùng `@LazySingleton`; `shell` chạy trước `ui`, `notifications` sau phần đăng ký của chính app | GetIt ném `"<Type> is not registered"` lúc boot, và `flutter analyze` không thấy | test (`apps/*/test/di_smoke_test.dart`), CI gate 3; composer verify V12 giữ test đó tồn tại | `cd apps/mobile && flutter test test/di_smoke_test.dart` | [§5](#5-thứ-tự-đăng-ký-di) |
| RULE-14 | Interface thứ hai trên cùng một implementation được bind qua `@module` (`ISessionState` và `ISessionRefreshListenable` ← `AuthProvider` trong `feature_auth`) | GetIt resolve đúng type, không bao giờ supertype — `getItOrNull<ISessionState>()` của shell lặng lẽ trả `null` và app mãi mãi ở trạng thái chưa đăng nhập | test (`apps/*/test/di_smoke_test.dart`: `checkAppContract` C02 / C04 cho contract mà app khai là `provided`), review | `cd apps/mobile && flutter test test/di_smoke_test.dart` | [§15](#15-giao-tiếp-giữa-các-feature) |
| RULE-15 | Mỗi package mà một app ghép vào đồ thị DI (được liệt kê trong một mục `di_groups`, hoặc là một tầng của module) khai `@InjectableInit.microPackage()` ở `lib/di/module.dart` không đối số (ngoại lệ duy nhất: `ignoreUnregisteredTypesInPackages` của `core_notifications`), kể cả khi nó không đăng ký gì; package không mục `di_groups` nào liệt kê (`platform_kernel`, `core_responsive`, một `<id>_api`) thì không có `module.dart`; không có module domain/data nguyên khối | Module theo package là thứ composer ghép và việc gỡ bỏ xoá đi | review (composer bỏ package thiếu marker khỏi `injection.dart`; smoke test bắt đăng ký mà có nơi dùng tới) | review | [guides/05_di §7](../guides/05_di.md) |
| RULE-16 | Composition đến từ `apps/<id>/app_manifest.yaml` qua `composer sync`: không bao giờ sửa tay vùng `composer:managed` (`workspace:` ở gốc, path dependency của app, vùng `imports` và `modules` của `injection.dart` (ngoài hai vùng đó chỉ có comment), vùng `facts` của `lib/app/app_profile.dart`, vùng `report` của `README.md` của app); mọi member khai `resolution: workspace` và gốc là nút workspace duy nhất | Composition và facts sinh ra không thể lệch khỏi manifest | composer verify (CI gate 0: V13 lệch ở mọi vùng và code nằm ngoài hai vùng của `injection.dart`, V17 không có `workspace:` lồng nhau), `flutter pub get` (member thiếu `resolution: workspace` bị từ chối) | `dart tools/composer/composer.dart verify` | [§20](#20-workspace-codegen-và-barrel) |

### 20–29 · Routing, điều hướng và ranh giới feature

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-20 | Không bao giờ sửa `app_router.dart` để thêm route: đóng góp `IFeatureRouteModule` / `INavDestinationModule` / `IAppEntryLocation` qua DI | Router được lắp từ DI, nhờ vậy feature gỡ được | review | review | [§11](#11-routing) |
| RULE-21 | Controller được tạo ở route (`build` của `*_route_module.dart`); `Page` không bao giờ tự bọc thêm `BlocProvider` / `ChangeNotifierProvider` | Bọc hai lần tạo hai controller; UI đọc nhầm cái | review | review | [§10](#10-vòng-đời-controller) |
| RULE-22 | Điều hướng xuyên feature đi qua navigator của module sở hữu trong `<id>_api` (implement trong `routing/` của feature đó), resolve bằng `getItOrNull`; không bao giờ hardcode path hay `GoRouter.of(context).go(...)` sang feature khác; shell dùng `ISignInLocation` / `IPostSignInLocation` | Path route là chi tiết riêng của chủ sở hữu | review, arch_check R8 (phần lookup), arch_check R1 / R10 (không file platform hay app nào import package API) | review | [§11](#11-routing) |
| RULE-23 | `BuildContext` được truyền trực tiếp từ nơi gọi ở UI — không bao giờ đọc từ một biến toàn cục: `NavigatorKeys.*.currentContext` hay bất kỳ nơi giữ navigator hoặc context tĩnh nào khác | Context toàn cục sống lâu hơn widget sở hữu nó | review | review | [§11](#11-routing) |
| RULE-24 | Mỗi package feature một mối quan tâm UI có biên; `feature_dashboard` chỉ là chrome; `INavDestinationModule` chỉ cho destination chính, với `order` duy nhất | Package gom nhiều màn hình không liên quan thì không gỡ riêng được | review, test (`apps/*/test/di_smoke_test.dart`: `checkAppContract` C06 `order` duy nhất, C12 hai tab trở lên cần dashboard) | review | [§11](#11-routing) |
| RULE-25 | Nhu cầu xuyên feature dùng một trong sáu mô hình được duyệt; hành động UI đi qua `I*ActionHandler` trong `<id>_api` của chủ sở hữu (implement trong `handlers/`) — không dùng cho điều hướng thuần hay logic domain | Coupling tường minh và một chiều | review | review | [§15](#15-giao-tiếp-giữa-các-feature) |

### 30–39 · UI, responsive, đa ngôn ngữ và khả năng truy cập

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-30 | Mọi kích thước được scale qua `BuildContext` (`context.w/h/sp/r`, `context.edgeInsets`, token): không số thô trong layout, không `16.w` trần; trong hàm async đọc giá trị trước `await` đầu tiên | Chỉ đọc qua context mới rebuild khi xoay, chia màn hình và resize | arch_check R7 (dạng trần), arch_check R20 (số thô trong các constructor layout và vẽ mà nó liệt kê), review (số thô đi qua biến hoặc widget không được liệt kê; thứ tự `await`) | `dart tools/arch_check/check.dart` | [§12](#12-responsive-ui) |
| RULE-31 | Widget tái sử dụng của `core_ui_kit` dùng tham số đúng như nhận và chỉ scale hằng số riêng của nó; token đã scale không bao giờ bị scale lại | Scale hai lần — hoặc không lần nào — là lỗi layout thầm lặng | review | review | [§12](#12-responsive-ui) |
| RULE-32 | Chọn layout theo window size class (`context.windowSizeClass`, `context.adaptive`, `AdaptiveLayout`) — không bao giờ `Platform.is*`, model thiết bị hay `shortestSide` tự chế (chuyển trang theo quy ước của hệ điều hành là một mục allow-list của RULE-82, không phải chọn layout) | Một thiết bị hiển thị nhiều cửa sổ | review (việc chọn theo window class, model thiết bị, `shortestSide`), arch_check R17 (nhánh `Platform.is*` / `kIsWeb` ngoài allow-list, RULE-82) | `dart tools/arch_check/check.dart` | [§12](#12-responsive-ui) |
| RULE-33 | Màu, kiểu chữ, khoảng cách và bo góc lấy từ design token (`context.colors`, `AppTextStyles.*(context)`, `AppSpacing` / `AppRadius`); con số đổi trong hằng `raw*`, không bao giờ hardcode trong widget | Một chỗ để đổi thương hiệu; sáng/tối miễn phí | arch_check R20 (số thô), review (màu, kiểu chữ, con số bị đổi ngoài `raw*`) | `dart tools/arch_check/check.dart` | [guides/11_design_system](../guides/11_design_system.md) |
| RULE-34 | Mọi chữ hiển thị cho người dùng được dịch: ARB của feature trong `assets/language/`, đăng ký qua `IFeatureLocalization` — không bao giờ sửa `app_material_wrapper.dart` của shell, nơi gom chúng; chuỗi toàn cục chỉ ở `core_base_ui`; `core_ui_kit` không có ARB. `AppFailure.message` là chữ dành cho lập trình viên và không bao giờ lên màn hình: `code` của failure được ánh xạ sang một chuỗi đã dịch | Delegate gom từ DI giữ cho feature gỡ được | arch_check R21 (mọi locale có đủ khoá của `en.arb`), review (việc một chuỗi có được dịch hay không) | `dart tools/arch_check/check.dart` | [§13](#13-đa-ngôn-ngữ-và-asset) |
| RULE-35 | Khoá ARB là `lowerCamelCase` | `gen-l10n` chép khoá thành tên getter, và code sinh ra không được phân tích | arch_check R21 | `dart tools/arch_check/check.dart` | [§13](#13-đa-ngôn-ngữ-và-asset) |
| RULE-36 | Mỗi dialog và bottom sheet là một widget class riêng (`*_dialog.dart` → `…Dialog`, `*_bottom_sheet.dart` → `…BottomSheet`), không bao giờ là cây widget inline trong builder của `showDialog` / `showModalBottomSheet` | Tái sử dụng, test và review được | review | review | [§14](#14-dialog-và-bottom-sheet) |
| RULE-37 | Asset riêng của feature nằm trong `assets/` của feature đó; `core_base_ui` chỉ giữ asset và chuỗi toàn cục, và không có widget | Kho asset toàn cục buộc mọi feature vào nhau | review | review | [§13](#13-đa-ngôn-ngữ-và-asset) |
| RULE-38 | Chữ theo cỡ chữ của hệ điều hành: không bao giờ `withNoTextScaling` hay `TooltipVisibility(visible: false)` (shell giới hạn ở `DisplayProfile.textScaleMax` — 2.0 trừ khi app đặt khác, không bao giờ dưới 2.0 và tối đa 4.0), không bao giờ khung chữ cao cố định; nút chỉ có icon mang `tooltip`, ảnh có nghĩa mang `semanticLabel` | Người nhìn kém và người dùng trình đọc màn hình | test (`platform/shell/app_shell/test/accessibility_test.dart` cho shell; các test text-scale của `feature_auth` và `feature_dashboard` cho các trang đó), analyzer (const assert trên `DisplayProfile.textScaleMax`), review (mọi màn hình khác) | `cd platform/shell/app_shell && flutter test test/accessibility_test.dart` | [§19](#19-khả-năng-truy-cập) |
| RULE-39 | Vùng chạm tối thiểu 48 × 48 dp (`kMinInteractiveDimension`); cạnh đầu/cuối dòng dùng `edgeInsetsDirectional`, không phải `left` / `right` vật lý | Khả năng truy cập vận động; ngôn ngữ viết phải sang trái | test (`platform/ui/ui_kit/test/default_sizes_test.dart`: `CustomButton` giữ 48 dp ở các độ rộng điện thoại 320 / 360 / 375 dp và nâng `height` nhỏ hơn mà bên gọi truyền; `accessibility_states_test.dart`: `CustomInputField` cao ít nhất 48 dp, các trạng thái của button, ô nhập và toast đạt độ tương phản; `modal_overlay_test.dart`: một dialog hay lớp loading ẩn trang phía sau; `platform/ui/design_system/test/palette_test.dart`: các dòng của `showDropDown` cao ít nhất 48 dp; `palette_contrast_test.dart`: các palette đi kèm), review (mọi widget khác, và `edgeInsetsDirectional`) | `cd platform/ui/ui_kit && flutter test test/default_sizes_test.dart test/semantics_test.dart test/accessibility_states_test.dart test/modal_overlay_test.dart` | [§19](#19-khả-năng-truy-cập) |

### 40–49 · Domain, data, storage, database và network

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-40 | Data source nằm trong `data_sources/remote/` và `data_sources/local/` — không bao giờ `datasources/` | Một quy ước trong mọi module | arch_check R14 | `dart tools/arch_check/check.dart` | [§8](#8-tầng-data) |
| RULE-41 | Data source trả về Model (vỏ bọc duy nhất: `BaseEntity<T>`), không bao giờ Entity hay type sinh ra (row Drift chuyển đổi ở biên); Model implement `BaseModel<E>` với `.toEntity()` | Type transport và lưu trữ ở lại trong package data | review | review | [§8](#8-tầng-data) |
| RULE-42 | `RepositoryImpl` kế thừa `BaseRepository` và bọc việc trong `execute()` / `executeSync()`; tầng data không bao giờ ném lỗi lên UI — nó trả `Result.failure(AppFailure)` | Lỗi đi qua biên dưới dạng giá trị | review | review | [§8](#8-tầng-data) |
| RULE-43 | Lỗi được phân loại bằng `ErrorHandler.handleError(e)` — không bao giờ tự chế `AppFailure.fromException()`; một họ exception mới (Firebase, platform) đăng ký một `ErrorClassifier` | Lỗi chưa phân loại rơi về mã 9999, "Unknown error occurred" | review | review | [§8](#8-tầng-data) |
| RULE-44 | `core_storage` không định nghĩa khoá: mỗi bên tiêu thụ khai `StorageValue<T>` của riêng mình, khoá từ `utils/*_storage_keys.dart` của chính nó, không bao giờ đưa nó cho package khác (hãy công bố interface — trong `core_di` khi giá trị trung lập với sản phẩm, như `IThemeStorage`; trong `<id>_api` của chủ sở hữu khi nó thuộc về một module), và chọn `secure` cho token/PII, `pref` cho cài đặt | Một object khoá dùng chung cho phép bất kỳ package nào đọc dữ liệu của package khác | review | review | [§4](#4-storage-do-package-sở-hữu) |
| RULE-45 | Chủ sở hữu storage là singleton (`@singleton` / `@lazySingleton` / `@Singleton(as:)`) kèm `@PostConstruct(preResolve: true)` — không bao giờ `@injectable` | Factory phát ra cache rỗng, getter lặng lẽ trả `null` | review | review | [§4](#4-storage-do-package-sở-hữu) |
| RULE-46 | Package cần SQL khai database Drift của riêng mình (bảng, DAO là `part of` nó) trên nền `core_database`; không có `AppDatabase` dùng chung | Drift gắn bảng lúc biên dịch — database dùng chung sở hữu mọi bảng | review | review | [guides/07_database](../guides/07_database.md) |
| RULE-47 | Migration được đăng ký có kiểu theo database của nó — `@LazySingleton(as: IDatabaseMigration<YourDatabase>)` — và lệnh mở `@preResolve` của database mang `@Order(1)` | Đăng ký không kiểu không bao giờ được gom; bước migrate lặng lẽ không chạy | review | review | [guides/07_database §11](../guides/07_database.md) |
| RULE-48 | SSL pinning là một quyết định tường minh theo từng flavor trong `app_manifest.yaml` (`flavors.<f>.ssl_pinning`: ít nhất hai pin — leaf + dự phòng — hoặc `disabled` kèm lý do); bắt buộc ở mọi nơi một platform đã khai báo có thể pin TLS (`AppPlatform.canPinTls`: mọi platform trừ web, nơi trình duyệt sở hữu TLS); trên Windows, macOS và Linux plugin chỉ thấy chứng chỉ leaf, nên các key đã pin phải gồm key của leaf; `composer sync` sinh nó vào `facts` của app (`AppFacts.sslPinning`, một `SslPinningPolicy`) và `AppInitializer.initBeforeRunApp` cài nó trước khi DI bắt đầu — không có nguồn pin nào khác. Các pin đã khai áp dụng cho **mọi host** mà process kết nối tới, không chỉ API (client pinning là `HttpOverrides` toàn cục), nên một CDN hay host bên thứ ba mà các key đã pin không bao phủ sẽ fail. Một quyết định `disabled` làm gate qua nhưng không phải là pin: template ship một quyết định như vậy, đánh dấu `TEMPLATE PLACEHOLDER`, cho `staging` và `prod`, mà README của app liệt kê dưới "Decisions to revisit before shipping" và log lúc boot, và bản release cần pin thật. Việc bỏ qua chứng chỉ chỉ có trong bản debug mà flavor đã khai là `dev` | Thiếu quyết định khiến traffic không được pin mà không ai chủ ý chọn | composer verify (V1 hình dạng và hai pin, V9 một quyết định cho mỗi flavor), analyzer (các const assert của `PinnedSsl` / `DisabledSsl`), test (`platform/foundation/common/test/pin_policy_matrix_test.dart`, `platform/foundation/common/test/ssl_pinning_enforcement_test.dart` — client đã cài và việc khớp pin thật, `platform/foundation/common/test/app_config_test.dart`; `apps/*/test/di_smoke_test.dart` qua `checkDeclaredStarts`: P04, flavor không có quyết định trên platform có thể pin), boot (chính P04 đó chặn app khởi động) | `dart tools/composer/composer.dart verify` · `cd platform/foundation/common && flutter test test/pin_policy_matrix_test.dart` | [guides/08_networking §10](../guides/08_networking.md) |
| RULE-49 | Entity dùng Freezed với `const Class._()`; use case là `@injectable`, làm một việc và trả `Result<T>` | Một bề mặt domain bất biến và đồng nhất | review | review | [§7](#7-domain-là-pure-dart) |

### 50–59 · Quản lý state

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-50 | Feature BLoC dùng `BaseBloc` + event Freezed (`BaseCubit` chỉ khi không cần event); feature Provider kế thừa `BaseProvider<T>` và dùng `executeOperation` | Mỗi thư viện state một mẫu | review | review | [§9](#9-freezed-bloc-và-state) |
| RULE-51 | Các subclass event Freezed là private (`= _HomeProfileStarted`), và Bloc dùng `part` / `part of` cho `<name>_event.dart`, `<name>_state.dart` và `<name>_bloc.freezed.dart` | Event là API riêng của Bloc | review | review | [§9](#9-freezed-bloc-và-state) |
| RULE-52 | Mọi handler `on<Event>` là `async` và nhận `(event, emit)` — không bao giờ closure đồng bộ gọi việc async không await | Nếu không: "emit was called after an event handler completed normally" | arch_check R18 (closure inline khai `async`, hoặc tear-off của method `async` trong cùng file), review (hình dạng `(event, emit)`; handler khai ở file khác) | `dart tools/arch_check/check.dart` | [§9](#9-freezed-bloc-và-state) |
| RULE-53 | State `BlocViewState<T>` được chốt qua `emitResult` (`BlocResultMixin` / `CubitResultMixin`); state tuỳ biến kết thúc mọi nhánh ở một state cuối; code generic ghi rõ đối số kiểu (`BlocViewState<T>.loading()`, không bao giờ `const BlocViewState.loading()`) | State `const` trong helper `<T>` là `BlocViewState<Never>` và không bao giờ bằng | review | review | [§9](#9-freezed-bloc-và-state) |
| RULE-54 | State xuyên feature được chia sẻ qua interface `Stream` / `ValueListenable` trung lập, không bao giờ qua instance Bloc hay Provider; chủ sở hữu đăng ký `@singleton` cụ thể và bind interface như RULE-14 nêu | Feature dùng thư viện state khác nhau vẫn tách rời | review | review | [§15](#15-giao-tiếp-giữa-các-feature) |

### 60–69 · Kiểm thử, logging và báo lỗi

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-60 | Test nằm trong `test/` của chính package; package Flutter dùng `flutter_test`, package Dart thuần (`domain_*`, `data_core`, `platform_kernel`, `tools`) dùng `package:test` | CI Gate 3 tự tìm mọi thư mục `test/` | CI gate 3 (tự tìm; fail nếu không có), arch_check R2 / R9 (test của domain hay kernel ở lại trên `package:test`; `data_core` và `tools` chỉ do review giữ), review | `cd <package> && flutter test` | [§17](#17-kiểm-thử) |
| RULE-61 | Fake được viết tay — không mockito, không mocktail | Không codegen cho test; fake chính là lời mô tả contract | review | `grep -rnE "mockito\|mocktail" --include=pubspec.yaml .` (rỗng) | [§17](#17-kiểm-thử) |
| RULE-62 | Widget test có scale phải bọc widget được test trong `ResponsiveInit` | `ResponsiveScope.of` assert thay vì lặng lẽ dùng giá trị chưa scale | test (widget test fail ở assert) | `cd <package> && flutter test` | [§17](#17-kiểm-thử) |
| RULE-63 | Mỗi app giữ `test/di_smoke_test.dart`, boot đồ thị DI thật cho mọi flavor mà manifest khai, dựng mọi lazy singleton và mọi factory `@injectable` (lỗi chỉ ra tên type), đối chiếu đồ thị với khai báo của app (`checkAppContract`) và kiểm tra mọi platform và flavor đã khai đều khởi động được (`checkDeclaredStarts`); plugin được chạm tới trong lúc DI (`@preResolve`, `@PostConstruct(preResolve: true)`) có test double ở đó | Nó bắt lỗi thứ tự DI và đăng ký thiếu trước khi thiết bị gặp | test (`apps/*/test/di_smoke_test.dart`), CI gate 3; composer verify V12 (file tồn tại, gọi `checkAppContract` và dựng mọi factory) | `cd apps/mobile && flutter test test/di_smoke_test.dart` | [§17](#17-kiểm-thử) |
| RULE-64 | Thay đổi một gate tool (`arch_check`, `composer`, `docs_check`, `dependency_sync`, barrel generator, …) phải thêm vào `tools/test/` ca kiểm lẽ ra đã bắt được bug | Gate không có test mục ruỗng âm thầm | review (CI gate 1 chạy `tools/test`, nên ca kiểm đã có không thể hồi quy; không gì kiểm tra rằng một thay đổi đã thêm ca mới) | `cd tools && dart test` | [§17](#17-kiểm-thử) |
| RULE-65 | Chẩn đoán lúc chạy đi qua `dynamic_logger` (`DynamicLogger.log`), không bao giờ `print` hay `debugPrint`; CLI tool ghi bằng `stdout.writeln` / `stderr.writeln` | `print` lọt vào log bản release và không lọc được | analyzer (avoid_print), arch_check R19 (`print`, `debugPrint`, `debugPrintStack` trong `lib/` của platform, module và app) | `flutter analyze` · `dart tools/arch_check/check.dart` | [§18](#18-logging-báo-lỗi-và-bí-mật) |
| RULE-66 | Bí mật không bao giờ được commit (env prod, keystore release và API key nằm trong gitignore; keystore duy nhất được track là khoá dev công khai `apps/mobile/android/keystore-dev.jks`, giúp bản clone mới build được `dev` và không bao giờ ký bản release) và không bao giờ bị log (header `Authorization` / `Cookie` và trường thông tin đăng nhập bị che; log network chỉ bật khi `kDebugMode`) | Lịch sử git và log thiết bị bị rò rỉ | review, `.gitignore` (vật liệu ký và `env.prod` không bị track), test (`platform/infra/network/test/logging_interceptor_test.dart`: che header và body) | review | [§18](#18-logging-báo-lỗi-và-bí-mật) |
| RULE-67 | Báo crash và lỗi được cắm vào bằng cách đăng ký một `IErrorReporter` (và tuỳ chọn `IAnalytics`) trong app — không bao giờ tự gán `FlutterError.onError` / `PlatformDispatcher.instance.onError` (bootstrap của `platform_app_shell`, tức `runShellApp`, sở hữu và nối chuỗi chúng); app đã đăng ký một cái thì khai nó là `provided` trong `capabilities:` (RULE-81) | Hook của shell nối chuỗi mọi handler; ghi đè một cái là mất phần còn lại | review (không gán hook ngoài bootstrap), composer verify V3 và test (`apps/*/test/di_smoke_test.dart`: `checkAppContract`) cho khai báo `capabilities:` | review | [§18](#18-logging-báo-lỗi-và-bí-mật) |

### 70–79 · Công cụ, vệ sinh repo và tài liệu

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-70 | `flutter analyze` báo 0 issue — kể cả info — với `strict-casts`, `strict-inference`, `strict-raw-types` và các lint bổ sung | Kiểu chặt bắt được thứ review bỏ sót | analyzer, CI gate 2 | `flutter analyze` | [§16](#độ-nghiêm-của-analyzer) |
| RULE-71 | Không có comment `// ignore:` / `// ignore_for_file:` trong Dart viết tay và không có `analysis_options.yaml` riêng của package; `analysis_options.yaml` duy nhất ở gốc chỉ tắt một lint hay bỏ qua một mã lỗi khi có comment ngay bên cạnh nói rõ vì sao, và một `false` / `ignore` mới được review như một thay đổi luật; deprecation được migrate sau khi nghiên cứu cách thay thế | Tắt lint che mất bug thật tiếp theo | arch_check R13 (comment ignore, `analysis_options.yaml` riêng của package), review (mọi thay đổi ở `analysis_options.yaml` gốc) | `dart tools/arch_check/check.dart` | [§16](#16-công-cụ-và-vệ-sinh-code) |
| RULE-72 | Không có script PowerShell (`.ps1`): ưu tiên tool `.dart` đa nền tảng; `.sh` / `.bat` chỉ khi Dart không làm được | Chính sách thực thi của Windows chặn `.ps1` | arch_check R12 | `dart tools/arch_check/check.dart` | [§16](#16-công-cụ-và-vệ-sinh-code) |
| RULE-73 | Lệnh được viết không có tiền tố `fvm`; tool gọi toolchain phải phát hiện FVM qua `tools/shared/toolchain.dart` | Có `.fvmrc` không có nghĩa là đã cài `fvm` | review | review | [§16](#16-công-cụ-và-vệ-sinh-code) |
| RULE-74 | Version dependency chỉ nằm trong `pubspec_dependencies.yaml` và đến các member qua `dart tools/dependency_sync.dart` | Một catalog, không lệch theo package | CI gate 4 (`dependency_sync --check`: lệch version, và dependency hosted không có trong catalog) | `dart tools/dependency_sync.dart --check` | [§16](#16-công-cụ-và-vệ-sinh-code) |
| RULE-75 | Mỗi package dưới `modules/` và `platform/` có một barrel, `lib/<package>.dart`, và không có barrel thư mục; bên trong một package, file import file cụ thể, không bao giờ import barrel; barrel generator được chạy lại sau khi thêm, đổi tên hay xoá file trong `lib/` — sau gen-l10n / build_runner — và không ai thêm tay `export` vào barrel | Generator thay mọi `export` bằng danh sách của riêng nó và export các file sinh ra đang có trên đĩa | CI barrel gate (barrel cũ hoặc `export` thêm tay), analyzer (`prefer_relative_imports`: không import `package:` file của chính package), review (import tương đối barrel của chính nó; chạy generator sau codegen) | `dart tools/barrel_generator/generate.dart <package>/lib` | [§20](#20-workspace-codegen-và-barrel) |
| RULE-76 | File sinh ra (`*.g.dart`, `*.freezed.dart`, `*.module.dart`, `*.config.dart`) không bao giờ được commit và không bao giờ bị sửa tay; codegen là `dart run build_runner build --workspace`, không có `-d` | Lần chạy sau xoá mất chỗ sửa | `.gitignore` (file sinh ra không bị track), arch_check R6 (file giống file sinh ra nhưng thiếu header của generator bị commit), review (không có `-d`) | `dart run build_runner build --workspace` | [§20](#20-workspace-codegen-và-barrel) |
| RULE-77 | Analyze sạch không phải là build: thay đổi DI, dependency hay chuyển chỗ type kết thúc bằng một lần build APK debug, và type mà code sinh ra dùng được import từ nhà thật của nó, không bao giờ qua re-export giới hạn bằng `show` | Analysis bỏ qua code sinh ra | CI gate build (job APK debug), review (vế re-export) | `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev` | [§20](#20-workspace-codegen-và-barrel) |
| RULE-78 | File, class và package theo bảng đặt tên (`_page`, `_provider`, `_bloc`, `_usecase`, `_entity`, `i_<name>_repository`, `_repository_impl`, tiền tố tầng `core_` / `domain_` / `data_` / `feature_`); tiền tố `I` đánh dấu interface, không bao giờ là class cụ thể | Tên nói lên file là gì | arch_check R15 (tiền tố `I`), arch_check R3 (package module được đặt tên theo thư mục của nó), review (hậu tố file) | `dart tools/arch_check/check.dart` | [02_naming](02_naming.md) |
| RULE-79 | Docs thay đổi cùng PR với code, ở `docs/en` **và** `docs/vi` với cùng hình dạng; mọi đường dẫn repo được nhắc tới đều tồn tại; một luật được phát biểu một lần — ở đây — và nơi khác trích `RULE-NN` | Docs lệch dạy sai pattern | docs_check (CI gate 5), review | `dart tools/docs_check/check.dart` | [CONTRIBUTING § 5](../../../CONTRIBUTING.md#5-documentation-contract) |

### 80–89 · App và composition

| ID | Luật | Vì sao | Thực thi bởi | Kiểm chứng | Chi tiết |
|---|---|---|---|---|---|
| RULE-80 | Mọi thứ riêng của từng app được khai trong `apps/<id>/`: platform, flavor, env và capability trong `app_manifest.yaml`; hành vi của shell trong `lib/app/app_profile.dart`; code trong `lib/app/app_hooks.dart`. Một package platform không bao giờ hardcode giá trị mà một app có thể muốn khác (design size, trần text-scale, locale, pin, timeout, orientation, vị trí fallback, công tắc splash / push / deep link) | App thứ hai phải khác được mà không sửa `platform/` | composer verify (V1 từ vựng, V9 pin, V11 khoá env, V13 facts sinh ra), test (`apps/*/test/app_profile_test.dart`), analyzer (const assert của profile), review (không giá trị riêng của app nào bị hardcode trong `platform/`) | `dart tools/composer/composer.dart verify` | [§21](#21-app-và-composition) |
| RULE-81 | Mọi contract tuỳ chọn trong catalog của shell (`SHELL_CONTRACTS`) có một trạng thái được khai trong `capabilities:` của từng app — `provided`, hoặc `absent` kèm lý do — và khai báo đó được đối chiếu với code ở Gate 0, trong smoke test và lúc boot | Sự vắng mặt phải là một quyết định, không phải tai nạn | composer verify (V2–V4, V14), arch_check R16, test (`apps/*/test/di_smoke_test.dart`) | `dart tools/composer/composer.dart verify` · `dart tools/arch_check/check.dart` | [§21](#21-app-và-composition) |
| RULE-82 | Khác biệt giữa các platform là quyết định của app, đọc từ `PlatformFacts`; `Platform.is*`, `kIsWeb`, `defaultTargetPlatform` và `TargetPlatform.*` chỉ xuất hiện trong `resolveAppPlatform()` và các chỗ được allow-list trong `kPlatformForkAllowList` (API hệ điều hành không có trên web, quy ước của hệ điều hành như chuyển trang), mỗi chỗ kèm lý do | Một nơi duy nhất để canh đúng nhánh web; app khai được platform bật thứ gì | arch_check R17 | `dart tools/arch_check/check.dart` | [§21](#21-app-và-composition) |

### Thêm hoặc sửa một luật

1. Thêm một dòng vào dải phù hợp với id trống kế tiếp — không bao giờ đánh số lại, không bao giờ tái sử dụng. Luật bị bỏ vẫn giữ dòng của nó, đánh dấu **retired**, kèm nơi nó chuyển tới.
2. Ghi rõ thứ thực thi nó. Nếu không có gì tự động, ghi `review` — đừng ngụ ý một gate không tồn tại. Khi luật trở thành được máy kiểm, cập nhật cột **Thực thi bởi** trong cùng PR.
3. Đặt phần giải thích (vì sao, ngoại lệ, lịch sử) vào mục bên dưới hoặc guide phù hợp, và link từ cột **Chi tiết**.
4. Phản chiếu dòng đó ở [`docs/en/reference/01_rules.md`](../../en/reference/01_rules.md). Nếu luật thuộc nhóm bị vi phạm nhiều nhất, thêm câu một dòng của nó vào bảng luật hàng đầu trong `CLAUDE.md` — dưới dạng id và một dòng, không diễn giải lại.

---

## 1. Hướng phụ thuộc

Bảng đăng ký: RULE-01 · RULE-02 · RULE-03.

**Luật.** Phụ thuộc luôn hướng vào trong: `Feature → Domain ← Data`, với `platform/*` là hạ tầng nằm dưới. **Không package `platform/*` nào được phụ thuộc một package dưới `modules/`** (`feature_*`, `data_*`, `domain_*` của sản phẩm, `<id>_api`) — bằng import, bằng khai báo trong `pubspec.yaml` (`dependencies:` hay `dev_dependencies:`) hay bằng import trong test — và một cạnh trỏ vào `domain_core` / `data_core` chỉ tồn tại nếu nó là một trong các cạnh đã duyệt dưới đây. Luật **R1** của `arch_check` chặn mọi cạnh khác.

**Vì sao.** Platform là vòng hạ tầng trong cùng. Nếu nó với tay ngược lên trên, vòng tròn khép lại thành chu trình và không tầng nào phía trên có thể gỡ ra hay tái sử dụng độc lập được nữa.

**Domain nằm ở tâm và không phụ thuộc ai.** Trạng thái đã kiểm chứng:

| Package | Phụ thuộc workspace | Flutter SDK |
|---|---|---|
| `domain_core` | **không có** | không |
| `domain_auth` | `domain_core` | không |

### Ngoại lệ hướng lên được duyệt

Chỉ có đúng bốn. Thêm cái thứ năm bắt buộc phải cập nhật trang này (RULE-01, cả hai ngôn ngữ) và danh sách cho phép `_approvedUpwardEdges` trong `tools/arch_check/check.dart` — nếu không, tool sẽ làm fail build, và nó in danh sách này ở đầu mỗi lần chạy.

| Ngoại lệ | Lý do |
|---|---|
| `provider_state_management → domain_core` | Cần `Result<T>` và `AppFailure` cho `executeOperation` / `OperationConfig`. |
| `platform_kernel → domain_core` | `ErrorHandler` sinh ra `AppFailure`, class nằm ở `domain_core` như một phần của hợp đồng `Result`. Core→Domain là chiều **đúng** của Clean Architecture. |
| `bloc_state_management → domain_core` | `BlocViewState.error` mang thẳng `AppFailure`, nên kiểu state cơ sở cần nó. |
| `data_core → domain_core` | `BaseRepository` trả `Result<T>` và `AppFailure`, vốn nằm ở `domain_core`. Data→Domain là chiều **đúng** của Clean Architecture, và cả hai package đều là platform layer. |

> [!NOTE]
> Bốn cạnh này là những cạnh `platform → domain_core` duy nhất, và mọi cạnh platform khác đều theo chiều giữa các nhóm (`docs/vi/architecture/02_core.md` § 0): `ui` không bao giờ phụ thuộc `state`, `infra` không bao giờ phụ thuộc một package infra khác, và foundation không bao giờ phụ thuộc `ui` hay một transport. `core_ui_kit` không khai package quản lý state nào — `LoadMoreListView` nằm ở `provider_state_management` (`state → ui` là chiều được phép) — và `provider_state_management` tự trang bị `DefaultLoadingWidget` / `DefaultEmptyWidget` trong `lib/src/base_view/default_state_widgets.dart` thay vì mượn của `core_ui_kit`. Kernel không gọi tên kiểu Dio nào: `core_network` đóng góp `DioFailureClassifier` qua `ErrorHandler.registerClassifier`.

### Chiều giữa các nhóm platform (R11)

Bên trong `platform/`, luật **R11** của `arch_check` giữ DAG giữa các nhóm. Nhóm chính là thư mục — `platform/<group>/<package>` — và một package nằm ngoài thư mục nhóm hợp lệ tự nó là vi phạm. Chỉ `dependencies:` bị kiểm: dev dependency không bao giờ được ship (test của `platform_app_shell` dùng `core_storage` cho fake).

| Nhóm (thư mục) | Được khai package platform thuộc |
|---|---|
| `layers/domain` (`domain_core`) | không gì cả — là lá |
| `foundation` | foundation, `layers/domain` |
| `layers/data` (`data_core`, mọi `layers/*` khác) | foundation, `layers/domain` |
| `infra` | foundation, layers — không bao giờ một package infra khác |
| `ui` | foundation, ui |
| `state` | foundation, layers, ui |
| `shell` | mọi nhóm |

R11 cho phép một cạnh theo nhóm; R1 vẫn đòi danh sách đã duyệt của nó cho mọi cạnh từ package core trỏ vào `domain_core` / `data_core`.

**Kiểm chứng**

```bash
# R1 + R11 — phép kiểm chính thức; mỗi lần chạy đều in ra các cạnh đã duyệt
dart tools/arch_check/check.dart

# core tuyệt đối không được nhắc tên package feature, data hay domain của sản phẩm
grep -rn "package:feature_\|package:data_" platform/*/*/lib
grep -lE "^  (feature_|data_)" platform/*/*/pubspec.yaml
grep -rn "package:domain_" platform/*/*/lib | grep -v "package:domain_core"

# domain tuyệt đối không chạm Flutter
grep -rn "package:flutter" modules/*/domain/lib
```

`arch_check` phải pass, và bốn lệnh grep phải không trả về gì.

❌ **Sai** — package core mượn widget của feature:
```dart
// platform/state/provider/lib/src/base_view/base_view_widget.dart
import 'package:feature_auth/feature_auth.dart';   // core → feature
```

✅ **Đúng** — định nghĩa widget dự phòng ngay trong package core:
```dart
import 'default_state_widgets.dart';   // đi kèm package
```

---

## 2. Khai báo dependency tường minh

Bảng đăng ký: RULE-06.

**Luật.** Mọi `package:` import dùng trong `lib/` phải có mục tương ứng trong `pubspec.yaml` của chính package đó. Import phục vụ production nằm ở `dependencies`, không bao giờ ở `dev_dependencies`. Gỡ bỏ mục không còn dùng.

**Vì sao.** Pub Workspaces dùng chung một `package_config.json`, nên import thiếu khai báo **vẫn compile được cục bộ**. Lỗi chỉ lộ ra khi tách package ra hoặc publish — còn mục thừa thì tạo ra ràng buộc ma, che giấu vi phạm phân tầng thật.

**Kiểm chứng** — hai nửa của luật do hai tool kiểm:

```bash
dart tools/arch_check/check.dart                      # R5: import trong lib/ nhưng thiếu ở `dependencies:` (khai ở dev_dependencies không được tính)
dart tools/unused_checker/check_unused_packages.dart  # đã khai ở `dependencies:` nhưng không hề import (CI: bước cuối của job `quality`, có chặn merge)
```

R5 chỉ đọc `lib/`: import trong `test/` của một package không thuộc phạm vi của nó, và package chỉ test mới dùng thì thuộc về `dev_dependencies:`.

---

## 3. Hằng số nằm trong `utils/`

Bảng đăng ký: RULE-09.

**Luật.** Mọi package, ở mọi tầng, giữ hằng số public của chính nó trong thư mục `utils/` bên trong package đó. Package không có hằng số nào thì không cần thư mục `utils/` — luật **R4** của `arch_check` bắt `static const` public nằm ngoài `utils/` (hoặc `styles/`) và không bao giờ đòi một thư mục rỗng. Một hằng số có đúng **một** chủ sở hữu. Cấm tạo file constants dùng chung xuyên domain.

**Vì sao.** File constants dùng chung cho phép bất kỳ package nào đọc — và gõ nhầm — key của domain khác. Storage key và API endpoint là hai thứ dễ bị gom thành god-object nhất; cả hai đều thuộc về package sở hữu dữ liệu.

Quy ước đang áp dụng:

| Loại | Vị trí | Ví dụ thật |
|---|---|---|
| Route path | `lib/src/utils/<feature>_path.dart` | `modules/home/feature/lib/src/utils/home_path.dart` |
| Storage key | `lib/src/utils/<owner>_storage_keys.dart` | `platform/shell/adapters/lib/src/utils/theme_storage_keys.dart` |
| API endpoint (riêng, hoặc cùng key trong package nhỏ) | `lib/src/utils/<owner>_api_constants.dart`, hoặc `<owner>_constants.dart` cho cả hai | `modules/auth/data/lib/src/utils/auth_constants.dart` (`AuthApiConstants` và `AuthStorageKeys`) |

Class hằng số dùng private constructor và thành viên `UPPER_SNAKE_CASE`:

```dart
// modules/auth/data/lib/src/utils/auth_constants.dart
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
}
```

> [!NOTE]
> **Ngoại lệ được duyệt — design token.** `AppSpacing`, `AppRadius`, `AppTextStyles`, `AppGradients`, `AppShadows` ở nguyên `platform/ui/design_system/lib/src/styles/`, *không* chuyển vào `utils/`.
>
> Chúng là API công khai của design system, và `styles/` mang đúng ngữ nghĩa đó trong khi `utils/` đọc lên là "linh tinh". Di chuyển sẽ làm hỏng mọi tham chiếu trong docs mà chẳng được gì. **Đừng "sửa" chỗ này ở lần audit sau.**

Đáy ngăn xếp chỉ giữ giá trị thực sự dùng chung toàn cục: `EnvConstants` (nối `String.fromEnvironment`), `ProfileConstants` (các công tắc `--dart-define` lúc build của app profile) và `ErrorCodes` (mã lỗi `ErrorHandler` gán). Chúng nằm trong `lib/src/utils/` của `platform_kernel` và `core_common` re-export toàn bộ kernel. Hằng số riêng của một package ở lại với package đó — id channel thông báo là `NotificationConstants` trong `platform/infra/notifications/lib/src/utils/`, endpoint của auth là `AuthApiConstants` trong `modules/auth/data/lib/src/utils/`.

---

## 4. Storage do package sở hữu

Bảng đăng ký: RULE-44 · RULE-45.

**Luật.** `core_storage` chỉ cung cấp **cơ chế** và định nghĩa **zero** key. Mỗi nơi tiêu thụ tự inject `StorageManager`, tự khai `StorageValue<T>` của mình, key lấy từ class trong `utils/` của chính nó.

**Vì sao.** Một object dùng chung giữ `StorageValue` của mọi domain thì ai inject nó vào cũng đọc hoặc xoá được dữ liệu của feature khác. Cô lập được cưỡng chế bằng đồ thị phụ thuộc: package không khai `data_auth` thì không thể với tới `AuthStorageKeys`.

Đăng ký **bắt buộc là singleton** kèm `@PostConstruct(preResolve: true)`:

```dart
// modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  /// Hydrates the cache from disk at startup, so [getUserToken] is correct from
  /// the first read.
  @PostConstruct(preResolve: true)
  Future<void> initialize() => _token.readFromStorage();
```

> [!CAUTION]
> **Cấm** đăng ký storage owner bằng `@injectable` (factory). Mỗi lần inject sẽ dựng instance mới với cache rỗng, nên getter đồng bộ âm thầm trả `null` — không báo lỗi, chỉ đơn giản là sai dữ liệu.

Chọn backend tường minh: `StorageType.secure` cho token và PII, `StorageType.pref` cho cài đặt và cờ. Tuyệt đối không trao `StorageValue` của package này cho package khác — hãy công bố interface trên `core_di` (như `IThemeStorage` / `ILanguageStorage` đang làm).

Các owner hiện có:

| Owner | Package | Key | Backend |
|---|---|---|---|
| `AuthLocalDataSource` | `data_auth` | `token` | secure |
| `ThemeStorageImpl` | app shell (`platform_shell_adapters`) | `themeMode` | pref |
| `LanguageStorageImpl` | app shell (`platform_shell_adapters`) | `locale` | pref |
| `AppBootStorage` | app shell (`platform_shell_adapters`) | `viewed_onboard` | pref |

Hướng dẫn đầy đủ: [`../guides/06_storage.md`](../guides/06_storage.md).

---

## 5. Thứ tự đăng ký DI

Bảng đăng ký: RULE-13 · RULE-63.

**Luật.** Một `@Singleton` eager tuyệt đối không được phụ thuộc type do module khởi tạo **sau** nó trong `configureDependencies()`. Dùng `@LazySingleton` khi phụ thuộc đến từ module chạy sau.

**Vì sao.** GetIt sẽ ném `"<Type> is not registered"` ngay lúc boot. Module khởi tạo theo đúng thứ tự khai trong `apps/mobile/lib/di/injection.dart`, được sinh từ `di_groups` của manifest: `core` (before), rồi — sau phần đăng ký của chính app — `notifications`, `shell`, `ui`, `domain`, `data`, `feature`, `other` (after). `apps/admin` không có nhóm `notifications`.

Có hai ràng buộc đang có hiệu lực. `shell` trước `ui`: `ThemeProvider` trong `core_base_ui` inject `IThemeStorage`, do `platform_shell_adapters` đăng ký (đứng đầu nhóm `shell`) — đảo hai nhóm là app hỏng lúc boot. Và `notifications` sau phần đăng ký của chính app: `PushNotificationService` là eager và inject `FirebaseOptions` do app đăng ký, nên `core_notifications` không thể nằm trong `core`.

> [!CAUTION]
> **`flutter analyze` KHÔNG bắt được loại lỗi này** — nó chỉ lộ ra lúc chạy, trên một lần boot. Lần boot đó chính là việc `test/di_smoke_test.dart` của mỗi app làm (RULE-63): mọi flavor, plugin thay bằng test double, mọi lazy singleton và mọi factory `@injectable` được dựng. CI Gate 3 chạy nó, nên lỗi thứ tự làm fail PR chứ không phải lần mở app đầu tiên.

**Kiểm chứng**

```bash
cd apps/mobile && flutter test test/di_smoke_test.dart
cd apps/admin && flutter test test/di_smoke_test.dart
```

**Chẩn đoán** — khi smoke test báo `"<Type> is not registered"`, đọc hai loại file sinh ra. `apps/mobile/lib/di/injection.config.dart` chỉ chứa **thứ tự module** (mỗi package một lệnh `…PackageModule().init(gh)`, cộng phần `FirebaseOptions` của chính app); còn đăng ký theo từng type — kèm các lệnh `gh<Dep>()` mà constructor của nó gọi — nằm trong `lib/di/module.module.dart` của từng package. Một `gh.singleton…` eager (kể cả `singletonAsync`) chỉ an toàn khi mọi `gh<Dep>()` nó gọi đã được đăng ký phía trên nó trong chính file đó, hoặc bởi một module có `init` chạy sớm hơn:

```bash
dart run build_runner build --workspace
grep -n "PackageModule().init" apps/mobile/lib/di/injection.config.dart       # thứ tự module
grep -rn -A4 "gh.singleton" platform/*/*/lib/di/module.module.dart modules/*/*/lib/di/module.module.dart   # đăng ký eager và các lệnh gh<Dep>() của nó
```

`@PostConstruct(preResolve: true)` trên `@lazySingleton` được await trong lúc module init rồi đăng ký lại thành lazy singleton đồng bộ thuần, nên các lệnh `gh<T>()` đồng bộ về sau đều an toàn.

---

## 6. Ranh giới feature và khả năng gỡ bỏ

Bảng đăng ký: RULE-04 · RULE-05 · RULE-12 · RULE-24.

**Luật.** Một feature = một mối quan tâm UI. Feature A tuyệt đối không import feature B — không có ngoại lệ; widget dùng chung lấy từ `core_ui_kit`, vốn là core. **App phải build và chạy được khi gỡ bỏ bất kỳ package feature nào.**

**Vì sao.** Một template mà không xoá được feature thì không phải template. Khả năng gỡ bỏ cũng chính là bằng chứng thực tế rằng ranh giới là có thật.

**Được máy cưỡng chế.** `arch_check` **R3** chặn một feature import feature khác (hay bất kỳ package data nào), **R8** chặn `getIt` / `getAll` kiểu ném lỗi trên một hợp đồng chỉ do module hiện thực, còn **R10** chặn việc *import* một module — kể cả package API của nó — ở bất cứ đâu trong app trừ `injection.dart`. R10 tồn tại vì riêng R8 là chưa đủ: `getItOrNull` canh một lookup, còn một import không giải được thì hỏng ngay ở khâu biên dịch, trước khi có lookup nào chạy. Nó đọc mọi file `.dart` của app — `lib/`, `test/`, `integration_test/`, `test_driver/`, `tool/` — nên một test nêu tên module cũng bị từ chối; chỉ `lib/di/injection.dart` được phép.

Mọi thứ app shell tiêu thụ lúc chạy đều đi qua một hợp đồng `core_di` kèm fallback:

| Cách tra cứu | Hành vi khi không có gì đăng ký |
|---|---|
| `getAllOrEmpty<T>()` | danh sách rỗng |
| `getItOrNull<T>()` | `null` |
| `getAll<T>()` | **ném lỗi** — đừng dùng cho đóng góp tuỳ chọn |

> [!WARNING]
> `getAll<T>()` và `getAllOrEmpty<T>()` khác nhau đúng ở chỗ này. `getAll` ném lỗi khi type chưa đăng ký, nên một lệnh `getAll<IFeatureLocalization>()` trần sẽ làm app crash ngay lúc dựng `MaterialApp` ở bất kỳ bản build nào không có feature nào đóng góp.

**Cưỡng chế bằng máy.** Luật **R8** của `arch_check` tự suy ra mọi contract của `core_di` và mọi type của `<id>_api` được implement bởi một package dưới `modules/` — ở bất kỳ tầng nào: `ISessionGateway` trong `data_auth` cũng tính như navigator của một feature — gắn với module implement nó, rồi chặn mọi lookup dạng ném lỗi lên chúng — `getIt<T>()`, `getIt.get<T>()`, `getAll<T>()`, `GetIt.I<T>()`, kể cả qua một alias khai trong cùng file — và cả class `@injectable` nằm ngoài mọi module mà nhận một contract như vậy làm tham số constructor bắt buộc:

```bash
dart tools/arch_check/check.dart      # luật R8 — Gate 1 của pr_quality_check.yml
```

Đây không phải luật về phong cách. Lookup ném lỗi vẫn **compile được**: package gọi nó phụ thuộc `core_di` chứ không phụ thuộc feature implement contract đó, nên `flutter analyze` không thấy gì sai. Nó chỉ vỡ lúc runtime, ở bản build không có feature đó, trên đúng màn hình nào gọi tới. (Một alias của `GetIt` đi qua nhiều file thì không theo dõi được; review giữ phần đó.) Contract do app shell implement (`IThemeStorage`, `ILanguageStorage`) thì luôn được đăng ký nên nằm ngoài tập hợp này. Module bị gỡ nguyên khối, nên mọi package của chính module implement được phép resolve contract của nó theo kiểu eager.

**Gỡ một feature** — manifest là file duy nhất sửa bằng tay:

1. dòng của nó trong mục `modules:` ở mọi `apps/<id>/app_manifest.yaml` có ghép nó;
2. nếu một capability mất nơi cung cấp cuối cùng, `dart tools/composer/composer.dart reconcile --reason "<why>"` khai nó `absent` trong các manifest (hoặc tự viết dòng `capabilities:` đó) — `composer verify` (V3) từ chối `provided` cho contract không còn gì đăng ký;
3. `dart tools/composer/composer.dart sync`, lệnh này sinh lại `injection.dart`, path dependency của app và danh sách `workspace:` ở root;
4. xoá các thư mục package của module (`modules/<id>/<layer>/`, rồi `modules/<id>/`): `composer verify` báo lỗi với package còn trên đĩa nhưng không thuộc cách ghép của app nào;
5. `flutter pub get` + `dart run build_runner build --workspace`.

Package mà một package khác vẫn liệt kê trong `pubspec.yaml` sẽ ở lại workspace (composer đi theo dependency), nên hãy bỏ các dependency và import đó trước.

Các import trong `injection.dart` là **tham chiếu cứng có chủ đích duy nhất** của app shell tới feature — với vai trò composition root, nó buộc phải gọi tên những gì nó lắp ráp. Mọi consumer khác đều đi qua `core_di` (hợp đồng trung lập với sản phẩm) hoặc package API của module sở hữu.

### Package API của module

Một hợp đồng tồn tại để một feature chạm tới **module khác** — navigator, action handler của nó — nằm trong package API của module đó, `modules/<id>/api`, tên `<id>_api` (`auth_api`, `home_api`). `core_di` chỉ giữ hợp đồng trung lập với sản phẩm, đặt tên theo thứ platform cần: phiên đăng nhập (`ISessionState`, `ISessionStatusStream`, …) và nơi shell đưa người dùng đã đăng xuất / đã đăng nhập tới (`ISignInLocation`, `IPostSignInLocation`).

| Luật | Cưỡng chế bởi |
|---|---|
| Package API chỉ phụ thuộc `platform/foundation/*` và package Flutter/pub — không phụ thuộc domain/data/feature của chính module, module khác hay API của nó, hay nhóm platform khác | `arch_check` R3 (import và pubspec) |
| Feature được import package API của module khác, không bao giờ import package feature hay data của nó | `arch_check` R3 |
| Type khai trong package API và chỉ được implement dưới `modules/` phải resolve bằng `getItOrNull` / `getAllOrEmpty` bên ngoài module của nó | `arch_check` R8 |
| Không package platform nào và không file app nào (trừ `injection.dart`) import package API | `arch_check` R1, R10 |

Package API được lắp ráp như layer `api` (`- { id: auth, layers: [api, domain, data, feature] }`): một workspace member, không bao giờ là dependency của app hay một mục trong `injection.dart`. `remove_sample <id>` gỡ nó cùng module — trừ khi một package ngoài bundle vẫn import nó; khi đó nó được **giữ lại**, tên các package import nó được in ra, và manifest giữ `{ id: <id>, layers: [api] }`, nên build vẫn biên dịch và lookup của nơi dùng trả về null.

**Kiểm chứng**

```bash
# sau khi gỡ một feature (và xoá các thư mục của nó)
dart tools/composer/composer.dart sync
dart tools/composer/composer.dart verify
flutter pub get && dart run build_runner build --workspace
dart tools/arch_check/check.dart
flutter analyze
```

---

## 7. Domain là Pure Dart

Bảng đăng ký: RULE-03 · RULE-49.

**Luật.** Không `package:flutter/...`, `package:dio/...`, `package:retrofit/...`, hay bất kỳ thư viện UI/network nào trong `modules/*/domain`. Khái niệm UI phải được dịch sang kiểu nguyên thuỷ hoặc enum.

**Vì sao.** Domain là tầng duy nhất nên sống lâu hơn lựa chọn framework. Điều này được đảm bảo ngay ở mức package graph: không `pubspec.yaml` domain nào khai Flutter SDK, và `domain_core` có zero phụ thuộc workspace.

Thành phần: `entities/` (Freezed, có `const Class._()`), `params/`, `repositories/` (interface), `usecases/` (`@injectable`, trả `Result<T>`), `utils/`.

---

## 8. Tầng Data

Bảng đăng ký: RULE-40 · RULE-41 · RULE-42 · RULE-43.

**Luật.**

- Thư mục là `data_sources/remote/` và `data_sources/local/` — **snake_case, số nhiều `data_sources`**, không bao giờ là `datasources/`.
- `RepositoryImpl` kế thừa `BaseRepository` và bọc công việc trong `execute()` (async) hoặc `executeSync()`.
- Lỗi chuyển đổi qua `ErrorHandler.handleError(e)`. **Không bao giờ** dùng `AppFailure.fromException()`.
- **DataSource trả Model, không bao giờ trả Entity** — và không bao giờ trả class do Drift sinh. Lớp bọc duy nhất được phép là envelope phản hồi `BaseEntity<T>` của `domain_core`: `AuthRemoteDataSource` trả `Future<BaseEntity<UserModel>>`, và repository bóc nó ra trong `mapper` của `execute`.
- Không bao giờ `throw` từ Data lên UI; trả về `Result.failure(AppFailure)`.

**Vì sao có luật Model.** Trả về class row của Drift làm rò rỉ thư viện lưu trữ vào mọi nơi tiêu thụ package. `CacheEntryModel` (`modules/cache/data/lib/src/models/cache_entry_model.dart`) tồn tại thuần tuý làm lớp chắn đó.

---

## 9. Freezed, BLoC và state

Bảng đăng ký: RULE-50 · RULE-51 · RULE-52 · RULE-53.

**Luật.**

- Subclass event của BLoC phải **private**: `const factory HomeProfileEvent.started() = _HomeProfileStarted;`
- Dùng `part` / `part of`: `home_profile_bloc.dart` khai `part 'home_profile_event.dart';` và `part 'home_profile_bloc.freezed.dart';`
- Handler nhận đủ hai tham số và phải `async`: `Future<void> _onAuthStatusChanged(_HomeProfileAuthStatusChanged event, Emitter<BlocViewState<SessionPrincipal?>> emit) async` (`modules/home/feature/lib/src/bloc/home_profile_bloc.dart`). `arch_check` R18 từ chối `on<Event>` mà handler không `async`

> [!CAUTION]
> Closure đồng bộ gọi việc async mà không await sẽ sinh ra `emit was called after an event handler completed normally` — handler trả về ngay lập tức, rồi việc async mới emit vào một sink đã đóng.

**Tồn tại hai kiểu state và chúng khác nhau.** Bản BLoC mang tên `BlocViewState<T>` để một file import cả hai barrel công khai không bao giờ gặp hai type cùng tên `ViewState`:

| | `ViewState` (Provider) | `BlocViewState<T>` (BLoC) |
|---|---|---|
| File | `platform/state/provider/lib/src/base/view_state_model.dart` | `platform/state/bloc/lib/src/bloc_view_state.dart` |
| Generic | không | có |
| Số variant | 5 (có `loadingMore`) | 4 |
| Lỗi | `error({ErrorState? error})` — nullable | `error(AppFailure error)` — bắt buộc |
| Chứa data | không (data nằm ở `ViewStateModel<T>`) | có |

> [!WARNING]
> `BaseBloc` / `BaseCubit` là **điểm mở rộng rỗng**. Bản tương đương `executeOperation` ở nhánh BLoC là tuỳ chọn: mix in `BlocResultMixin<T>` / `CubitResultMixin<T>` (`bloc_state_management`) rồi gọi `emitResult` — loading, success, failure, none/cancel và exception được xử lý sẵn. Handler nào không dùng nó thì tự unwrap `Result`.

---

## 10. Vòng đời controller

Bảng đăng ký: RULE-10 · RULE-21.

**Luật.** Controller gắn với màn hình là `@injectable` (factory). Các controller toàn app nêu trong RULE-10 — `ThemeProvider`, `LanguageProvider`, `DeeplinkProvider`, `AuthProvider` — là `@lazySingleton`. Controller được khởi tạo **tại route**, trong `build` của `*_route_module.dart`.

**Vì sao.** ViewModel `@singleton` bị GetIt giữ mãi mãi, nên pop màn hình là rò rỉ nó, và lần vào tiếp theo sẽ dùng lại state cũ.

> [!CAUTION]
> Nếu route đã bọc page trong `BlocProvider` / `ChangeNotifierProvider` thì widget `Page` **không được** bọc lại lần nữa. Bọc hai lần sẽ dựng hai controller; cái mà UI đọc không phải cái route tạo ra.

---

## 11. Routing

Bảng đăng ký: RULE-20 · RULE-22 · RULE-23 · RULE-24.

**Luật.** Tuyệt đối không sửa `platform/shell/app_shell/lib/src/navigation/app_router.dart` để thêm route. Thay vào đó feature tự đăng ký một hợp đồng `core_di`:

| Hợp đồng | Mục đích | Có thứ tự? |
|---|---|---|
| `IFeatureRouteModule` | route dạng stack dưới `ShellRoute` của app | không (khớp theo path) |
| `INavDestinationModule` | một tab bottom-nav + một `StatefulShellBranch` | **có** — `order` tăng dần |
| `IAppEntryLocation` | `initialLocation` của lần vào đầu — mặc định chỉ ở lần chạy đầu tiên, các lần cold-start sau dùng fallback (`RouterProfile.entry`) | không áp dụng |
| `IDashboardRouteModule` | chỉ phần chrome của dashboard | chỉ `feature_dashboard` |

Điều hướng xuyên feature đi qua interface Navigator khai trong package API của module sở hữu (`modules/<id>/api`, ví dụ `AuthNavigator` trong `auth_api`), implement trong `routing/` của feature thuộc module đó, và resolve bằng `getItOrNull`. App shell không dùng navigator của module nào: nó đưa người dùng tới `ISignInLocation` / `IPostSignInLocation` (`core_di`), fallback về `AppRouter.fallbackLocation`. Cấm hardcode path hoặc gọi `GoRouter.of(context).go(...)` sang feature khác. **`BuildContext` phải được truyền trực tiếp từ nơi gọi ở UI** — đừng với lấy `NavigatorKeys.*.currentContext`.

`feature_dashboard` **chỉ là chrome**: không được import feature tab, không sở hữu page của tab, không hardcode danh sách destination, và không tự đăng ký `INavDestinationModule`. Chỉ dùng `INavDestinationModule` cho destination chính cần một `StatefulShellBranch` ổn định, và giữ `order` của nó duy nhất — smoke test DI kiểm điều này.

---

## 12. Responsive UI

Bảng đăng ký: RULE-30 · RULE-31 · RULE-32.

**Luật.** Mọi kích thước — rộng, cao, padding, margin, cỡ chữ, bo góc — đều phải scale **qua `BuildContext`** bằng `core_responsive`: `context.w(x)`, `context.h(x)`, `context.sp(x)`, `context.r(x)` (và `context.spMin`, `context.dg`, `context.dm`). Cấm double thô trong layout, và cấm luôn dạng gọi trên receiver trần `16.h`.

**Vì sao dạng trần thậm chí không tồn tại.** `core_responsive` **không** cung cấp extension nào trên `num`, nên `16.h` không biên dịch được. Đó là chủ đích: một con số không mang theo context, nên extension kiểu đó chỉ có thể đọc một singleton toàn cục, mà widget đọc singleton thì không bao giờ biết metrics màn hình đã đổi. Ngược lại, `context.h(16)` **đăng ký dependency InheritedWidget** lên `ResponsiveScope`, nên nó rebuild khi metrics đổi: xoay máy, split-screen, resize cửa sổ desktop. Bắt buộc phải có context chính là cách biến "làm đúng" thành lựa chọn duy nhất viết được — và luật R7 của `arch_check` từ chối dạng trần trong mọi file `lib/` viết tay, không chỉ các file import `core_responsive`, cùng mọi extension trên `num` khai `w`, `h`, `r`, `sp`, `spMin`, `dg` hay `dm`, nên một extension khai ở nơi khác cũng không lén đưa nó trở lại được.

❌ **Sai** — không biên dịch được, và nếu có thì giá trị cũng sẽ cũ dần:
```dart
SizedBox(height: 16.h)
```

✅ **Đúng** — theo dõi được thay đổi metrics:
```dart
SizedBox(height: context.h(16))
```

**Design token cũng nhận context:** `AppSpacing.lg(context)`, `AppRadius.xxlRadius(context)`, `AppTextStyles.bodyMediumStyle(context)`. Con số nằm trong các hằng `raw*` — sửa `raw*`, đừng sửa accessor. Không bao giờ scale lại một token đã scale.

**Không có context trong tầm với?** Trong hàm `async`, hãy đọc giá trị từ context **trước lệnh `await` đầu tiên** rồi truyền đi. Tuyệt đối không giữ `BuildContext` xuyên qua `await`. Mẫu minh hoạ — không màn hình nào trong template cần tới:

```dart
Future<void> _loadAvatar() async {
  final side = context.w(96).toInt();   // đọc khi context còn hợp lệ
  final bytes = await _repository.fetchAvatar(size: side);
  if (!mounted) return;                 // lúc này widget có thể đã bị huỷ
  setState(() => _avatar = bytes);
}
```

**Trục scale của các helper** — đọc từ `platform/ui/responsive/lib/src/context_extension.dart`:

| Helper | Scale theo |
|:--|:--|
| `context.edgeInsets(all: x)` | `w` |
| `context.edgeInsets(horizontal: x)` | `w` |
| `context.edgeInsets(vertical: x)` | `h` |
| `context.edgeInsetsDirectional(start: x)` / `(end: x)` | `w` — đảo theo chiều văn bản |
| `context.borderRadius(all: x)` | `r` |
| `context.verticalSpace(x)` | `h` |
| `context.horizontalSpace(x)` | `w` |

> [!WARNING]
> `context.edgeInsets` scale mỗi trục theo đúng trục của nó — ngang theo `w`, dọc theo `h`, và `all:` theo `w`, nên nó thay thế trực tiếp được `EdgeInsets.all(context.w(16))`. `borderRadius` là ngoại lệ: nó dùng `r`, vì bán kính chỉ scale theo một trục sẽ biến hình tròn thành elip. Khi không chắc, hãy viết dạng tường minh vì nó nói rõ đang scale theo trục nào.

**Widget dùng lại dùng tham số đúng như nhận được và không được scale chúng.** Scale là việc của nơi gọi, nên giá trị đến nơi đã ở đơn vị pixel thiết bị. Còn hằng số **của chính** widget thì nó vẫn scale — `widget.paddingBottom ?? context.h(10)` đúng ở cả hai vế.

❌ **Sai** — một lệnh ghi đè bên trong âm thầm vứt bỏ giá trị của caller:
```dart
// bên trong một widget dùng lại của core_ui_kit
@override
double? get leadingWidth => context.w(64);   // ghi đè super.leadingWidth vĩnh viễn
```

✅ **Đúng** — nhận tham số qua constructor, để nơi gọi tự scale.

**Kích thước không to ra trên tablet.** Mọi hệ số đều bị kẹp bởi một `ScaleBounds`, và mặc định `ScaleBounds.downOnly()` dừng ở 1:1: cửa sổ nhỏ hơn khung thiết kế thì thiết kế thu nhỏ, cửa sổ lớn hơn thì vẽ đúng cỡ thiết kế. Đừng tinh chỉnh màn hình với kỳ vọng `context.w(16)` sẽ lớn hơn trên iPad — hãy dùng chỗ dư cho layout. Nếu một lớp cửa sổ thực sự nên to ra, app opt-in cho riêng lớp đó trong profile của mình bằng một chính sách có chặn (`DisplayProfile(scale: {WindowClass.expanded: ScalePolicy.fixed(), WindowClass.large: ScalePolicy.bounded(max: 1.2)})` trong `lib/app/app_profile.dart`, RULE-80; `scale` thay thế map của template chứ không gộp với nó, nên hãy giữ mục `expanded`). Xem [design system §6](../guides/11_design_system.md#6-đặt-chính-sách-scale-theo-từng-lớp-cửa-sổ).

**Chọn layout theo lớp kích thước cửa sổ, không bao giờ theo thiết bị.** Dùng `context.windowSizeClass`, `context.adaptive(...)`, `AdaptiveLayout` hoặc `AdaptiveSplitView` — đừng bao giờ dùng đời máy, `Platform.isIOS` hay một phép kiểm `shortestSide` tự chế. Một thiết bị có nhiều cửa sổ — iPad đang Split View, màn hình ngoài của máy gập, cửa sổ desktop bị kéo hẹp — và chỉ lớp cửa sổ mới thấy được chúng. Việc dashboard đổi giữa bottom bar và rail là mẫu tham chiếu; xem [design system §7](../guides/11_design_system.md#7-bố-cục-cho-tablet-máy-gập-và-chia-đôi-màn-hình).

❌ **Sai** — một phép kiểm "tablet" tự chế: ngưỡng riêng, không biết breakpoint của app, và nó hỏi "đây có phải tablet?" thay vì "cửa sổ này có đủ rộng cho hai ô?":
```dart
final twoPane = MediaQuery.sizeOf(context).shortestSide >= 600;
```

✅ **Đúng** — lớp chiều rộng của cửa sổ, theo breakpoint của app:
```dart
final twoPane = context.isExpandedOrWider;
```

**Kiểm chứng**

```bash
dart tools/arch_check/check.dart      # luật R7 — mọi dạng gọi scale bare; luật R20 — số thô trong tham số layout
```

Hai nửa của luật này được **cưỡng chế bằng máy**: R7 (extension trần) và R20 (số thô làm giá trị của tham số layout hay vẽ — `SizedBox`, `EdgeInsets`, `BorderRadius`, `fontSize:`, các tham số kích thước của `Container`, `Icon`, `Positioned`, … — trong `lib/` ngoài `styles/` và `utils/`) chạy như Gate 1 của `pr_quality_check.yml` ở mọi PR và in `file:line` cho từng vi phạm. R20 là phép quét từ vựng trên các constructor nó liệt kê: số double thô đi qua biến hay widget không được liệt kê, thứ tự đọc trước `await`, chính sách scale và việc chọn lớp cửa sổ do review giữ.

---

## 13. Đa ngôn ngữ và asset

Bảng đăng ký: RULE-34 · RULE-35 · RULE-37.

**Luật.** Toàn bộ chữ hiển thị cho người dùng phải được dịch — cấm hardcode chuỗi UI. Mỗi feature sở hữu file `.arb` trong `assets/language/` của mình và đăng ký `IFeatureLocalization` qua DI. Truy cập qua extension của feature: `context.l10nAuth.someKey`.

Feature **không được** sửa shell để thêm delegate; `platform/shell/app_shell/lib/src/app_material_wrapper.dart` tự gom chúng bằng `getAllOrEmpty<IFeatureLocalization>()`.

Chuỗi toàn cục nằm ở `core_base_ui`. `core_ui_kit` **không được** định nghĩa `.arb` riêng — nó dùng của `core_base_ui`.

**Asset cũng thuộc về feature.** Ảnh, SVG và animation riêng của một feature nằm trong `assets/` của chính feature đó (ví dụ có sẵn là `modules/auth/feature/assets/language/`; ảnh đặt cạnh đó trong một `assets/images/` do feature tự tạo). `core_base_ui` dành riêng cho asset toàn cục — logo app, icon toàn cục, font — và chuỗi dự phòng toàn cục, và không chứa widget nào.

**Khóa ARB dùng `lowerCamelCase`.** `flutter gen-l10n` biến mỗi khóa thành getter Dart nguyên văn, nên khóa `snake_case` sinh ra `context.l10nAuth.welcome_back` — một định danh phá vỡ quy ước đặt tên của chính Dart ở mọi nơi gọi. File sinh ra bị loại khỏi analysis, nên không linter nào báo cho bạn; `arch_check` R21 thì có, và còn chặn một locale có tập khoá khác `en.arb`, vì `gen-l10n` chỉ ghi `untranslated-messages.txt` còn màn hình lặng lẽ hiện tiếng Anh. Hãy chọn kiểu viết ngay trong `.arb`; đó là nơi duy nhất bạn chọn được.

**`AppFailure.message` là chữ dành cho lập trình viên.** Đó là thứ `ErrorHandler` hay một data source viết cho log, không phải cho màn hình. Màn hình hiển thị một chuỗi đã dịch được chọn từ `code` của failure — `core_base_ui` có sẵn ánh xạ chung `context.l10n.failureMessage(failure.code)` (`failure_message_extension.dart`, được test trong `platform/ui/design_system/test/failure_message_test.dart`), và feature nào nói được cụ thể hơn thì dùng ARB riêng — và không bao giờ hiển thị `message` thô.

---

## 14. Dialog và bottom sheet

Bảng đăng ký: RULE-36.

**Luật.** Mỗi dialog và bottom sheet là một class widget riêng trong file riêng. Cấm viết cây widget inline bên trong `showDialog()` / `showModalBottomSheet()`.

Hậu tố: `_dialog.dart` → `Dialog`, `_bottom_sheet.dart` → `BottomSheet`. Ví dụ thật: `platform/ui/ui_kit/lib/src/dialogs/retry_dialog.dart`.

---

## 15. Giao tiếp giữa các feature

Bảng đăng ký: RULE-08 · RULE-14 · RULE-25 · RULE-54.

**Luật.** Sáu mô hình được công nhận; chọn theo thứ bạn cần chia sẻ.

| # | Nhu cầu | Cơ chế |
|---|---|---|
| 1 | Logic nghiệp vụ | UseCase Domain dùng chung |
| 2 | Hạ tầng | core service (`core_storage`, `core_network`, …) |
| 3 | State xuyên feature | interface `Stream` / `ValueListenable` trung lập trên `core_di`, đăng ký kép |
| 4 | Tuỳ chọn UI thuần (theme, locale) | bỏ qua Domain → interface storage ở `core_di` → impl ở app shell |
| 5 | Nhúng widget của feature khác | builder interface trong `<id>_api` của module sở hữu |
| 6 | Hành động UI xuyên feature | `I*ActionHandler` trong `modules/<id>/api/lib/src/actions/` của module sở hữu |

**Đăng ký kép** (mô hình 3): feature sở hữu đăng ký class cụ thể là `@singleton`, rồi bind interface qua `@module` của DI:

```dart
// modules/auth/feature/lib/di/module.dart
@module
abstract class AuthDiModule {
  /// The neutral session stream other features listen to.
  @singleton
  ISessionStatusStream bindISessionStatusStream(AuthStatusStreamImpl impl) =>
      impl;
  // …
}
```

Nhờ vậy chủ sở hữu inject được type cụ thể qua constructor, còn mọi feature khác chỉ nhìn thấy interface.

> [!NOTE]
> GetIt phân giải theo **đúng type**, không bao giờ theo supertype. Đăng ký `Impl as InterfaceA` **không** làm cho `getIt<InterfaceB>()` chạy được, kể cả khi `InterfaceA implements InterfaceB` — phải bind riêng từng cái. Xem `modules/auth/feature/lib/di/module.dart`, nơi `AuthProvider` được bind một lần cho mỗi contract nó implement (`ISessionState`, `ISessionRefreshListenable`).

Đừng dùng Action Handler cho điều hướng thuần (dùng Navigator) hay cho logic thuần Domain (dùng UseCase).

**Contract của `core_di` giữ trung lập** (RULE-08). Contract không bao giờ nêu tên một type `domain_*` — nó khai một value type nhỏ hơn, do contract sở hữu (`SessionPrincipal`), mà chủ sở hữu ánh xạ sang ở biên của mình (`AuthStatusStreamImpl.updateAuthStatus`). Nó trả về type Flutter thuần (`IAppTreeWrapper.wrap()` trả `Widget`) để không thư viện state nào bị ép lên bên kia, và ưu tiên `sealed class` của Dart 3 hơn Freezed (`SessionFailure`): `core_di` chỉ chạy codegen của injectable, và một file `part` trên contract sẽ bắt mọi bên tiêu thụ chờ `build_runner`. State UI toàn cục (theme, ngôn ngữ, deep link) dùng một tiện ích trung lập duy nhất — `ChangeNotifier` / `ValueNotifier` hoặc `Stream` thuần — để không feature nào bị ép import thư viện state nó không dùng.

---

## 16. Công cụ và vệ sinh code

Bảng đăng ký: RULE-70 · RULE-71 · RULE-72 · RULE-73 · RULE-74.

| Luật | Chi tiết |
|---|---|
| Cấm `print()` trong `tools/` | dùng `stdout.writeln()` / `stderr.writeln()` |
| Cấm tắt lint | `// ignore:` và `// ignore_for_file:` bị cấm, và không package nào có `analysis_options.yaml` riêng (R13); lint bị tắt trong file gốc phải có comment nói rõ vì sao; hãy tìm cách migrate thật |
| Cấm script PowerShell | `.ps1` bị cấm (chính sách thực thi của Windows); dùng `.dart` |
| Không bao giờ sửa tay file sinh | `.g.dart`, `.freezed.dart`, `.module.dart`, `.config.dart` |
| Version lấy từ catalog | sửa `pubspec_dependencies.yaml` rồi chạy tool sync |
| Chạy lại barrel generator | sau khi thêm, đổi tên, hoặc xoá file trong `lib/`, sau codegen |
| Xử lý deprecation đàng hoàng | nghiên cứu đường migrate; cấm vá tạm và cấm ignore |

**FVM là tuỳ chọn.** `.fvmrc` ghim một version, nhưng không có nghĩa là `fvm` đã được cài: viết lệnh trần (`flutter pub get`) và tự thêm `fvm ` nếu máy bạn dùng nó. Tool gọi toolchain phát hiện nó lúc chạy qua `tools/shared/toolchain.dart` (`useFvm`, `dartExecutable` / `dartArgs`, `flutterExecutable` / `flutterArgs`), vốn đòi cả file cấu hình lẫn `fvm --version` chạy được.

### Độ nghiêm của analyzer

Một file `analysis_options.yaml` duy nhất ở root áp dụng cho mọi package. Ngoài `flutter_lints`, nó bật ba strict mode của ngôn ngữ và một nhóm rule; phần header của file giải thích từng cái và cách thêm rule. `flutter analyze` phải báo **0 issue** — CI Gate 2 fail cả với info.

| Thiết lập | Yêu cầu với code của bạn |
|---|---|
| `strict-casts` | cast giá trị `dynamic` trước khi dùng như kiểu cụ thể — `jsonDecode(body) as Map<String, dynamic>` |
| `strict-inference` | ghi type argument mà suy luận không tìm ra — `Future<void>.delayed(...)`, `catchError((Object e, StackTrace s) {...})` |
| `strict-raw-types` | không bỏ type argument của kiểu generic — `StreamSubscription<User>`, `AppFailure<dynamic>` (giữ `<dynamic>` cho `AppFailure`: `==` do Freezed sinh so sánh `runtimeType`) |
| `unawaited_futures` | trong thân async, `await` Future hoặc bọc bằng `unawaited(...)` của `dart:async` kèm comment giải thích lý do |
| `cancel_subscriptions` / `close_sinks` | field `StreamSubscription` phải được cancel, field `StreamController` phải được close, ngay trong class sở hữu nó |
| `avoid_dynamic_calls` | không gọi method hay truy cập property trên `dynamic` — cast trước |
| `empty_catches` | `catch` rỗng phải chứa comment giải thích vì sao bỏ lỗi là an toàn; ưu tiên thu hẹp nó (`on FileSystemException`) |

`discarded_futures` **không** được bật: trong Flutter nó chủ yếu báo `subscription.cancel()` / `controller.close()` trong `dispose()` đồng bộ và dialog mở từ callback `void`. Thêm một rule nghĩa là sửa mọi chỗ nó báo — không bao giờ `// ignore:` — và sinh thử một module (`generate.dart 1 smoke "" 2 2`) để chứng minh template của generator vẫn đạt.

---

## 17. Kiểm thử

Bảng đăng ký: RULE-60 · RULE-61 · RULE-62 · RULE-63 · RULE-64.

**Luật.** Test nằm cạnh code nó kiểm, trong thư mục `test/` riêng của từng package. Package Flutter dùng `flutter_test`; package Dart thuần (`domain_*`, `data_core`, `platform_kernel`, `tools`) dùng `package:test`, được ghim trong catalog — `arch_check` R2 và R9 từ chối `flutter_test` trong package domain hay kernel; với `data_core` và `tools` đó là quy ước do review giữ. Fake được viết tay — repo không khai mockito hay mocktail.

**Vì sao.** CI Gate 3 không giữ danh sách: nó tìm mọi thư mục có cả `pubspec.yaml` lẫn `test/` và chạy `flutter test --coverage` ở đó, và fail nếu không tìm thấy thư mục nào. Package mới có test được phủ ngay khi nó tồn tại. Fake viết tay không cần codegen và đọc lên như lời phát biểu về contract nó thay thế.

Ba test gánh luật ở nơi khác trong file này:

| Test | Giữ |
|---|---|
| `apps/<id>/test/di_smoke_test.dart` (mọi app) | Boot đồ thị DI sinh ra thật của app cho mọi flavor mà manifest khai với mọi plugin thay bằng test double, dựng mọi lazy singleton và mọi factory `@injectable` (lỗi chỉ ra tên type), đối chiếu đồ thị với `capabilities:` của app (`checkAppContract`: mọi contract bắt buộc, mọi `provided` / `absent` đã khai, có màn hình, `order` duy nhất, `AppRouter.router` ráp được) và hỏi `checkDeclaredStarts` xem mọi platform và flavor đã khai có khởi động được không — bằng chứng lúc chạy cho RULE-13, RULE-14, RULE-24 (`order` duy nhất), RULE-48 (một quyết định pin cho mỗi flavor, P04) và RULE-81 |
| `platform/shell/app_shell/test/accessibility_test.dart` | Nút chỉ có icon giữ tooltip làm nhãn ngữ nghĩa; cỡ chữ của hệ điều hành đi qua tới `DisplayProfile.textScaleMax` (RULE-38) |
| `tools/test/` | Mọi gate tool, mỗi ca trong một workspace dùng xong bỏ ở thư mục tạm (RULE-64); CI chạy nó ngay sau Gate 1, và Gate 3 bỏ qua `tools/` |

Plugin mà đồ thị DI chạm tới trong lúc khởi tạo — một factory `@preResolve`, một `@PostConstruct(preResolve: true)` — cần test double được thêm vào smoke test, nếu không chúng fail với `MissingPluginException` của plugin đó.

**Widget có scale cần `ResponsiveInit`.** Widget test mà đối tượng đọc `context.w` / `context.sp` phải bọc nó trong `ResponsiveInit`; thiếu nó `ResponsiveScope.of` assert, có chủ đích, thay vì layout ở giá trị chưa scale mà không ai để ý.

**Kiểm chứng**

```bash
cd platform/foundation/common && flutter test          # một package
cd apps/mobile && flutter test test/di_smoke_test.dart # boot DI, mọi flavor
cd tools && dart test                                  # các gate tool
dart tools/coverage_report/report.dart                 # coverage theo package sau --coverage (tham khảo)
```

---

## 18. Logging, báo lỗi và bí mật

Bảng đăng ký: RULE-43 · RULE-65 · RULE-66 · RULE-67.

**Luật.** Chẩn đoán lúc chạy đi qua `dynamic_logger` (`DynamicLogger.log`), không bao giờ `print` hay `debugPrint` — lint `avoid_print` của analyzer từ chối `print`, còn `arch_check` R19 từ chối `print`, `debugPrint` và `debugPrintStack` trong `lib/` của mọi package platform, module và app. CLI tool trong `tools/` ghi bằng `stdout.writeln` / `stderr.writeln`. Không có gì bí mật bị log hay commit.

**Vì sao.** Đầu ra của `print` lọt vào log thiết bị bản release và không lọc được theo mức hay tag. Stack network cho thấy chuẩn che dữ liệu: `LoggingInterceptor` chỉ chạy khi `kDebugMode` ở cả ba hook, kể cả `onError`, và che header `Authorization` / `Cookie` cùng các trường thông tin đăng nhập trong body (mọi key kết thúc bằng `password`, `token`, `secret`, `apikey`, …, hoặc `otp`, `pin`, `cvv`, … đứng nguyên từ) và giá trị query của URL; FCM token không được log — xem [`../architecture/02_core.md`](../architecture/02_core.md#chuỗi-interceptor) § 6. File env production, keystore, `key.properties` và API key (`tools/code_review/.gemini_api_key`, `apps/mobile/fastlane/Config.yaml`) nằm trong gitignore, với một ngoại lệ có chủ đích: `apps/mobile/android/keystore-dev.jks` và `key-dev.properties` được track để bản clone mới build được flavor `dev` — một khoá công khai không bao giờ ký bản release (`SECURITY.md`). `env.dev` / `env.stg` không chứa bí mật và được track; `env.prod` thì không. CI dựng phần còn lại từ secret ([`../operations/01_cicd.md`](../operations/01_cicd.md) § 7).

**Báo lỗi.** `runShellApp` là nơi duy nhất đặt các hook lỗi (`installShellErrorHooks` trong `platform/shell/app_shell/lib/src/bootstrap.dart`): zone handler, `FlutterError.onError` — giữ handler trước đó — và `PlatformDispatcher.instance.onError` đều kết thúc ở một lần báo cáo, gọi `onError` tuỳ chọn của app rồi `getItOrNull<IErrorReporter>()` với `fatal: true`; `ErrorHandler.onUnclassifiedError` gửi các exception `ErrorHandler` không phân loại được tới cùng reporter với `fatal: false`. Muốn cắm Crashlytics hay Sentry, đăng ký một implementation `IErrorReporter` trong app (`@LazySingleton(as: IErrorReporter)` trong `lib/` của chính nó); `IAnalytics` cũng vậy, và mọi page `GoRouteDataCustom` báo màn hình của nó qua đó. Tự gán `FlutterError.onError` là thay thế chuỗi thay vì gia nhập nó. Chi tiết: [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) § "Lỗi và crash reporting".

**Phân loại lỗi.** Lỗi đến UI dưới dạng `AppFailure` do `ErrorHandler.handleError(e)` tạo ra. `ErrorHandler` không nêu tên type transport nào; một họ exception mà nó cần hiểu thì đăng ký `ErrorClassifier` qua `ErrorHandler.registerClassifier` — như cách `core_network` đóng góp `DioFailureClassifier`. Hiện chưa có classifier cho Firebase: `FirebaseException`, `FirebaseAuthException` và `PlatformException` đều rơi về `ServerFailure(code: 9999)`, "Unknown error occurred" ở bản release. Hãy đăng ký một cái trước khi màn hình nào dựa vào mã lỗi Firebase.

---

## 19. Khả năng truy cập

Bảng đăng ký: RULE-38 · RULE-39 · RULE-30 (inset theo hướng).

**Luật.**

- **Chữ theo cỡ chữ của hệ điều hành.** Shell bọc mọi `builder` trong `MediaQuery.withClampedTextScaling(maxScaleFactor: display.textScaleMax)` — `DisplayProfile.textScaleMax` là 2.0 trừ khi app đặt khác, và một `const` assert từ chối mọi giá trị dưới 2.0. Không bao giờ `MediaQuery.withNoTextScaling`, không bao giờ `TooltipVisibility(visible: false)` — nó tước nhãn của icon button khỏi semantics; `tooltipTheme` của theme (`triggerMode: manual`) đã chặn popup khi nhấn giữ.
- **Khung chứa chữ lớn theo chữ.** Đừng đặt chiều cao cố định `context.h(...)` cho khung chứa chữ; để nó tự co theo nội dung, hoặc thu nhỏ bằng `TextScaleDown`.
- **Mọi thứ tương tác được đều có tên.** `IconButton` chỉ có icon mang `tooltip` (nó trở thành nhãn ngữ nghĩa); ảnh có nghĩa truyền `semanticLabel` (`CustomCacheNetworkImage` làm vậy); ảnh trang trí để `null`.
- **Vùng chạm tối thiểu 48 × 48 dp** (`kMinInteractiveDimension`) — thu nhỏ phần nhìn, không thu vùng chạm.
- **Các trạng thái của kit luôn đọc được (WCAG 2.x AA: 4.5:1 cho chữ, 3:1 cho đường biên của control).** `CustomButton` vẽ nhãn bằng `textInverse` trên nền thương hiệu; khi bị vô hiệu, nó có nền `surfaceVariant` và nhãn `textSecondary` (button trong suốt không có nền). `CustomInputField` có viền nghỉ `textSecondary`, viền focus `primary` dày 2 px, viền `error`, viền `border` dịu hơn khi bị vô hiệu (được miễn quy tắc tương phản), gợi ý `textSecondary` và chiều cao tối thiểu 48 dp. Toast pill là `textPrimary` với alpha `SharedUiConstants.TOAST_BACKGROUND_ALPHA` (0.92), gần như đục một cách có chủ đích. Các dòng của `showDropDown` cao ít nhất 48 dp. Sửa palette làm hỏng một trong các cặp màu này sẽ fail `palette_contrast_test.dart`.
- **Một lớp modal là modal với công nghệ hỗ trợ và bàn phím.** `AppOverlay` bọc dialog và lớp loading trong một lớp modal (`BlockSemantics`, `scopesRoute`, một `FocusScope`), nên trang phía sau bị ẩn khỏi trình đọc màn hình và focus bàn phím ở lại trong lớp; toast không lấy trang đi.
- **Phải sang trái.** Padding mang nghĩa đầu/cuối dòng dùng `context.edgeInsetsDirectional(start:, end:)`, tự lật khi RTL; `edgeInsets(left:/right:)` là vật lý.

**Vì sao.** `withNoTextScaling` ghim mọi chữ ở 100 % bất kể người dùng chọn gì, và một `TooltipVisibility(visible: false)` toàn cục làm câm mọi icon button với trình đọc màn hình. Test của shell chỉ phủ shell; việc tuân thủ của từng màn hình do review giữ, kèm một test text-scale cho `feature_auth` và `feature_dashboard`. Trong kit, `CustomButton` không bao giờ xuống dưới 48 dp, toast là live region và spinner mang nhãn `loading` đã dịch, mỗi thứ có test (`platform/ui/ui_kit/test/default_sizes_test.dart`, `semantics_test.dart`), còn các trạng thái ở trên do `accessibility_states_test.dart`, `modal_overlay_test.dart` và `palette_contrast_test.dart` giữ. Chi tiết: [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) § 7.

**Kiểm chứng**

```bash
cd platform/shell/app_shell && flutter test test/accessibility_test.dart
cd modules/auth/feature && flutter test test/login_page_test.dart
cd modules/dashboard/feature && flutter test test/dashboard_text_scale_test.dart
cd platform/ui/ui_kit && flutter test test/default_sizes_test.dart test/semantics_test.dart test/accessibility_states_test.dart test/modal_overlay_test.dart
cd platform/ui/design_system && flutter test test/palette_test.dart test/palette_contrast_test.dart
```

---

## 20. Workspace, codegen và barrel

Bảng đăng ký: RULE-16 · RULE-75 · RULE-76 · RULE-77.

**Composition được sinh ra.** Mỗi `apps/<id>/app_manifest.yaml` là mô tả duy nhất được sửa tay của một app. `dart tools/composer/composer.dart sync` ghi năm thứ từ nó, mỗi thứ nằm giữa marker `composer:managed`: danh sách `workspace:` ở gốc, path dependency của app trong `pubspec.yaml` của nó, `lib/di/injection.dart` của nó (các import và danh sách module cùng điểm vào `configureDependencies` là hai vùng được sinh; ngoài hai vùng đó file chỉ có comment), vùng `facts` của `lib/app/app_profile.dart` (khai báo dưới dạng const Dart) và vùng `report` trong `README.md` của app. `composer verify` là Gate 0 và fail khi có bất kỳ sai lệch nào, đồng thời đối chiếu khai báo với mã nguồn ([§21](#21-app-và-composition)). Module generator thêm module mới vào mọi manifest (hoặc chỉ các app nêu bằng `--apps`) và tự chạy `sync`; `composer new` tạo cả một app. Workspace phẳng: `resolution: workspace` ở mọi member, không có nút workspace trung gian.

**Barrel.** Mỗi package dưới `modules/` và `platform/` có đúng một barrel, `lib/<package_name>.dart`; bên trong một package, file import file cụ thể, không bao giờ import barrel. `dart tools/barrel_generator/generate.dart <package>/lib` (đường dẫn không phải `lib/` của một package thì thoát với mã 64) viết lại nó từ những gì có trên đĩa: một danh sách `export` đã sắp xếp cho mọi file thư viện dưới `lib/`, kể cả file sinh ra đang có trên đĩa (`module.module.dart`, `lib/src/gen/**`), và nó xoá barrel thư mục viết tay. Nó **thay** mọi directive `export` của barrel, nên export thêm tay sẽ lặng lẽ biến mất — hãy đặt re-export có chủ đích trong một file nguồn bình thường (`platform/foundation/common/lib/src/kernel.dart` đúng là vậy). Vì barrel đã commit liệt kê cả file sinh ra nằm trong gitignore, lần chạy cuối phải đến **sau** gen-l10n và build_runner — đúng thứ tự `tools/workspace_setup/configure.dart` dùng — và CI chạy lại nó rồi fail khi barrel hay bất kỳ file `.dart` nào đang được track bị khác đi (bước "Barrels match the generator").

**Code sinh ra vô hình với analysis.** `analysis_options.yaml` loại `**.freezed.dart`, `**.g.dart`, `**.mocks.dart`, `**.config.dart` và `**.module.dart`, nên `flutter analyze` sạch không có nghĩa là app biên dịch được. Ví dụ: `bloc_view_state.freezed.dart` cần `$AppFailureCopyWith` do `domain_core` khai; một re-export liệt kê type trong mệnh đề `show`, như `platform/foundation/kernel/lib/src/error/failures.dart`, không mang theo được nó. Analyze báo *No issues found*; build APK fail với `Type '$AppFailureCopyWith' not found`. Luật: import type mà code sinh ra dùng từ nhà thật của nó (`bloc_state_management` import `package:domain_core/domain_core.dart`).

`build_runner` không nhận `-d`: `--delete-conflicting-outputs` đã bị gỡ và bị bỏ qua kèm cảnh báo.

**Kiểm chứng** — sau khi đổi annotation DI, dependency của package hay nhà của một type Freezed/JSON:

```bash
dart run build_runner build --workspace
flutter analyze
(cd modules/<module>/<layer> && flutter test)    # mỗi package có thư mục test/
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev
```

Build APK cần các file `firebase_options_<flavor>.dart` và `google-services.json` nằm trong gitignore; `dart tools/workspace_setup/configure.dart --stub-firebase` ghi stub chỉ-để-biên-dịch ([`../getting-started/01_setup.md`](../getting-started/01_setup.md) § 3).

---

## 21. App và composition

Bảng đăng ký: RULE-80 · RULE-81 · RULE-82 · RULE-16.

**Luật.** Một app nói mình là gì ở bốn nơi, và không nơi nào khác:

| Kênh | Chứa | Nằm ở | Được giữ bởi |
|---|---|---|---|
| Manifest | Sự thật mà một tool phải thấy trước khi code biên dịch: danh tính, flavor (kèm quyết định SSL pin của từng flavor), key env, platform và thứ mỗi platform bật, capability, composition | `apps/<id>/app_manifest.yaml`, sinh vào vùng `facts` của `lib/app/app_profile.dart` | `composer verify` (Gate 0), `checkAppContract`, boot |
| Profile | Shell cư xử thế nào: display, router, locale, theme, giới hạn mạng — có kiểu, `const`, mặc định của template | `lib/app/app_profile.dart`, phần bên dưới vùng sinh ra | analyzer (const assert), `apps/<id>/test/app_profile_test.dart` |
| Hook | Code chạy ở những điểm cố định của quá trình boot (`ShellHooks`) | `lib/app/app_hooks.dart` | analyzer |
| Contract | Interface của `core_di` mà app hoặc module đăng ký, được resolve qua catalog của shell | module, `lib/app/*.dart` | `composer verify` (V3), `checkAppContract`, boot |

Chia thế nào trong một câu: manifest nói app **là** gì và chạy ở đâu, profile nói shell **cư xử** ra sao, hook là **code**. Package platform giữ cơ chế và một mặc định có tài liệu, bằng đúng hành vi của template (RULE-80); nó không bao giờ sở hữu giá trị mà một app có thể muốn khác.

Shell resolve mọi contract tuỳ chọn qua một catalog duy nhất, `SHELL_CONTRACTS` (`utils/shell_contract_constants.dart` trong `platform_app_shell`: 7 dòng bắt buộc do chính các package của shell đăng ký, 14 dòng tuỳ chọn do app hoặc module đóng góp — tổng 21; `composer describe --catalog` in bảng thật). App khai từng dòng tuỳ chọn là `provided` hoặc `{ state: absent, reason }` (RULE-81): `composer verify` từ chối dòng chưa khai (V2), khai báo mà code mâu thuẫn ở cả hai chiều (V3), bundle mà các thành viên bất đồng (V4) và lý do rỗng hoặc `TODO` (V14); `checkAppContract` đối chiếu cùng khai báo đó với đồ thị app thực sự dựng, trong smoke test của từng app và lúc boot; `arch_check` R16 giữ cho chính catalog luôn đầy đủ, nên thêm một lookup của shell mà không đưa vào catalog sẽ fail Gate 1.

**Vì sao.** Một quyết định riêng của app mà nằm trong một hằng số của package dùng chung, một nhánh `Platform.is*` hay một file native thì vô hình với mọi tool: không có gì nói app phải đăng ký gì, mỗi platform bật gì hay app được phép đổi gì, và app thứ hai không thể khác mà không sửa `platform/`. Khai trong manifest, profile, hook và contract thì mỗi quyết định có đúng một chỗ và một gate đọc nó.

**Khác biệt giữa các platform** là quyết định của app (RULE-82): `platforms.<p>` trong manifest khai app chạy ở đâu và mỗi platform bật gì (splash, push, deep link, orientation, window), shell mỗi lần chạy đọc đúng một `PlatformFacts`, và nhánh chính sách duy nhất dựa trên `kIsWeb` / `defaultTargetPlatform` là `resolveAppPlatform()`. Một nhánh mới phải được biện minh trong `kPlatformForkAllowList` (`tools/arch_check/platform_forks.dart`) kèm lý do, nếu không R17 fail.

**Thứ còn bị khoá** — muốn đổi phải sửa package dùng chung, cho mọi app: breakpoint, component theme, page transition, chuỗi interceptor và chính sách retry mặc định của `Dio`, trang 404, màu shadow và scrim, channel và icon của push, allow-list của deep link, giới hạn của logger, overlay system-UI, tuỳ chọn secure-storage. Thay một type do shell sở hữu bằng thứ tự đăng ký là không được hỗ trợ: GetIt giữ đăng ký đầu tiên của một type.

**Kiểm chứng**

```bash
dart tools/composer/composer.dart verify               # Gate 0 — khai báo, các vùng sinh ra, mã nguồn
dart tools/composer/composer.dart describe --app <id>  # báo cáo: app khai gì và shell resolve gì từ nó
dart tools/arch_check/check.dart                       # R16 (catalog đầy đủ), R17 (nhánh theo platform)
cd apps/<id> && flutter test test/di_smoke_test.dart   # checkAppContract cho mọi flavor
```

Cách đọc một app, thêm platform, capability, pin, locale hay hook, và toàn bộ danh sách kiểm tra của Gate 0: [`../guides/13_app_composition.md`](../guides/13_app_composition.md).

---

## Bảng tra luật → lệnh

| Kiểm tra | Lệnh |
|---|---|
| Dependency chưa khai (có import, không có trong `dependencies:`) | `dart tools/arch_check/check.dart` (R5) |
| Dependency thừa (có khai, không bao giờ import) | `dart tools/unused_checker/check_unused_packages.dart` |
| Catalog version bị lệch | `dart tools/dependency_sync.dart --check` |
| Asset, file, bản dịch không dùng | `dart tools/unused_checker/check_script.dart` |
| Phân tích tĩnh | `flutter analyze` |
| Code sinh ra đã cập nhật | `dart run build_runner build --workspace` |
| An toàn thứ tự DI | `cd apps/mobile && flutter test test/di_smoke_test.dart` (và `apps/admin`) |
| core ⇏ feature / data / domain sản phẩm | `dart tools/arch_check/check.dart` (R1) |
| Contract gỡ được resolve dạng tuỳ chọn | `dart tools/arch_check/check.dart` (R8) |
| App shell không import module nào | `dart tools/arch_check/check.dart` (R1 cho `platform_app_shell` / `platform_shell_adapters`, R10 cho `apps/*`) |
| Chiều giữa các nhóm platform | `dart tools/arch_check/check.dart` (R11) |
| Package API của module chỉ phụ thuộc foundation; feature import API của module khác, không bao giờ feature của nó | `dart tools/arch_check/check.dart` (R3) |
| Không `.ps1`, không tắt lint, không `datasources/`, không class cụ thể `I*` | `dart tools/arch_check/check.dart` (R12–R15) |
| Mọi lookup của shell nằm trong catalog; nhánh theo platform được allow-list kèm lý do | `dart tools/arch_check/check.dart` (R16, R17) |
| Handler Bloc async; không `print` / `debugPrint` trong `lib/`; không số thô trong tham số layout | `dart tools/arch_check/check.dart` (R18, R19, R20) |
| Mọi locale có đủ khoá của `en.arb`; khoá ARB là `lowerCamelCase` | `dart tools/arch_check/check.dart` (R21) |
| File có tên giống file sinh ra mà thiếu header của generator | `dart tools/arch_check/check.dart` (R6) |
| Hằng số trong `utils/` | `dart tools/arch_check/check.dart` (R4) |
| Domain thuần; kernel Dart thuần | `dart tools/arch_check/check.dart` (R2, R9) |
| Barrel khớp với generator | Bước CI "Barrels match the generator" — ở local `dart tools/barrel_generator/generate.dart <package>/lib`, rồi `git status` |
| Composition khớp manifest | `dart tools/composer/composer.dart verify` |
| Một app khai gì và shell resolve gì từ nó | `dart tools/composer/composer.dart describe --app <id>` |
| Đường dẫn trong docs và tương đồng en ↔ vi | `dart tools/docs_check/check.dart` |
| Code sinh ra biên dịch được | `cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev` |

---

**Tiếp theo:** [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md) · [`04_review_checklist.md`](04_review_checklist.md)
