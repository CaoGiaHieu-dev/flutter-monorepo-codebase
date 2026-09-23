# Hướng dẫn: Đa ngôn ngữ, Theme & Responsive UI

**File này trả lời:** làm sao một feature mang theo bản dịch của riêng nó mà không đụng vào app shell, và làm sao mọi màu sắc, font chữ, kích thước giữ được sự nhất quán giữa sáng/tối và giữa các cỡ màn hình.

**Đọc xong bạn làm được:** thêm một chuỗi dịch, thêm một ngôn ngữ, style widget bằng design token, và canh kích thước responsive mà không phá vỡ hợp đồng của widget dùng lại.

---

# Phần A — Đa ngôn ngữ

## 1. Phi tập trung theo thiết kế

Mỗi feature tự sở hữu bản dịch của mình. App shell không hề biết tên chúng.

| Ở đâu | Chứa gì |
|---|---|
| `modules/<f>/feature/assets/language/*.arb` | File dịch của feature |
| `modules/<f>/feature/l10n.yaml` | Cấu hình codegen cho feature đó |
| `modules/<f>/feature/lib/src/gen/language/` | Delegate + class được sinh ra |
| `modules/<f>/feature/lib/di/localization.dart` | Phần implement `IFeatureLocalization` |
| `core_base_ui` | Chuỗi global / fallback dùng chung |

> [!CAUTION]
> Một feature **tuyệt đối không** được sửa `platform/app_shell/lib/presentation/root_app.dart` hay `app_material_wrapper.dart` để đăng ký delegate của nó. Việc đăng ký đi qua DI — xem §3.

## 2. Hợp đồng

```dart
// platform/di/lib/src/feature_localization.dart
/// Interface for feature localization delegates.
/// Enables safe registration and retrieval via getAllOrEmpty<IFeatureLocalization>() in the app shell.
abstract class IFeatureLocalization {
  LocalizationsDelegate get delegate;
}
```

## 3. App shell gom delegate như thế nào

```dart
// platform/app_shell/lib/presentation/app_material_wrapper.dart
// `getAllOrEmpty`, not `getIt.getAll`: the latter throws when no feature
// registers `IFeatureLocalization`. Every feature package is removable, so
// an app built without any of them must still resolve its delegates —
// falling back to the global `core_base_ui` ones.
final delegates = [
  ...getAllOrEmpty<IFeatureLocalization>().map((e) => e.delegate),
  ...AppLocalizations.localizationsDelegates,
];
```

Chính `getAllOrEmpty` là thứ khiến feature có thể gỡ bỏ được: xoá package đi thì danh sách chỉ đơn giản là ngắn lại.

## 4. Thêm một chuỗi dịch — từng bước

### Bước 1 — sửa các file `.arb`

```json
// modules/home/feature/assets/language/en.arb
{
  "@@locale": "en",
  "home": "Home",
  "tabLabel": "Home",
  "user_logged_in": "User is Logged In",
  "user_logged_out": "User is Logged Out",
  "refresh_profile": "Refresh profile"
}
```

Phải thêm cùng một key vào **mọi** file ngôn ngữ (`vi.arb`, …). File template là file mà `l10n.yaml` chỉ định.

### Bước 2 — kiểm tra `l10n.yaml` của feature

```yaml
# modules/home/feature/l10n.yaml
arb-dir: assets/language
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: FeatureHomeLocalizations
preferred-supported-locales: [en, vi]
untranslated-messages-file: untranslated-messages.txt
output-dir: lib/src/gen/language
```

Mỗi feature có `output-class` **riêng** (`FeatureHomeLocalizations`, `FeatureAuthLocalizations`, …) nên các delegate không bao giờ đụng nhau.

### Bước 3 — sinh code

```bash
cd modules/home/feature && flutter gen-l10n && cd -
```

`build_runner` không đụng tới file ARB; `gen-l10n` đọc `l10n.yaml` của package.
`dart tools/workspace_setup/configure.dart` chạy lệnh này cho mọi package có file đó.

Chuỗi còn thiếu bản dịch sẽ được liệt kê trong `untranslated-messages.txt`.

### Bước 4 — đăng ký delegate (một lần cho mỗi feature)

```dart
// modules/home/feature/lib/di/localization.dart
@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
```

### Bước 5 — phơi ra một extension có kiểu

```dart
// modules/home/feature/lib/src/extensions/l10n_home_extension.dart
extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

### Bước 6 — dùng

```dart
Text(context.l10nHome.userLoggedIn)
```

## 5. Quy tắc

- **Không hard-code chuỗi hiển thị cho người dùng.** Không ngoại lệ. Toast, dialog, thông báo lỗi, nhãn nút — tất cả đều đi qua delegate.
- Chuỗi riêng của feature → `.arb` của feature đó.
- Chuỗi thật sự dùng chung → `core_base_ui`.
- `core_ui_kit` **không** định nghĩa `.arb` riêng. Nó là thư viện widget mà mọi feature dùng; chuỗi của nó lấy từ `core_base_ui`.

---

# Phần B — Theme

## 6. Design token và màu sắc

Token nằm trong `platform/base_ui/lib/src/styles/`; màu đến từ một
`ThemeExtension` nên tự đổi theo light/dark.

| Class token | File | Nhiệm vụ |
|---|---|---|
| `AppSpacing` | `app_spacing.dart` | Padding, margin, khoảng cách |
| `AppRadius` | `app_radius.dart` | Bo góc, đối tượng `BorderRadius` |
| `AppTextStyles` | `app_text_styles.dart` | Typography, lấy từ theme |
| `AppGradients` | `app_gradients.dart` | Gradient, lấy từ theme |
| `AppShadows` | `app_shadows.dart` | Shadow đổ bóng |

Mọi accessor đều nhận `BuildContext`, vì việc scale được quy đổi qua
extension trên `BuildContext` của `core_responsive`:

```dart
Container(
  color: context.colors.surface,
  padding: EdgeInsets.all(AppSpacing.lg(context)),
  child: Text(
    context.l10nHome.home,
    style: AppTextStyles.bodyMediumStyle(context),
  ),
)
```

> [!CAUTION]
> Tuyệt đối không hardcode `Color`, `fontSize`, số spacing hay `BorderRadius`
> trong widget. Thiếu token thì thêm vào `core_base_ui` — đừng nhét thẳng giá
> trị vào chỗ dùng. Và đừng scale lại token đã scale:
> `context.w(AppSpacing.lg(context))` là scale hai lần.

> [!NOTE]
> **Việc cấu hình design system — đổi bảng màu, đổi font, chỉnh lại thang,
> đổi khung thiết kế, thêm token — có trang riêng:
> [`11_design_system.md`](11_design_system.md).** Tách ra để chỉ có đúng một nơi
> mô tả cách định nghĩa những giá trị này.

## 8. `ThemeMode.system` bám theo OS ngay lúc chạy

`ThemeMode.system` phân giải theo độ sáng của OS, mà giá trị này có thể đổi khi app đang chạy. `ThemeProvider` lắng nghe điều đó:

```dart
// platform/base_ui/lib/src/theme/theme_provider.dart
/// Called by the framework when the OS switches between Light and Dark.
///
/// Only [ThemeMode.system] derives its appearance from the platform, so an
/// explicit light/dark choice is left untouched — no wasted rebuild.
@override
void didChangePlatformBrightness() {
  super.didChangePlatformBrightness();
  if (_themeMode != ThemeMode.system) return;

  // Refresh the status/navigation bar styling for the new brightness…
  setSystemTheme();
  // …and rebuild consumers, because `currentTheme` now resolves differently.
  notifyListeners();
}
```

Nó dùng `WidgetsBindingObserver` (một **danh sách**) thay vì gán `platformDispatcher.onPlatformBrightnessChanged` (một **slot đơn** mà thư viện khác có thể ghi đè). Việc dọn dẹp được nối vào DI:

```dart
@disposeMethod
@override
void dispose() {
  if (_isObservingPlatform) {
    WidgetsBinding.instance.removeObserver(this);
```

Giá trị đã lưu được đọc qua `IThemeStorage` — xem [`06_storage.md`](06_storage.md#8-vượt-ranh-giới-package).

---

# Phần C — Responsive UI

## 9. `core_responsive` là bắt buộc

Mọi kích thước đều phải scale, và **luôn qua `BuildContext`**:

| Lời gọi | Dùng cho |
|---|---|
| `context.w(x)` | Chiều rộng, padding/margin ngang |
| `context.h(x)` | Chiều cao, khoảng cách dọc |
| `context.sp(x)` | Cỡ chữ |
| `context.r(x)` | Bo góc, kích thước vuông/tròn |

**Không có extension trên `num`:** `24.h` không biên dịch được. Một con số
không mang theo context, nên extension kiểu đó chỉ có thể đọc một biến toàn
cục — và widget đọc biến toàn cục thì không bao giờ biết metrics màn hình đã
đổi. Dù sao thì luật R7 của `arch_check` cũng chặn dạng viết trần này.

```dart
// ❌ Sai
SizedBox(height: 24)
padding: EdgeInsets.all(16)
fontSize: 16

// ✅ Đúng — extension trên BuildContext
SizedBox(height: context.h(24))
padding: EdgeInsets.all(context.r(16))
fontSize: context.sp(16)

// ✅ Tốt hơn — dùng token
SizedBox(height: AppSpacing.lgH(context))
padding: EdgeInsets.all(AppSpacing.lg(context))
```

> [!NOTE]
> `context.edgeInsets(all: 16)` scale bằng `w`, nên nó **thay thế trực tiếp
> được** cho `EdgeInsets.all(context.w(16))`. `horizontal:` scale bằng `w`,
> `vertical:` bằng `h`. Xem bảng trục đầy đủ ở
> [`11_design_system.md`](11_design_system.md).

Những giá trị **không phải** kích thước vật lý thì được miễn: `TextStyle.height` là hệ số giãn dòng, `flex` là tỉ lệ.

## 10. Widget scale hằng số của chính nó, không scale tham số

> [!CAUTION]
> Widget dùng lại trong `core_ui_kit` **không được scale tham số nó nhận vào**. Bên gọi scale trước khi truyền, nên giá trị đến nơi đã ở đơn vị pixel thiết bị và phải được dùng nguyên vẹn; scale thêm lần nữa là scale hai lần, và người truyền token thì **không thể** ghi đè được nữa. Hằng số **của chính** widget thì ngược lại: nó phải scale, nếu không widget không responsive.

Luật này cấm điều gì — một `AppBar` trong `core_ui_kit` kết thúc bằng:

```dart
// ❌ Cấm: override cứng bên trong một widget dùng lại
@override
double? get leadingWidth => context.w(64);
```

Đoạn override đó vừa scale bên trong, **vừa âm thầm vứt bỏ** giá trị `leadingWidth` mà người gọi truyền qua `super.leadingWidth` — tham số trở thành vô dụng. `AppBarCustom` thay vào đó chuyển tiếp mọi thứ cho `AppBar`:

```dart
// platform/ui_kit/lib/navigation/app_bar_custom.dart
class AppBarCustom extends AppBar {
  AppBarCustom({
    super.key,
    super.leading,
    super.automaticallyImplyLeading = true,
    // ... mọi field đều chuyển tiếp, không override cái nào ...
  }) : assert(elevation == null || elevation >= 0.0);
}
```

Nơi gọi mới scale:

```dart
AppBarCustom(leadingWidth: context.w(64), title: Text(context.l10nHome.home))
```

## 11. Hằng số của `core_ui_kit`

Các giá trị mặc định không phải kích thước nằm trong `utils/` của chính package:

```dart
// platform/ui_kit/lib/utils/shared_ui_constants.dart
/// Timing and overlay constants owned by `core_ui_kit`.
///
/// Package-internal by convention: these are defaults for the reusable
/// widgets in this package. Features that need a different value pass it
/// explicitly through the widget's constructor instead of reading these.
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(milliseconds: 200);
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
```

## 12. Dialog và bottom sheet là class, không phải closure

> [!CAUTION]
> Không bao giờ dựng dialog inline bên trong `showDialog()` / `showModalBottomSheet()`. Phải tách ra file và class riêng.

| Loại | Hậu tố file | Hậu tố class |
|---|---|---|
| Dialog | `_dialog.dart` | `Dialog` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` |

Ví dụ có sẵn trong `platform/ui_kit/lib/dialogs/`: `error_dialog.dart`, `warning_dialog.dart`, `retry_dialog.dart`, `bottom_wrapper_dialog.dart`.

Builder inline không thể tái sử dụng, không preview được, không test riêng được — và hầu như luôn kết thúc bằng chuỗi cứng và kích thước cứng.

---

## 13. Checklist

- [ ] Không còn chuỗi hiển thị nào bị hard-code
- [ ] Key mới đã thêm vào **tất cả** file `.arb`, đã chạy `flutter gen-l10n`
- [ ] Feature đăng ký `IFeatureLocalization`; `root_app.dart` không bị đụng tới
- [ ] `core_ui_kit` dùng chuỗi của `core_base_ui`, không định nghĩa `.arb`
- [ ] Màu qua `context.colors.*`, typography qua `AppTextStyles.*(context)`
- [ ] Mọi kích thước đều scale qua context (`context.w/h/sp/r`) hoặc lấy từ token
- [ ] Token không bị scale hai lần (`AppSpacing.lg(context)`, không phải `context.w(AppSpacing.lg(context))`)
- [ ] Widget dùng lại nhận giá trị thô, không scale gì bên trong
- [ ] Dialog/bottom sheet đã tách ra file riêng đúng hậu tố

## Xem thêm

- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_base_ui` chứa zero widget
- [`../architecture/05_features.md`](../architecture/05_features.md) — bố cục package feature
- [`06_storage.md`](06_storage.md) — theme và ngôn ngữ được lưu như thế nào
- [`../reference/01_rules.md`](../reference/01_rules.md) — danh sách luật đầy đủ
