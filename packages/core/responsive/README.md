# Core Responsive

Micro-core package cung cấp cơ chế **scale kích thước UI theo design size**.

Toàn bộ việc scale đi qua `BuildContext`. Đây không phải quy ước về style — nó là điều kiện để widget **rebuild đúng chỗ** khi kích thước màn hình đổi (xoay máy, split-screen, resize cửa sổ desktop).

---

## 🌟 Tính Năng Cốt Lõi

- **`ResponsiveInit`**: Widget mount **một lần duy nhất**, phía trên `MaterialApp`. Nhận `designSize` (artboard thiết kế) và publish metrics xuống toàn bộ subtree.
- **`ResponsiveScope`**: `InheritedWidget` mang `ResponsiveMetrics`. Đọc qua nó sẽ **đăng ký dependency**, nên Flutter tự lo phần rebuild targeting.
- **`ResponsiveMetrics`**: Value object bất biến, chứa toàn bộ phép toán scale (`scaleWidth`, `scaleHeight`, `scaleText`, `width`, `height`, `radius`, `diagonal`, `diameter`, `sp`, `spMin`).
- **`ResponsiveContext`**: Extension trên `BuildContext` — `context.w`, `.h`, `.r`, `.sp`, `.spMin`, `.dg`, `.dm`, `.edgeInsets`, `.borderRadius`, `.verticalSpace`, `.horizontalSpace`.
- **`ResponsiveConstants`**: Hằng số của package (`SPLIT_SCREEN_MIN_HEIGHT = 700`, design mặc định `360x690`).

---

## 🚀 1. Khởi tạo

Đã được wire sẵn ở `app/lib/main_scope.dart`. Feature **không bao giờ** tự mount `ResponsiveInit` của riêng mình.

```dart
ResponsiveInit(
  designSize: AppConfig.design,
  minTextAdapt: true,
  splitScreenMode: true,
  child: const RootApp(),
)
```

`ResponsiveInit` là `StatelessWidget` — đây là chủ đích. Nó đọc `MediaQuery.sizeOf(context)`, vốn chỉ đăng ký dependency vào **khía cạnh size**, nên nó rebuild khi resize và đứng yên khi brightness / textScale / padding đổi. Không cần `WidgetsBindingObserver`, không cần `setState`.

| Tham số | Ý nghĩa |
|:--|:--|
| `designSize` | Artboard mà bản thiết kế được vẽ ở đó. Mặc định `360x690` |
| `splitScreenMode` | Kẹp sàn chiều cao ở `700` trước khi chia, tránh giá trị scale theo chiều dọc sụp xuống mức không đọc được khi cửa sổ quá thấp |
| `minTextAdapt` | Chữ scale theo trục nhỏ hơn thay vì theo width |
| `fontSizeResolver` | Tự quyết định cỡ chữ. **Cảnh báo:** truyền resolver là ghi đè toàn bộ việc scale chữ, khiến `minTextAdapt` trở nên vô tác dụng |

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
| `context.spMin(x)` | `sp` nhưng chặn trên ở giá trị design — chữ co lại chứ không phình ra |
| `context.dg(x)` | Cả hai trục |
| `context.dm(x)` | Trục lớn hơn |
| `context.edgeInsets(all:)` / `(horizontal:)` | `w` |
| `context.edgeInsets(vertical:)` | `h` |
| `context.borderRadius(all:)` | `r` |
| `context.verticalSpace(x)` / `horizontalSpace(x)` | `h` / `w` |

Mỗi trục scale theo đúng trục nó thuộc về, nên padding giữ được tỉ lệ thay vì bám theo một chiều duy nhất. Vì vậy `context.edgeInsets(all: 16)` là bản thay thế trực tiếp cho `EdgeInsets.all(context.w(16))`.

---

## ⛔ 3. Không có extension trên `num`

`16.w` **không compile được**. Package cố tình không cung cấp extension nào trên `num`, và cũng không có singleton global nào để đọc.

Lý do: một con số không mang theo context. Extension kiểu `16.w` vì thế chỉ có thể đọc từ một biến global — và widget nào đọc global thì **không bao giờ biết metrics đã đổi**: nó tính một lần rồi thôi. Đó là bug giá trị cũ (stale value) im lặng, không lộ ra cho tới khi máy bị xoay.

Bắt buộc truyền context biến "thứ đúng" thành "thứ duy nhất viết được". Việc rebuild do `InheritedWidget` của Flutter lo, nên không có cờ nào để bật/tắt.

## ⚠️ 4. Hai cái bẫy

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

## 🤖 5. Được máy kiểm tra

`dart tools/arch_check/check.dart` — rule **R7**, Gate 1 của `pr_quality_check.yml` — quét mọi file có import `core_responsive` và **chặn build** khi gặp bất kỳ bare sizing extension nào, in ra `file:line`. Rule này không phụ thuộc vào review.

Test của package nằm ở `packages/core/responsive/test/`.
