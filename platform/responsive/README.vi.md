🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# Core Responsive

Micro-core package cung cấp cơ chế **scale kích thước UI theo design size** — mặc định chỉ thu nhỏ, phóng to là opt-in theo từng lớp cửa sổ — cùng **lớp kích thước cửa sổ** và các **widget layout thích ứng** cho tablet, máy gập và chia đôi màn hình.

Toàn bộ việc scale đi qua `BuildContext`. Đây không phải quy ước về style — nó là điều kiện để widget **rebuild đúng chỗ** khi kích thước màn hình đổi (xoay máy, split-screen, resize cửa sổ desktop).

---

## 🌟 Tính Năng Cốt Lõi

- **`ResponsiveInit`**: Widget mount **một lần duy nhất**, phía trên `MaterialApp`. Nhận `designSize` (artboard thiết kế) và publish metrics xuống toàn bộ subtree.
- **`ResponsiveScope`**: `InheritedWidget` mang `ResponsiveMetrics`. Đọc qua nó sẽ **đăng ký dependency**, nên Flutter tự lo phần rebuild targeting.
- **`ResponsiveMetrics`**: Value object bất biến, chứa toàn bộ phép toán scale (`scaleWidth`, `scaleHeight`, `scaleText`, `width`, `height`, `radius`, `diagonal`, `diameter`, `sp`, `spMin`), các giá trị đã resolve (`activeProfile`, `effectiveDesignSize`, `effectiveScaleBounds`, `effectiveTextScaleBounds`, `effectiveMinTextAdapt`) và `windowSizeClass`, `windowHeightClass`, `orientation`.
- **`ScaleBounds`**: Khoảng mà một hệ số scale được phép nhận — `downOnly()` (mặc định), `fixed()`, `unbounded()`, hoặc `ScaleBounds(min:, max:)`.
- **`ResponsiveProfile`**: Ghi đè `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` cho một `WindowSizeClass`.
- **`WindowSizeClass` / `WindowHeightClass` / `ResponsiveBreakpoints`**: Phân lớp **cửa sổ** (không phải thiết bị) theo breakpoint Material 3.
- **`ResponsiveContext`**: Extension trên `BuildContext` — `context.w`, `.h`, `.r`, `.sp`, `.spMin`, `.dg`, `.dm`, `.edgeInsets`, `.borderRadius`, `.verticalSpace`, `.horizontalSpace`, `.responsive`, `.windowSizeClass`, `.windowHeightClass`.
- **`AdaptiveContext`**: Extension trên `BuildContext` — `context.adaptive(...)`, `.isCompactWindow`, `.isExpandedOrWider`, `.separatingDisplayFeature`, `.foldPosture`.
- **`AdaptiveBuilder` / `AdaptiveLayout` / `AdaptiveSplitView` / `AdaptiveContent`**, **`FoldPosture`**: Widget layout thích ứng — xem §3.
- **`ResponsiveConstants`** / **`AdaptiveConstants`**: Hằng số của package (`SPLIT_SCREEN_MIN_HEIGHT = 700`, design mặc định `360x690`, các `BREAKPOINT_*` theo chiều rộng và chiều cao; `SPLIT_PRIMARY_FRACTION = 0.4`, `SPLIT_DIVIDER_EXTENT = 1`, `CONTENT_MAX_WIDTH = 640`).

---

## 🚀 1. Khởi tạo

Đã được wire sẵn ở `platform/app_shell/lib/main_scope.dart`. Feature **không bao giờ** tự mount `ResponsiveInit` của riêng mình. Cấu hình thật của app (đã lược bớt comment) — `AppConfig.design` là artboard `375x812`, không phải mặc định `360x690` của package:

```dart
// platform/app_shell/lib/main_scope.dart — _ResponsiveWrapper.build
return ResponsiveInit(
  // The phone artboard every window class starts from.
  designSize: AppConfig.design,
  // …
  profiles: const {
    // …
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

`ResponsiveInit` là `StatelessWidget` — đây là chủ đích. Nó đọc `MediaQuery.sizeOf(context)`, vốn chỉ đăng ký dependency vào **khía cạnh size**, nên nó rebuild khi resize và đứng yên khi brightness / textScale / padding đổi. Không cần `WidgetsBindingObserver`, không cần `setState`.

| Tham số | Mặc định | Ý nghĩa |
|:--|:--|:--|
| `designSize` | `360x690` | Artboard mà bản thiết kế được vẽ ở đó — mọi lớp cửa sổ quy chiếu về nó, trừ khi profile chỉ định khung khác |
| `scaleBounds` | `ScaleBounds.downOnly()` | Khoảng của hệ số layout: `w`, `h`, và `r` / `dg` / `dm` dựng từ chúng |
| `textScaleBounds` | `ScaleBounds.downOnly()` | Khoảng của hệ số chữ đứng sau `sp`, độc lập với `scaleBounds` |
| `profiles` | `{}` | `Map<WindowSizeClass, ResponsiveProfile>` — ghi đè `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` cho từng lớp (`null` là kế thừa). Áp dụng profile của đúng lớp, không có thì của lớp nhỏ hơn gần nhất |
| `breakpoints` | `ResponsiveBreakpoints.material3()` | Nơi mỗi lớp cửa sổ bắt đầu: `compact` < 600 ≤ `medium` < 840 ≤ `expanded` < 1200 ≤ `large` < 1600 ≤ `extraLarge`; theo chiều cao: `compact` < 480 ≤ `medium` < 900 ≤ `expanded` |
| `splitScreenMode` | `false` | Kẹp sàn chiều cao ở `700` trước khi chia, tránh giá trị scale theo chiều dọc sụp xuống mức không đọc được khi cửa sổ quá thấp |
| `minTextAdapt` | `false` | Chữ scale theo trục nhỏ hơn thay vì theo width |
| `fontSizeResolver` | `null` | Tự quyết định cỡ chữ. **Cảnh báo:** truyền resolver là ghi đè toàn bộ việc scale chữ — `minTextAdapt` vô tác dụng, và kết quả **không bao giờ bị kẹp** bởi `textScaleBounds` hay profile (đọc `metrics.effectiveTextScaleBounds` trong resolver nếu muốn tôn trọng bound) |

### Chính sách scale: mặc định thu nhỏ, phóng to khi opt-in

Hệ số scale là tỉ lệ cửa sổ / artboard, rồi bị kẹp bởi một `ScaleBounds`. Không kẹp thì cửa sổ rộng 1280 so với artboard rộng 375 thành 3,4× — tiêu đề 20 px vẽ ra 68 px.

| Bound | Khoảng | Ý nghĩa |
|:--|:--|:--|
| `ScaleBounds.downOnly()` — **mặc định** | 0 – 1 | Cửa sổ nhỏ hơn artboard thì thu nhỏ; lớn hơn thì vẽ 1:1, chỗ dư để cho layout |
| `ScaleBounds(max: 1.2)` | 0 – 1,2 | Phóng to có chặn — phải opt-in |
| `ScaleBounds.fixed()` | 1 – 1 | Luôn đúng cỡ thiết kế |
| `ScaleBounds.unbounded()` | 0 – ∞ | Tỉ lệ thô, hành vi cũ trước khi có bound |

Vì vậy **đừng chờ kích thước to ra trên tablet**. Muốn một lớp cửa sổ to ra thì opt-in cho riêng lớp đó bằng một `ResponsiveProfile`; profile đặt ở một lớp cũng phủ mọi lớp rộng hơn chưa khai profile riêng. Chi tiết: [`docs/vi/guides/11_design_system.md`](../../docs/vi/guides/11_design_system.md) §6.

---

## 📏 2. Sử dụng

```dart
SizedBox(height: context.h(24)),
Text('Hi', style: TextStyle(fontSize: context.sp(16))),
Container(
  width: context.w(280),
  padding: context.edgeInsets(horizontal: 16, vertical: 8),
  decoration: BoxDecoration(borderRadius: context.borderRadius(all: 12)),
),
```

| Helper | Scale theo |
|:--|:--|
| `context.w(x)` | Width — cũng dùng cho thứ cần giữ hình vuông |
| `context.h(x)` | Height — khoảng cách dọc, chiều cao hàng |
| `context.r(x)` | Trục nhỏ hơn — bo góc, viền, độ dày nét |
| `context.sp(x)` | Cỡ chữ |
| `context.spMin(x)` | `sp` nhưng chặn trên ở giá trị design — chữ co lại chứ không phình ra. Với bound mặc định thì bằng `sp`; chỉ khác khi profile hoặc `fontSizeResolver` cho chữ to ra |
| `context.dg(x)` | Cả hai trục |
| `context.dm(x)` | Trục lớn hơn |
| `context.edgeInsets(all:)` / `(horizontal:)` | `w` |
| `context.edgeInsets(vertical:)` | `h` |
| `context.edgeInsetsDirectional(start:)` / `(end:)` | `w` — `EdgeInsetsDirectional`, đảo chiều khi RTL |
| `context.borderRadius(all:)` | `r` |
| `context.verticalSpace(x)` / `horizontalSpace(x)` | `h` / `w` |

Mỗi trục scale theo đúng trục nó thuộc về, nên padding giữ được tỉ lệ thay vì bám theo một chiều duy nhất. Vì vậy `context.edgeInsets(all: 16)` là bản thay thế trực tiếp cho `EdgeInsets.all(context.w(16))`.

---

## 🧩 3. Layout thích ứng: tablet, máy gập, chia đôi màn hình

Scale quyết định vẽ to cỡ nào; phần này quyết định vẽ **cái gì**. Mọi thứ phân lớp theo **cửa sổ**, không theo thiết bị, và chạy được cả khi không có `ResponsiveInit` phía trên (khi đó dùng breakpoint Material 3).

```dart
// One value per class; a missing class takes the nearest smaller one.
final columns = context.adaptive(compact: 1, expanded: 3);

// One subtree per class.
AdaptiveLayout(
  compact: (_) => const InboxList(),
  expanded: (_) => const InboxWithPreview(),
)

// A form that does not stretch across a tablet or desktop window.
AdaptiveContent(child: form)
```

| Thành phần | Dùng khi |
|:--|:--|
| `context.windowSizeClass` / `windowHeightClass` | Hỏi lớp của cửa sổ; so sánh bằng `isAtLeast` / `isSmallerThan` |
| `context.adaptive(compact:, medium:, …)` | Chọn một giá trị theo lớp; `isCompactWindow`, `isExpandedOrWider` là dạng viết tắt |
| `AdaptiveLayout` / `AdaptiveBuilder` | Chọn cả một cây con theo lớp — chỉ layout đang hiển thị được dựng |
| `AdaptiveSplitView` | Master–detail: hai ô tại nếp gập dọc / bản lề (kể cả dưới `splitAt`), trên–dưới tại nếp gập ngang (`tabletopSplit`, mặc định bật), cạnh nhau từ `splitAt` (mặc định `expanded`, ô chính chiếm `primaryFraction` = `0.4` hoặc `primaryWidth`), còn lại chỉ ô chính — `secondary` không được dựng. `AdaptiveSplitView.isSplit(context)` (gọi bằng context **bên dưới** split view) cho phần tử danh sách biết nên chọn hay push route |
| `AdaptiveContent` | Chặn chiều rộng nội dung ở `640` — pixel cửa sổ, **không** scale |
| `context.separatingDisplayFeature` / `foldPosture` | Nếp gập hoặc bản lề đang chia cửa sổ; `FoldPosture.flat` / `book` / `tabletop` |

> [!WARNING]
> `AdaptiveSplitView` chỉ tôn trọng nếp gập khi nó trải hết cửa sổ theo phương của nếp gập (toạ độ nếp gập tính theo cửa sổ): rộng bằng cửa sổ với nếp gập dọc (`book`), cao bằng cửa sổ với nếp gập ngang (`tabletop`). Đặt cạnh `NavigationRail` thì nếp gập dọc bị bỏ qua; dưới app bar thì nếp gập ngang bị bỏ qua — khi đó quy tắc `splitAt` quyết định.

**Chọn layout theo lớp cửa sổ, không bao giờ theo `Platform.isIOS`, đời máy hay phép kiểm `shortestSide` tự chế.** Mẫu tham chiếu: `modules/dashboard/feature/lib/src/pages/dashboard_page.dart` — bottom bar ở `compact`, `NavigationRail` từ `medium`, dạng mở rộng từ `large`. Chi tiết: [`docs/vi/guides/11_design_system.md`](../../docs/vi/guides/11_design_system.md) §7.

---

## ⛔ 4. Không có extension trên `num`

`16.w` **không compile được**. Package cố tình không cung cấp extension nào trên `num`, và cũng không có singleton global nào để đọc.

Lý do: một con số không mang theo context. Extension kiểu `16.w` vì thế chỉ có thể đọc từ một biến global — và widget nào đọc global thì **không bao giờ biết metrics đã đổi**: nó tính một lần rồi thôi. Đó là bug giá trị cũ (stale value) im lặng, không lộ ra cho tới khi máy bị xoay.

Bắt buộc truyền context biến "thứ đúng" thành "thứ duy nhất viết được". Việc rebuild do `InheritedWidget` của Flutter lo, nên không có cờ nào để bật/tắt.

## ⚠️ 5. Hai cái bẫy

**Trong `async`:** đọc giá trị scale **trước lệnh `await` đầu tiên**, rồi truyền kết quả đi. Không bao giờ giữ `BuildContext` qua một async gap.

```dart
final size = context.w(200).toInt();   // đọc trước
final thumb = await _load(size);       // rồi mới await
```

**Trong widget test:** widget nào có scale thì test phải bọc nó trong `ResponsiveInit`, nếu không `ResponsiveScope.of` sẽ assert:

```dart
await tester.pumpWidget(
  ResponsiveInit(designSize: const Size(360, 690), child: subject),
);
```

Việc assert là chủ đích. Âm thầm fallback về giá trị chưa scale sẽ ship ra một layout sai trên mọi thiết bị trừ đúng artboard thiết kế, và không có gì chỉ ra nguyên nhân.

---

## 🤖 6. Được máy kiểm tra

`dart tools/arch_check/check.dart` — rule **R7**, Gate 1 của `pr_quality_check.yml` — quét mọi file có nhắc tới `core_responsive` (thực tế: import nó) trong `lib/` và **chặn merge** (exit 1) khi gặp bất kỳ bare sizing extension nào (`16.w`, `(x).sp`, …), in ra `file:line`. Rule này không phụ thuộc vào review.

Test của package nằm ở `platform/responsive/test/`.
