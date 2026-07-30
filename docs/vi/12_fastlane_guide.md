# 🚀 Cẩm Nang Kỹ Thuật Hệ# 12. Hướng Dẫn CI/CD Fastlane Cấp Caorkspace Root Execution)

Tài liệu này cung cấp hướng dẫn chi tiết, toàn diện nhất về hệ thống tích hợp liên tục và phân phối tự động (CI/CD) được xây dựng bằng **Fastlane** cho cấu trúc Monorepo. Đặc biệt, hệ thống này đã được nâng cấp lên kiến trúc **CWD-Independent** (Độc lập thư mục làm việc), cho phép thực thi tất cả các tác vụ biên dịch ngay từ thư mục gốc (Root Workspace) của dự án mà không cần di chuyển thư mục (`cd`) thủ công.

---

## 🏛| 1. Kiến Trúc Lắp Ráp Proxy Từ Workspace Root

Hệ thống CI/CD được phân chia làm hai phần: **Cổng ủy thác tại Root** và **Lõi thực thi modular tại App**. Kiến trúc này đảm bảo toàn bộ mã nguồn Fastlane thực tế được đóng gói gọn gàng bên trong thư mục `app/` nhưng vẫn có thể kích hoạt trong suốt tại Root:

```text
/ (Workspace Root)
├── Gemfile                      # [ROOT PROXY] Gọi eval_gemfile "app/Gemfile"
├── fastlane/
│   ├── Pluginfile               # [ROOT PROXY] Gọi eval_gemfile "../app/fastlane/Pluginfile"
│   └── Fastfile                 # [ROOT PROXY] Đổi CWD sang app/fastlane và import lõi modular
└── app/                         # Host Application
    ├── Gemfile                  # Định nghĩa dependencies (fastlane, dotenv, cocoapods)
    └── fastlane/
        ├── Pluginfile           # Nạp plugin (ví dụ: firebase_app_distribution)
        ├── Config.yaml          # Tập hợp toàn bộ thông số cấu hình tĩnh của dự án
        └── modules/             # Lõi modular được chia nhỏ theo chức năng
            ├── helpers.rb       # Hàm run_build trung tâm & Logic xử lý tham số chuyên sâu
            ├── android_lanes.rb # Tuyến đường (Lanes) biên dịch/phân phối Android
            ├── ios_lanes.rb     # Tuyến đường (Lanes) biên dịch/phân phối iOS
            └── flutter_lanes.rb # Tuyến đường (Lanes) kết hợp đa nền tảng
```

### Cơ chế Thay Đổi Ngữ Cảnh Thư Mục (CWD Shifting)
Tệp `fastlane/Fastfile` tại thư mục gốc đóng vai trò là một proxy thông minh:
```ruby
# Đưa thư mục làm việc của Fastlane sang thư mục con app/fastlane một cách an toàn
Dir.chdir("../app/fastlane")

# Import toàn bộ các mô-đun nghiệp vụ thực tế từ thư mục app
import "../app/fastlane/modules/helpers.rb"
import "../app/fastlane/modules/ios_lanes.rb"
import "../app/fastlane/modules/android_lanes.rb"
import "../app/fastlane/modules/flutter_lanes.rb"
```
*Nhờ cơ chế shift CWD này, Fastlane luôn nhìn nhận thư mục `app/` là ngữ cảnh làm việc gốc khi biên dịch mã nguồn Flutter, giải quyết triệt để lỗi thiếu tệp tin hoặc sai đường dẫn tương đối.*

---

## 🧭 2. Giải Quyết Đường Dẫn Tuyệt Đối Cố Định (CWD-Independent Paths)

Bên trong lõi thực thi `app/fastlane/modules/helpers.rb`, thay vì sử dụng các đường dẫn tương đối `../` rất dễ bị lỗi nếu CWD thay đổi, chúng ta định nghĩa một hằng số tuyệt đối cố định dựa trên vị trí của tệp `helpers.rb`:

```ruby
# Định vị tĩnh thư mục APP chính xác 100% không phụ thuộc vào nơi bạn đứng chạy lệnh terminal
APP_DIR = File.expand_path("../..", __dir__)
```

Tất cả các tham chiếu thư mục trong toàn bộ hệ thống Fastlane đều sử dụng hằng số này:
- Đường dẫn đầu ra Android: `#{APP_DIR}/build/app/outputs/flutter-apk`
- Đường dẫn nạp cấu hình: `#{APP_DIR}/fastlane/Config.yaml`
- Đường dẫn tệp Keystore, Firebase credentials, v.v.

---

## 🏎️ 3. Danh Sách Các Lệnh Thực Thi (Lanes Directory)

Bạn có thể kích hoạt các lệnh này trực tiếp tại thư mục gốc của monorepo bằng cú pháp:
`fastlane <nền_tảng> <tên_lệnh> <các_tham_số>`

### A. Tuyến Đường Hỗ Trợ Android (Android Lanes)

| Cú pháp lệnh | Vai trò | Các tham số quan trọng |
| :--- | :--- | :--- |
| `fastlane android build` | Biên dịch APK hoặc AAB tự động | `flavor`, `build_type` (apk/aab), `distribute_store` (true/false) |
| `fastlane android store` | Biên dịch AAB và đẩy trực tiếp lên CH Play | `version`, `build_number`, `track` (internal/closed/production) |

### B. Tuyến Đường Hỗ Trợ iOS (iOS Lanes)

| Cú pháp lệnh | Vai trò | Các tham số quan trọng |
| :--- | :--- | :--- |
| `fastlane ios build` | Biên dịch IPA và phân phối TestFlight/Firebase | `flavor`, `distribute_store`, `distribute_firebase` |
| `fastlane ios store` | Biên dịch IPA bản Prod và đẩy lên App Store | `version`, `build_number` |

### C. Tuyến Đường Hỗ Trợ Đa Nền Tảng (Flutter Lanes)

| Cú pháp lệnh | Vai trò | Các tham số quan trọng |
| :--- | :--- | :--- |
| `fastlane flutter` | Biên dịch & phân phối cả Android + iOS cùng lúc | `flavor`, `version`, `build_number` |
| `fastlane store` | Đẩy bản Production lên cả 2 Store cùng lúc | `version`, `build_number` |

---

## 💎 4. Chi Tiết Các Tham Số Thực Thi (Run Build Arguments Map)

Hàm trung tâm `run_build` được cấu hình cực kỳ linh hoạt để hỗ trợ cả hai chế độ: **Chạy tương tác nhập liệu (Interactive Prompt)** và **Chạy tự động không can thiệp (Non-interactive CLI)**.

| Tham số | Kiểu dữ liệu | Giá trị mặc định | Chi tiết & Tác dụng |
| :--- | :--- | :--- | :--- |
| `flavor` | String | *Hỏi người dùng* | Chọn môi trường: `dev`, `staging`, `prod`. |
| `flutter_version` | String | `stable` | Phiên bản SDK Flutter cần biên dịch . |
| `version` | String | `1.0.0` | Số phiên bản hiển thị (Version Name). |
| `build_number` | String | `auto` | Nếu để `auto`, hệ thống tự kết nối Store/Firebase lấy số lớn nhất cộng 1. |
| `build_type` | String | `apk` | Định dạng xuất cho Android (`apk` hoặc `aab`). |
| `distribute_store` | Boolean | `false` | Có đẩy lên Google Play / App Store TestFlight không. |
| `distribute_firebase`| Boolean | `true` | Có đẩy lên Firebase App Distribution để kiểm thử không. |
| `skip_setup` | Boolean | `false` | Nếu `true`, bỏ qua dọn dẹp, tải thư viện, sinh mã để tăng tốc build. |
| `change_log` | String | *Hỏi người dùng* | Nội dung Release Notes hiển thị cho Tester. |

---

## 📘 5. Hướng Dẫn Sử Dụng Thực Tế Tại Terminal

Đảm bảo bạn đang đứng ở **thư mục gốc của Monorepo** (không cần `cd app/`):

### Ví dụ 1: Biên dịch APK dev và đẩy lên Firebase để Test nhanh
```powershell
fastlane android build flavor:dev build_type:apk distribute_firebase:true change_log:"Fix loi dang nhap"
```

### Ví dụ 2: Chỉ biên dịch cục bộ để kiểm tra lỗi, bỏ qua toàn bộ khâu phân phối và setup (Tốc độ tối đa)
```powershell
fastlane android build flavor:dev build_type:apk distribute_firebase:false distribute_store:false skip_setup:true
```

### Ví dụ 3: Đẩy bản Production AAB lên Google Play Console (Track Internal)
```powershell
fastlane android store version:1.2.0 build_number:45 track:internal
```

---

## ⚠️ 6. Các Cơ Chế Tự Động Hóa Đặc Biệt (Automated Logic Gate)

1. **Auto-Select Flutter Version**:
   Nếu tham số `flutter_version` được truyền một phiên bản cụ thể (ví dụ: `3.22.0`), hệ thống tự động sử dụng công cụ quản lý phiên bản tương ứng. Nếu truyền `stable` hoặc trống, hệ thống sử dụng SDK Flutter cài đặt trực tiếp trên OS.
2. **Xcode Export IPA Auto-Retry**:
   Đối với môi trường macOS khi build iOS, nếu quá trình đóng gói IPA gặp lỗi do xung đột cache Provisioning Profile tạm thời, Fastlane tự động kích hoạt cơ chế thử lại (Auto-Retry) trực tiếp bằng lệnh `xcodebuild` thuần lên đến **3 lần** liên tiếp trước khi báo lỗi.
3. **Dynamic Firebase App IDs Fetching**:
   Tùy thuộc vào tham số `flavor` truyền vào, hệ thống tự động ánh xạ cấu hình trong `Config.yaml` để lấy đúng App ID tương ứng trên Firebase Console, hoàn toàn loại bỏ lỗi đẩy nhầm bản build dev sang môi trường production.
4. **Localization & Code Generation Checklist**:
   Trước khi biên dịch, hệ thống tự động quét toàn bộ thư mục `packages/` trong workspace để tìm các file `l10n.yaml`. Nếu có, nó sẽ tự động chạy `flutter gen-l10n` cho từng package tương ứng. Sau đó, hệ thống sẽ kích hoạt lệnh `dart run build_runner build --workspace` tại thư mục gốc để sinh mã đồng bộ cho toàn bộ các Micro-packages.

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
