# 🤖 Công Cụ Đánh Giá Code AI - Flutter Clean Architecture

Một công cụ đánh giá code thông minh, chính xác được cung cấp bởi Gemini AI, được thiết kế đặc biệt cho các dự án Flutter theo nguyên tắc Clean Architecture.

## ✨ Tính Năng Chính

- **🎯 Chính xác & Thông minh**: Chỉ báo cáo các vấn đề thực sự (lỗi kiến trúc, logic, hiệu năng), không báo cáo các lỗi nhỏ nhặt về style để tránh gây nhiễu.
- **🏗️ Tập trung vào Kiến trúc**: Xác thực sự tuân thủ các lớp của Clean Architecture, các nguyên tắc SOLID, và các pattern của dự án.
- **🚀 Phân tích Hiệu năng & Bảo mật**: Xác định các điểm nghẽn cổ chai, rò rỉ bộ nhớ (memory leak) và các lỗ hổng bảo mật.
- **📊 Báo cáo Toàn diện**: Phân tích chi tiết theo từng file, chấm điểm chất lượng theo 5 hạng mục và đưa ra các hành động cần ưu tiên.
- **🌐 Hỗ trợ Đa ngôn ngữ**: Báo cáo có thể được tạo bằng 8 ngôn ngữ khác nhau (bao gồm tiếng Việt).
- **⚡ Xử lý Hiệu quả**: Chế độ xử lý hàng loạt (batch mode) giúp review nhiều file song song, có cơ chế tự động xử lý khi gặp giới hạn của API.

## 🚀 Hướng Dẫn Nhanh

### 1. Lấy API Key
Lấy Gemini API key miễn phí của bạn tại: https://makersuite.google.com/app/apikey

### 2. Thiết Lập API Key
**Cách 1: Biến môi trường (Khuyến khích)**
```bash
export GEMINI_API_KEY="your_api_key_here"
```

**Cách 2: Lưu vào file cấu hình**
Chạy lệnh sau và làm theo hướng dẫn để lưu key cho các lần sử dụng sau:
```bash
dart tools/code_review/code_review.dart --config
```

### 3. Chạy Review
**Chế độ tương tác (Dễ nhất cho người mới)**
```bash
dart tools/code_review/code_review.dart
```

**Review tất cả các file**
```bash
dart tools/code_review/code_review.dart --all
```

**Review các file đã thay đổi (so với Git)**
```bash
dart tools/code_review/code_review.dart --changed
```

## 📖 Hướng Dẫn Sử Dụng Chi Tiết

### Các Lệnh Phổ Biến

- **Review theo thư mục**:
  ```bash
  # Chỉ review domain layer (quan trọng nhất)
  dart tools/code_review/code_review.dart --folder lib/domain
  ```
- **Review các file đã dàn dựng (staged) cho commit**:
  ```bash
  dart tools/code_review/code_review.dart --staged
  ```
- **Tập trung vào các khía cạnh cụ thể**:
  ```bash
  # Chỉ kiểm tra bảo mật
  dart tools/code_review/code_review.dart --all --focus security

  # Kiểm tra nhiều khía cạnh
  dart tools/code_review/code_review.dart --all --focus security,performance,bugs
  ```
  *Các `focus` hợp lệ: `architecture`, `security`, `performance`, `bugs`, `testing`, `documentation`, `naming`, `solid`.*

- **Loại trừ file**:
  ```bash
  # Loại trừ các file được tạo tự động
  dart tools/code_review/code_review.dart --all --exclude "**/*.g.dart"
  ```

- **Tùy chọn Ngôn ngữ & Định dạng**:
  ```bash
  # Báo cáo bằng tiếng Việt
  dart tools/code_review/code_review.dart --all --language vi

  # Xuất ra định dạng HTML
  dart tools/code_review/code_review.dart --all --format html
  ```

### Quy trình làm việc hiệu quả

1.  **Trước khi Commit**:
    ```bash
    # Review các file đã staged để đảm bảo chất lượng trước khi commit
    dart tools/code_review/code_review.dart --staged
    ```
2.  **Review theo Tầng (hàng tuần)**:
    ```bash
    # Thứ 2: Review domain layer
    dart tools/code_review/code_review.dart --folder lib/domain --focus architecture,solid

    # Thứ 4: Review data layer
    dart tools/code_review/code_review.dart --folder lib/data
    ```
3.  **Trước khi Release**:
    ```bash
    # Kiểm tra bảo mật và hiệu năng toàn bộ dự án
    dart tools/code_review/code_review.dart --all --focus security,performance
    ```

## 🔧 Cấu Hình

- **Xem cấu hình hiện tại**:
  ```bash
  dart tools/code_review/code_review.dart --show-config
  ```
- **Thay đổi cấu hình (tương tác)**:
  ```bash
  dart tools/code_review/code_review.dart --config
  ```
- **Các tùy chọn cấu hình**:
  - `reportLanguage`: Ngôn ngữ báo cáo (`en`, `vi`, `ja`, `ko`, `zh`, `fr`, `de`, `es`).
  - `outputFormat`: Định dạng file báo cáo (`markdown`, `html`, `json`, `txt`).
  - `batchSize`: Số lượng file xử lý song song trong một lô (1-20).
  - `delayBetweenBatches`: Thời gian chờ (ms) giữa các lô để tránh giới hạn API.

## 🔗 Tích Hợp CI/CD

Sử dụng công cụ này trong GitHub Actions để tự động review code trên mỗi Pull Request.

```yaml
# .github/workflows/code_review.yml
name: AI Code Review
on: [pull_request]
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - name: Run Code Review
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
        run: |
          dart tools/code_review/code_review.dart --changed --format json
```

## 🐛 Xử Lý Sự Cố

- **Lỗi "API key not found"**:
  - Chạy `dart tools/code_review/code_review.dart --config` để lưu API key.
  - Hoặc đặt biến môi trường `GEMINI_API_KEY`.

- **Lỗi "Rate limit exceeded"**:
  - Công cụ sẽ tự động chờ và thử lại.
  - Nếu vẫn bị, hãy tăng thời gian chờ: `dart tools/code_review/code_review.dart --config` và đặt `delayBetweenBatches` thành `2000`-`3000` ms.

- **Lỗi "Timeout" hoặc "Failed to parse response"**:
  - Thường do file quá lớn hoặc prompt bị chặn. Công cụ sẽ tự động thử lại.
  - Nếu vẫn thất bại, hãy thử review riêng file đó.

---

## 📚 Phụ Lục A: Checklist Review Nhanh

Sử dụng checklist này để tự review code của bạn.

### 🏛️ Kiến Trúc
- [ ] **Quy Tắc Phụ Thuộc**: Code có vi phạm quy tắc `Presentation → Domain ← Data` không?
- [ ] **Lớp Domain Thuần Túy**: Lớp Domain có import `flutter` hoặc `dart:ui` không? (Cấm).

### 🧬 Theo Từng Lớp
- **Core**: Không sử dụng trực tiếp `SharedPreferences` (phải dùng `StorageValuePresets`).
- **Domain**: `Entity` phải thuần túy (không có `statusCode`, `message`). `Repository` phải trả về `Future<Result<T>>`.
- **Data**: `Repository` phải `implement` interface từ Domain. Mọi lệnh gọi API phải dùng `executeApi`.
- **Presentation**: `Provider` KHÔNG được chứa controller UI. Các lệnh gọi bất đồng bộ phải dùng `executeOperation`.

### 💅 Đặt Tên & Style
- **Hằng Số**: Biến `static const` phải ở dạng `UPPER_SNAKE_CASE`.
- **Thành Viên Private**: Phải bắt đầu bằng `_`.
- **`final`**: Các biến không gán lại phải là `final`.

---

## 🎓 Phụ Lục B: Case Study - Refactor Tính Năng Auth

Đây là một ví dụ thực tế về việc xác định và sửa các lỗi kiến trúc.

### 1. Các Vi Phạm Ban Đầu

- **`BaseEntity` trong Domain**: `lib/domain/entities/base/base_entity.dart` chứa các trường của API như `statusCode`, `message`.
  - **Tác động**: Lớp Domain bị phụ thuộc vào cấu trúc của API.
- **`Repository` trả về `BaseEntity`**: `Future<BaseEntity<UserEntity>> login(...)`.
  - **Tác động**: Gây ra việc phải "mở gói" (unwrap) dữ liệu 2 lần ở UseCase và Provider.
- **Không có Interface cho `DataSource`**: `AuthRemoteDataSource` là một lớp cụ thể, không có interface.
  - **Tác động**: Không thể mock để test, vi phạm Dependency Inversion.

### 2. Kế hoạch Refactor

1.  **Tạo `ApiResponse` DTO**: Tạo một Data Transfer Object trong lớp Data để đại diện cho phản hồi thô từ API.
2.  **Tạo Interface cho `DataSource`**: Tạo `IAuthRemoteDataSource` và `IAuthLocalDataSource` trong lớp Domain.
3.  **Cập nhật `Repository`**: Sửa lại interface và implementation của `AuthRepository` để trả về `Future<Result<UserEntity>>`.
4.  **Cập nhật `UseCase`**: `LoginUseCase` giờ sẽ trả về trực tiếp `Result<UserEntity>` từ repository.
5.  **Cập nhật `Provider`**: Logic trong `AuthProvider` trở nên đơn giản hơn vì chỉ cần xử lý `Result<UserEntity>`.

### 3. Kết Quả

- **Kiến trúc Sạch sẽ**: Lớp Domain trở nên hoàn toàn độc lập.
- **Code Đơn giản**: `UseCase` và `Provider` giảm đáng kể độ phức tạp.
- **Dễ Test**: Có thể dễ dàng mock `DataSource` và `Repository` để viết unit test.