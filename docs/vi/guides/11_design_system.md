# Hướng dẫn: Cấu hình design system

**Trang này trả lời:** mỗi màu, font, bước spacing và bo góc được định nghĩa ở đâu, phải sửa đúng file nào để template trông giống sản phẩm *của bạn* thay vì bản mẫu, và giao diện scale cũng như thích ứng ra sao từ điện thoại sang tablet, máy gập hay cửa sổ desktop.

**Đọc xong bạn có thể:** đổi bảng màu thương hiệu, đổi font chữ, chỉnh lại thang spacing và bo góc, đổi khung thiết kế gốc, quyết định mỗi lớp cửa sổ được scale tới đâu, dàn layout cho tablet, máy gập và chia đôi màn hình, và thêm token hoàn toàn mới rồi dùng được qua `context`.

Đây là hướng dẫn **cấu hình**. Còn quy tắc *sử dụng* token trong code widget hằng ngày — cấm hardcode màu, widget dùng lại nhận giá trị raw — xem [`09_localization_theming.md`](09_localization_theming.md).

---

## 1. Bản đồ: token và theme

Có hai thứ khác nhau nằm trong `core_base_ui`, và nhầm lẫn giữa chúng là nguyên nhân rối phổ biến nhất.

| | **Token** | **Theme** |
|---|---|---|
| Là gì | Giá trị thiết kế thô | Phần nối các giá trị đó vào Material |
| Nằm ở | [`lib/src/styles/`](../../../platform/base_ui/lib/src/styles/) | [`lib/src/theme/`](../../../platform/base_ui/lib/src/theme/) |
| Truy cập qua | `AppSpacing.lg(context)` | `context.colors.surface`, `Theme.of(context)` |
| Sửa khi muốn… | đổi kích thước một khoảng cách, thêm shadow | đổi màu thương hiệu, đổi font |

| Class | File | Sở hữu |
|---|---|---|
| `AppSpacing` | `styles/app_spacing.dart` | thang padding / margin / khoảng cách |
| `AppRadius` | `styles/app_radius.dart` | bo góc, kèm `BorderRadius` dựng sẵn |
| `AppTextStyles` | `styles/app_text_styles.dart` | typography, lấy từ theme đang hoạt động |
| `AppGradients` | `styles/app_gradients.dart` | gradient, lấy từ theme đang hoạt động |
| `AppShadows` | `styles/app_shadows.dart` | shadow đổ bóng (không theo theme — xem §9) |
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

Mở [`theme/theme_system_interface.dart`](../../../platform/base_ui/lib/src/theme/theme_system_interface.dart). File này khai báo mọi ô màu mà app có thể yêu cầu:

```dart
// platform/base_ui/lib/src/theme/theme_system_interface.dart
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

Cả hai bảng màu là static field thuần trong [`theme/theme_system_extensions.dart`](../../../platform/base_ui/lib/src/theme/theme_system_extensions.dart):

```dart
// platform/base_ui/lib/src/theme/theme_system_extensions.dart
/// Light theme extension
static ThemeSystemExtension light = ThemeSystemExtension(
  primary: const Color(0xff0A7E8C),
  primaryContainer: const Color(0xff8B5CF6),
  background: const Color(0xffF8FAFC),
  surface: const Color(0xffFFFFFF),
  textPrimary: const Color(0xff0F172A),
  // …
);

/// Dark theme extension
static ThemeSystemExtension dark = ThemeSystemExtension(
  primary: const Color(0xff22D3EE),
  background: const Color(0xff0B0F19),
  surface: const Color(0xff151F32),
  textPrimary: const Color(0xffF8FAFC),
  // …
);
```

Đổi mã hex, lưu, hot-restart. **Luôn sửa cả hai** — chỉ sửa light sẽ để chế độ dark giữ nguyên bảng màu mẫu.

Chỉ có một ô màu tồn tại vì màn hình mẫu: `liquidOnboardingColors`, gradient của splash (`AppGradients.liquidOnboarding`). Khi xoá sample splash, hãy xoá luôn ô đó khỏi interface, cả hai bảng màu và `AppGradients` thay vì để lại màu chết.

### Bước 3 — đọc màu trong widget

```dart
// qua extension ở platform/base_ui/lib/src/extensions/context_extension.dart
Container(
  color: context.colors.surface,
  child: Text('Hi', style: TextStyle(color: context.colors.textPrimary)),
)
```

> [!NOTE]
> `context.colors` và `context.primary` **không** giống nhau. `context.colors.*` đọc từ `ThemeSystemExtension` của bạn; còn các getter trần (`context.primary`, `context.surface`, …) đọc từ `ColorScheme` của Material. Chỉ hai trong số đó được nối vào bảng màu của bạn — `ThemeProvider` copy `primary` và `surface` sang `ColorScheme`. Với màu thương hiệu, hãy ưu tiên `context.colors.*`.

---

## 3. Đổi font chữ

Typography được dựng một lần cho mỗi theme trong [`theme/theme_provider.dart`](../../../platform/base_ui/lib/src/theme/theme_provider.dart), rồi mới được scale.

### Đổi font family

Font chữ — Plus Jakarta Sans — được **đóng gói sẵn** trong `core_base_ui`, mỗi độ đậm một file dưới cùng một family:

```yaml
# platform/base_ui/pubspec.yaml
  fonts:
    - family: PlusJakartaSans
      fonts:
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-Regular.ttf
          weight: 400
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-Medium.ttf
          weight: 500
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-Bold.ttf
          weight: 700
```

Theme áp family đó cho toàn bộ thang chữ. `FontFamily.plusJakartaSans` do `flutter_gen` sinh ra (`lib/src/gen/fonts.gen.dart`) với giá trị `packages/core_base_ui/PlusJakartaSans` — font khai báo trong một package chỉ phân giải được dưới tên đó:

```dart
// platform/base_ui/lib/src/theme/theme_provider.dart
// The type scale's sizes. A Material 3 `ThemeData().textTheme` carries
// colours only — its sizes are merged in later, when MaterialApp
// …
final geometry = Typography.material2021().englishLike;

// …
TextTheme applyFont(TextTheme colors) =>
    geometry.merge(colors).apply(fontFamily: FontFamily.plusJakartaSans);

final defaultTheme = switch (mode) {
  ThemeMode.dark => applyFont(ThemeData.dark().textTheme),
  ThemeMode.light => applyFont(ThemeData.light().textTheme),
  ThemeMode.system => applyFont(
    ThemeData.from(colorScheme: colorScheme).textTheme,
  ),
};
```

**Vì sao đóng gói, không dùng `google_fonts`.** `google_fonts` đăng ký mỗi *độ đậm* thành một family riêng, nên một style đổi độ đậm về sau — `copyWith(fontWeight: FontWeight.bold)`, như tiêu đề app bar và các sample đang làm — vẫn giữ file nét thường và engine tự giả lập nét đậm. Một family với mỗi độ đậm một file cho phép Flutter chọn đúng mặt chữ cho bất kỳ `fontWeight` nào. Cách này cũng chạy offline và không tải gì lúc runtime. Giấy phép đi kèm file font: `assets/fonts/plus_jakarta_sans/OFL.txt`, được `registerBaseUiLicenses()` (gọi trong `runShellApp`) đăng ký với `LicenseRegistry`, nên hiện trên `showLicensePage`.

**Dùng font khác:** đặt các file vào `platform/base_ui/assets/fonts/<tên>/` kèm giấy phép, khai từng độ đậm trong `flutter: fonts:` (độ đậm nào thiết kế dùng mà không có file sẽ được tổng hợp từ file gần nhất), chạy `dart run build_runner build --workspace` để `FontFamily` có hằng số mới, rồi trỏ `applyFont` vào nó — giữ nguyên `geometry.merge`, cỡ chữ lấy từ đó. Đổi luôn phần đăng ký giấy phép sang file giấy phép mới.

### Cơ chế scale font

Cỡ chữ lấy từ `Typography.material2021().englishLike` — thang chữ Material 3 — vì `ThemeData().textTheme` chỉ mang màu (Material thêm cỡ chữ về sau, khi `MaterialApp` localize theme; scale một theme chỉ có màu là không scale gì cả). Sau đó mọi cỡ chữ được scale lại qua context-aware extension, tiêu đề app bar cũng vậy (`BaseUiConstants.APP_BAR_TITLE_FONT_SIZE`):

```dart
// platform/base_ui/lib/src/theme/theme_provider.dart
double? scaleFont(double? size) => size == null ? null : context.sp(size);
```

Dùng `sp`, nên chữ đi theo `textScaleBounds` của app (§6). Với mặc định `ScaleBounds.downOnly()`, chữ thu nhỏ trên cửa sổ hẹp hơn thiết kế rộng 375 và không bao giờ lớn hơn cỡ thiết kế; lớp cửa sổ nào có `ResponsiveProfile` cho phép phóng to thì chữ cũng to theo. Với cấu hình của app này, chữ đúng bằng cỡ thiết kế trên mọi cửa sổ rộng từ 375 trở lên — điện thoại, tablet hay desktop.

Đó chính là lý do `ThemeProvider.currentTheme`, `lightTheme` và `darkTheme` đều nhận `BuildContext` — không có context thì không scale được. Chúng được gọi từ bên trong builder của `Consumer2` ở `platform/app_shell/lib/presentation/app_material_wrapper.dart`, nơi có sẵn context.

`AppTextStyles` sau đó chỉ việc đọc lại theme đã dựng xong:

```dart
// platform/base_ui/lib/src/styles/app_text_styles.dart
static TextStyle bodyMediumStyle(BuildContext context) =>
    context.bodyMediumStyle;
```

> [!CAUTION]
> Đừng thêm `.sp` ở nơi gọi. Text style **đã được scale** trước khi `AppTextStyles` trả về. Viết `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: context.sp(14))` là scale hai lần.

---

## 4. Đổi thang spacing và bo góc

Cả hai class theo cùng một khuôn: một **accessor nhận context** để dùng trong widget, và một **hằng số `raw*`** là nguồn duy nhất của con số.

```dart
// platform/base_ui/lib/src/styles/app_spacing.dart
static double lg(BuildContext context) => context.w(rawLg);
// …
static const double rawLg = 16;
```

Muốn chỉnh lại thang, hãy sửa hằng số `raw*` — mọi accessor đều dẫn xuất từ nó, nên bạn chỉ đổi một con số chứ không phải hai.

```dart
// platform/base_ui/lib/src/styles/app_radius.dart
static double md(BuildContext context) => context.r(rawMd);

static BorderRadius mdRadius(BuildContext context) =>
    BorderRadius.all(Radius.circular(md(context)));

static const double rawMd = 8;
```

**Quy ước đặt tên.** `xxs → xs → sm → md → lg → xl → xxl → xxxl → huge` cho spacing; `xs → … → xxl` cộng `circular` cho bo góc. Riêng `AppSpacing` còn có biến thể `H` cho mỗi bước (`lgH`, `xlH`, …), scale theo trục **chiều cao**.

### Chọn trục nào: `w`, `h` hay `r`?

| Extension | Scale theo | Dùng cho |
|---|---|---|
| `context.w(x)` | tỉ lệ **chiều rộng** cửa sổ, kẹp bởi `scaleBounds` | padding, margin, khoảng cách ngang, chiều rộng |
| `context.h(x)` | tỉ lệ **chiều cao** cửa sổ, kẹp bởi `scaleBounds` | khoảng cách dọc, chiều cao cố định |
| `context.r(x)` | **min** của hệ số rộng và cao | bo góc, hình tròn, mọi thứ phải giữ được độ tròn |
| `context.sp(x)` | tỉ lệ chữ, kẹp bởi `textScaleBounds` | chỉ dùng cho cỡ chữ |
| `context.spMin(x)` | `sp`, chặn trên bằng giá trị thiết kế | chữ phải giữ đúng cỡ thiết kế kể cả ở nơi một profile (hay `fontSizeResolver`) cho chữ to ra — với bound mặc định thì nó bằng `sp` |

`r` cố ý lấy hệ số nhỏ hơn trong hai hệ số — scale bo góc theo một trục duy nhất sẽ biến hình tròn thành hình elip trên máy quá cao hoặc quá rộng.

Mặc định hãy dùng `w` cho spacing. Chỉ dùng `h` khi giá trị thực sự mang tính dọc *và* nên co lại trên màn hình thấp; lạm dụng `h` sẽ khiến layout bị bí khi xoay ngang.

### Các helper tiện lợi — và một cái bẫy

`core_responsive` cung cấp các dạng viết tắt trên cùng extension của `BuildContext`. Đối chiếu trực tiếp với `platform/responsive/lib/src/context_extension.dart`, chúng ánh xạ sang các trục như sau:

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
// platform/common/lib/src/config/app_config.dart
/// Design size used for responsive UI calculations
/// Based on iPhone X dimensions (375x812)
static Size get design => const Size(375, 812);
```

Giá trị này được truyền cho `ResponsiveInit` đúng một lần, ở ngoài cùng cây widget — `_ResponsiveWrapper` trong `platform/app_shell/lib/main_scope.dart` bọc mọi thứ, kể cả `AppMaterialWrapper`; lời gọi đầy đủ nằm ở §6. Đây là khung mà **mọi lớp cửa sổ** quy chiếu về, trừ khi một profile chỉ định khung riêng: `context.w(16)` nghĩa là "16 logical pixel trên khung rộng 375".

> [!CAUTION]
> **Đổi `designSize` là scale lại toàn bộ app cùng lúc.** Mọi lời gọi `context.w/h/r/sp` đều quy chiếu về nó, và cửa sổ nào hẹp hơn hoặc thấp hơn khung sẽ thu nhỏ thiết kế theo đúng tỉ lệ đó — đổi từ 375×812 sang 390×844 là mọi thứ trên điện thoại rộng 375 đều nhỏ đi. Chỉ đổi khi nguồn thiết kế gốc thực sự thay đổi, rồi rà lại app trên máy nhỏ, máy cao và tablet.

---

## 6. Chính sách scale: mặc định thu nhỏ, phóng to khi opt-in, theo từng lớp cửa sổ

Hệ số scale là tỉ lệ giữa cửa sổ và khung thiết kế trên một trục. Để mặc kệ thì nó tăng không giới hạn: cửa sổ desktop rộng 1280 so với khung rộng 375 là 3,4×, nên chữ 20 px thành 68 px và tiêu đề bị cắt. Vì vậy `core_responsive` kẹp mọi hệ số bằng một `ScaleBounds`:

| Bound | Khoảng | Dùng khi |
|---|---|---|
| `ScaleBounds.downOnly()` — **mặc định** | 0 – 1 | Thu nhỏ trên cửa sổ nhỏ hơn khung, vẽ 1:1 trên cửa sổ lớn hơn. Chỗ dư dành cho layout (§7), không phải cho pixel to hơn |
| `ScaleBounds(max: 1.2)` | 0 – 1,2 | Phóng to có chặn, phải opt-in. Thêm `min:` để ngừng thu nhỏ ở mức chữ không còn đọc được hay nút không còn bấm được |
| `ScaleBounds.fixed()` | 1 – 1 | Luôn đúng cỡ thiết kế — cho lớp cửa sổ được dàn bằng logical pixel thật |
| `ScaleBounds.unbounded()` | 0 – ∞ | Tỉ lệ thô, hành vi trước khi có bound. Hiếm khi đúng cho app chạy trên nhiều dạng thiết bị |

Layout và chữ được kẹp **riêng rẽ**: `scaleBounds` kẹp `w` và `h` (cùng `r` / `dg` / `dm` dựng từ chúng), `textScaleBounds` kẹp hệ số đứng sau `sp`. Tablet đủ chỗ cho lề rộng hơn từ rất lâu trước khi đủ chỗ cho chữ nội dung to hơn.

Một **`ResponsiveProfile`** ghi đè khung thiết kế, cả hai bound và `minTextAdapt` cho một `WindowSizeClass` (§7); trường nào để `null` thì kế thừa giá trị cấp trên. Profile được áp dụng là profile gắn với lớp của cửa sổ, nếu không có thì của lớp **nhỏ hơn** gần nhất có profile, nếu vẫn không có thì không profile nào — nên một profile đặt ở `expanded` cũng phủ luôn `large` và `extraLarge` cho tới khi chúng khai profile riêng, giống cách một media query `min-width` lan lên các cỡ lớn hơn.

Đây là toàn bộ cấu hình của app:

```dart
// platform/app_shell/lib/main_scope.dart — _ResponsiveWrapper.build
return ResponsiveInit(
  // The phone artboard every window class starts from.
  designSize: AppConfig.design,
  // Left at their defaults, `scaleBounds` and `textScaleBounds` are
  // `ScaleBounds.downOnly()`: a phone narrower than the artboard scales
  // the design down to fit, and nothing ever scales up — a tablet or a
  // desktop window draws it 1:1 and gives the extra room to the layout
  // (see `AdaptiveLayout`). To let a class grow, opt in with a bound:
  // `ResponsiveProfile(scaleBounds: ScaleBounds(max: 1.2))`.
  profiles: const {
    // Tablets in landscape, unfolded foldables, desktop windows — and
    // most phones in landscape, which are 840 or wider — are laid out
    // in real logical pixels. Without this, a laptop window
    // shorter than the 812-tall phone artboard would still shrink every
    // vertical gap and radius.
    WindowSizeClass.expanded: ResponsiveProfile(
      scaleBounds: ScaleBounds.fixed(),
      textScaleBounds: ScaleBounds.fixed(),
    ),
  },
  // Keeps height scaling sane when the app is a short split-screen pane.
  splitScreenMode: true,
  child: child,
);
```

Kết quả, theo từng cửa sổ:

| Cửa sổ | Lớp | Kết quả |
|---|---|---|
| Điện thoại hẹp hơn 375 | `compact` | Thu nhỏ cho vừa: `w` và `sp` theo tỉ lệ rộng, `h` theo tỉ lệ cao |
| Điện thoại rộng từ 375 | `compact` | `w` và `sp` 1:1. `h` và `r` vẫn thu nhỏ trên máy thấp hơn 812 — không bao giờ dưới 700/812, nhờ `splitScreenMode` |
| Rộng 600–839 | `medium` | Như hàng trên: `downOnly` chặn mọi hệ số ở 1 |
| Rộng từ 840 | `expanded` trở lên | 1:1 trên mọi trục (`fixed`), dù cửa sổ thấp đến đâu |

| Tham số | Mặc định | App này | Ý nghĩa |
|---|---|---|---|
| `designSize` | 360×690 | `AppConfig.design` (375×812) | Khung mà mọi lớp quy chiếu về, trừ khi profile của lớp đó chỉ định khung khác |
| `scaleBounds` | `ScaleBounds.downOnly()` | mặc định | Khoảng của các hệ số layout: `w`, `h`, và `r` / `dg` / `dm` dựng từ chúng |
| `textScaleBounds` | `ScaleBounds.downOnly()` | mặc định | Khoảng của hệ số chữ đứng sau `sp`. Độc lập với `scaleBounds` |
| `profiles` | `{}` | `expanded` → `fixed` / `fixed` | `Map<WindowSizeClass, ResponsiveProfile>`: `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` theo từng lớp (`null` là kế thừa). Ưu tiên đúng lớp, không có thì lớp nhỏ hơn gần nhất |
| `breakpoints` | `ResponsiveBreakpoints.material3()` | mặc định | Nơi mỗi lớp cửa sổ bắt đầu (§7). Cả profile lẫn `context.windowSizeClass` đều phân lớp theo nó |
| `minTextAdapt` | `false` | mặc định | `true` scale chữ theo tỉ lệ **nhỏ hơn** giữa rộng và cao thay vì theo rộng — chữ không phình trên cửa sổ rộng mà thấp, nhưng nhỏ đi khi xoay ngang |
| `splitScreenMode` | `false` | `true` | Chặn dưới chiều cao dùng để scale dọc ở `ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT` (700), để một ô chia đôi màn hình thấp không làm mọi `h` sụp xuống |
| `fontSizeResolver` | `null` | không đặt | Thay **hoàn toàn** cách scale chữ, và kết quả **không bao giờ bị kẹp** — không `textScaleBounds`, không profile, không `minTextAdapt`. Đọc `metrics.effectiveTextScaleBounds` bên trong nó nếu muốn tôn trọng bound |

**Opt-in phóng to** là một profile cho mỗi lớp được phép to ra, kèm mức chặn:

```dart
// Illustrative — not in the template: medium windows may grow 20 %, text 10 %.
WindowSizeClass.medium: ResponsiveProfile(
  scaleBounds: ScaleBounds(max: 1.2),
  textScaleBounds: ScaleBounds(max: 1.1),
),
```

Khi làm vậy, hãy kiểm tra hai điều. Lớp được phóng to gặp lớp kế bên bằng một **bước nhảy thấy được**: cạnh profile `expanded` kiểu `fixed` của app này, ví dụ trên dàn layout ở 1,2× khi rộng 839 và ở 1× khi rộng 840. Và một profile có `designSize` rộng hơn chiều rộng đầu tiên của lớp đó (600 với `medium`, 840 với `expanded`) sẽ khiến mọi thứ nhỏ đi ngay khi cửa sổ bước vào lớp; khung không rộng hơn thì bắt đầu ở tỉ lệ từ 1 trở lên, mà `downOnly` vẽ 1:1 ở cả hai phía ranh giới.

`context.responsive` cho thấy những gì đã được resolve — `activeProfile`, `effectiveDesignSize`, `effectiveScaleBounds`, `effectiveTextScaleBounds`, `effectiveMinTextAdapt`, `windowSizeClass`, `orientation` — hữu ích cho debug overlay hay test.

> [!NOTE]
> Việc rebuild không cần cấu hình gì. `ResponsiveInit` là `StatelessWidget` và đọc `MediaQuery.sizeOf(context)` — một dependency **chỉ theo size** — rồi phát `ResponsiveMetrics` xuống qua `ResponsiveScope`, một `InheritedWidget`. Mỗi lời gọi `context.w/h/r/sp` đăng ký dependency vào scope đó, nên Flutter rebuild đúng những widget có đọc giá trị đã scale. Đó cũng là lý do không có extension trên `num`: `16.w` chỉ có thể đọc một biến toàn cục, mà biến toàn cục thì không báo được cho ai. Luật R7 của `arch_check` cưỡng chế điều này.

> [!TIP]
> `ResponsiveScope.of(context)` sẽ assert khi phía trên không có `ResponsiveInit`, thay vì lặng lẽ trả về giá trị chưa scale. Widget test nào có scale đều phải bọc widget cần test trong `ResponsiveInit`.

---

## 7. Layout thích ứng: tablet, máy gập, chia đôi màn hình

§6 quyết định vẽ to cỡ nào; mục này quyết định vẽ **cái gì** với chỗ dư mà cửa sổ lớn hơn mang lại — thêm cột, một rail bên cạnh, một ô thứ hai. Mọi thứ ở đây nằm trong `core_responsive` (`platform/responsive/lib/src/adaptive/`) và phân lớp theo **cửa sổ**, không theo thiết bị: iPad đang Split View, cửa sổ desktop bị kéo hẹp và màn hình ngoài của máy gập đều nhận đúng lớp của khoảng không gian app thực sự có. Khác với `context.w`, không thứ nào ở đây cần `ResponsiveInit` — thiếu nó, cửa sổ được phân lớp theo mặc định Material 3.

### Lớp kích thước cửa sổ

| `WindowSizeClass` | Chiều rộng (logical px) | Cửa sổ điển hình |
|---|---|---|
| `compact` | < 600 | Điện thoại để dọc; điện thoại gập vỏ sò, mở hẳn hoặc gập hờ; một ô chia đôi màn hình hẹp |
| `medium` | 600 – 839 | Tablet hoặc máy gập để dọc; nửa màn hình chia đôi trên tablet lớn |
| `expanded` | 840 – 1199 | Tablet nằm ngang (iPad); máy gập mở hẳn; cửa sổ desktop nhỏ |
| `large` | 1200 – 1599 | Tablet lớn nằm ngang; cửa sổ desktop |
| `extraLarge` | ≥ 1600 | Cửa sổ desktop lớn |

Điện thoại xoay ngang thuộc `medium` hoặc `expanded` theo chiều rộng. `context.windowHeightClass` phân biệt được nó: `WindowHeightClass.compact` dưới 480, `medium` 480–899, `expanded` từ 900.

Các ranh giới là một `ResponsiveBreakpoints` — mặc định `const ResponsiveBreakpoints.material3()`, giá trị nằm ở `ResponsiveConstants.BREAKPOINT_*`. Truyền bộ khác vào `ResponsiveInit(breakpoints:)` thì profile scale, `context.windowSizeClass` và mọi widget bên dưới cùng dịch theo. So sánh lớp bằng `isAtLeast` / `isSmallerThan`, đừng so với chiều rộng thô.

### Một giá trị cho mỗi lớp: `context.adaptive`

```dart
// from the doc comment in platform/responsive/lib/src/adaptive/adaptive_context_extension.dart
final columns = context.adaptive(compact: 1, expanded: 3);
// compact 1 · medium 1 · expanded 3 · large 3 · extraLarge 3
```

Lớp nào không được cho giá trị sẽ lùi về lớp **nhỏ hơn** gần nhất có giá trị, tận cùng là `compact` bắt buộc — nên thêm một breakpoint không bao giờ làm đổi các layout hẹp hơn đang chạy đúng. Viết tắt: `context.isCompactWindow`, `context.isExpandedOrWider`.

### Một cây widget cho mỗi lớp: `AdaptiveLayout`

```dart
AdaptiveLayout(
  compact: (_) => const InboxList(),
  expanded: (_) => const InboxWithPreview(),
)
```

Cùng quy tắc lùi: `medium` hiện danh sách, `large` và `extraLarge` hiện bản xem trước. Slot là builder, nên chỉ layout đang trên màn hình mới được dựng — và khi bước sang lớp do builder khác phục vụ, cây con bị thay, mang theo cả vị trí cuộn lẫn chữ đang gõ. State phải sống sót qua xoay máy hay resize thì giữ ở controller cấp route, phía trên widget này. `AdaptiveBuilder(builder: (context, windowSizeClass) => …)` làm điều tương tự khi rẽ nhánh bằng code.

### Master–detail: `AdaptiveSplitView`

```dart
// from the doc comment in platform/responsive/lib/src/adaptive/adaptive_split_view.dart
AdaptiveSplitView(
  primary: MailList(
    // `itemContext` is the tapped item's: below the split view.
    onOpen: (itemContext, id) => AdaptiveSplitView.isSplit(itemContext)
        ? setState(() => _openId = id) // shown in the secondary pane
        : MailRoute(id: id).push(itemContext), // one pane: push it
  ),
  secondary: _openId == null ? null : MailView(id: _openId!),
  secondaryPlaceholder: const NothingSelected(),
)
```

Nó chia theo quy tắc đầu tiên khớp:

1. **Nếp gập hoặc bản lề dọc** (`FoldPosture.book`) — hai ô cạnh nhau, chia đúng tại đó, không vẽ gì bên dưới nó. Thắng cả khi dưới `splitAt`: máy gập mở hờ có hai nửa vật lý.
2. **Nếp gập ngang** (`FoldPosture.tabletop`) khi `tabletopSplit` là `true` (mặc định) — `primary` ở trên, `secondary` ở dưới. Tắt nó cho nội dung không được cắt đôi, như một form.
3. **Cửa sổ từ `splitAt` trở lên** (mặc định `WindowSizeClass.expanded`) — hai ô cạnh nhau, `primary` chiếm `primaryWidth` hoặc `primaryFraction` (0,4) chiều rộng, kèm `divider` tuỳ chọn.
4. **Còn lại** — chỉ `primary`. `secondary` không được dựng, nên app push route của mục đó; `AdaptiveSplitView.isSplit(context)` là cách phần tử danh sách biết nên làm gì. `context` của nó phải nằm *dưới* view — bên trong một ô, hoặc qua một `Builder`.

`primary` nằm ở cạnh bắt đầu (bên phải khi RTL). Cả hai ô giữ nguyên vị trí trong cây dù quy tắc nào áp dụng, nên vị trí cuộn của danh sách và chữ đang gõ sống sót qua xoay máy hay khi mở máy gập. View cần một hộp có giới hạn — đừng đặt trực tiếp trong scroll view hay `Row` / `Column` không bị ràng buộc.

**Nếp gập.** `context.separatingDisplayFeature` là nếp gập hoặc bản lề đang chia cửa sổ: bản lề thì luôn luôn; nếp gập chỉ khi đang mở hờ (`DisplayFeatureState.postureHalfOpened`), vì mở phẳng thì nó là một màn hình liền; lỗ camera thì không bao giờ — `SafeArea` lo phần đó. `context.foldPosture` gọi tên kết quả: `FoldPosture.flat`, `book` (Galaxy Z Fold hay Pixel Fold mở hờ) hoặc `tabletop` (Galaxy Z Flip gập hờ dựng trên bàn).

> [!WARNING]
> **Quy tắc nếp gập chỉ áp dụng khi view trải hết cửa sổ theo phương của nếp gập.** Toạ độ của nếp gập tính theo cửa sổ, mà widget không biết mình nằm đâu cho tới sau layout. Nên quy tắc 1 cần view rộng đúng bằng cửa sổ, quy tắc 2 cần cao đúng bằng; ở chỗ khác nếp gập bị bỏ qua và quy tắc 3–4 quyết định. Hãy để view là toàn bộ body của route và đặt chrome bên cạnh vào trong `primary`. Trong một tab của dashboard, mỗi phía mất một quy tắc: từ `medium` trở lên rail chiếm chiều rộng, nên nếp gập kiểu book bị bỏ qua; ở `compact` bottom bar chiếm chiều cao, nên nếp gập kiểu tabletop bị bỏ qua. Split view cần tôn trọng cả hai thì thuộc về một stack route (`IFeatureRouteModule`) có toàn bộ body chính là view.

### Chiều rộng dễ đọc: `AdaptiveContent`

```dart
// modules/auth/feature/lib/src/pages/login_page.dart
child: SingleChildScrollView(
  padding: EdgeInsets.all(AppSpacing.xl(context)),
  // On a tablet or desktop window the form keeps a readable width
  // instead of stretching across the screen.
  child: AdaptiveContent(
    child: Consumer<AuthProvider>(
      // …
    ),
  ),
),
```

Nó chặn widget con ở `maxWidth` — `AdaptiveConstants.CONTENT_MAX_WIDTH`, 640 — và đặt ở chính giữa phía trên của khoảng còn lại. Trên điện thoại, cửa sổ hẹp hơn mức chặn nên không gì thay đổi. `maxWidth` tính bằng **pixel cửa sổ và không bao giờ scale**: nó trả lời một dòng được dài tới đâu, điều mà mắt người đọc quyết định chứ không phải khung thiết kế — bọc trong `context.w` thì nó sẽ lớn theo chính cái tỉ lệ mà nó sinh ra để chặn. `padding`, như mọi tham số của widget dùng lại, được dùng đúng như nhận: hãy scale nó tại nơi gọi.

### Mẫu tham chiếu: chrome điều hướng theo lớp cửa sổ

`feature_dashboard` đổi chrome theo lớp cửa sổ: bottom bar ở `compact`, `NavigationRail` từ `medium` trở lên, dạng mở rộng (nhãn nằm cạnh icon) từ `large` trở lên. Cả hai dựng từ cùng những `NavDestination` mà mỗi tab đóng góp qua `INavDestinationModule`, nên không tab nào biết cái nào đang hiển thị.

```dart
// modules/dashboard/feature/lib/src/pages/dashboard_page.dart
final sizeClass = context.windowSizeClass;
if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
  return Scaffold(
    body: navigationShell,
    bottomNavigationBar: BottomNavigationBar(
      // …
    ),
  );
}

final extended = sizeClass.isAtLeast(WindowSizeClass.large);
return Scaffold(
  body: Row(
    children: [
      SafeArea(
        right: false,
        child: NavigationRail(
          // …
          extended: extended,
          // …
        ),
      ),
      Expanded(child: navigationShell),
    ],
  ),
);
```

Toàn bộ page, và những gì dashboard không được sở hữu: [`../architecture/05_features.md`](../architecture/05_features.md) §4.

---

## 8. Thêm một class token mới

Giả sử bạn muốn có `AppElevation`. Hãy theo đúng khuôn mà các class hiện có đang dùng — private constructor, hằng số `raw*`, accessor nhận context.

**Bước 1** — tạo `platform/base_ui/lib/src/styles/app_elevation.dart`:

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
dart tools/barrel_generator/generate.dart platform/base_ui/lib
```

`styles/styles.dart` là file tự sinh — tuyệt đối không sửa tay; generator sẽ xoá mọi dòng `export` viết thủ công ở lần chạy sau.

**Bước 3** — dùng thôi. Barrel công khai của `core_base_ui` vốn đã re-export `styles/`, nên mọi feature dùng được ngay:

```dart
Material(elevation: AppElevation.raised(context), child: …)
```

---

## 9. Gradient và shadow

`AppGradients` đọc màu trực tiếp từ theme đang chạy, nên gradient tự đổi màu theo bảng màu:

```dart
// platform/base_ui/lib/src/styles/app_gradients.dart
static LinearGradient primaryGradient(BuildContext context) {
  final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors.primaryGradientColors,
  );
}
```

Muốn đổi gradient, hãy sửa **danh sách màu** trong bảng màu (`primaryGradientColors`, `liquidOnboardingColors`), không sửa widget.

`AppShadows` là ngoại lệ — nó hardcode màu đen kèm alpha và **không** theo theme:

```dart
// platform/base_ui/lib/src/styles/app_shadows.dart
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

## 10. Những quy tắc không đổi

Danh sách đầy đủ trong [`../reference/01_rules.md`](../reference/01_rules.md). Luật nào do máy giữ đều được ghi rõ, vì điều đó quyết định bạn tin được bao nhiêu vào việc review bắt lỗi.

- **Tuyệt đối không hard-code** `Color`, `fontSize`, con số spacing hay `BorderRadius` trong widget. Thiếu token? Thêm vào `core_base_ui` — đừng nhét thẳng giá trị. *Do review giữ.* Xem ghi chú bên dưới để biết vì sao.
- **Mọi kích thước đều phải scale.** `SizedBox(height: 24)` trần là bug; hãy viết `SizedBox(height: context.h(24))` hoặc `context.verticalSpace(24)`. *`arch_check` R7 giữ phần extension trần (`24.h`); phần số double thô do review giữ.*
- **Widget scale hằng số của chính nó, không bao giờ scale tham số.** Một widget `core_ui_kit` nhận vào giá trị đã được scale sẵn — người gọi đã scale — nên dùng tham số ở dạng thô là đúng, còn `context.w(widget.width)` là bug scale hai lần. Nhưng padding và radius *của chính nó* thì bắt buộc phải scale, nếu không nó không responsive. `custom_input_field.dart` thể hiện cả hai trong một dòng: `widget.paddingBottom ?? context.h(10)`. *Do review giữ.*
- **Đừng scale một giá trị đã scale.** `AppSpacing.lg(context)` là giá trị cuối; `context.w(AppSpacing.lg(context))` là bug scale hai lần. Tương tự `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: ...)` — `ThemeProvider` đã scale mọi bậc rồi, nên ghi đè size là vứt bỏ thang đo và ghim cứng một con số mà design system không đổi được. Hãy chọn một bậc khác. *Do review giữ.*
- **Sửa `raw*`, không sửa accessor**, khi chỉnh lại một thang đo.
- **Đừng chờ kích thước to ra trên tablet.** Mặc định mọi hệ số dừng ở 1:1; hãy dùng chỗ dư cho layout (§7). Phóng to là opt-in theo từng lớp cửa sổ, có chặn (§6). *Do mặc định của `ResponsiveInit` giữ.*
- **Chọn layout theo lớp kích thước cửa sổ** — `context.windowSizeClass`, `context.adaptive`, `AdaptiveLayout` — đừng bao giờ theo đời máy, `Platform.isIOS` hay một phép kiểm `shortestSide` tự chế. Một thiết bị có nhiều cửa sổ: Split View, màn hình ngoài, cửa sổ desktop bị resize. *Do review giữ.*

> [!NOTE]
> **Vì sao luật về màu và font size không được máy kiểm.**
>
> Đã cân nhắc và cố ý để cho review. Một phép kiểm `Colors.<name>` sẽ phải cho qua những chỗ mà màu literal là *đúng* — `AppShadows`, vốn là file token, và mọi lớp phủ modal, nơi `ModalBarrier` của chính Flutter là màu đen cố định và một giá trị theo theme sẽ *làm sáng* màn hình ở chế độ tối. Trên cây code này là bảy chỗ được duyệt so với hai vi phạm thật, và một luật mà danh sách ngoại lệ dài hơn số phát hiện sẽ dạy người ta thói quen đọc lướt.
>
> Repo cũng cấm comment suppression, nên không có lối thoát trung thực nào cho các trường hợp hợp lệ. Vậy nên: review. Và đó chính là lý do ba bug dark-mode sống sót trong `core_ui_kit` cho tới khi có người đi soát — điều đáng nhớ khi bạn copy một widget ra khỏi đó.

---

## 11. Tra nhanh

| Tôi muốn đổi… | Sửa file |
|---|---|
| Một màu thương hiệu | `theme/theme_system_extensions.dart` → cả `light` **và** `dark` |
| Thêm một ô màu mới | `theme/theme_system_interface.dart`, rồi cả hai bảng màu + `lerp` |
| Font chữ | `pubspec.yaml` → `flutter: fonts:` + `theme/theme_provider.dart` → `applyFont` |
| Một cỡ chữ trong thang | `theme/theme_provider.dart` → khối `copyWith` |
| Một bước spacing | `styles/app_spacing.dart` → hằng số `raw*` |
| Một mức bo góc | `styles/app_radius.dart` → hằng số `raw*` |
| Một gradient | danh sách màu trong `theme/theme_system_extensions.dart` |
| Một shadow | `styles/app_shadows.dart` |
| Khung thiết kế gốc | `platform/common/lib/src/config/app_config.dart` → `design` |
| Một lớp cửa sổ được scale tới đâu (bound, profile, breakpoint) | `platform/app_shell/lib/main_scope.dart` → `ResponsiveInit` (§6) |
| Layout trên tablet, máy gập hay chia đôi màn hình | chính page đó — `context.adaptive`, `AdaptiveLayout`, `AdaptiveSplitView`, `AdaptiveContent` (§7) |
| Thêm hẳn một class token mới | file mới trong `styles/`, rồi chạy barrel generator |

---

## Xem thêm

- [`09_localization_theming.md`](09_localization_theming.md) — dùng token trong code widget, và bản dịch theo từng feature
- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_base_ui` nằm ở đâu, và vì sao nó không chứa widget nào; API công khai của `core_responsive`
- [`../reference/01_rules.md`](../reference/01_rules.md) — các luật được cưỡng chế, kèm lệnh kiểm chứng
