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

**Cách 2: Để tool tự hỏi**
Chạy tool khi chưa có key: nó sẽ hỏi key và đề nghị lưu vào `tools/code_review/.gemini_api_key` — file đã được gitignore, nên key không bao giờ lọt vào commit. (`--api-key "<key>"` cũng dùng được cho một lần chạy.)

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
  dart tools/code_review/code_review.dart --folder modules/auth/domain
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
  *Các `focus` hợp lệ: `architecture`, `security`, `performance`, `bugs`, `style`, `testing`. Giá trị khác bị từ chối.*

- **Loại trừ file**:
  ```bash
  # Loại trừ các file được tạo tự động
  dart tools/code_review/code_review.dart --all --exclude "**/*.g.dart"
  ```

- **Tùy chọn Ngôn ngữ & Định dạng**:
  ```bash
  # Báo cáo bằng tiếng Việt
  dart tools/code_review/code_review.dart --all --language vi
  ```
  Báo cáo luôn được ghi ra Markdown (`code_review_reports/code_review_report_<ngày>_<giờ>.md`); `--format` chỉ lưu lựa chọn vào cấu hình.

### Quy trình làm việc hiệu quả

1.  **Trước khi Commit**:
    ```bash
    # Review các file đã staged để đảm bảo chất lượng trước khi commit
    dart tools/code_review/code_review.dart --staged
    ```
2.  **Review theo Tầng (hàng tuần)**:
    ```bash
    # Thứ 2: Review domain layer
    dart tools/code_review/code_review.dart --folder modules/auth/domain --focus architecture

    # Thứ 4: Review data layer
    dart tools/code_review/code_review.dart --folder modules/auth/data
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
  - `outputFormat`: được lưu nhưng hiện chưa dùng — báo cáo luôn là Markdown.
  - `batchSize`: Số lượng file xử lý song song trong một lô (1-20).
  - `delayBetweenBatches`: Thời gian chờ (ms) giữa các lô để tránh giới hạn API.

## 🔗 Tích Hợp CI/CD

Workflow thật là [`.github/workflows/code_review.yml`](../../.github/workflows/code_review.yml): trên mỗi Pull Request chạm tới file Dart trong `apps/*/lib`, `modules/` hoặc `platform/`, nó chạy tool với `--file` cho từng file thay đổi, tải report lên thành artifact và đăng gợi ý inline lên PR. Secret cần có: `GEMINI_API_KEY`. Workflow này không chặn merge.

## 🐛 Xử Lý Sự Cố

- **Lỗi "API key not found"**:
  - Đặt biến môi trường `GEMINI_API_KEY`, truyền `--api-key`, hoặc chạy tool và đồng ý lưu key khi được hỏi.

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
- **Core**: Không sử dụng trực tiếp `SharedPreferences` (phải đi qua `StorageManager` + `StorageValue<T>` của `core_storage`). `platform/*` KHÔNG được phụ thuộc `feature_*` hay `data_*`.
- **Domain**: `Entity` phải thuần túy (không có `statusCode`, `message`). `Repository` phải trả về `Future<Result<T>>`.
- **Data**: `RepositoryImpl` phải `implement` interface từ Domain và bọc mọi lệnh gọi trong `execute()` / `executeSync()` của `IBaseRepository` (`data_core`).
- **Presentation**: `Provider` KHÔNG được chứa controller UI. Các lệnh gọi bất đồng bộ phải dùng `executeOperation`.

### 💅 Đặt Tên & Style
- **Hằng Số**: Biến `static const` phải ở dạng `UPPER_SNAKE_CASE`.
- **Thành Viên Private**: Phải bắt đầu bằng `_`.
- **`final`**: Các biến không gán lại phải là `final`.
