# 09. Sử Dụng Các Component Dùng Chung (Commons & Reusable UI)

Để đảm bảo tính nhất quán cao độ về mặt trải nghiệm thị giác (User Experience) và tuân thủ nguyên lý **DRY (Don't Repeat Yourself)**, codebase phân định rõ ràng các thành phần tái sử dụng thành hai gói mô-đun chuyên biệt: **`core_base_ui`** (Hệ thống thiết kế) và **`feature_shared`** (Các widget dùng chung).

---

## 🏛️ 1. Bản Đồ Phân Định Thành Phần Tái Sử Dụng

Lập trình viên bắt buộc phải nắm rõ ranh giới kiến trúc để đặt tài nguyên và Widget dùng chung vào đúng vị trí:

```text
                        [ TÀI NGUYÊN & WIDGET TÁI SỬ DỤNG ]
                                        │
             ┌──────────────────────────┴──────────────────────────┐
             ▼ (Chỉ chứa Token/Tài nguyên thô - Không có Widget)    ▼ (Chứa toàn bộ các Widget dùng chung)
    [ core_base_ui (Design Tokens) ]                    [ feature_shared (Common Widget Library) ]
    - Phông chữ, Màu sắc (Color Palette, Themes)        - Các Widget thô, nguyên tử (CustomButton, CustomInputField)
    - Tài sản tĩnh (Images, Icons SVG)                 - Các Widget nghiệp vụ chứa logic (JobCardWidget, UserAvatar)
    - Tệp bản dịch ngôn ngữ (L10n ARB)                  - Khung hội thoại dùng chung (AppDialog)
    - Extension giao diện (context.themeExtension)      - Trạng thái phản hồi (LoadingWidget, EmptyWidget)
```

---

## 🎨 2. Hệ Thống Thiết Kế Cốt Lõi: `packages/core/base_ui`

Gói này đóng vai trò là **Design System** vật lý (chỉ chứa các giá trị hằng số, style và asset) của ứng dụng. 

> [!IMPORTANT]
> **Gói `core_base_ui` chứa 0 Flutter Widgets**. Tuyệt đối cấm tự tạo thư mục `widgets/` hoặc đặt các lớp Widget giao diện vào gói này để tránh làm phức tạp hóa vòng đời phụ thuộc.

- **Typography & Extensions (Sức mạnh Dart)**:
  Sử dụng các Extension để viết mã nguồn UI cực ngắn, tự động scale theo kích thước màn hình thiết bị:
  - Lấy màu chủ đạo: `context.themeExtension.primary` thay cho dòng code dài dòng `Theme.of(context).primaryColor`.
  - Spacing nhanh: `16.verticalSpace` hoặc `8.horizontalSpace` (Được hỗ trợ qua ScreenUtil tích hợp).
  - Kiểu chữ nhanh: `context.textTheme.titleMedium`.
  - Dịch ngôn ngữ nhanh: `context.l10n.keyName`.
- **Generated Assets**: Quản lý ảnh/icons thông qua sinh mã tự động `Assets.gen.dart`.

---

## 🧬 3. Thư Viện Widget Dùng Chung: `packages/features/shared`

Gói này được tạo ra để chứa **tất cả các Widget giao diện tái sử dụng** của ứng dụng, được chia làm hai loại chính:

### A. Các Widget giao diện thô (Atomic Widgets)
Các thành phần giao diện không mang logic nghiệp vụ nhưng được tùy biến theo thiết kế của thương hiệu:
- `CustomButton`: Nút bấm chuẩn thương hiệu (chữ nhật, hình tròn, outlined, dropdown), tích hợp sẵn hiệu ứng phản hồi xúc giác (Haptic Feedback) và loading.
- `CustomInputField`: Ô nhập dữ liệu tích hợp sẵn validation, đếm ký tự, trạng thái lỗi.
- `LoadingWidget`, `EmptyWidget`: Các chỉ báo trạng thái hệ thống.

### B. Các Widget nghiệp vụ (Domain-Aware Widgets)
Các widget hiển thị dùng chung ở nhiều màn hình khác nhau nhưng **có tham chiếu trực tiếp đến mô hình thực thể dữ liệu (`Entities`)** hoặc cần gọi các UseCase:
- `JobCardWidget`: Nhận tham số `JobEntity` và hiển thị chi tiết thẻ công việc.
- `UserAvatar`: Nhận tham số `UserEntity` để tải ảnh đại diện và viền theo vai trò người dùng.

### Quy tắc phụ thuộc:
Các Widget trong `feature_shared` có thể phụ thuộc vào các gói `domain_*`, `core_common`, và `core_base_ui`.

---

## 🛠| 4. Quy Trình 3 Bước Trước Khi Viết Component Mới

Để tránh việc tạo ra hàng tá Widget trùng lặp làm phình to dung lượng ứng dụng:

1. **Bước 1: Tìm kiếm widget thô** trong `packages/features/shared/lib/` xem đã có nút bấm hay ô nhập liệu tương tự chưa.
2. **Bước 2: Tìm kiếm widget nghiệp vụ** trong `packages/features/shared/lib/` xem đồng nghiệp đã từng viết thẻ hiển thị đối tượng này chưa.
3. **Bước 3: Tham khảo Extension** xem các tiện ích định dạng ngày tháng, tiền tệ đã được định nghĩa trong `core_common` chưa.

*Nếu chưa có, hãy tiến hành viết mới tại đúng danh mục con trong `feature_shared` và xuất bản (Export) qua tệp barrel chính (`feature_shared.dart`) để chia sẻ tài nguyên cho toàn bộ hệ thống.*

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
