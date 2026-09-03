# Checklist review PR

**File này trả lời:** phải thoả những gì thì PR này mới được merge?

**Đọc xong bạn có thể:** review một thay đổi theo đúng kiến trúc trong vài phút, và biết mục nào có lệnh tự kiểm hộ bạn.

Bỏ qua phần nào PR không đụng tới. Mục nào có dòng **Kiểm chứng** thì phải *chạy*, đừng nhìn bằng mắt.

---

## 0. Cổng tự động — chạy trước tiên

```bash
dart tools/dependency_sync.dart --check              # lệch version catalog
dart tools/unused_checker/check_unused_packages.dart # dependency thừa / thiếu khai
dart run build_runner build -d --workspace           # code sinh đã cập nhật
flutter analyze                                      # phân tích tĩnh
```

- [ ] Cả bốn lệnh đều sạch
- [ ] Test pass ở mọi package bị đụng — `cd packages/<layer>/<pkg> && flutter test`
- [ ] Không file nào trong `lib/` bị sửa tay nếu nó kết thúc bằng `.g.dart`, `.freezed.dart`, `.module.dart` hoặc `.config.dart`
- [ ] Đã chạy lại barrel generator nếu có file được thêm, đổi tên hoặc xoá

---

## 1. Cấu trúc package

- [ ] Package mới khai `resolution: workspace` trong `pubspec.yaml` của nó
- [ ] Package mới có mặt trong khối `workspace:` của `pubspec.yaml` gốc
- [ ] API công khai được export qua barrel `lib/<package_name>.dart`; phần cài đặt nằm trong `src/`
- [ ] Tên package khớp tiền tố tầng — `core_` / `domain_` / `data_` / `feature_`
- [ ] Package có thư mục `utils/` giữ hằng số **của chính nó** ([luật 3](01_rules.md#3-bắt-buộc-có-thư-mục-utils))

---

## 2. Hướng phụ thuộc

- [ ] Không package `core/*` nào import hay khai `feature_*` / `data_*`
- [ ] Mọi phụ thuộc hướng lên mới đều nằm trong bốn ngoại lệ đã duyệt, hoặc `AGENTS.md` được cập nhật trong cùng PR
- [ ] Mọi `package:` import trong `lib/` đều có mục tương ứng trong `pubspec.yaml`
- [ ] Import phục vụ production nằm ở `dependencies`, không phải `dev_dependencies`
- [ ] Code bị xoá thì dependency không còn dùng cũng được gỡ theo

**Kiểm chứng**

```bash
grep -rn "package:feature_\|package:data_" packages/core/*/lib   # phải rỗng
dart tools/unused_checker/check_unused_packages.dart
```

---

## 3. Tầng Domain

- [ ] Không có import `flutter` / `dio` / `retrofit` trong `packages/domain/*`
- [ ] Không `pubspec.yaml` domain nào khai Flutter SDK
- [ ] Entity dùng `freezed` với private constructor `const Class._()`
- [ ] Mỗi use case làm đúng một việc và trả `Result<T>`
- [ ] Use case được đánh dấu `@injectable`

**Kiểm chứng**

```bash
grep -rn "package:flutter" packages/domain/*/lib   # phải rỗng
```

---

## 4. Tầng Data

- [ ] Thư mục là `data_sources/remote/` và `data_sources/local/` — không phải `datasources/`
- [ ] **DataSource trả Model, không bao giờ trả Entity**
- [ ] Không class nào do Drift sinh xuất hiện trong chữ ký công khai — chuyển đổi ở lớp biên (`CacheEntryModel`)
- [ ] Model có `.toEntity()` và implement `BaseModel<E>`
- [ ] `RepositoryImpl` kế thừa `IBaseRepository` và bọc công việc trong `execute()` / `executeSync()`
- [ ] Lỗi đi qua `ErrorHandler.handleError(e)` — **không** dùng `AppFailure.fromException()`
- [ ] Không có `throw` nào từ Data lên UI; lỗi trả về dạng `Result.failure(AppFailure)`

---

## 5. Quyền sở hữu storage

- [ ] Storage key mới nằm trong `utils/` của **package sở hữu**, không nằm ở `core_common`
- [ ] Owner tự khai `StorageValue<T>` từ `StorageManager` được inject
- [ ] Owner được đăng ký là **singleton** (`@singleton` / `@lazySingleton` / `@Singleton(as:)`) kèm `@PostConstruct(preResolve: true)`
- [ ] Nó **không** phải `@injectable` — factory sẽ phát ra cache rỗng
- [ ] Backend được chọn có chủ đích: `StorageType.secure` cho token/PII, `StorageType.pref` cho cài đặt
- [ ] Không `StorageValue` nào bị truyền giữa các package; truy cập xuyên package đi qua interface ở `core_di`

---

## 6. Dependency injection

- [ ] Package mới khai `@InjectableInit.microPackage()` tại `lib/di/module.dart`
- [ ] Module của nó được đăng ký đúng nhóm trong `app/lib/di/injection.dart`
- [ ] Controller gắn màn hình là `@injectable` — **không bao giờ** `@singleton` / `@lazySingleton`
- [ ] Controller singleton phải thực sự dùng toàn app
- [ ] Không `@Singleton` eager nào phụ thuộc type đăng ký ở module chạy sau ([luật 5](01_rules.md#5-thứ-tự-đăng-ký-di))
- [ ] Phụ thuộc đi qua constructor; không gọi `getIt<T>()` trong ViewModel, Repository hay UseCase
- [ ] Bind một impl cho interface thứ hai phải dùng `@module` tường minh — GetIt không phân giải theo supertype

**Kiểm chứng** — sau bất kỳ thay đổi DI nào, đọc file lắp ráp sinh ra và xác nhận phụ thuộc của mỗi đăng ký eager xuất hiện trước nó trong `init()`:

```bash
grep -n "PackageModule().init\|gh.singleton<" app/lib/di/injection.config.dart
```

---

## 7. Ranh giới feature và khả năng gỡ bỏ

- [ ] Mỗi package feature giữ đúng một mối quan tâm UI
- [ ] Không feature nào import feature khác (không ngoại lệ — widget dùng chung lấy từ `core_ui_kit`)
- [ ] Điều hướng xuyên feature dùng interface Navigator ở `core_di`, không import trực tiếp
- [ ] Hành động UI xuyên feature dùng `I*ActionHandler`
- [ ] Đóng góp tuỳ chọn được đọc bằng `getAllOrEmpty` / `getItOrNull` kèm fallback — **không bao giờ `getAll`**
- [ ] App shell không phát sinh tham chiếu cứng mới tới feature ngoài `injection.dart`
- [ ] Nếu thêm hợp đồng `core_di` mới, phía tiêu thụ phải suy biến an toàn khi không ai đăng ký

**Kiểm chứng** — với feature lẽ ra phải gỡ được, hãy gỡ theo bốn bước trong `injection.dart` rồi xác nhận:

```bash
flutter pub get && dart analyze app
```

---

## 8. Routing

- [ ] `app_router.dart` **không** bị sửa để thêm route
- [ ] Feature đăng ký `IFeatureRouteModule` và/hoặc `IDashboardTabModule` (kèm `IAppEntryLocation` tuỳ chọn)
- [ ] `IDashboardTabModule.order` khớp đúng index bottom-nav mong muốn
- [ ] `IDashboardTabModule` chỉ dùng cho điểm đến bottom-nav thật, không dùng cho màn hình chỉ push
- [ ] `feature_dashboard` vẫn chỉ là chrome — không có page của tab, không hardcode danh sách nav item
- [ ] Hằng số route path nằm ở `lib/src/utils/<feature>_path.dart`
- [ ] Controller được tạo tại route; widget `Page` **không** bọc lại lần nữa
- [ ] `BuildContext` được truyền từ nơi gọi ở UI, không lấy từ `NavigatorKeys`

---

## 9. UI và tầng trình bày

- [ ] Controller kế thừa `BaseProvider` / `BaseBloc`
- [ ] Event của BLoC là subclass private dùng `part` / `part of`
- [ ] Mọi handler `on<Event>` đều `async` và nhận `(event, emit)`
- [ ] Dùng đúng loại `ViewState` — `BlocViewState<T>` cho nhánh BLoC, `ViewState` cho nhánh Provider
- [ ] Mọi kích thước đi qua `BuildContext` — `context.w(x)` / `context.h(x)` / `context.sp(x)` / `context.r(x)`; không double thô, không dạng bare `16.h` (`arch_check` R7 chặn)
- [ ] Design token gọi kèm context — `AppSpacing.lg(context)`, `AppRadius.md(context)`, không dùng getter trần, không scale hai lần
- [ ] Giá trị cần dùng sau `await` được đọc từ context **trước** đó, không giữ context xuyên qua
- [ ] Widget dùng lại trong `core_ui_kit` nhận giá trị **chưa scale** và không tự scale bên trong
- [ ] Dialog và bottom sheet là class widget riêng, không phải builder inline
- [ ] Màu lấy từ `context.colors.*`, typography lấy từ `AppTextStyles.*(context)`

---

## 10. Đa ngôn ngữ

- [ ] Không có chuỗi hiển thị nào bị hardcode
- [ ] Chuỗi của feature nằm trong `assets/language/*.arb` của chính feature đó
- [ ] Feature đăng ký `IFeatureLocalization` — `root_app.dart` không bị sửa
- [ ] Chuỗi được đọc qua extension của feature (`context.l10nAuth.someKey`)
- [ ] `core_ui_kit` không định nghĩa `.arb` riêng; nó dùng của `core_base_ui`
- [ ] Asset riêng của feature nằm trong `assets/` của feature đó, không nằm ở `core_base_ui`

---

## 11. Công cụ và vệ sinh code

- [ ] Công cụ CLI dùng `stdout.writeln` / `stderr.writeln`, không bao giờ `print()`
- [ ] Không thêm `// ignore_for_file:` hay bất kỳ cách tắt lint nào
- [ ] Không thêm script `.ps1`
- [ ] Cảnh báo deprecation được xử lý bằng migrate thật, không phải bị bịt đi
- [ ] Version được đổi trong `pubspec_dependencies.yaml` rồi sync — không hardcode ở từng package
- [ ] Không commit secret (file env, keystore, API key)

---

## 12. Tài liệu

- [ ] Thay đổi hành vi được phản ánh vào **cả** `docs/en/` **và** `docs/vi/`
- [ ] Luật kiến trúc mới được thêm vào `.agents/AGENTS.md` và vào [`01_rules.md`](01_rules.md)
- [ ] Code mẫu trong docs được copy từ file thật, không viết theo trí nhớ
- [ ] Giới hạn đã biết được nói thẳng chứ không bỏ qua

---

**Xem thêm:** [`01_rules.md`](01_rules.md) · [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md)
