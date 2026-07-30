# 01. Tầng Core (Core Infrastructure Layer)

Trong mô hình **Micro-packages Monorepo**, tầng Core không còn là một thư mục đơn khối mà được chia nhỏ thành nhiều gói chuyên biệt độc lập (Micro-packages) nằm dưới thư mục `packages/core/`. Thiết kế này giúp tối ưu hóa việc phân chia trách nhiệm, cô lập lỗi và tăng tốc thời gian biên dịch mã nguồn.

---

## 🏛️ 1. Bản Đồ Tổ Chức Các Gói Core (Micro-Cores Map)

Các gói Core được thiết kế độc lập và chỉ tương tác với nhau theo chiều đi xuống để tránh lỗi tham chiếu vòng:

```text
packages/core/
├── common/             # [Pinnacle Core] Hằng số hệ thống, Base Routes, Enums, Errors
├── di/                 # [DI Hub] Trạm trung chuyển Interface Navigators, Routing Modules
├── base_ui/            # [Design System] Themes, TextStyles, Assets (Chữ, Ảnh, Icon), Global UI Components
├── provider_state_management/   # [State Engine] BaseProvider, ViewStateModel, executeOperation helper
├── bloc_state_management/       # [State Engine] BaseBloc, BaseCubit, ViewState (Freezed) cho kiến trúc BLoC
├── storage/            # [Security Cache] Hardened Secure Storage, Reactive Storage Values, SharedPreferences
├── database/           # [Local DB] Drift + SQLite trên background isolate
├── network/            # [Network Client] ApiClient (Dio Factory), Retrofit helper, Interceptors
└── notifications/      # [Push Service] Trình quản lý thông báo đẩy toàn cục
```

---

## 📂 2. Khảo Sát Chi Tiết Từng Micro-core Package

### A. Core Common (`packages/core/common`)
Đóng vai trò là hạt nhân kết nối và định nghĩa chung cho toàn hệ thống:
- **Constants & Enums**: Nơi định nghĩa cấu hình môi trường, các khóa bộ nhớ cục bộ, endpoint API và các enum dùng chung.
- **Utils & Helpers**: Các hàm tiện ích xử lý chuỗi, định dạng ngày tháng, kiểm tra logic...

### B. Core DI (`packages/core/di`)
Đây là "Hub" giao tiếp cốt lõi để giải quyết Circular Dependency:
- **Decentralized Navigator Interfaces**: Chứa các Interface Navigator (`AuthNavigator`, `HomeNavigator`, `SettingsNavigator`, …) cho phép các Feature gọi sang nhau mà không cần import trực tiếp mã nguồn của nhau.
- **Hợp đồng đóng góp route**: `IFeatureRouteModule` (route stack, không order), `IDashboardTabModule` (tab bottom-nav có order), `IAppEntryLocation` (cold start), `DashboardRouteModule` (chỉ chrome dashboard), kèm `NavigatorKeys`.
- Helper host nằm ở `core_common`: `getItOrNull`, `getAll`, `getAllOrEmpty`.

### C. Core Base UI (`packages/core/base_ui`)
Là **Design System** (Hệ thống thiết kế) vật lý của ứng dụng:
- **Themes & Colors**: Cấu hình chế độ sáng/tối mở rộng (`ThemeMode`, `AppTheme`).
- **Assets Catalog**: Lớp bao bọc (Wrapper) an toàn cho phông chữ (Fonts), hình ảnh (Images), biểu tượng (Icons) dùng chung.
- **Design Tokens**: Assets catalog, phông chữ (Fonts), hình ảnh (Images), biểu tượng (Icons) và tệp ngôn ngữ dịch thuật (L10n). Chứa 0 Flutter widgets.

### C. Core Network (`packages/core/network`)
Hạ tầng kết nối API và mạng lưới:
- **`ApiClient`**: Factory tạo Dio Client theo yêu cầu của từng gói.
- **Security Interceptors**: 
  - `AuthInterceptor`: Tự động tiêm Bearer JWT Token từ Secure Storage vào Header.
  - `LoggingInterceptor`: Xuất log HTTP dạng JSON trực quan thông qua `dynamic_logger`.
  - `RetryInterceptor` & `RetryHandler`: Cơ chế **Global Retry Queue**. Khi nhiều luồng API call bị rớt mạng cùng lúc, hệ thống sẽ tạm dừng (block) toàn bộ hàng đợi, gộp chúng lại và gọi hàm hiển thị UI Dialog duy nhất một lần. Nếu người dùng chọn "Thử lại", hệ thống tự động chạy lại toàn bộ các request đang bị kẹt.
- **Dependency Inversion qua `NetworkConfig`**: Do package Network không được phép import trực tiếp các module Storage (để lấy Token) hay UI (để hiện Retry Dialog), gói này khai báo một interface mở là `NetworkConfig`. Gói Host App (`app`) sẽ viết một lớp `NetworkConfigImpl` cung cấp các tham số (Storage Token, AppDialogController) và truyền ngược lại vào `core_network` thông qua Dependency Injection. (Lưu ý: Để tránh `build_runner` báo lỗi missing dependency ảo, module mạng được cấu hình `ignoreUnregisteredTypes: [NetworkConfig]` ở `@InjectableInit`).

### D. Core Storage (`packages/core/storage`)
Hệ thống lưu trữ bảo mật cao cấp:
- **AES-256 mã hóa**: Tự động mã hóa phần mềm với ngẫu nhiên IV cho mỗi bản ghi.
- **Bảo mật phần cứng**: Lưu Master Key và dữ liệu mã hóa vào Apple Keychain / Android KeyStore.
- **Reactive Values**: Giá trị lưu trữ hoạt động như một Listener, tự động thông báo và đồng bộ với giao diện khi ghi dữ liệu.

### E. Core Database (`packages/core/database`)
Database quan hệ cục bộ xây trên Drift:
- **Background isolate**: `NativeDatabase.createInBackground` giữ I/O sqlite3 khỏi UI thread.
- **Truy vấn type-safe**: Bảng, DAO và migration do `drift_dev` sinh mã.
- **Sẵn sàng cho Data layer**: `AppDatabase` đăng ký qua DI `@preResolve`; xem [14. Hệ Thống Database](./14_database_system.md).

### F. Core State Management (`packages/core/provider_state_management`)
Khung sườn quản lý UI logic và đồng bộ trạng thái giao diện:
- **`BaseProvider`**: Lớp cơ sở cho các ViewModel, bọc sẵn các hàm xử lý vòng đời.
- **`executeOperation`**: Bộ xử lý bất đồng bộ, tự động quản lý cờ hiển thị Loading, bắt Exception toàn cục và chuyển hóa thành thông báo lỗi thân thiện.
- **`ProviderStateListener` & `MultiProviderStateListener`**: Bộ đôi tiện ích lắng nghe side-effects trên giao diện một cách declarative, loại bỏ hoàn toàn boilerplate code (`StreamSubscription`, `initState`, `dispose`) và đảm bảo type-safety hoàn hảo.

#### 🎨 Kiến Trúc Sealed ViewState & Polymorphic ErrorState
Để nâng cao tính linh hoạt và khả năng kiểm soát lỗi tùy biến sâu từ phía UI, hệ thống quản lý trạng thái đã được nâng cấp lên mô hình **Sealed ViewState** kết hợp **Polymorphic ErrorState**:

##### 1. Sealed Class `ViewState`
`ViewState` được định nghĩa dưới dạng một sealed class (Freezed Union) giúp đảm bảo tính cạn kiệt (exhaustive matching) khi render UI:
* `ViewState.initial()`: Trạng thái khởi tạo.
* `ViewState.loading()`: Đang thực thi tác vụ.
* `ViewState.success()`: Thực thi thành công.
* `ViewState.error({ErrorState? error})`: Thất bại, đính kèm đối tượng `ErrorState` tùy biến.

##### 2. Tùy Biến `ErrorState` Không Giới Hạn
Bên sử dụng (Feature mô-đun) có thể tự do mở rộng `ErrorState` để định nghĩa cấu trúc dữ liệu lỗi riêng cho nghiệp vụ của họ:
```dart
class MyCustomErrorState extends ErrorState {
  final String code;
  final String description;

  const MyCustomErrorState({required this.code, required this.description});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'my_custom_error',
        'code': code,
        'description': description,
      };

  factory MyCustomErrorState.fromJson(Map<String, dynamic> json) =>
      MyCustomErrorState(
        code: json['code'] as String,
        description: json['description'] as String,
      );
}
```

##### 3. Cơ Chế Polymorphic Serialization & Fallback Registry
Khi trạng thái ứng dụng được lưu trữ hoặc gửi qua môi trường mạng (hoặc lưu đệm offline như Hydrated Bloc/Hydrated Provider), `ViewStateModel` hỗ trợ đầy đủ việc tuần tự hóa (serialization) và giải tuần tự hóa (deserialization) đa hình thông qua **`ErrorStateRegistry`**.

###### ❓ Tại sao cần `ErrorStateRegistry`?
Vì `ErrorState` là một lớp trừu tượng (`abstract class`), thư viện sinh code như `json_serializable` khi đọc một chuỗi JSON **sẽ không thể biết** cấu trúc JSON đó ứng với thực thể con (subclass) cụ thể nào để khởi tạo lại. `ErrorStateRegistry` giải quyết bài toán này bằng cách đóng vai trò như một **bản đồ định tuyến kiểu động (Polymorphic Routing Map)**:

1. Mỗi subclass của `ErrorState` cần trả về một khóa nhận diện kiểu (ví dụ: `'type': 'my_custom_error'`) trong phương thức `toJson()`.
2. Ta đăng ký khóa nhận diện này kèm theo hàm khởi tạo `fromJson` của nó vào registry.
3. Khi giải tuần tự, registry tự động trích xuất thuộc tính `'type'` từ JSON và gọi đúng hàm khởi tạo tương ứng.

###### 📝 Cấu trúc JSON khi Tuần Tự Hóa (Serialization)
Khi một `ViewStateModel` chứa custom `ErrorState` được serialize, cấu trúc JSON sẽ được tạo ra như sau:
```json
{
  "state": {
    "state": "error",
    "error": {
      "type": "my_custom_error",
      "code": "ERR_AUTH_001",
      "description": "Phiên đăng nhập đã hết hạn"
    }
  },
  "data": null,
  "message": "Phiên đăng nhập đã hết hạn"
}
```

###### 🛠️ Cách thức Đăng ký & Vòng đời Đăng ký (Registry Lifecycle)
Việc đăng ký các Deserializer **bắt buộc phải thực hiện sớm nhất có thể trong vòng đời ứng dụng** (trước khi bất kỳ tiến trình khôi phục hoặc đọc trạng thái offline nào diễn ra). Địa điểm lý tưởng nhất là trong hàm `main()` của ứng dụng tại `app/lib/main.dart` hoặc tại khối thiết lập DI:

```dart
// Đăng ký Deserializer trong main() trước khi khởi chạy runApp()
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Đăng ký toàn bộ các kiểu lỗi nghiệp vụ đặc thù của dự án
  ErrorStateRegistry.register('my_custom_error', MyCustomErrorState.fromJson);
  ErrorStateRegistry.register('validation_error', ValidationErrorState.fromJson);
  
  runApp(const MyApp());
}
```

###### 🛡️ Cơ chế Phòng vệ Tự Động Fallback (`RawErrorState`)
Nếu hệ thống giải tuần tự hóa một cấu trúc JSON lỗi chứa `"type": "unknown_type"` chưa từng được đăng ký trong hệ thống:
* Registry sẽ **tự động chuyển đổi** cấu trúc đó về đối tượng **`RawErrorState`**.
* Lớp `RawErrorState` này bọc lại toàn bộ Map JSON thô của lỗi đó. Điều này đảm bảo **100% dữ liệu không bị thất thoát**, ứng dụng **không bị crash**, và lập trình viên vẫn có thể truy cập dữ liệu thô thông qua thuộc tính `.json` nếu cần thiết:
  ```dart
  if (error is RawErrorState) {
    final rawJson = error.json; // Trả về { "type": "unknown_type", "custom_field": "..." }
  }
  ```

##### 4. Cấu Hình Tác Vụ Lỗi Linh Hoạt Qua `OperationConfig`
Khi định cấu hình tác vụ bất đồng bộ, lập trình viên có thể tùy ý tiêm một hàm chuyển đổi từ `AppFailure` sang đối tượng `ErrorState` mong muốn bằng cách sử dụng tham số `errorStateBuilder`:
```dart
await executeOperation(OperationConfig(
  operation: () => authRepository.login(username, password),
  errorStateBuilder: (failure) => MyCustomErrorState(
    code: 'LOGIN_FAILED',
    description: failure.message,
  ),
));
```

##### 5. Xử Lý Phản Hồi Trạng Thái Trên UI (Type-safe Exhaustive Matching)
Nhờ tính chất Sealed của `ViewState`, tầng Presentation (như `BaseViewWidget`) có thể xử lý trạng thái cực kỳ chặt chẽ thông qua API `.when()` hoặc `.whenOrNull()` tự sinh:
```dart
return viewState.state.when(
  initial: () => const InitialWidget(),
  loading: () => const LoadingWidget(),
  success: () => const SuccessWidget(),
  error: (error) {
    if (error is MyCustomErrorState) {
      return SpecialErrorWidget(code: error.code);
    }
    return GeneralErrorWidget(message: viewState.message);
  },
);
```

##### 6. Cơ Chế Lắng Nghe Trạng Thái Giao Diện (Declarative State Listening)
Khi ứng dụng cần thực thi các tác vụ chỉ xảy ra một lần dựa trên sự thay đổi trạng thái (chẳng hạn như hiển thị Toast thông báo, bật Dialog, hoặc điều hướng màn hình), việc lắng nghe thủ công bằng `StreamSubscription` trong `initState` và `dispose` rất dễ gây ra rò rỉ bộ nhớ (memory leaks) và tốn nhiều effort bảo trì.

Để giải quyết triệt để vấn đề này, gói `provider_state_management` tích hợp sẵn hai công cụ chuyên dụng:
1. **`ProviderStateListener<P, T>`**: Lắng nghe một `BaseProvider` duy nhất.
2. **`MultiProviderStateListener`**: Tổ hợp nhiều listener đầu vào mà không gây lồng cây widget sâu (Deep Nesting).

###### Cú Pháp Chi Tiết của `ProviderStateListener`
```dart
ProviderStateListener<AuthProvider, UserEntity>(
  // Được gọi khi state chuyển sang loading
  onLoading: (context) {
    // Ví dụ: hiển thị loading HUD cục bộ
  },
  // Được gọi khi state chuyển sang success
  onSuccess: (context, user) {
    // Ví dụ: điều hướng sang Dashboard
  },
  // Được gọi khi state chuyển sang error, nhận vào ErrorState đa hình & message
  onError: (context, error, message) {
    if (error is AuthErrorState) {
      error.maybeWhen(
        invalidCredentials: () => AppOverlay.showToast(content: 'Sai thông tin đăng nhập'),
        orElse: () => AppOverlay.showToast(content: message ?? 'Đã có lỗi xảy ra'),
      );
    }
  },
  // (Tùy chọn) Bộ lọc kiểm soát điều kiện kích hoạt callback
  listenWhen: (previous, current) => previous.state != current.state,
  child: Scaffold(...),
)
```

###### Thiết Kế "Blueprint Pattern" Của `MultiProviderStateListener`
Để tránh việc lồng các widget listener gây khó đọc mã nguồn, `MultiProviderStateListener` cho phép khai báo danh sách các listener phẳng bằng cách sử dụng các đối tượng cấu hình nhẹ `ProviderStateListenerEntry` thay vì lồng widget thủ công:

```dart
MultiProviderStateListener(
  listeners: [
    ProviderStateListenerEntry<AuthProvider, UserEntity>(
      onError: (context, error, message) => AppOverlay.showToast(content: message),
    ),
    ProviderStateListenerEntry<CartProvider, CartData>(
      onSuccess: (context, cart) => AppOverlay.showToast(content: 'Cập nhật giỏ hàng thành công'),
    ),
  ],
  child: MyScreenBody(),
)
```
* **Lưu ý kỹ thuật quan trọng**: `ProviderStateListenerEntry` kế thừa từ `ProviderStateListenerBase` và KHÔNG phải là một widget. Nó đóng vai trò là một "bản thiết kế" (blueprint) định nghĩa hành vi lắng nghe. Khi được nạp vào `MultiProviderStateListener`, hệ thống sẽ tự động gọi phương thức `buildWithChild()` để lồng các widget một cách type-safe nhất, giúp giữ nguyên vẹn generic type arguments của từng Provider phục vụ việc tra cứu phụ thuộc (dependency lookup) của Flutter.

---

### F. Core Bloc State Management (`packages/core/bloc_state_management`)
Khung sườn quản lý trạng thái dành cho các Feature sử dụng kiến trúc BLoC:
- **`BaseBloc` / `BaseCubit`**: Các lớp cơ sở thuần túy, không gò ép logic phức tạp, giúp các lập trình viên BLoC tự do triển khai các helper, logging hoặc exception handling theo phong cách đặc thù của BLoC.
- **`ViewState`**: Lớp trạng thái tiêu chuẩn (Freezed Union) đồng nhất (`initial`, `loading`, `success`, `error`) để sử dụng chung cho toàn bộ các màn hình, giúp UI dễ dàng pattern-matching mà không cần tự định nghĩa lại trạng thái.

---

## 🔌 3. Cơ Chế Đăng Ký DI và Phơi API (Micro-core Exposure)

Mỗi mô-đun Core tự chịu trách nhiệm đăng ký phụ thuộc của nó thông qua `@InjectableInit.microPackage()` tại tệp `lib/di/module.dart` của mình.

Gói chính `app` sẽ nạp các mô-đun này tại `injection.dart`.

**Thứ tự:** Giữ core hạ tầng trong `externalPackageModulesBefore`. Đặt `CoreBaseUiPackageModule` trong `externalPackageModulesAfter` (qua `_uiModules`) vì nó phụ thuộc `ILanguageStorage` / `IThemeStorage` đăng ký tại App Shell.

```dart
@InjectableInit(
  externalPackageModulesBefore: [
    ExternalModule(CoreCommonPackageModule),
    ExternalModule(CoreNetworkPackageModule),
    ExternalModule(CoreNotificationsPackageModule),
    ExternalModule(CoreStoragePackageModule),
    ExternalModule(CoreDiPackageModule),
  ],
  externalPackageModulesAfter: [
    ExternalModule(CoreBaseUiPackageModule),
    ExternalModule(ProviderStateManagementPackageModule),
    ExternalModule(BlocStateManagementPackageModule),
    // ... các module micro-package domain_*, data_*, feature_*
  ],
)
```

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
