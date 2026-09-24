🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# 🤖 Công Cụ Đánh Giá Code AI - Flutter Clean Architecture

Một công cụ đánh giá code dùng Gemini AI (model `gemini-3-flash-preview`, đặt trong `lib/core/constants.dart`), được thiết kế riêng cho các dự án Flutter theo nguyên tắc Clean Architecture. Hướng dẫn cho AI nằm ở `review_prompt.md`.

## ✨ Tính Năng Chính

- **🎯 Tập trung vào vấn đề thật**: Prompt yêu cầu chỉ báo cáo các vấn đề thực sự (lỗi kiến trúc, logic, hiệu năng), không báo cáo các lỗi nhỏ nhặt về style để tránh gây nhiễu.
- **🏗️ Tập trung vào Kiến trúc**: Xác thực sự tuân thủ các lớp của Clean Architecture, các nguyên tắc SOLID, và các pattern của dự án.
- **🚀 Phân tích Hiệu năng & Bảo mật**: Xác định các điểm nghẽn cổ chai, rò rỉ bộ nhớ (memory leak) và các lỗ hổng bảo mật.
- **📊 Báo cáo tổng hợp**: Phân tích theo từng file, kèm bảng chấm điểm (`Project Rules`, `Architecture`, `SOLID/Code` và `Overall`, thang X/10) và các hành động cần ưu tiên.
- **🌐 Hỗ trợ Đa ngôn ngữ**: Báo cáo có thể được tạo bằng 8 ngôn ngữ (`en`, `vi`, `ja`, `ko`, `zh`, `fr`, `de`, `es`).
- **⚡ Batch mode**: Khi có nhiều hơn một file, tool hỏi chọn Batch (mặc định) hay Individual. Batch review các file của một lô song song, nghỉ giữa các lô, và tự thử lại file bị giới hạn API hoặc timeout.

## 🚀 Hướng Dẫn Nhanh

### 1. Lấy API Key
Lấy Gemini API key miễn phí của bạn tại: https://aistudio.google.com/app/apikey

### 2. Thiết Lập API Key
**Cách 1: Biến môi trường (Khuyến khích)**
```bash
export GEMINI_API_KEY="your_api_key_here"
```

**Cách 2: Để tool tự hỏi**
Chạy tool khi chưa có key: nó sẽ hỏi key và đề nghị lưu vào `tools/code_review/.gemini_api_key` — file đã được gitignore, nên key không bao giờ lọt vào commit. (`--api-key "<key>"` cũng dùng được cho một lần chạy.)

Thứ tự tìm key: `--api-key` → `GEMINI_API_KEY` → `tools/code_review/.gemini_api_key` → hỏi trên terminal.

### 3. Chạy Review
**Chế độ tương tác (Dễ nhất cho người mới)** — chạy không kèm lựa chọn file nào (hoặc với `-i`):
```bash
dart tools/code_review/code_review.dart
```

**Review tất cả các file** (mọi `lib/` dưới `apps/`, `modules/`, `platform/`)
```bash
dart tools/code_review/code_review.dart --all
```

**Review các file đã thay đổi so với commit hiện tại** (`git diff HEAD`: staged + unstaged; file untracked không tính)
```bash
dart tools/code_review/code_review.dart --changed
```

## 📖 Hướng Dẫn Sử Dụng Chi Tiết

### Các Lệnh Phổ Biến

- **Review file cụ thể** (lặp lại `--file` cho nhiều file):
  ```bash
  dart tools/code_review/code_review.dart --file apps/mobile/lib/main.dart
  ```
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
  # Loại trừ thêm theo glob
  dart tools/code_review/code_review.dart --all --exclude "**/routing/**"
  ```
  File sinh tự động (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gen.dart`, `*.mocks.dart`, mọi thứ dưới `gen/` / `generated/`, `firebase_options_*.dart`), file test (`/test/`) và mọi file bị git ignore **luôn** bị loại, dù có `--exclude` hay không.

- **Tùy chọn Ngôn ngữ & Định dạng**:
  ```bash
  # Báo cáo bằng tiếng Việt
  dart tools/code_review/code_review.dart --all --language vi
  ```
  `--language` chỉ áp dụng cho lần chạy đó — không ghi vào `code_review_config.json`; đổi mặc định bằng `--config`.
  Báo cáo luôn là Markdown (`code_review_reports/code_review_report_<ngày>_<giờ>.md`; đổi thư mục bằng `--output-dir`, tắt file báo cáo bằng `--no-summary`). `--format` chỉ nhận `markdown` — giữ lại để các script đang truyền `--format markdown` không vỡ. `-v` / `--verbose` in thêm chi tiết.

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
- **Các tùy chọn trong `code_review_config.json`** (giá trị đang commit: `vi`, `3`, `1000`):
  - `reportLanguage`: Ngôn ngữ báo cáo (`en`, `vi`, `ja`, `ko`, `zh`, `fr`, `de`, `es`).
  - `batchSize`: Số lượng file xử lý song song trong một lô (1-20; thiếu thì `5`).
  - `delayBetweenBatches`: Thời gian chờ (ms) giữa các lô để tránh giới hạn API (thiếu thì `2000`).
  - `includeTimestamps`: Ghi thời điểm tạo vào báo cáo.

## 🔗 Tích Hợp CI/CD

Workflow thật là [`.github/workflows/code_review.yml`](../../.github/workflows/code_review.yml): trên mỗi Pull Request (vào `main`, `develop`, `master`) chạm tới file Dart trong `apps/*/lib`, `modules/` hoặc `platform/` (trừ `*.g.dart`, `*.freezed.dart`, `*.module.dart`), nó chạy tool với `--file` cho từng file thay đổi (`--language vi`), tải report lên thành artifact và đăng review kèm gợi ý inline lên PR. Có thể chạy tay (`workflow_dispatch`) với phạm vi `changed` / `all` / `domain` / `data` / `platform` / `presentation`. Secret cần có: `GEMINI_API_KEY`. Workflow này không chặn merge.

## 🐛 Xử Lý Sự Cố

- **Lỗi "Gemini API key not found"**:
  - Đặt biến môi trường `GEMINI_API_KEY`, truyền `--api-key`, hoặc chạy tool và đồng ý lưu key khi được hỏi.

- **Lỗi "Rate limit exceeded"** (HTTP 429 / 503):
  - Ở Batch mode, công cụ tự chờ (theo `Retry-After`, mặc định 60 giây) rồi thử lại, tối đa 3 lần. Individual mode không tự thử lại.
  - Nếu vẫn bị, hãy tăng thời gian chờ: `dart tools/code_review/code_review.dart --config` và đặt `delayBetweenBatches` thành `2000`-`3000` ms, hoặc giảm `batchSize`.

- **Lỗi "Timeout" hoặc "Failed to parse successful API response"**:
  - Timeout (60 giây mỗi request) được Batch mode tự thử lại sau 30 / 60 / 90 giây. Lỗi parse response không được thử lại.
  - Thường do file quá lớn hoặc response bị chặn/cắt. Nếu vẫn thất bại, hãy thử review riêng file đó (`--file`).

---

## 📚 Phụ Lục A: Checklist Review Nhanh

Sử dụng checklist này để tự review code của bạn.

### 🏛️ Kiến Trúc
- [ ] **Quy Tắc Phụ Thuộc**: Code có vi phạm quy tắc `Presentation → Domain ← Data` không?
- [ ] **Lớp Domain Thuần Túy**: Lớp Domain có import `flutter`, `dart:ui`, `dio`, `retrofit` hay bất kỳ package `core_*` nào không? (Cấm).

### 🧬 Theo Từng Lớp
- **Core**: Không sử dụng trực tiếp `SharedPreferences` (phải đi qua `StorageManager` + `StorageValue<T>` của `core_storage`). `platform/*` KHÔNG được phụ thuộc `feature_*`, `data_*` hay `domain_*` — ngoại trừ ba cạnh đã duyệt tới `domain_core` (arch_check R1).
- **Domain**: `Entity` phải thuần túy (không có `statusCode`, `message`). `Repository` phải trả về `Future<Result<T>>`.
- **Data**: `RepositoryImpl` phải `implement` interface từ Domain và bọc mọi lệnh gọi trong `execute()` / `executeSync()` của `IBaseRepository` (`data_core`).
- **Presentation**: `Provider` KHÔNG được chứa controller UI. Các lệnh gọi bất đồng bộ phải dùng `executeOperation`.

### 💅 Đặt Tên & Style
- **Hằng Số**: Biến `static const` phải ở dạng `UPPER_SNAKE_CASE`.
- **Thành Viên Private**: Phải bắt đầu bằng `_`.
- **`final`**: Các biến không gán lại phải là `final`.
