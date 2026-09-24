<!-- translated-from: docs/en/guides/09_localization_theming.md@b65f8b3 -->
# Hướng dẫn: Đa ngôn ngữ, Theme & Responsive UI

## Mục tiêu

Bạn phát hành bản dịch riêng của một feature mà không đụng tới app shell, thêm một ngôn ngữ, tạo kiểu cho widget bằng design token, và định kích thước để nó scale và thích ứng. Bạn cũng giữ cho widget dùng lại "trung thực": chúng nhận giá trị đã scale và không bao giờ scale lại.

## Điều kiện cần

- Một feature package — [`01_new_feature.md`](01_new_feature.md).
- **Bản dịch của feature tới `MaterialApp` thế nào** mà shell không cần gọi tên chúng — [`../architecture/06_app_shell.md` § 7](../architecture/06_app_shell.md#bản-dịch-của-feature-tới-materialapp-thế-nào).
- Mỗi token được định nghĩa ở đâu, và cách đổi bảng màu, font hay các thang đo: [`11_design_system.md`](11_design_system.md). Hướng dẫn này nói về việc *dùng* chúng.

---

## 1. Thêm một chuỗi dịch

Chuỗi nằm ở đâu (RULE-34, RULE-37):

- Mọi chuỗi hiển thị cho người dùng đều đi qua delegate — kể cả toast, dialog, thông báo lỗi và nhãn nút. Không bao giờ hard-code.
- Chuỗi của một feature nằm trong các file `.arb` của feature đó.
- Chuỗi thật sự dùng chung nằm ở `core_base_ui`.
- `core_ui_kit` **không** định nghĩa `.arb` riêng: nó là thư viện widget mà mọi feature dùng, và chuỗi của nó lấy từ `core_base_ui`.

### Sửa các file `.arb`

Trong `modules/home/feature/assets/language/en.arb` — ARB là JSON thuần, nên dán kèm một comment `//` sẽ làm `gen-l10n` lỗi:

```json
{
  "@@locale": "en",
  "home": "Home",
  "tabLabel": "Home",
  "userLoggedIn": "User is Logged In",
  "userLoggedOut": "User is Logged Out",
  "refreshProfile": "Refresh profile"
}
```

Phải thêm cùng một key vào **mọi** file ngôn ngữ (`vi.arb`, …). File template là file mà `l10n.yaml` chỉ định.

### Kiểm tra `l10n.yaml` của feature

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

### Sinh code Dart

```bash
cd modules/home/feature && flutter gen-l10n && cd -
```

`build_runner` không đụng tới file ARB; `gen-l10n` đọc `l10n.yaml` của package.
`dart tools/workspace_setup/configure.dart` chạy lệnh này cho mọi package có file đó.

Chuỗi còn thiếu bản dịch sẽ được liệt kê trong `untranslated-messages.txt`.

### Đăng ký delegate (một lần cho mỗi feature)

```dart
// modules/home/feature/lib/di/localization.dart
@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
```

### Phơi ra một extension có kiểu

```dart
// modules/home/feature/lib/src/extensions/l10n_home_extension.dart
extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

### Dùng chuỗi

```dart
Text(context.l10nHome.userLoggedIn)
```

## 2. Thêm một ngôn ngữ

Thêm một ngôn ngữ đụng tới `core_base_ui` **và mọi feature có chuỗi dịch** — không chỉ feature bạn đang làm. Lấy tiếng Nhật (`ja`) làm ví dụ.

### Thêm ARB và tên ngôn ngữ vào `core_base_ui`

Tạo `ja.arb` trong `platform/ui/design_system/assets/language/` với `"@@locale": "ja"` và mọi key của file template `en.arb`. Rồi thêm tên hiển thị của ngôn ngữ vào **mọi** ARB của `core_base_ui` — `en.arb`, `vi.arb` lẫn `ja.arb` — cạnh `languageEn` / `languageVi`:

```json
{
  "@@locale": "en",
  "languageEn": "English",
  "languageVi": "Tiếng Việt",
  "languageJa": "Japanese"
}
```

`AppLocalizations.supportedLocales` của `core_base_ui` chính là những gì app cung cấp: `MaterialApp.supportedLocales` (`platform/shell/app_shell/lib/presentation/app_material_wrapper.dart`), phần kiểm tra locale đã lưu của `LanguageProvider` và bộ chọn ngôn ngữ ở Settings (`modules/settings/feature/lib/src/pages/settings_page.dart`) đều đọc nó. `gen-l10n` dựng nó từ các file ARB đang có, nên chính file mới là thứ thêm locale vào.

### Đặt tên ngôn ngữ trong bộ chọn

`platform/ui/design_system/lib/src/extensions/locale_extension.dart` ánh xạ mã ngôn ngữ sang tên đó; thiếu một nhánh thì bộ chọn chỉ hiện tag trần `ja`:

```dart
return switch (languageCode) {
  'vi' => context.l10n.languageVi,
  'en' => context.l10n.languageEn,
  'ja' => context.l10n.languageJa,
  _ => toLanguageTag(),
};
```

### Thêm ARB cho mọi feature

Thêm `assets/language/ja.arb`, dịch đủ mọi key, vào **từng** feature có `l10n.yaml` — hiện là `modules/{auth,home,onboarding,settings,splash}/feature`. Bước này không tuỳ chọn: extension của mỗi feature ép non-null delegate của nó —

```dart
FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
```

— và một feature không có `ja.arb` thì delegate không hỗ trợ `ja`, nên `of(this)` trả `null` và lần `context.l10nHome` đầu tiên sau khi người dùng chọn tiếng Nhật sẽ ném lỗi. `find modules -name l10n.yaml` liệt kê chúng. Feature được scaffold sau này chỉ nhận `en.arb` / `vi.arb` từ `tools/module_generator/templates/feature/localization/` — hãy thêm locale vào đó, hoặc thêm tay cho từng feature mới.

### Sắp thứ tự ngôn ngữ trong `preferred-supported-locales`

`platform/ui/design_system/l10n.yaml` và `l10n.yaml` của từng feature ghi `preferred-supported-locales: [en, vi]`, `l10n.yaml.mustache` của generator cũng vậy. `gen-l10n` vẫn nhận `ja.arb` mà không cần sửa — danh sách này chỉ **sắp thứ tự** các locale, locale nào không có trong đó thì xếp sau theo bảng chữ cái — nhưng locale được hỗ trợ đầu tiên là locale dự phòng (`localeResolutionCallback` và `LanguageProvider` đều lùi về `supportedLocales.first`). Hãy thêm locale mới vào cuối để thứ tự rõ ràng: `[en, vi, ja]`.

### Sinh lại

```bash
dart tools/workspace_setup/configure.dart   # gen-l10n cho mọi package có l10n.yaml, rồi codegen + barrel
```

Hoặc `flutter gen-l10n` trong `platform/ui/design_system` và trong từng feature. Kiểm tra `untranslated-messages.txt` của mọi package đều trống.

## 3. Tạo kiểu cho widget bằng design token

Token nằm trong `platform/ui/design_system/lib/src/styles/`; màu đến từ một
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

## 4. Scale mọi kích thước qua context

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
padding: EdgeInsets.all(context.w(16))
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
>
> Với cạnh mang nghĩa đầu hoặc cuối dòng, dùng
> `context.edgeInsetsDirectional(start:, end:)` — `left:`/`right:` là cạnh
> vật lý và không đảo chiều ở locale viết từ phải sang trái.

Những giá trị **không phải** kích thước vật lý thì được miễn: `TextStyle.height` là hệ số giãn dòng, `flex` là tỉ lệ.

Mặc định không gì được scale vượt cỡ thiết kế: cửa sổ tablet hay desktop vẽ thiết kế 1:1, và chỗ dư được dùng cho layout, chọn theo lớp kích thước cửa sổ. Chính sách scale và các widget thích ứng nằm ở [`11_design_system.md`](11_design_system.md) §6–§7.

## 5. Scale hằng số của chính widget dùng lại, không scale tham số

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
// platform/ui/ui_kit/lib/navigation/app_bar_custom.dart
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

## 6. Giữ giá trị mặc định của widget dùng chung trong `utils/`

Các giá trị mặc định không phải kích thước nằm trong `utils/` của chính package:

```dart
// platform/ui/ui_kit/lib/utils/shared_ui_constants.dart
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

## 7. Tách dialog và bottom sheet thành class

> [!CAUTION]
> Không bao giờ dựng dialog inline bên trong `showDialog()` / `showModalBottomSheet()`. Phải tách ra file và class riêng.

| Loại | Hậu tố file | Hậu tố class |
|---|---|---|
| Dialog | `_dialog.dart` | `Dialog` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` |

Ví dụ có sẵn trong `platform/ui/ui_kit/lib/dialogs/`: `error_dialog.dart`, `warning_dialog.dart`, `retry_dialog.dart`, `bottom_wrapper_dialog.dart`.

Builder inline không thể tái sử dụng, không preview được, không test riêng được — và hầu như luôn kết thúc bằng chuỗi cứng và kích thước cứng.

---

## Kiểm tra

```bash
cd modules/<name>/feature && flutter gen-l10n && cd -   # rồi kiểm tra untranslated-messages.txt trống
dart tools/unused_checker/check_unused_translate.dart   # không còn key nào bị bỏ không dùng
dart tools/arch_check/check.dart                        # R7: không có extension kích thước trần (24.h)
flutter analyze                                         # No issues found!
cd modules/<name>/feature && flutter test               # test page chạy dưới ResponsiveInit (RULE-62)
```

Trên thiết bị, hãy đổi ngôn ngữ trong Settings và bật/tắt chế độ tối: mọi chuỗi và màu trên màn hình của bạn phải đổi theo. Chạy một lần trên điện thoại và một lần trên cửa sổ rộng hoặc chia đôi màn hình.

Checklist review:

- [ ] Không còn chuỗi hiển thị nào bị hard-code
- [ ] Key mới đã thêm vào **tất cả** file `.arb`, đã chạy `flutter gen-l10n`
- [ ] Ngôn ngữ mới: có ARB trong `core_base_ui` **và mọi feature**, có tên trong `locale_extension.dart` (bước 2)
- [ ] Feature đăng ký `IFeatureLocalization`; `root_app.dart` không bị đụng tới
- [ ] `core_ui_kit` dùng chuỗi của `core_base_ui`, không định nghĩa `.arb`
- [ ] Màu qua `context.colors.*`, typography qua `AppTextStyles.*(context)`
- [ ] Mọi kích thước đều scale qua context (`context.w/h/sp/r`) hoặc lấy từ token
- [ ] Token không bị scale hai lần (`AppSpacing.lg(context)`, không phải `context.w(AppSpacing.lg(context))`)
- [ ] Widget dùng lại dùng tham số đúng như nhận được (bên gọi đã scale); chỉ scale hằng số của chính nó
- [ ] Dialog/bottom sheet đã tách ra file riêng đúng hậu tố

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `context.l10nX.newKey` không tồn tại | Chưa chạy `gen-l10n` sau khi sửa ARB | `cd modules/<name>/feature && flutter gen-l10n` (bước 1) |
| `gen-l10n` lỗi ở một file ARB | Có comment `//` hoặc dấu phẩy thừa — ARB là JSON chặt | Bỏ nó đi (bước 1) |
| App ném lỗi ở lần `context.l10nX` đầu tiên sau khi chọn ngôn ngữ mới | Feature đó không có ARB cho ngôn ngữ ấy, nên delegate trả `null` | Thêm ARB cho **mọi** feature (bước 2) |
| Bộ chọn hiện một mã trần như `ja` | `locale_extension.dart` chưa có nhánh cho mã đó | Thêm nhánh (bước 2) |
| Widget không đổi kích thước khi xoay máy hay chia đôi màn hình | Một số double thô, hoặc giá trị được tính ngoài `build` | Scale qua `context` bên trong `build` (bước 4) |
| `ResponsiveScope.of` báo assert trong widget test | Widget được test không được bọc trong `ResponsiveInit` | Bọc nó (RULE-62) |
| Một kích thước to gấp đôi thiết kế | Giá trị bị scale hai lần (`context.w(AppSpacing.lg(context))`) | Dùng token nguyên trạng (bước 3 và 5) |
| Một màu sai ở chế độ tối | `Color` bị hard-code | Dùng `context.colors.*` (bước 3) |

## Liên quan

- Luật: RULE-30 (scale qua context), RULE-31 (widget dùng lại dùng tham số như nhận được), RULE-33 (chỉ dùng token), RULE-34 (dịch mọi thứ), RULE-35 (key `lowerCamelCase`), RULE-36 (dialog là class), RULE-37 (asset của feature nằm trong feature), RULE-62 (`ResponsiveInit` trong test) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`11_design_system.md`](11_design_system.md) — cấu hình token, chính sách scale và layout thích ứng
- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_base_ui` không chứa widget nào
- [`../architecture/05_features.md`](../architecture/05_features.md) — bố cục feature package
- [`06_storage.md`](06_storage.md) — theme và locale được lưu thế nào
