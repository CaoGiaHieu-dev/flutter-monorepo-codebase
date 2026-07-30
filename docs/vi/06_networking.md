# 06. Hạ Tầng Mạng & Kết Nối API (Networking Layer)

Mạng lưới kết nối dữ liệu của **Codebase Provider Monorepo** được đóng gói hoàn toàn trong gói Core chuyên biệt **`packages/core/network`**. Hạ tầng này được xây dựng cực kỳ chặt chẽ xoay quanh thư viện **`dio`** (để cấu hình HTTP client) và **`retrofit`** (để tự động hóa khai báo API theo chuẩn RESTful).

---

## 🏛️ 1. Trái Tim Kết Nối: `ApiClient` (Dynamic Factory)

Thay vì cấu hình một instance Dio cứng duy nhất cho toàn app, lớp `ApiClient` hoạt động như một **Dynamic Factory**. Nó được quản lý qua DI và cho phép các gói con tạo ra nhiều instance Dio với các cấu hình riêng biệt thông qua phương thức `createClient()`:

### Các Tham Số Cấu Hình Linh Hoạt:
- `baseUrl`: Ghi đè URL cơ sở mặc định.
- `useDefaultInterceptors`: Bật/tắt các interceptor cốt lõi (Auth, Retry, Logging). Mặc định là `true`.
- `interceptors`: Danh sách các interceptor tùy chỉnh bổ sung.
- `options`: Ghi đè cấu hình nâng cao như Timeout (kết nối, nhận dữ liệu).

### Ví dụ Cài Đặt Nhiều Client Khác Nhau Trong Module:
```dart
@module
abstract class RegisterModule {
  // Client mặc định: Đầy đủ các interceptor bảo mật, tự động thử lại và xuất log
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();

  // Client Công cộng (Public API): Không cần chèn Token tự động, chỉ cần ghi nhận log
  @Named('public_api')
  @lazySingleton
  Dio publicDio(ApiClient apiClient) => apiClient.createClient(
    useDefaultInterceptors: false,
    interceptors: [LoggingInterceptor(tag: 'PublicAPI')],
  );

  // Client dành cho dịch vụ Bản đồ bên thứ 3: Có Base URL riêng biệt và tăng Timeout kết nối
  @Named('external_api')
  @lazySingleton
  Dio externalDio(ApiClient apiClient) => apiClient.createClient(
    baseUrl: 'https://api.mapservice.com',
    options: BaseOptions(connectTimeout: const Duration(seconds: 30)),
  );
}
```

---

## 🛡️ 2. Hệ Thống Bộ Lọc Bảo Mật (Interceptors Grid)

Mọi HTTP request khi đi qua Client mặc định đều phải duyệt qua chuỗi lọc tự động:

1. **`AuthInterceptor`**:
   - Tự động kiểm tra xem có JWT Token nào được lưu trữ trong `core_storage` hay không.
   - Nếu có, tự động tiêm Bearer Token `Authorization: Bearer <token>` vào Header.
2. **`RetryInterceptor`**:
   - Lắng nghe các lỗi mất kết nối vật lý hoặc timeout.
   - Tự động kích hoạt cơ chế thử lại (Auto-Retry) sử dụng thuật toán giãn cách lũy thừa (Exponential Backoff).
3. **`LoggingInterceptor`**:
   - Xuất log chi tiết các thông tin: URL, Method, Request Body, Response Code và Response Body.
   - Được định dạng dạng JSON thụt lề cực kỳ dễ đọc qua `dynamic_logger` và tự động tắt trên môi trường Production để bảo mật.

---

## 🔌 3. Định Nghĩa Tuyên Bố API: Retrofit Integration

Trong tầng Data (`packages/data/* (Micro-packages)`), chúng ta nghiêm cấm tuyệt đối việc code chay các dòng lệnh gửi HTTP thủ công như `dio.get('/users')`. Mọi endpoint phải được định nghĩa an toàn kiểu qua Retrofit Interface:

```dart
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:data/models/user_response.dart';

part 'auth_remote_datasource.g.dart';

@RestApi()
abstract class AuthRemoteDataSource {
  // Trình sinh mã sẽ tự động viết logic gọi API thực tế vào tệp .g.dart
  factory AuthRemoteDataSource(Dio dio) = _AuthRemoteDataSource;

  @POST('/auth/login')
  Future<UserResponse> login(@Body() Map<String, dynamic> body);
}
```
*Lợi ích: Tránh lỗi chính tả URL, type-safety tuyệt đối cho dữ liệu gửi đi/nhận về, dễ dàng bảo trì khi API thay đổi cấu trúc.*

---

## 📊 4. Chuẩn Hóa Dữ Liệu Trả Về & Phân Trang (Pagination)

Để tránh việc viết lặp lại cấu trúc bao bọc cho từng API, gói `core_network` cung cấp sẵn các thực thể chuẩn hóa:

- **`BaseEntity<T>`**: Đối tượng bọc dữ liệu chuẩn từ server (chứa status, message, và payload thực tế).
- **`PaginatedEntity<T>`**: Lớp chứa thông tin phân trang chuẩn hóa (danh sách kết quả, tổng số bản ghi, trang hiện tại, kích thước trang):
  ```dart
  class PaginatedEntity<T> {
    final List<T> items;
    final int totalCount;
    final int currentPage;
    final int pageSize;
    // ...
  }
  ```
- **`BaseRequest`**: Hỗ trợ đính kèm nhanh chóng các tham số phân trang (`page`, `pageSize`, `searchQuery`) vào query URL.

---

## 🔒 5. Bảo Mật SSL/TLS Certificate Pinning

Để bảo vệ ứng dụng khỏi các cuộc tấn công nghe lén, giả mạo Certificate mạng (Man-in-the-Middle - MITM), ứng dụng tích hợp gói bảo mật **`http_security_pinning`** của tác giả **`CaoGiaHieu-dev`**.

Hạ tầng này thực hiện **SPKI (Subject Public Key Info) SHA-256 Certificate Pinning** trực tiếp ở mức lõi kết nối trên các nền tảng di động (Android & iOS). Chúng ta hỗ trợ cả 2 cơ chế cấu hình: **Local Pinning (Dio-specific)** và **Global Pinning (Toàn bộ ứng dụng)**.

### 🌐 5.1. Cơ Chế Khống Chế Global HttpOverrides (Khuyên Dùng)

Thay vì chỉ cấu hình riêng cho từng client `Dio`, việc sử dụng `HttpOverrides.global` giúp áp dụng SSL Pinning cho **TẤT CẢ** các kết nối mạng khởi tạo bởi Dart VM (bao gồm `Dio`, gói `http`, WebSockets, các bộ tải ảnh như `CachedNetworkImage`, v.v.).

Cơ chế này được cài đặt thông minh và khống chế động theo từng môi trường (Flavor) tại [app_initializer.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/common/lib/src/config/app_initializer.dart):

1. **Ở môi trường Phát triển (`Flavor.dev`)**:
   Kích hoạt bypass validation để thuận tiện cho việc test cục bộ với các máy chủ sử dụng chứng chỉ tự ký (Self-signed certificates):
   ```dart
   class _MyHttpOverrides extends HttpOverrides {
     @override
     HttpClient createHttpClient(SecurityContext? context) {
       return super.createHttpClient(context)
         ..badCertificateCallback = (cert, host, port) => true;
     }
   }
   ```

2. **Ở môi trường Staging & Production (`Flavor.staging` / `Flavor.prod`)**:
   Áp dụng lớp phủ **`_MyHttpSecurityPinningHttpOverrides`** sử dụng `HttpSecurityPinningClient` để tự động xác thực tất cả các kết nối HTTPS thông qua danh sách SPKI hashes lấy từ `NetworkConfig`:
   ```dart
   class _MyHttpSecurityPinningHttpOverrides extends HttpOverrides {
     final List<String> pins;
     _MyHttpSecurityPinningHttpOverrides(this.pins);

     @override
     HttpClient createHttpClient(SecurityContext? context) {
       return HttpSecurityPinningClient(pins);
     }
   }
   ```

### 🛠️ 5.2. Cơ Chế Cấu Hình Cục Bộ (Local Pinning):
Nếu không muốn áp dụng cho toàn bộ ứng dụng mà chỉ muốn bảo vệ riêng các yêu cầu API gửi đi từ `ApiClient` (Dio):
```dart
if (!kIsWeb && _config.sslPinningHashes.isNotEmpty) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      return HttpSecurityPinningClient(_config.sslPinningHashes);
    },
  );
}
```

### 💡 Hướng Dẫn Lấy Mã Băm SPKI Mới Của Server:
Nếu bạn chưa biết mã băm SPKI SHA-256 của máy chủ:
1. Hãy để danh sách `sslPinningHashes` trống hoặc điền một mã băm không chính xác.
2. Thực hiện một kết nối bất kỳ đến API của server.
3. Thư viện `http_security_pinning` sẽ chặn kết nối và **tự động ghi nhận chuỗi mã băm SPKI thực tế** của server ra cửa sổ Debug Console:
   `I/HttpSecurityPinningClient(12345): Certificate chain for api.domain.com: [HASH_1], [HASH_2], ...`
4. Sao chép các mã băm hợp lệ này và điền ngược lại vào `sslPinningHashes` trong tệp tin `network_config_impl.dart`.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
