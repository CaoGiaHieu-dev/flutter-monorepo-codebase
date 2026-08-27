# Tài liệu

🌍 *Ngôn ngữ:* [English](../en/README.md) | **Tiếng Việt**

Mọi thứ bạn cần để làm việc trong monorepo Flutter này, sắp xếp theo **việc bạn đang muốn làm** chứ không theo package nào tình cờ chứa chủ đề đó. Mọi code sample trong các trang này đều trích từ source thật kèm đường dẫn file, nên bạn luôn mở được bản gốc.

---

## Bắt đầu từ đâu?

| Nếu bạn… | Vào |
|---|---|
| 🚀 **Vừa clone repo** và muốn chạy được app | [`getting-started/`](getting-started/01_setup.md) |
| 🧭 **Muốn hiểu hệ thống** — các tầng, ranh giới, vì sao | [`architecture/`](architecture/01_overview.md) |
| 🔨 **Muốn làm một thứ gì đó** — màn hình, API, bảng dữ liệu | [`guides/`](guides/01_new_feature.md) |
| 📖 **Cần tra nhanh** — quy ước đặt tên, một luật, một lệnh | [`reference/`](reference/01_rules.md) |
| 🚢 **Cần build, ký và phát hành** | [`operations/`](operations/01_cicd.md) |

Mới vào dự án? Đọc theo thứ tự: **`getting-started/01` → `02` → `architecture/01` → guide của thứ bạn đang làm.**

---

## 🚀 Getting started

Từ số 0 đến app chạy được, và nhịp làm việc hàng ngày sau đó.

| Trang | Trả lời |
|---|---|
| [`01_setup.md`](getting-started/01_setup.md) | Cần cài gì, và chính xác những lệnh nào đưa tôi từ `git clone` đến app chạy được? |
| [`02_project_tour.md`](getting-started/02_project_tour.md) | Mỗi thư mục để làm gì, package nào sở hữu cái gì, muốn sửa X thì vào đâu? |
| [`03_daily_workflow.md`](getting-started/03_daily_workflow.md) | Chạy lệnh nào, khi nào? Bỏ qua thì hỏng gì? |

---

## 🧭 Architecture

Hệ thống được bố trí thế nào và vì sao. Đọc để đặt file mới đúng chỗ, hoặc để phân xử một `import` có hợp lệ hay không.

| Trang | Trả lời |
|---|---|
| [`01_overview.md`](architecture/01_overview.md) | Monorepo này được bố trí ra sao, package nào được phép phụ thuộc package nào? |
| [`02_core.md`](architecture/02_core.md) | Bên trong `packages/core/*` có gì, và tôi nên dùng package nào? |
| [`03_domain.md`](architecture/03_domain.md) | Nghiệp vụ nào nằm ở `packages/domain/*`, vì sao code đó bị cấm chạm vào Flutter, và `Result<T>` cho ta cái gì? |
| [`04_data.md`](architecture/04_data.md) | `packages/data/*` hiện thực hợp đồng repository của Domain thế nào — và không được rò rỉ qua những ranh giới nào? |
| [`05_features.md`](architecture/05_features.md) | Một package sở hữu màn hình được tổ chức ra sao, và các feature giữ độc lập thế nào mà vẫn ghép thành một app? |
| [`06_app_shell.md`](architecture/06_app_shell.md) | Từ lúc chạm icon đến khi thấy màn hình đầu tiên, điều gì xảy ra và ai lắp ráp mọi thứ? |

---

## 🔨 Guides

Thực hành, từng bước, có code chạy được. Đây là phần "how to use".

| Trang | Trả lời |
|---|---|
| [`01_new_feature.md`](guides/01_new_feature.md) | Làm sao thêm một khu vực màn hình mới vào app, từ đầu đến cuối? |
| [`02_new_domain_data.md`](guides/02_new_domain_data.md) | Làm sao thêm một năng lực nghiệp vụ mới — entity, use case, repository, data source? |
| [`03_state_management.md`](guides/03_state_management.md) | Màn hình này nên dùng nhánh state-management nào, và viết controller ra sao? |
| [`04_routing.md`](guides/04_routing.md) | Làm sao thêm một màn hình, và điều hướng sang màn hình thuộc feature khác? |
| [`05_di.md`](guides/05_di.md) | Dùng annotation nào, module đăng ký ở đâu, và vì sao app ném "not registered" lúc khởi động? |
| [`06_storage.md`](guides/06_storage.md) | Làm sao lưu một giá trị sống sót qua khởi động lại — mà không package nào khác đọc/ghi đè được? |
| [`07_database.md`](guides/07_database.md) | Làm sao lưu dữ liệu quan hệ để xoá package của tôi là xoá luôn database của nó? |
| [`08_networking.md`](guides/08_networking.md) | Một request HTTP rời app thế nào, phiên hết hạn được làm mới ra sao, và cái gì đang bảo vệ kết nối? |
| [`09_localization_theming.md`](guides/09_localization_theming.md) | Một feature tự mang bản dịch của nó ra sao, và màu/font/kích thước giữ nhất quán thế nào? |
| [`10_cross_feature.md`](guides/10_cross_feature.md) | Feature A cần thứ gì đó từ feature B — làm sao, mà không import nó? |
| [`11_design_system.md`](guides/11_design_system.md) | Mọi màu, font, bước spacing và bo góc định nghĩa ở đâu — và sửa file nào để đổi nhận diện cho app? |

---

## 📖 Reference

Ngắn, đặc, làm ra để Ctrl+F.

| Trang | Trả lời |
|---|---|
| [`01_rules.md`](reference/01_rules.md) | Cái gì được phép, cái gì cấm, và *vì sao* — cho từng tầng. |
| [`02_naming.md`](reference/02_naming.md) | File này, class này, thư mục này đặt tên là gì? |
| [`03_tooling.md`](reference/03_tooling.md) | Chạy script nào, với tham số gì, khi nào? |
| [`04_review_checklist.md`](reference/04_review_checklist.md) | PR này phải thoả điều gì trước khi merge? |

---

## 🚢 Operations

Build, ký và phát hành.

| Trang | Trả lời |
|---|---|
| [`01_cicd.md`](operations/01_cicd.md) | Có những pipeline nào, cần secret gì, và hiện đang hỏng chỗ nào? |
| [`02_fastlane_release.md`](operations/02_fastlane_release.md) | Có những lane Fastlane nào, app được ký ra sao, và quy trình phát hành đầy đủ là gì? |

---

## Tôi muốn… → đọc cái này

| Việc | Bắt đầu ở | Rồi tới |
|---|---|---|
| Thêm màn hình mới | [`guides/01_new_feature.md`](guides/01_new_feature.md) | [`guides/04_routing.md`](guides/04_routing.md) |
| Gọi một endpoint API mới | [`guides/02_new_domain_data.md`](guides/02_new_domain_data.md) | [`guides/08_networking.md`](guides/08_networking.md) |
| Thêm một bảng database | [`guides/07_database.md`](guides/07_database.md) | [`architecture/04_data.md`](architecture/04_data.md) |
| Lưu một token hoặc một cờ | [`guides/06_storage.md`](guides/06_storage.md) | [`guides/05_di.md`](guides/05_di.md) |
| Thêm một chuỗi dịch | [`guides/09_localization_theming.md`](guides/09_localization_theming.md) | — |
| Đổi theme, màu hoặc spacing | [`guides/11_design_system.md`](guides/11_design_system.md) | [`architecture/02_core.md`](architecture/02_core.md) |
| Chia sẻ state giữa hai feature | [`guides/10_cross_feature.md`](guides/10_cross_feature.md) | [`guides/05_di.md`](guides/05_di.md) |
| Gỡ một feature khỏi app | [`guides/01_new_feature.md`](guides/01_new_feature.md) § gỡ feature | [`reference/01_rules.md`](reference/01_rules.md) |
| Chọn Provider hay BLoC | [`guides/03_state_management.md`](guides/03_state_management.md) | — |
| Sửa lỗi "not registered" lúc khởi động | [`guides/05_di.md`](guides/05_di.md) | [`architecture/06_app_shell.md`](architecture/06_app_shell.md) |
| Sửa CI đang đỏ | [`operations/01_cicd.md`](operations/01_cicd.md) | [`reference/03_tooling.md`](reference/03_tooling.md) |
| Phát hành một bản build | [`operations/02_fastlane_release.md`](operations/02_fastlane_release.md) | [`operations/01_cicd.md`](operations/01_cicd.md) |
| Review PR của người khác | [`reference/04_review_checklist.md`](reference/04_review_checklist.md) | [`reference/01_rules.md`](reference/01_rules.md) |
| Biết một `import` có hợp lệ không | [`reference/01_rules.md`](reference/01_rules.md) | [`architecture/01_overview.md`](architecture/01_overview.md) |

---

## Quy ước trong bộ tài liệu này

- **Mọi link đều là đường dẫn tương đối.** Chúng chạy đúng trên GitHub, trong bản xem trước của IDE, và trên docs server chạy cục bộ.
- **Mọi code block đều ghi tên file nguồn** ở dòng comment đầu — mở ra để xem bản hiện tại.
- Các callout có trọng lượng khác nhau: `> [!NOTE]` là bối cảnh, `> [!WARNING]` là thứ sẽ cắn bạn, `> [!CAUTION]` là thứ có thể làm mất dữ liệu hoặc ship một bản build hỏng.
- Nơi nào một luật có ngoại lệ đã được duyệt, ngoại lệ đó được ghi lại kèm lý do — để lần audit sau không ai "sửa" nhầm.

> [!NOTE]
> Các package feature / domain / data có sẵn ở đây (auth, home, settings, onboarding, splash, dashboard, language) là **mã mẫu tham chiếu**. Chúng minh hoạ cách wiring; đó là pattern để copy hoặc xoá, không phải business logic production. Luật dành cho AI Agent nằm ở [`../../.agents/AGENTS.md`](../../.agents/AGENTS.md).
