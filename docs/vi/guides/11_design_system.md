# Hướng dẫn: Cấu hình design system

**Trang này trả lời:** mỗi màu, font, bước spacing và bo góc được định nghĩa ở đâu, và phải sửa đúng file nào để template trông giống sản phẩm *của bạn* thay vì bản mẫu.

**Đọc xong bạn có thể:** đổi bảng màu thương hiệu, đổi font chữ, chỉnh lại thang spacing và bo góc, đổi khung thiết kế gốc, và thêm token hoàn toàn mới rồi dùng được qua `context`.

Đây là hướng dẫn **cấu hình**. Còn quy tắc *sử dụng* token trong code widget hằng ngày — cấm hardcode màu, widget dùng lại nhận giá trị raw — xem [`09_localization_theming.md`](09_localization_theming.md).

---

## 1. Bản đồ: token và theme

Có hai thứ khác nhau nằm trong `core_base_ui`, và nhầm lẫn giữa chúng là nguyên nhân rối phổ biến nhất.

| | **Token** | **Theme** |
|---|---|---|
| Là gì | Giá trị thiết kế thô | Phần nối các giá trị đó vào Material |
| Nằm ở | [`lib/src/styles/`](../../../packages/core/base_ui/lib/src/styles/) | [`lib/src/theme/`](../../../packages/core/base_ui/lib/src/theme/) |
| Truy cập qua | `AppSpacing.lg(context)` | `context.colors.surface`, `Theme.of(context)` |
| Sửa khi muốn… | đổi kích thước một khoảng cách, thêm shadow | đổi màu thương hiệu, đổi font |

| Class | File | Sở hữu |
|---|---|---|
| `AppSpacing` | `styles/app_spacing.dart` | thang padding / margin / khoảng cách |
| `AppRadius` | `styles/app_radius.dart` | bo góc, kèm `BorderRadius` dựng sẵn |
| `AppTextStyles` | `styles/app_text_styles.dart` | typography, lấy từ theme đang hoạt động |
| `AppGradients` | `styles/app_gradients.dart` | gradient, lấy từ theme đang hoạt động |
| `AppShadows` | `styles/app_shadows.dart` | shadow đổ bóng (không theo theme — xem §7) |
| `ThemeSystemInterface` | `theme/theme_system_interface.dart` | **hợp đồng**: có những ô màu nào |
| `ThemeSystemExtension` | `theme/theme_system_extensions.dart` | **giá trị**: bảng màu light và dark |
| `ThemeProvider` | `theme/theme_provider.dart` | dựng `ThemeData`, quản lý chuyển light/dark |
| `ContextExtension` | `extensions/context_extension.dart` | các accessor `context.colors` / `context.bodyMediumStyle` |

> [!NOTE]
> **Token là ngoại lệ đã được duyệt của luật "hằng số phải nằm trong `utils/`".** Chúng ở lại `styles/` vì đây là *API công khai* của design system, được mọi feature import trực tiếp, và vì `styles/` mô tả đúng bản chất hơn hẳn cái tên chung chung `utils/`. Đừng "sửa" chỗ này ở lần dọn dẹp sau — xem [`../reference/01_rules.md`](../reference/01_rules.md).

---

## 2. Đổi bảng màu thương hiệu

Màu được cung cấp dưới dạng [`ThemeExtension`](https://api.flutter.dev/flutter/material/ThemeExtension-class.html) của Flutter — đó là lý do chúng tự đổi theo light/dark và chuyển màu mượt giữa hai chế độ.

### Bước 1 — xác định có cần ô màu mới không

Mở [`theme/theme_system_interface.dart`](../../../packages/core/base_ui/lib/src/theme/theme_system_interface.dart). File này khai báo mọi ô màu mà app có thể yêu cầu:

```dart
// packages/core/base_ui/lib/src/theme/theme_system_interface.dart
abstract class ThemeSystemInterface<T extends ThemeExtension<T>>
    extends ThemeExtension<T> {
  // Core colors
  final Color primary;
  final Color primaryContainer;
  final Color secondary;
  final Color secondaryContainer;

  // Backgrounds & Surfaces
  final Color background;
  final Color surface;
  final Color surfaceVariant;

  // Texts
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color textInverse;
  // …
}
```

**Chỉ đổi màu?** Nhảy sang Bước 2 — các ô đã có sẵn.

**Thêm ô mới** (ví dụ `brandAccent`)? Bạn phải sửa ba chỗ, theo đúng thứ tự:

1. `theme_system_interface.dart` — thêm field `final Color brandAccent;` và mục `required this.brandAccent` trong constructor.
2. `theme_system_extensions.dart` — thêm `required super.brandAccent` vào constructor, thêm dòng `brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!` bên trong `lerp`, và thêm giá trị vào **cả** `light` lẫn `dark`.
3. Hết. `context.colors.brandAccent` dùng được ngay, vì `context.colors` trả về chính đối tượng extension.

> [!WARNING]
> Quên dòng trong `lerp` vẫn biên dịch bình thường nhưng làm hỏng *hiệu ứng chuyển* theme — màu mới sẽ nhảy giật thay vì chuyển mượt khi người dùng đổi light/dark.

### Bước 2 — sửa giá trị

Cả hai bảng màu là static field thuần trong [`theme/theme_system_extensions.dart`](../../../packages/core/base_ui/lib/src/theme/theme_system_extensions.dart):

```dart
// packages/core/base_ui/lib/src/theme/theme_system_extensions.dart
/// Light theme extension
static ThemeSystemExtension light = ThemeSystemExtension(
  primary: const Color(0xff0A7E8C),          // Customer teal accent
  primaryContainer: const Color(0xff8B5CF6), // Owner violet accent
  background: const Color(0xffF8FAFC),
  surface: const Color(0xffFFFFFF),
  textPrimary: const Color(0xff0F172A),
  // …
);

/// Dark theme extension
static ThemeSystemExtension dark = ThemeSystemExtension(
  primary: const Color(0xff22D3EE),          // Customer dark cyan accent
  background: const Color(0xff0B0F19),
  surface: const Color(0xff151F32),
  textPrimary: const Color(0xffF8FAFC),
  // …
);
```

Đổi mã hex, lưu, hot-restart. **Luôn sửa cả hai** — chỉ sửa light sẽ để chế độ dark giữ nguyên bảng màu mẫu.

Các tên màu đi kèm template (`chatMe`, `liquidOnboardingColors`, `liquidCustomerColors`, `liquidOwnerColors`, `liquidAuthColors`) sinh ra từ các màn hình mẫu. Nếu sản phẩm của bạn không có chat và không dùng gradient "liquid", hãy xoá hẳn các ô đó khỏi interface và cả hai bảng màu thay vì để lại màu chết.

### Bước 3 — đọc màu trong widget

```dart
// qua extension ở packages/core/base_ui/lib/src/extensions/context_extension.dart
Container(
  color: context.colors.surface,
  child: Text('Hi', style: TextStyle(color: context.colors.textPrimary)),
)
```

> [!NOTE]
> `context.colors` và `context.primary` **không** giống nhau. `context.colors.*` đọc từ `ThemeSystemExtension` của bạn; còn các getter trần (`context.primary`, `context.surface`, …) đọc từ `ColorScheme` của Material. Chỉ hai trong số đó được nối vào bảng màu của bạn — `ThemeProvider` copy `primary` và `surface` sang `ColorScheme`. Với màu thương hiệu, hãy ưu tiên `context.colors.*`.

---

## 3. Đổi font chữ

Typography được dựng một lần cho mỗi theme trong [`theme/theme_provider.dart`](../../../packages/core/base_ui/lib/src/theme/theme_provider.dart), rồi mới được scale.

### Đổi font family

Template đang dùng Google Fonts:

```dart
// packages/core/base_ui/lib/src/theme/theme_provider.dart
final defaultTheme = switch (mode) {
  ThemeMode.dark => GoogleFonts.plusJakartaSansTextTheme(
    ThemeData.dark().textTheme,
  ),
  ThemeMode.light => GoogleFonts.plusJakartaSansTextTheme(
    ThemeData.light().textTheme,
  ),
  // …
};
```

**Dùng font Google khác:** thay `plusJakartaSansTextTheme` bằng `GoogleFonts.<tên>TextTheme` bất kỳ, ở tất cả các nhánh.

**Dùng font đóng gói sẵn:** khai báo trong mục `flutter: fonts:` của [`packages/core/base_ui/pubspec.yaml`](../../../packages/core/base_ui/pubspec.yaml), rồi thay lời gọi bằng `ThemeData.light().textTheme.apply(fontFamily: 'YourFont')`. Nhớ gỡ dependency `google_fonts` khi không còn ai dùng — `dart tools/arch_check/check.dart` sẽ báo nếu bạn khai mà không dùng.

### Cơ chế scale font

Mọi kích thước trong `TextTheme` đều được scale lại qua context-aware extension:

```dart
// packages/core/base_ui/lib/src/theme/theme_provider.dart
double? scaleFont(double? size) => size == null ? null : context.sp(size);
```

Đó chính là lý do `ThemeProvider.currentTheme`, `lightTheme` và `darkTheme` đều nhận `BuildContext` — không có context thì không scale được. Chúng được gọi từ bên trong builder của `Consumer2` ở `app/lib/presentation/app_material_wrapper.dart`, nơi có sẵn context.

`AppTextStyles` sau đó chỉ việc đọc lại theme đã dựng xong:

```dart
// packages/core/base_ui/lib/src/styles/app_text_styles.dart
static TextStyle bodyMediumStyle(BuildContext context) =>
    context.bodyMediumStyle;
```

> [!CAUTION]
> Đừng thêm `.sp` ở nơi gọi. Text style **đã được scale** trước khi `AppTextStyles` trả về. Viết `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: context.sp(14))` là scale hai lần.

---

## 4. Đổi thang spacing và bo góc

Cả hai class theo cùng một khuôn: một **accessor nhận context** để dùng trong widget, và một **hằng số `raw*`** là nguồn duy nhất của con số.

```dart
// packages/core/base_ui/lib/src/styles/app_spacing.dart
static double lg(BuildContext context) => context.w(rawLg);
// …
static const double rawLg = 16;
```

Muốn chỉnh lại thang, hãy sửa hằng số `raw*` — mọi accessor đều dẫn xuất từ nó, nên bạn chỉ đổi một con số chứ không phải hai.

```dart
// packages/core/base_ui/lib/src/styles/app_radius.dart
static double md(BuildContext context) => context.r(rawMd);

static BorderRadius mdRadius(BuildContext context) =>
    BorderRadius.all(Radius.circular(md(context)));

static const double rawMd = 8;
```

**Quy ước đặt tên.** `xxs → xs → sm → md → lg → xl → xxl → xxxl → huge` cho spacing; `xs → … → xxl` cộng `circular` cho bo góc. Riêng `AppSpacing` còn có biến thể `H` cho mỗi bước (`lgH`, `xlH`, …), scale theo trục **chiều cao**.

### Chọn trục nào: `w`, `h` hay `r`?

| Extension | Scale theo | Dùng cho |
|---|---|---|
| `context.w(x)` | **chiều rộng** màn hình | padding, margin, khoảng cách ngang, chiều rộng |
| `context.h(x)` | **chiều cao** màn hình | khoảng cách dọc, chiều cao cố định |
| `context.r(x)` | **min** của hệ số rộng và cao | bo góc, hình tròn, mọi thứ phải giữ được độ tròn |
| `context.sp(x)` | scale font | chỉ dùng cho cỡ chữ |
| `context.spMin(x)` | scale font, chặn trên bằng giá trị gốc | chữ không được phép to ra trên màn hình lớn |

`r` cố ý lấy hệ số nhỏ hơn trong hai hệ số — scale bo góc theo một trục duy nhất sẽ biến hình tròn thành hình elip trên máy quá cao hoặc quá rộng.

Mặc định hãy dùng `w` cho spacing. Chỉ dùng `h` khi giá trị thực sự mang tính dọc *và* nên co lại trên màn hình thấp; lạm dụng `h` sẽ khiến layout bị bí khi xoay ngang.

### Các helper tiện lợi — và một cái bẫy

`core_responsive` cung cấp các dạng viết tắt trên cùng extension của `BuildContext`. Đối chiếu trực tiếp với `packages/core/responsive/lib/src/context_extension.dart`, chúng ánh xạ sang các trục như sau:

```dart
context.edgeInsets(all: X)          // → EdgeInsets.all(w(X))
context.edgeInsets(horizontal: X)   // → left/right = w(X)
context.edgeInsets(vertical: X)     // → top/bottom = h(X)
context.edgeInsets(left: X)         // → w(X)      (right cũng vậy)
context.edgeInsets(top: X)          // → h(X)      (bottom cũng vậy)
context.borderRadius(all: X)        // → BorderRadius.circular(r(X))
context.verticalSpace(X)            // → SizedBox(height: h(X))
context.horizontalSpace(X)          // → SizedBox(width: w(X))
```

> [!NOTE]
> **`context.edgeInsets(all:)` scale bằng `w`**, nên nó là bản thay thế trực tiếp cho `EdgeInsets.all(context.w(16))`. Mỗi trục của `edgeInsets` được scale theo đúng trục nó thuộc về, nhờ vậy padding giữ được tỉ lệ thay vì bám theo một chiều duy nhất.
>
> `borderRadius` dùng `r` — bo góc mà scale theo một trục duy nhất sẽ biến hình tròn thành elip. Khi không chắc, hãy viết dạng tường minh, nó nói rõ trục nào đang được scale.

---

## 5. Đổi khung thiết kế gốc

Mọi thứ ở trên đều scale *tương đối so với một khung tham chiếu*: kích thước màn hình mà designer đã thiết kế trên đó.

```dart
// packages/core/common/lib/src/config/app_config.dart
/// Design size used for responsive UI calculations
/// Based on iPhone X dimensions (375x812)
static Size get design => const Size(375, 812);
```

Giá trị này được truyền cho package đúng một lần, ở gốc cây widget:

```dart
// app/lib/main_scope.dart
return ResponsiveInit(
  designSize: AppConfig.design,
  minTextAdapt: true,
  fontSizeResolver: (fontSize, metrics) {
    final display = View.of(context).display;
    final screenSize = display.size / display.devicePixelRatio;
    final scaleWidth = screenSize.width / AppConfig.design.width;

    return fontSize * scaleWidth;
  },
  splitScreenMode: true,
  child: child,
);
```

| Tham số | Ý nghĩa |
|---|---|
| `designSize` | Khung tham chiếu (`core_responsive` mặc định 360×690; app này truyền `AppConfig.design`). `context.w(16)` nghĩa là "16 logical pixel **trên khung rộng 375**", rồi quy đổi sang thiết bị thật. |
| `minTextAdapt` | Tính `sp` theo hệ số **nhỏ hơn** trong hai hệ số rộng/cao, để chuỗi dài không tràn trên màn hình nhỏ. |
| `fontSizeResolver` | Ghi đè **hoàn toàn** cách tính `sp` — khi nó được đặt thì `minTextAdapt` nằm im. Template này quy đổi font hoàn toàn theo **tỉ lệ chiều rộng**, nên chữ scale cùng hệ số với spacing ngang thay vì lệch đi trên màn hình cao. |
| `splitScreenMode` | Chặn dưới chiều cao dùng để scale ở `ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT` (700), giữ cho việc scale còn hợp lý khi app chạy ở dạng cửa sổ chia đôi thay vì toàn màn hình. |

> [!CAUTION]
> **Đổi `designSize` là scale lại toàn bộ app cùng lúc.** Mọi lời gọi `context.w/h/r/sp` đều quy chiếu về nó, nên giao diện tinh chỉnh ở 375×812 sẽ không đơn giản là "to ra" khi đổi sang 390×844 — tỉ lệ sẽ dịch chuyển. Chỉ đổi khi nguồn thiết kế gốc thực sự thay đổi, rồi rà lại app trên máy nhỏ, máy cao và tablet.

`ResponsiveInit` nằm ở ngoài cùng (`_ResponsiveWrapper` trong `main_scope.dart` bọc mọi thứ, kể cả `AppMaterialWrapper`), nên mọi context widget trong app đều dùng được extension.

> [!NOTE]
> Việc rebuild không cần cấu hình gì. `ResponsiveInit` là `StatelessWidget` và đọc `MediaQuery.sizeOf(context)` — một dependency **chỉ theo size** — rồi phát `ResponsiveMetrics` xuống qua `ResponsiveScope`, một `InheritedWidget`. Mỗi lời gọi `context.w/h/r/sp` đăng ký dependency vào scope đó, nên Flutter rebuild đúng những widget có đọc giá trị đã scale. Đó cũng là lý do không có extension trên `num`: `16.w` chỉ có thể đọc một biến toàn cục, mà biến toàn cục thì không báo được cho ai. Luật R7 của `arch_check` cưỡng chế điều này.

> [!TIP]
> `ResponsiveScope.of(context)` sẽ assert khi phía trên không có `ResponsiveInit`, thay vì lặng lẽ trả về giá trị chưa scale. Widget test nào có scale đều phải bọc widget cần test trong `ResponsiveInit`.

---

## 6. Thêm một class token mới

Giả sử bạn muốn có `AppElevation`. Hãy theo đúng khuôn mà các class hiện có đang dùng — private constructor, hằng số `raw*`, accessor nhận context.

**Bước 1** — tạo `packages/core/base_ui/lib/src/styles/app_elevation.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:core_responsive/core_responsive.dart';

/// Thang elevation, quy đổi qua extension trên BuildContext.
class AppElevation {
  AppElevation._();

  static double flat(BuildContext context) => context.r(rawFlat);
  static double raised(BuildContext context) => context.r(rawRaised);

  /// Giá trị thiết kế, chưa scale. Nguồn duy nhất của các số ở trên.
  static const double rawFlat = 0;
  static const double rawRaised = 4;
}
```

**Bước 2** — sinh lại barrel để nó được export:

```bash
dart tools/barrel_generator/generate.dart packages/core/base_ui/lib
```

`styles/styles.dart` là file tự sinh — tuyệt đối không sửa tay; generator sẽ xoá mọi dòng `export` viết thủ công ở lần chạy sau.

**Bước 3** — dùng thôi. Barrel công khai của `core_base_ui` vốn đã re-export `styles/`, nên mọi feature dùng được ngay:

```dart
Material(elevation: AppElevation.raised(context), child: …)
```

---

## 7. Gradient và shadow

`AppGradients` đọc màu trực tiếp từ theme đang chạy, nên gradient tự đổi màu theo bảng màu:

```dart
// packages/core/base_ui/lib/src/styles/app_gradients.dart
static LinearGradient primaryGradient(BuildContext context) {
  final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors.primaryGradientColors,
  );
}
```

Muốn đổi gradient, hãy sửa **danh sách màu** trong bảng màu (`primaryGradientColors`, `liquidOnboardingColors`, …), không sửa widget.

`AppShadows` là ngoại lệ — nó hardcode màu đen kèm alpha và **không** theo theme:

```dart
// packages/core/base_ui/lib/src/styles/app_shadows.dart
static List<BoxShadow> get sm => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.05),
    blurRadius: 4,
    offset: const Offset(0, 2),
  ),
];
```

> [!NOTE]
> Trên bảng màu tối, shadow đen gần như vô hình. Nếu sản phẩm của bạn dựa nhiều vào đổ bóng ở chế độ dark, hãy đưa màu shadow vào `ThemeSystemInterface` (§2, Bước 1) và cho các getter này nhận `BuildContext` như các class token khác. Template cố ý để đơn giản.

---

## 8. Những quy tắc không đổi

Các quy tắc này được giữ bằng review, và một phần bằng `dart tools/arch_check/check.dart`. Danh sách đầy đủ ở [`../reference/01_rules.md`](../reference/01_rules.md).

- **Tuyệt đối không hardcode** `Color`, `fontSize`, số spacing hay `BorderRadius` trong widget. Thiếu token? Thêm vào `core_base_ui` — đừng nhét thẳng giá trị vào chỗ dùng.
- **Mọi kích thước đều phải scale.** `SizedBox(height: 24)` trần là lỗi; phải viết `SizedBox(height: context.h(24))` hoặc `context.verticalSpace(24)`.
- **Widget dùng lại trong `core_ui_kit` nhận giá trị RAW và không bao giờ tự scale bên trong.** Caller scale trước khi truyền vào. Widget nào tự scale tham số constructor sẽ scale hai lần với caller đã scale sẵn. Xem [`09_localization_theming.md`](09_localization_theming.md).
- **Không scale lại giá trị đã scale.** `AppSpacing.lg(context)` là kết quả cuối; `context.w(AppSpacing.lg(context))` là lỗi scale hai lần.
- **Sửa `raw*`, đừng sửa accessor** khi muốn chỉnh lại thang.

---

## 9. Tra nhanh

| Tôi muốn đổi… | Sửa file |
|---|---|
| Một màu thương hiệu | `theme/theme_system_extensions.dart` → cả `light` **và** `dark` |
| Thêm một ô màu mới | `theme/theme_system_interface.dart`, rồi cả hai bảng màu + `lerp` |
| Font chữ | `theme/theme_provider.dart` → `GoogleFonts.*TextTheme` |
| Một cỡ chữ trong thang | `theme/theme_provider.dart` → khối `copyWith` |
| Một bước spacing | `styles/app_spacing.dart` → hằng số `raw*` |
| Một mức bo góc | `styles/app_radius.dart` → hằng số `raw*` |
| Một gradient | danh sách màu trong `theme/theme_system_extensions.dart` |
| Một shadow | `styles/app_shadows.dart` |
| Khung thiết kế gốc | `packages/core/common/lib/src/config/app_config.dart` → `design` |
| Cách scale (`minTextAdapt`, `fontSizeResolver`) | `app/lib/main_scope.dart` → `ResponsiveInit` |
| Thêm hẳn một class token mới | file mới trong `styles/`, rồi chạy barrel generator |

---

## Xem thêm

- [`09_localization_theming.md`](09_localization_theming.md) — dùng token trong code widget, và bản dịch theo từng feature
- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_base_ui` nằm ở đâu, và vì sao nó không chứa widget nào
- [`../reference/01_rules.md`](../reference/01_rules.md) — các luật được cưỡng chế, kèm lệnh kiểm chứng
