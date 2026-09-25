# Shared UI Kit (`core_ui_kit`)

Các widget hiển thị dùng chung, không phụ thuộc feature, và hệ thống overlay duy nhất của app. Chỉ import barrel của package:

```dart
import 'package:core_ui_kit/core_ui_kit.dart';
```

Nằm dưới `platform/` thay vì `modules/*/feature/` là có chủ đích: đây là thư viện dùng chung mà mọi feature đều có thể phụ thuộc, không phải một feature có thể gỡ bỏ. Nó chỉ phụ thuộc vào các package platform khác và không bao giờ phụ thuộc vào một feature.

> **Không** import widget dùng chung từ package app (`package:mobile_app/...`) — app không chứa widget. Widget chỉ nằm trong package này.

`core_base_ui` chứa design token, asset và l10n toàn cục — **không** chứa widget.

## Cấu trúc thư mục

```
lib/
├── core_ui_kit.dart   # the public API (generated barrel)
├── di/                # Micro-package DI module
└── src/
    ├── buttons/       # CustomButton.rectangle
    ├── dialogs/       # AppOverlay (dialogs, toast, loading), OverlayDialogWidget, RetryDialog
    ├── feedback/      # LoadingWidget, EmptyWidget (LoadMoreListView lives in provider_state_management)
    ├── inputs/        # CustomInputField
    ├── layout/        # TextScaleDown
    ├── media/         # CustomCacheNetworkImage
    ├── navigation/    # BottomTransitionPage
    └── utils/         # SharedUiConstants — the kit's own defaults
```

## Cách dùng

```dart
CustomButton.rectangle(
  onPressed: handleSubmit,
  child: Text(submitLabel),
);

CustomInputField(
  controller: emailController,
  hintText: context.l10nAuth.enterYourEmail,
);

AppOverlay.showToast(content: context.l10n.somethingWentWrong);
```

## Overlay

`AppOverlay` là hệ thống overlay duy nhất. App shell mount `AppOverlayInitializer` trong `MaterialApp.builder`; từ đó bất cứ đâu — một callback mạng, một listener phiên đăng nhập — đều có thể hiện overlay mà không cần `BuildContext`. Thứ tự xếp lớp, từ dưới lên: loading < dialog < toast.

| Lời gọi | Tác dụng |
|:--|:--|
| `AppOverlay.showDialog<T>(builder: …)` | Đưa dialog vào hàng đợi; mỗi lúc chỉ hiện một dialog. Trả về kết quả khi dialog đóng (`null` nếu bị bỏ qua). `identity` dùng để chống trùng. |
| `OverlayDialogState.closeDialog([result])` | Đóng *chính* dialog này — gọi muộn không bao giờ đóng dialog kế tiếp. |
| `AppOverlay.dismissDialog(result: …)` / `clearDialogs()` | Đóng dialog đang hiện / đóng nó cùng mọi dialog trong hàng đợi. |
| `AppOverlay.showToast(content: …)` / `removeToastOverlay()` | Toast tự biến mất sau `SharedUiConstants.TOAST_DURATION`. |
| `AppOverlay.showLoading()` / `removeLoadingOverlay()` | Lớp loading toàn màn hình. |

Nút back hệ thống khi đang có dialog sẽ đóng dialog `barrierDismissible`, còn với dialog khác thì bị nuốt, nên trang phía sau không bao giờ bị pop. Barrier và lớp loading dùng token `scrim` của bảng màu (`colorScheme.scrim`). Mỗi dialog là một lớp con `OverlayDialogWidget` riêng trong file `*_dialog.dart` (RULE-36).

## Quy tắc

- Bên gọi áp dụng `core_responsive` (`context.w` / `context.h` / `context.sp` / `context.r`) **trước** khi truyền kích thước vào widget dùng chung; widget chỉ scale giá trị mặc định của chính nó (RULE-31).
- Kích thước, bo góc và khoảng cách lấy từ `AppSpacing` / `AppRadius`, hoặc từ `SharedUiConstants` cho hình học riêng của widget — không bao giờ để số trần trong widget (RULE-33).
- Lấy màu từ `context.colors.*` (bảng màu `ThemeSystemExtension`) và text style từ `AppTextStyles`, cả hai đều thuộc `core_base_ui`. `context.colorScheme` mang cùng bảng màu đó trong các slot của Material.
- Kit không có ARB (RULE-34): widget cần chữ thì nhận chữ qua tham số hoặc dùng l10n toàn cục của `core_base_ui`.
