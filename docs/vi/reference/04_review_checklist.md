<!-- translated-from: docs/en/reference/04_review_checklist.md@1261ffb -->
# Checklist review PR

**File này trả lời:** phải thoả những gì thì PR này mới được merge?

**Đọc xong bạn có thể:** review một thay đổi theo đúng kiến trúc trong vài phút, và biết mục nào có lệnh tự kiểm hộ bạn.

Mỗi ô ghi tên dòng trong bảng đăng ký mà nó kiểm. Bản thân luật, lý do và lệnh kiểm chứng nằm một lần duy nhất ở [`01_rules.md`](01_rules.md) — trang này chỉ nói cần nhìn vào đâu. Bỏ qua phần nào PR không đụng tới. Thứ gì có gate thực thi thì phải *chạy*, đừng nhìn bằng mắt.

---

## 0. Cổng tự động — chạy trước tiên

Đúng các cổng mà `.github/workflows/pr_quality_check.yml` chạy, theo đúng thứ tự (trước đó CI chạy `dart tools/workspace_setup/configure.dart` — pub get, gen-l10n, build_runner, barrel):

```bash
dart run build_runner build --workspace              # code sinh đã cập nhật
dart tools/composer/composer.dart verify             # Gate 0 — phần lắp ráp khớp app_manifest.yaml
dart tools/arch_check/check.dart                     # Gate 1 — luật R1–R15
(cd tools && dart test)                              # Gate 1 — test của chính các gate tool
flutter analyze                                      # Gate 2 — phân tích tĩnh, 0 issue
# Gate 3 — `flutter test` ở mọi package có thư mục test/ (apps/*: smoke test DI)
dart tools/dependency_sync.dart --check              # Gate 4 — lệch version catalog
dart tools/docs_check/check.dart                     # Gate 5 — đường dẫn trong docs, tương đồng en ↔ vi, trích dẫn RULE-ID
dart tools/unused_checker/check_unused_packages.dart # tham khảo — đã khai mà không import
```

- [ ] Gate 0–5 đều sạch (bước kiểm dependency thừa chỉ mang tính tham khảo)
- [ ] **RULE-60 · RULE-63** — test pass ở mọi package bị đụng có thư mục `test/`, kể cả smoke test DI của mỗi app
- [ ] **RULE-76** — không file sinh ra nào (`.g.dart`, `.freezed.dart`, `.module.dart`, `.config.dart`) bị sửa tay
- [ ] **RULE-75** — đã chạy lại barrel generator, sau codegen, nếu có file trong `lib/` được thêm, đổi tên hoặc xoá
- [ ] **RULE-77** — thay đổi DI, dependency hay chuyển chỗ type đã được theo sau bởi một lần build APK debug (job `build` của CI)

---

## 1. Cấu trúc package

- [ ] **RULE-16** — package mới khai `resolution: workspace` và vào danh sách `workspace:` ở gốc qua `composer sync`, không sửa tay
- [ ] **RULE-78** — tên của nó khớp tiền tố tầng (`core_` / `domain_` / `data_` / `feature_` / `<id>_api`); file và class theo bảng hậu tố
- [ ] **RULE-75** — API công khai được export qua barrel; phần hiện thực nằm dưới `src/`
- [ ] **RULE-09** — hằng số công khai nằm trong `utils/` của chính nó

---

## 2. Hướng phụ thuộc

- [ ] **RULE-01** — không package platform nào phụ thuộc module; cạnh `→ domain_core` mới được duyệt đã cập nhật danh sách cho phép và bảng đăng ký trong cùng PR
- [ ] **RULE-02** — package platform mới nằm trong một thư mục nhóm và `dependencies:` của nó theo DAG nhóm
- [ ] **RULE-06** — mọi import `package:` đều được khai trong `dependencies:`; code bị xoá đã xoá luôn mục không còn dùng
- [ ] **RULE-04** — không feature nào import feature khác hay package data; package API của module chỉ phụ thuộc foundation

**Kiểm chứng**

```bash
dart tools/arch_check/check.dart                            # R1, R2, R3, R5, R11
grep -rn "package:feature_\|package:data_" platform/*/*/lib   # phải rỗng
dart tools/unused_checker/check_unused_packages.dart        # đã khai mà không dùng
```

---

## 3. Tầng Domain

- [ ] **RULE-03** — không import hay dependency Flutter, Dio, Retrofit hay `core_*` trong `modules/*/domain`
- [ ] **RULE-49** — entity dùng Freezed với `const Class._()`; mỗi use case là `@injectable`, làm một việc và trả `Result<T>`

**Kiểm chứng**

```bash
grep -rn "package:flutter" modules/*/domain/lib   # phải rỗng
```

---

## 4. Tầng Data

- [ ] **RULE-40** — data source nằm dưới `data_sources/remote/` và `data_sources/local/`
- [ ] **RULE-41** — data source trả Model (`BaseEntity<T>` là vỏ bọc duy nhất); không có row Drift trong chữ ký công khai; Model implement `BaseModel<E>` với `.toEntity()`
- [ ] **RULE-42** — `RepositoryImpl` kế thừa `BaseRepository` và dùng `execute()` / `executeSync()`; không gì ném lỗi lên UI
- [ ] **RULE-43** — lỗi đi qua `ErrorHandler.handleError(e)`; họ exception mới đã đăng ký `ErrorClassifier`

---

## 5. Storage và database

- [ ] **RULE-44** — khoá mới nằm trong `utils/` của package sở hữu; chủ sở hữu khai `StorageValue<T>` của riêng mình, chọn `secure` / `pref` có chủ đích, và chỉ chia sẻ qua interface trên `core_di`
- [ ] **RULE-45** — chủ sở hữu storage là singleton kèm `@PostConstruct(preResolve: true)`, không bao giờ `@injectable`
- [ ] **RULE-46** — bảng và DAO mới nằm trong database riêng của package sở hữu
- [ ] **RULE-47** — thay đổi schema đã tăng `schemaVersion` và đăng ký `IDatabaseMigration<YourDatabase>`; lệnh mở mang `@Order(1)`
- [ ] **RULE-48** — thay đổi chạm tới networking giữ `SslPinningConfig` được bind và nói rõ `sslPinningHashes` đã được điền hay chưa

---

## 6. Dependency injection

- [ ] **RULE-15** — package mới khai `@InjectableInit.microPackage()` ở `lib/di/module.dart`
- [ ] **RULE-16** — nó được ghép qua từng `apps/<id>/app_manifest.yaml` và `composer verify` sạch
- [ ] **RULE-10** — controller của màn hình là `@injectable`; singleton thực sự là toàn app
- [ ] **RULE-11** — dependency đến qua constructor; không `getIt<T>()` trong ViewModel, Bloc, Repository hay UseCase
- [ ] **RULE-13 · RULE-63** — không `@Singleton` eager nào phụ thuộc nhóm chạy sau; plugin được chạm tới trong lúc DI có test double trong smoke test
- [ ] **RULE-14** — interface thứ hai trên cùng một implementation được bind qua `@module`

**Kiểm chứng** — smoke test DI boot đồ thị thật cho mọi flavor:

```bash
cd apps/mobile && flutter test test/di_smoke_test.dart
cd apps/admin && flutter test test/di_smoke_test.dart
```

---

## 7. Ranh giới feature và khả năng gỡ bỏ

- [ ] **RULE-24** — mỗi package feature một mối quan tâm UI có biên
- [ ] **RULE-04 · RULE-22 · RULE-25** — điều hướng và hành động UI xuyên feature đi qua `<id>_api` của chủ sở hữu
- [ ] **RULE-12** — contract do module sở hữu được resolve bằng `getItOrNull` / `getAllOrEmpty` + fallback
- [ ] **RULE-05** — không file nào của app ngoài `injection.dart`, và không package shell nào, import một module
- [ ] **RULE-08** — contract `core_di` mới trung lập sản phẩm, mang value type riêng, và bên tiêu thụ xuống cấp an toàn khi không ai đăng ký

**Kiểm chứng** — với feature lẽ ra phải gỡ được, xoá nó khỏi manifest của app rồi xác nhận:

```bash
dart tools/composer/composer.dart sync
flutter pub get && dart run build_runner build --workspace
dart tools/arch_check/check.dart
flutter analyze
```

---

## 8. Routing

- [ ] **RULE-20** — `app_router.dart` không bị sửa; feature đóng góp `IFeatureRouteModule` / `INavDestinationModule` / `IAppEntryLocation`
- [ ] **RULE-24** — `INavDestinationModule` chỉ dùng cho destination chính, `order` duy nhất, và `feature_dashboard` vẫn chỉ là chrome
- [ ] **RULE-09** — hằng số path route nằm trong `lib/src/utils/<feature>_path.dart`
- [ ] **RULE-21** — controller được tạo ở route; `Page` không tự bọc thêm lần nữa
- [ ] **RULE-23** — `BuildContext` đến từ nơi gọi ở UI, không từ `NavigatorKeys`

---

## 9. UI và tầng trình bày

- [ ] **RULE-50** — controller kế thừa `BaseProvider` / `BaseBloc` (`BaseCubit` chỉ khi không có event)
- [ ] **RULE-51 · RULE-52** — event BLoC là subclass `part` private; mọi handler `on<Event>` là `async (event, emit)`
- [ ] **RULE-53** — state `BlocViewState<T>` được chốt qua `emitResult`; code generic ghi rõ đối số kiểu
- [ ] **RULE-54** — state xuyên feature là interface `Stream` / `ValueListenable` trung lập, đăng ký kép
- [ ] **RULE-30** — mọi kích thước đi qua `BuildContext`; giá trị cần sau `await` đã được đọc trước nó
- [ ] **RULE-31** — widget tái sử dụng dùng tham số đúng như nhận; không gì bị scale hai lần
- [ ] **RULE-32** — lựa chọn layout dùng window size class, không `Platform.is*` hay kiểm tra thiết bị
- [ ] **RULE-33** — màu, kiểu chữ, khoảng cách và bo góc lấy từ design token
- [ ] **RULE-36** — dialog và bottom sheet là widget class riêng

---

## 10. Đa ngôn ngữ, asset và khả năng truy cập

- [ ] **RULE-34** — không chuỗi hiển thị nào bị hardcode; chuỗi của feature nằm trong ARB riêng, đăng ký qua `IFeatureLocalization`
- [ ] **RULE-35** — khoá ARB mới là `lowerCamelCase`
- [ ] **RULE-37** — asset riêng của feature nằm trong `assets/` của feature đó
- [ ] **RULE-38** — không ghi đè text scaling hay khung chữ cao cố định; nút chỉ có icon có `tooltip`, ảnh có nghĩa có `semanticLabel`
- [ ] **RULE-39** — vùng chạm tối thiểu 48 × 48 dp; padding đầu/cuối dòng dùng `edgeInsetsDirectional`

---

## 11. Công cụ, kiểm thử và vệ sinh code

- [ ] **RULE-70 · RULE-71** — `flutter analyze` sạch mà không thêm chỗ tắt lint nào; deprecation đã được migrate
- [ ] **RULE-72** — không thêm script `.ps1`
- [ ] **RULE-73** — không lệnh hay tool nào hardcode `fvm`
- [ ] **RULE-74** — version được đổi trong `pubspec_dependencies.yaml` rồi sync
- [ ] **RULE-65 · RULE-66** — không `print`; không gì bí mật bị commit hay log
- [ ] **RULE-67** — báo lỗi đi qua `IErrorReporter`, không gán lại `FlutterError.onError`
- [ ] **RULE-61 · RULE-62** — fake viết tay; widget test có scale bọc đối tượng trong `ResponsiveInit`
- [ ] **RULE-64** — thay đổi một gate tool đã thêm ca kiểm vào `tools/test/`

---

## 12. Tài liệu

- [ ] **RULE-79** — thay đổi hành vi được phản ánh ở `docs/en/` **và** `docs/vi/`, và `docs_check` pass
- [ ] Luật mới hoặc thay đổi là một dòng trong bảng đăng ký ở cả hai ngôn ngữ, với cột **Thực thi bởi** nói đúng sự thật; trang khác trích id thay vì phát biểu lại
- [ ] Code mẫu trong docs được chép từ file thật, không viết theo trí nhớ
- [ ] Hạn chế đã biết được nói thẳng thay vì lược đi

---

**Xem thêm:** [`01_rules.md`](01_rules.md) · [`02_naming.md`](02_naming.md) · [`03_tooling.md`](03_tooling.md)
