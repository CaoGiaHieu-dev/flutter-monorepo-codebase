# 06. Networking Infrastructure & API Connection (Networking Layer)

The data connection network of the **Codebase Provider Monorepo** is fully encapsulated within the specialized Core package **`packages/core/network`**. This infrastructure is built extremely tightly around the **`dio`** library (for HTTP client configuration) and **`retrofit`** (for automating RESTful standard API declarations).

---

## 🏛️ 1. The Heart of Connection: `ApiClient` (Dynamic Factory)

Instead of configuring a single hardcoded Dio instance for the entire app, the `ApiClient` class acts as a **Dynamic Factory**. It is managed via DI and allows child packages to create multiple Dio instances with custom configurations through the `createClient()` method:

### Flexible Configuration Parameters:
- `baseUrl`: Overrides the default base URL.
- `useDefaultInterceptors`: Enables/disables core interceptors (Auth, Retry, Logging). Default is `true`.
- `interceptors`: List of additional custom interceptors.
- `options`: Overrides advanced configurations like Timeout (connection, receive data).

### Example of Setting Up Multiple Different Clients In A Module:
```dart
@module
abstract class RegisterModule {
  // Default Client: Full security interceptors, auto-retry, and logging
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();

  // Public Client (Public API): No automatic Token injection, just logging
  @Named('public_api')
  @lazySingleton
  Dio publicDio(ApiClient apiClient) => apiClient.createClient(
    useDefaultInterceptors: false,
    interceptors: [LoggingInterceptor(tag: 'PublicAPI')],
  );

  // Client for 3rd-party Map services: Distinct Base URL and increased connection Timeout
  @Named('external_api')
  @lazySingleton
  Dio externalDio(ApiClient apiClient) => apiClient.createClient(
    baseUrl: 'https://api.mapservice.com',
    options: BaseOptions(connectTimeout: const Duration(seconds: 30)),
  );
}
```

---

## 🛡️ 2. Security Filter System (Interceptors Grid)

Every HTTP request going through the default Client must pass through an automatic filter chain:

1. **`AuthInterceptor`**:
   - Automatically checks if any JWT Token is stored in `core_storage`.
   - If present, automatically injects the Bearer Token `Authorization: Bearer <token>` into the Header.
2. **`RetryInterceptor`**:
   - Listens for physical connection loss or timeout errors.
   - Automatically triggers the Auto-Retry mechanism using the Exponential Backoff algorithm.
3. **`LoggingInterceptor`**:
   - Outputs detailed log information: URL, Method, Request Body, Response Code, and Response Body.
   - Formatted as an extremely readable indented JSON via `dynamic_logger` and is automatically disabled in the Production environment for security.

---

## 🔌 3. API Declaration Definition: Retrofit Integration

In the Data layer (`packages/data/* (Micro-packages)`), it is absolutely forbidden to manually hardcode HTTP sending commands like `dio.get('/users')`. Every endpoint must be safely type-defined via a Retrofit Interface:

```dart
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:data/models/user_response.dart';

part 'auth_remote_datasource.g.dart';

@RestApi()
abstract class AuthRemoteDataSource {
  // The code generator will automatically write actual API calling logic into the .g.dart file
  factory AuthRemoteDataSource(Dio dio) = _AuthRemoteDataSource;

  @POST('/auth/login')
  Future<UserResponse> login(@Body() Map<String, dynamic> body);
}
```
*Benefits: Avoid URL typos, absolute type-safety for sent/received data, easy to maintain when API changes structure.*

---

## 📊 4. Standardizing Return Data & Pagination

To avoid repeatedly writing wrapper structures for each API, the `core_network` package provides pre-built standardized entities:

- **`BaseEntity<T>`**: The standard data wrapper object from the server (contains status, message, and the actual payload).
- **`PaginatedEntity<T>`**: A class containing standardized pagination info (list of results, total records, current page, page size):
  ```dart
  class PaginatedEntity<T> {
    final List<T> items;
    final int totalCount;
    final int currentPage;
    final int pageSize;
    // ...
  }
  ```
- **`BaseRequest`**: Supports quickly attaching pagination parameters (`page`, `pageSize`, `searchQuery`) into the query URL.

---

## 🔒 5. SSL/TLS Certificate Pinning Security

To protect the application against eavesdropping and fake network Certificates (Man-in-the-Middle - MITM) attacks, the app integrates the **`http_security_pinning`** security package by author **`CaoGiaHieu-dev`**.

This infrastructure performs **SPKI (Subject Public Key Info) SHA-256 Certificate Pinning** directly at the connection core level on mobile platforms (Android & iOS). We support both configuration mechanisms: **Local Pinning (Dio-specific)** and **Global Pinning (App-wide)**.

### 🌐 5.1. Global HttpOverrides Control Mechanism (Recommended)

Instead of just configuring specifically for each `Dio` client, using `HttpOverrides.global` helps apply SSL Pinning to **ALL** network connections initiated by the Dart VM (including `Dio`, `http` package, WebSockets, image loaders like `CachedNetworkImage`, etc.).

This mechanism is intelligently installed and dynamically controlled per environment (Flavor) at [app_initializer.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/common/lib/src/config/app_initializer.dart):

1. **In the Development Environment (`Flavor.dev`)**:
   Activates bypass validation to facilitate local testing with servers using Self-signed certificates:
   ```dart
   class _MyHttpOverrides extends HttpOverrides {
     @override
     HttpClient createHttpClient(SecurityContext? context) {
       return super.createHttpClient(context)
         ..badCertificateCallback = (cert, host, port) => true;
     }
   }
   ```

2. **In Staging & Production Environments (`Flavor.staging` / `Flavor.prod`)**:
   Applies the **`_MyHttpSecurityPinningHttpOverrides`** overlay using `HttpSecurityPinningClient` to automatically validate all HTTPS connections via a list of SPKI hashes retrieved from `NetworkConfig`:
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

### 🛠️ 5.2. Local Pinning Configuration Mechanism:
If you do not want to apply it app-wide but only want to separately protect outgoing API requests from `ApiClient` (Dio):
```dart
if (!kIsWeb && _config.sslPinningHashes.isNotEmpty) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      return HttpSecurityPinningClient(_config.sslPinningHashes);
    },
  );
}
```

### 💡 Guide To Obtaining Server's New SPKI Hash:
If you do not know the server's SPKI SHA-256 hash:
1. Leave the `sslPinningHashes` list empty or fill in an incorrect hash.
2. Make any connection to the server's API.
3. The `http_security_pinning` library will block the connection and **automatically log the server's actual SPKI hash string** out to the Debug Console window:
   `I/HttpSecurityPinningClient(12345): Certificate chain for api.domain.com: [HASH_1], [HASH_2], ...`
4. Copy these valid hashes and paste them back into `sslPinningHashes` in the `network_config_impl.dart` file.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
