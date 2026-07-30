# 04. Tầng Trình Diễn & Giao Diện (Presentation Layer - Features Hub)

Tầng Presentation chịu trách nhiệm quản lý vòng đời hiển thị, nhận tương tác từ người dùng, và vẽ giao diện UI. Trong kiến trúc mới, tầng này không còn nằm chung một thư mục chính mà được phân chia thành **các gói tính năng độc lập (Feature Packages)** nằm dưới `packages/features/` để tối đa hóa tính đóng gói độc lập.

---

## 🏛️ 1. Bản Đồ Tổ Chức Gói Tính Năng (Feature Monorepo Grid)

```text
packages/features/
├── splash/       # Module Splash: Màn hình chào khởi chạy ban đầu
├── onboarding/   # Module Onboarding: Giới thiệu ứng dụng & hướng dẫn ban đầu
├── auth/         # Module Auth: Đăng nhập, Đăng ký, Quên mật khẩu
├── dashboard/    # Module Dashboard: Chỉ shell Bottom Bar (ghép route của các feature khác)
├── home/         # Module Home: Nội dung tab Home (mẫu)
├── settings/     # Module Settings: Nội dung tab Settings (mẫu) — tách khỏi Home
└── shared/       # Module Shared: Chứa các widget hiển thị dùng chung giữa các feature
```

> **Ghi chú Clean Architecture:** Dashboard chỉ sở hữu **chrome shell** (`DashboardRouteModule`). Màn tab đăng ký `IDashboardTabModule` trong package riêng; `AppRouter` lắp branch. Xem `docs/vi/08_routing.md` mục Dashboard.

### Cấu Trúc Nội Bộ Một Feature Package (ví dụ: `feature_auth`)
```text
feature_auth/
├── lib/
│   ├── auth.dart         # Barrel file xuất bản API công khai và Routes của Feature
│   ├── src/
│   │   ├── pages/        # Các màn hình lớn gắn liền định tuyến (ví dụ: LoginPage)
│   │   ├── widgets/      # Widget nhỏ chuyên biệt chỉ dùng riêng cho module này
│   │   ├── provider/     # Bộ điều khiển logic giao diện (ViewModels)
│   │   └── routing/      # Khai báo cấu hình GoRouter riêng của Feature
│   └── di/
│       └── module.dart   # Khởi tạo DI cục bộ cho gói Auth
```

---

## 🧬 2. Trái Tim Giao Diện: Cơ Chế MVVM / MVI (Agnostic State Management)

Hệ thống cung cấp cơ chế hỗ trợ đa nền tảng State Management (Provider, BLoC, Riverpod). Các Feature module được quyền tự do lựa chọn công cụ phù hợp với team:
- **View (Pages/Widgets)**: Chỉ vẽ giao diện dựa trên trạng thái bất biến hiện tại, lắng nghe sự thay đổi thông qua cơ chế của thư viện tương ứng (ví dụ: `Consumer`, `BlocBuilder`).
- **ViewModel/Bloc**: Khuyến khích kế thừa từ các Base tương ứng (**`BaseProvider<T>`** cho Provider, hoặc **`BaseBloc`** cho BLoC — dùng **`BaseCubit` chỉ khi không cần Event**), chịu trách nhiệm hứng các tương tác người dùng, gọi UseCases của Domain, và cập nhật trạng thái UI.

### Trạng thái UI Chuẩn Hóa (`ViewState<T>` / `ViewStateModel<T>`)
Với **Provider**, UI state được bọc qua `ViewStateModel<T>` trong `BaseProvider`.

Với **BLoC**, `ViewState<T>` là **helper tùy chọn dùng chung** (`initial` / `loading` / `success` / `error`) — hữu ích cho màn hình đơn giản và đồng bộ với module Provider. **Không bắt buộc**: feature BLoC phức tạp được tự định nghĩa Freezed UI state (`BaseBloc<Event, CustomState>`).
- `initial`: Màn hình vừa khởi chạy.
- `loading`: Hệ thống đang xử lý tải dữ liệu/thực thi tác vụ.
- `success(T data)`: Xử lý thành công, nhả dữ liệu sạch.
- `error(String message)`: Có lỗi xảy ra, nhả thông điệp lỗi trực quan.

### 📚 Chi Tiết Triển Khai (Hướng Dẫn Dành Riêng Cho Từng Thư Viện)

Do tính chất Agnostic của hệ thống, các tài liệu hướng dẫn cụ thể (ví dụ như cách gọi API, cách tự động hóa Loading, cách vẽ danh sách phân trang, hay lắng nghe side-effects) không được định nghĩa cứng tại đây.

Thay vào đó, bạn **bắt buộc phải đọc tài liệu (README)** đính kèm bên trong mỗi gói State Management để nắm bắt toàn bộ tính năng mạnh mẽ mà hệ thống đã xây dựng sẵn cho thư viện bạn đang chọn:

- 👉 **[Tài liệu Cốt lõi của Provider (`provider_state_management`)](file:///c:/Users/PC/Desktop/codebase/packages/core/provider_state_management/README.md)**: Dành cho team sử dụng Provider. Đọc để biết cách dùng `executeOperation`, `BaseViewWidget`, `ProviderStateListener`, `BaseProxyWidget`, v.v.
- 👉 **[Tài liệu Cốt lõi của BLoC (`bloc_state_management`)](file:///c:/Users/PC/Desktop/codebase/packages/core/bloc_state_management/README.md)**: Dành cho team dùng BLoC. Gồm `BaseBloc`, `ViewState` (tùy chọn), Freezed state riêng, `BlocBuilder` / Pattern Matching, và route-level providers.

---

## ⚡ 3. Chiến Lược Quản Lý Vòng Đời UI Controller (Agnostic Lifecycle)

Lập trình viên bắt buộc phải phân loại rõ ràng phạm vi sử dụng của UI Controller (ViewModel / Bloc) để áp dụng đúng cơ chế đăng ký:

| Đặc tính phân loại | Feature Controller (ViewModel/Bloc gắn với 1 màn hình) | Global Controller (App Service/Theme/Auth) |
| :--- | :--- | :--- |
| **Phạm vi hoạt động** | Chỉ gắn liền với một Page / một luồng cụ thể | Toàn bộ ứng dụng (App-wide) |
| **Thời gian sống** | Tự động hủy khi tắt màn hình (Auto-dispose) | Sống suốt đời ứng dụng (Singleton) |
| **Cơ chế Đăng ký DI** | Dùng `@injectable` (tạo mới mỗi lần gọi `getIt`) | Sử dụng `@lazySingleton` (khởi tạo duy nhất 1 lần) |

#### Vị trí khởi tạo UI Controller (Route-Level Instantiation)
Đối với Feature Controller, **bắt buộc khởi tạo chúng tại tầng Routing** (trong file `route_module.dart`) thay vì khởi tạo bên trong Widget của màn hình. Bằng cách kết hợp `@injectable` và `ChangeNotifierProvider` (hoặc `BlocProvider`), GetIt sẽ tự động lo việc khởi tạo các class phụ thuộc (UseCases), còn Provider Framework sẽ chịu trách nhiệm tự động gọi hàm `dispose()` hoặc `close()` để giải phóng RAM khi người dùng rời khỏi màn hình đó.

*(Chi tiết về cách bọc Route và liên kết phụ thuộc State chéo (Proxy State), vui lòng xem thêm tại tài liệu của gói SM hoặc mục 6 của [08. Định Tuyến & Điều Hướng](08_routing.md))*



---

## 🚦 4. Giao Tiếp Định Tuyến Decoupled qua Scoped Navigator (Decentralized Routing)

Trong View hoặc ViewModel của một Feature, **tuyệt đối không được import trực tiếp tệp định tuyến của Feature khác** để tự gọi lệnh di chuyển trang. Điều này phá vỡ tính đóng gói và gây lỗi tham chiếu vòng.

Mọi hành động điều phối ra bên ngoài Feature đều phải thông qua một **Interface Navigator riêng biệt** (định nghĩa tại `core_di` và được triển khai cục bộ bên trong chính Feature đó, ví dụ: `AuthNavigator` được triển khai tại `feature_auth`):

```dart
// Định nghĩa tại packages/core/di/lib/src/navigators/auth_navigator.dart
import 'package:core_di/core_di.dart';

abstract class AuthNavigator {
  void toRegister(BuildContext context);
}

// ViewModel sử dụng:
```dart
class MyViewModel extends BaseController {
  // Navigator giao tiếp được tiêm tự động thông qua GetIt
  final AuthNavigator _navigator;

  MyViewModel(this._navigator);

  void onUserClickRegister(BuildContext context) {
    // Chuyển hướng: ViewModel gọi navigator cục bộ, không cần quan tâm trang Register nằm ở đâu
    _navigator.toRegister(context);
  }
}
```

### 🤝 Chia Sẻ Page / Widget Giữa Các Feature Trong Mô Hình Decoupled

Trong kiến trúc Monorepo phi tập trung (Decoupled), các Feature không được phép import trực tiếp lẫn nhau để tránh gây lỗi **Circular Dependency** (tham chiếu vòng). Khi Feature A muốn hiển thị một Page hoặc một Widget con thuộc sở hữu của Feature B, ta áp dụng các chiến lược sau:

#### 1. Chia Sẻ Page (Dưới dạng một màn hình nguyên vẹn)

*   **Chuyển trang độc lập**: Sử dụng định tuyến thông qua **Navigator Interface** (đã trình bày ở trên). Lớp cài đặt (Implementation) tại gói Feature cục bộ sẽ chỉ đạo `GoRouter` di chuyển đến màn hình đích của Feature B.
*   **Ghép trang làm con (Ví dụ: Tab trong DashboardPage)**:
    *   Feature Dashboard **không** được import `HomePage` / `ChatPage` / `ProfilePage`.
    *   Mỗi feature tab đăng ký `IDashboardTabModule` (order, path, routes, nav item).
    *   `feature_dashboard` triển khai `DashboardRouteModule` (chrome) và dựng bottom bar từ `getAllOrEmpty<IDashboardTabModule>()`.
    *   `AppRouter` dựng `StatefulShellBranch` từ cùng các module — **không** hardcode route tab trong `app_router.dart`.
    *   Quy tắc / anti-pattern đầy đủ: `docs/vi/08_routing.md` mục Dashboard.

#### 2. Chia Sẻ Widget Con (Nhúng Widget của Feature B vào giao diện Feature A)

*   **Trường hợp Widget giao diện thuần túy (Không có business logic / provider)**:
    *   Nếu widget là các thành phần giao diện tái sử dụng chung (như nút bấm, thẻ thông tin chung, thanh tiến trình...), hãy đặt chúng vào gói **`feature_shared`** (`packages/features/shared`). Tất cả các feature package đều có thể import gói này.
*   **Trường hợp Widget gắn liền với Logic / Provider của Feature B**:
    *   *Ví dụ:* Feature Chat cần hiển thị một thẻ xem nhanh thông tin người dùng (`UserProfileCardWidget`) thuộc gói Profile.
    *   *Giải pháp:* Sử dụng cơ chế **Widget Builder Interface qua Dependency Injection (GetIt)**:
        
        1. Khai báo một Interface Builder tại tầng liên kết dùng chung (ví dụ: `core_di` hoặc `core_common`):
           ```dart
           abstract class ProfileWidgetBuilder {
             Widget buildProfileCard({required String userId});
           }
           ```
        2. Triển khai Interface đó tại gói `feature_profile` và đăng ký nó với GetIt dưới dạng `@Singleton` hoặc `@LazySingleton`:
           ```dart
           import 'package:core_di/core_di.dart';
           
           @Singleton(as: ProfileWidgetBuilder)
           class ProfileWidgetBuilderImpl implements ProfileWidgetBuilder {
             @override
             Widget buildProfileCard({required String userId}) {
               // Có thể khởi tạo Provider/Proxy cục bộ và bọc quanh Widget con nếu cần
               return UserProfileCardWidget(userId: userId);
             }
           }
           ```
        3. Tại `feature_chat`, chỉ cần tiêm interface `ProfileWidgetBuilder` thông qua GetIt để render giao diện mà không cần biết chi tiết cài đặt hay import mã nguồn của `feature_profile`:
           ```dart
           class ChatItemWidget extends StatelessWidget {
             final String senderId;
             const ChatItemWidget({required this.senderId});
           
             @override
             Widget build(BuildContext context) {
               return Row(
                 children: [
                   // Nhúng widget Profile Card một cách decoupled hoàn toàn
                   getIt<ProfileWidgetBuilder>().buildProfileCard(userId: senderId),
                   const Text('Nội dung tin nhắn...'),
                 ],
               );
             }
           }
           ```

*   **Trường hợp Dialog / BottomSheet**:
    *   Nếu Widget cần mở dưới dạng hộp thoại hội thoại hoặc tấm trượt dưới đáy màn hình, ta khai báo một phương thức hiển thị trong Navigator Interface của feature đó:
       ```dart
       abstract class ChatNavigator {
         void showProfileDialog(BuildContext context, {required String userId});
       }
       ```
    *   Lớp triển khai Navigator cục bộ tại tầng App Shell (`app/`) sẽ chịu trách nhiệm import widget `UserProfileDialog` của `feature_profile` và gọi hàm hiển thị `showDialog(context, builder: ...)` tương ứng.

---

## 🤝 5. Chia Sẻ Services & Logic Nghiệp Vụ Giữa Các Feature (Cross-Feature Communication)

Trong kiến trúc đa mô-đun (Multi-package Monorepo), nguyên tắc cốt lõi là **đảm bảo tính đóng gói độc lập và triệt tiêu phụ thuộc lẫn nhau (Loose Coupling)**. Các package Feature không được phép import trực tiếp code của nhau để tránh lỗi tham chiếu vòng (Circular Dependency). 

Để chia sẻ dữ liệu, nghiệp vụ hoặc trạng thái giữa các Feature với nhau, hệ thống quy định 4 mô hình thiết kế chuẩn hóa dưới đây:

---

### 🏛️ Mô Hình 1: Chia Sẻ Logic Nghiệp Vụ qua Tầng Domain (Domain UseCase Sharing)

Đây là mô hình **khuyến khích nhất** đối với hầu hết các bài toán chia sẻ nghiệp vụ. Thay vì Feature A gọi trực tiếp Feature B, cả hai Feature đều giao tiếp thông qua tầng **Domain** (`packages/domain/* (Micro-packages)`) dùng chung.

*   **Cách hoạt động**: 
    - Gói `domain` chứa toàn bộ các Entity, interfaces (Repository contracts), và UseCases của ứng dụng.
    - Mọi Feature package đều có thể phụ thuộc vào gói `domain`.
    - Khi Feature A (ví dụ: `feature_booking`) cần thông tin hoặc thực hiện hành động liên quan đến Feature B (ví dụ: `feature_auth`), nó sẽ tiêm (inject) UseCase tương ứng từ `domain` (ví dụ: `GetProfileUseCase`) thông qua `GetIt`.
*   **Sơ đồ luồng**:
    ```mermaid
    graph LR
        feature_booking["feature_booking"] -->|"Import & Inject Usecase"| domain_usecase["GetProfileUseCase"]
        feature_auth["feature_auth"] -->|"Triển khai & Cung cấp"| domain_usecase
    ```

*   **Ví dụ**:
    ```dart
    // Trong feature_booking/lib/src/provider/booking_controller.dart
    import 'package:domain_*/domain_*.dart'; // Phụ thuộc duy nhất vào Domain
    
    class BookingController {
      final CreateBookingUseCase _createBookingUseCase;
      // Sử dụng UseCase của Auth thông qua tầng Domain
      final GetProfileUseCase _getProfileUseCase;
    
      BookingController(
        this._createBookingUseCase,
        this._getProfileUseCase,
      );
    
      Future<void> makeReservation() async {
        // Lấy thông tin user hiện tại từ UseCase mà không cần import feature_auth
        final userResult = await _getProfileUseCase();
        // ... xử lý logic tiếp theo
      }
    }
    ```

---

### ⚙️ Mô Hình 2: Chia Sẻ Dịch Vụ Core & Tiện Ích Hạ Tầng (Core Infrastructure Services)

Các dịch vụ hạ tầng mang tính dùng chung cho toàn bộ ứng dụng (chạy ngầm, không chứa UI) được đóng gói độc lập trong các thư mục `packages/core/`.

*   **Cách hoạt động**:
    - Thiết lập các thư viện core như: `core_storage` (quản lý local database, cache), `core_network` (kết nối HTTP/gọi API), `core_notifications` (quản lý Push Notification).
    - Các Feature package chỉ cần import các thư viện core này để thực hiện lưu trữ hoặc gửi nhận dữ liệu.
*   **Ví dụ**:
    ```dart
    // Trong feature_chat/lib/src/controller/chat_controller.dart
    import 'package:core_storage/core_storage.dart'; // Import core package
    
    class ChatController {
      final LocalStorage _localStorage; // Khai báo sử dụng interface từ core_storage
      
      ChatController(this._localStorage);
      
      Future<void> saveDraftMessage(String draft) async {
        // Lưu trữ trực tiếp xuống Local Storage
        await _localStorage.write(StoragePresets.chatDraftKey, draft);
      }
    }
    ```

---

### 🌐 Mô Hình 3: Chia Sẻ Trạng Thái Toàn Cục & Giao Tiếp Chéo Hệ Lạ (Agnostic Streams)

**Lưu ý cực kỳ quan trọng:** Khi làm việc trong môi trường đa State Management, việc Feature A (dùng BLoC) muốn lắng nghe Feature B (dùng Provider) hoặc lấy trạng thái toàn cục sẽ vấp phải rào cản thư viện. Để giải quyết, toàn bộ hệ thống áp dụng **Neutral Streams trên DI Hub**:

*   **Quy tắc Global State**: Trạng thái toàn cục không thuộc tính năng nào (ví dụ Theme, Deeplink) bắt buộc dùng **1 tiêu chuẩn duy nhất** (Provider hoặc Dart `Stream`/`ValueNotifier` thuần) để không ép các Feature phải phụ thuộc chéo thư viện.
*   **Giao tiếp chéo (Cross-feature SM)**:
    1. Feature A tạo ra một Interface bọc Dart `Stream` hoặc `ValueListenable` thuần túy và đăng ký lên GetIt.
    2. Feature A không bao giờ phơi (expose) trực tiếp instance của BLoC hay Provider ra ngoài.
    3. Feature B chỉ việc tiêm (inject) Interface này và lắng nghe thông tin trung lập mà không cần biết Feature A được code bằng công cụ UI nào.
*   **Sơ đồ luồng**:
    ```mermaid
    graph TD
        Hub["DI Hub (core_di)<br/>&lt;I_NeutralStreamInterface&gt;"]
        
        FeatA["Feature A<br/>(Dùng Provider)"]
        FeatB["Feature B<br/>(Dùng BLoC)"]

        FeatA -->|"Đẩy dữ liệu"| Hub
        Hub -->|"Lắng nghe Stream"| FeatB
    ```

*   **Quy tắc Đăng ký Kép (Dual Registration)**: Để tránh việc ép kiểu (`as`) thủ công, hãy đăng ký Implementation dưới dạng `@singleton` cụ thể và dùng một `@module` để liên kết nó với Interface. Cách này cho phép Feature chủ quản tiêm (inject) trực tiếp class cụ thể qua constructor, trong khi các Feature khác vẫn chỉ lắng nghe qua Interface.

*   **Ví dụ Thực tế (`IAuthStatusStream`)**:

    **Bước 1: Định nghĩa interface trung lập trong `packages/core/di/lib/src/agnostic_streams/i_auth_status_stream.dart`**
    *(Lưu ý: Tầng DI Hub được phép import các domain micro-packages để định kiểu (type) rõ ràng cho dữ liệu truyền tải).*
    ```dart
    import 'package:domain_auth/domain_auth.dart';
    
    /// Interface Stream Trung lập cho Trạng thái Đăng nhập.
    /// Các features khác có thể lắng nghe [authStatusStream] để phản ứng với sự kiện login/logout
    /// mà không cần phụ thuộc trực tiếp vào `feature_auth`.
    abstract class IAuthStatusStream {
      Stream<UserEntity?> get authStatusStream;
      UserEntity? get currentUser;
    }
    ```

    **Bước 2: Triển khai và đăng ký tại Feature Chủ quản (`packages/features/auth/lib/src/services/auth_status_stream_impl.dart`)**
    ```dart
    import 'dart:async';
    import 'package:core_di/core_di.dart';
    import 'package:domain_auth/domain_auth.dart';
    import 'package:injectable/injectable.dart';

    @singleton
    class AuthStatusStreamImpl implements IAuthStatusStream {
      final _controller = StreamController<UserEntity?>.broadcast();
      UserEntity? _currentUser;

      @override
      Stream<UserEntity?> get authStatusStream => _controller.stream;

      @override
      UserEntity? get currentUser => _currentUser;

      /// Hàm nội bộ dành cho feature_auth cập nhật trạng thái
      void updateAuthStatus(UserEntity? user) {
        _currentUser = user;
        _controller.add(user);
      }
    }
    ```

    **Bước 3: Gọi cập nhật từ Feature Chủ quản (`packages/features/auth/lib/src/provider/auth_provider.dart`)**
    ```dart
    // Tiêm (Inject) trực tiếp class `AuthStatusStreamImpl _authStream` qua constructor
    Future<void> login(String email, String password) async {
      await executeOperation(
        OperationConfig(
          operation: () => _loginUseCase(LoginParams(email: email, password: password)),
          onSuccess: (user) async {
            // Đẩy trạng thái mới lên DI Hub
            _authStream.updateAuthStatus(user);
          },
        ),
      );
    }
    ```

    **Bước 4: Các Feature khác lắng nghe một cách trung lập (`packages/features/home/lib/src/pages/home_page.dart`)**
    ```dart
    import 'package:core_di/core_di.dart';
    import 'package:domain_auth/domain_auth.dart';

    // ...
    // feature_home lắng nghe IAuthStatusStream mà không cần import feature_auth
    StreamBuilder<UserEntity?>(
      stream: getIt<IAuthStatusStream>().authStatusStream,
      builder: (context, snapshot) {
        final isLoggedIn = snapshot.data != null;
        return Text(isLoggedIn ? 'Đã đăng nhập' : 'Chưa đăng nhập');
      },
    )
    ```

---

### 🎨 Mô Hình 4: Quản lý Trạng Thái Thuần UI (Bỏ Qua Tầng Domain)

**ThemeMode** và **Locale** là tùy chọn UI thuần túy. Chúng không thể đi qua tầng Domain vì Domain là **Pure Dart** và không được import `package:flutter/material.dart`.

*   **Cách hoạt động**:
    - UI Providers trong `core_base_ui` (`ThemeProvider`, `LanguageProvider`) quản lý state trong RAM.
    - Lưu trữ qua interface trung lập trên DI Hub (`IThemeStorage`, `ILanguageStorage`).
    - Implementation cụ thể nằm ở **App Shell** (`app/lib/di/`) và đọc/ghi `StorageValuePresets` từ `core_storage`.
*   **Sơ đồ luồng**:
    ```mermaid
    graph LR
        ThemeUI["ThemeProvider<br/>(core_base_ui)"] -->|"Lưu trực tiếp"| ITheme["IThemeStorage<br/>(core_di)"]
        ITheme -->|"Implements"| ThemeImpl["ThemeStorageImpl<br/>(app/di)"]
        ThemeImpl --> Presets["StorageValuePresets<br/>(core_storage)"]

        LangUI["LanguageProvider<br/>(core_base_ui)"] -->|"Lưu trực tiếp"| ILang["ILanguageStorage<br/>(core_di)"]
        ILang -->|"Implements"| LangImpl["LanguageStorageImpl<br/>(app/di)"]
        LangImpl --> Presets
    ```
*   **Luồng hiện tại**:
    - **Theme**: `ThemeProvider` ➔ `IThemeStorage` ➔ `StorageValuePresets.themeMode`
    - **Language**: `LanguageProvider` ➔ `ILanguageStorage` ➔ `StorageValuePresets.locale`

---

### 🤝 Mô Hình 5: Giao Tiếp qua Interface Builder & Service Locator (Decoupled Service Interfaces)

Trong trường hợp Feature A muốn tương tác với logic đặc thù hoặc kích hoạt trạng thái của Feature B (ví dụ: `feature_payment` cần kích hoạt popup cập nhật thông tin thẻ trong `feature_profile`), nhưng nghiệp vụ này không thuộc tầng Domain và không thể giải quyết bằng UI Route đơn thuần.

*   **Cách hoạt động**:
    1. Định nghĩa một Interface giao tiếp (Contract) tại thư viện dùng chung `core_di` hoặc `core_common`.
    2. Feature B thực hiện triển khai (Implement) interface này và đăng ký với GetIt dưới dạng `@Singleton`.
    3. Feature A chỉ cần gọi GetIt để lấy interface này ra dùng mà không hề biết chi tiết triển khai hay import thư viện của Feature B.

*   **Ví dụ thực tế**:
    
    **Bước 1: Khai báo interface dùng chung tại `packages/core/di/lib/src/services/payment_service_delegate.dart`**
    ```dart
    abstract class PaymentServiceDelegate {
      Future<bool> verifyUserProfile(BuildContext context, {required String userId});
    }
    ```
    
    **Bước 2: Triển khai và đăng ký tại `packages/features/profile`**
    ```dart
    import 'package:core_di/core_di.dart';
    
    @Singleton(as: PaymentServiceDelegate)
    class ProfilePaymentServiceDelegateImpl implements PaymentServiceDelegate {
      @override
      Future<bool> verifyUserProfile(BuildContext context, {required String userId}) async {
        // Thực hiện logic giao diện hoặc gọi dialog xác thực thông tin tại Profile
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => const UserProfileVerificationDialog(),
        );
        return result ?? false;
      }
    }
    ```
    
    **Bước 3: Sử dụng tại `packages/features/payment`**
    ```dart
    import 'package:core_di/core_di.dart';
    
    class PaymentController {
      final PaymentServiceDelegate _profileDelegate;
      
      // Tiêm interface vào constructor
      PaymentController(this._profileDelegate);
      
      Future<void> executeCheckout(BuildContext context) async {
        // Kích hoạt xác thực thông tin thông qua delegate lỏng lẻo
        final isVerified = await _profileDelegate.verifyUserProfile(context, userId: 'user123');
        
        if (!isVerified) {
          // Dừng thanh toán...
          return;
        }
        
        // Tiến hành thanh toán...
      }
    }
    ```

---

### 🎛️ Mô Hình 6: Hành Động UI Liên Feature qua Action Handlers

Khi Feature A cần **kích hoạt một hành động gắn UI thuộc Feature B** (ví dụ Settings ở `feature_settings` gọi logout thuộc `feature_auth`) mà không được import Feature B, dùng hợp đồng **Action Handler** trên DI Hub.

*   **Khi nào dùng**: Hành động cần Provider / UI context của Feature B (`BuildContext`, `context.read<AuthProvider>()`, dialogs), **không** phải điều hướng thuần (dùng Navigator) và **không** chỉ gọi Domain UseCase.
*   **Cách hoạt động**:
    1. Khai báo `I*ActionHandler` tại `packages/core/di/lib/src/actions/`.
    2. Triển khai `*ActionHandlerImpl` trong **feature sở hữu** (hoặc App Shell nếu owner là global app state) và đăng ký `@Injectable(as: I*ActionHandler)` / `@LazySingleton(as: ...)`.
    3. Feature tiêu thụ gọi `getIt<I*ActionHandler>().method(context)` mà không import package sở hữu.
*   **Ví dụ thực tế (`IAuthActionHandler`)**:

    **Bước 1: Interface tại `packages/core/di/lib/src/actions/i_auth_action_handler.dart`**
    ```dart
    import 'package:flutter/widgets.dart';

    abstract class IAuthActionHandler {
      void logout(BuildContext context);
    }
    ```

    **Bước 2: Implementation tại `packages/features/auth/lib/src/handlers/auth_action_handler_impl.dart`**
    ```dart
    @Injectable(as: IAuthActionHandler)
    class AuthActionHandlerImpl implements IAuthActionHandler {
      @override
      void logout(BuildContext context) {
        context.read<AuthProvider>().logout();
      }
    }
    ```

    **Bước 3: Consumer tại `feature_settings`**
    ```dart
    getIt<IAuthActionHandler>().logout(context);
    ```

*   **Đặt tên**:
    - File interface: `i_<feature>_action_handler.dart` / class `I*ActionHandler`
    - File implementation: `<feature>_action_handler_impl.dart` / class `*ActionHandlerImpl`
    - **CẤM TUYỆT ĐỐI** đặt tên class implementation với tiền tố `I` (tiền tố này dành riêng cho interface).

---

### 📊 Bảng Tổng Kết So Sánh Lựa Chọn Giải Pháp

| Bài toán cần giải quyết | Giải pháp phù hợp | Cách thực hiện |
| :--- | :--- | :--- |
| Gọi API, xử lý Database, Logic nghiệp vụ không chứa UI | **Mô Hình 1: Domain UseCase** | Định nghĩa UseCase tại `domain`, inject vào ViewModel thông qua constructor. |
| Lưu cấu hình ứng dụng, kiểm tra kết nối mạng, log analytic | **Mô Hình 2: Core Service** | Import trực tiếp thư viện `core_storage`, `core_network`, `core_notifications`. |
| Theo dõi trạng thái đăng nhập giữa feature mà không gắn SM | **Mô Hình 3: Agnostic Streams** | Interface `Stream` / `ValueListenable` trung lập trên `core_di`; dual-register impl owner. |
| Persist ThemeMode / pure UI prefs (không qua Domain) | **Mô Hình 4: Pure UI State** | `ThemeProvider` → `IThemeStorage` → Storage. |
| Kích hoạt popup, nhúng widget con phức tạp giữa các feature | **Mô Hình 5: Service / Builder Interface** | Khai báo Interface ở `core_di`, implement ở feature gốc, dùng qua GetIt. |
| Kích hoạt hành động UI Feature B (logout, ...) từ Feature A | **Mô Hình 6: Action Handler** | `I*ActionHandler` ở `core_di`, `*ActionHandlerImpl` ở feature sở hữu. |

---

Chi tiết cấu hình định tuyến phân tán tránh xung đột này được trình bày cụ thể tại [08. Định Tuyến & Điều Hướng Phân Rã Toàn Diện](08_routing.md).

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
